import '../config/api_endpoints.dart';
import '../config/storage_keys.dart';
import '../models/api_exception.dart';
import '../models/health_models.dart';
import '../store/app_store.dart';
import 'api_client.dart';
import 'health_gateway.dart';
import 'storage_service.dart';

abstract interface class HealthSyncRepository {
  Future<HealthProviderAvailability> availability();
  Future<HealthAccessStatus> accessStatus();
  Future<bool> requestAccess();
  Future<HealthSyncResult> synchronize({bool forceFull = false});
  Future<HealthSyncResult?> cachedResult();
  Future<void> installProvider();
  Future<void> openSettings();
}

abstract interface class HealthSyncUploader {
  Future<void> upload(List<HealthDailySummary> days);
}

class ApiHealthSyncUploader implements HealthSyncUploader {
  ApiHealthSyncUploader({ApiClient? client})
      : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  @override
  Future<void> upload(List<HealthDailySummary> days) async {
    for (int offset = 0; offset < days.length; offset += 1000) {
      final int end = (offset + 1000).clamp(0, days.length).toInt();
      final List<HealthDailySummary> chunk = days.sublist(offset, end);
      final Map<String, dynamic> response = await _client.post(
        ApiEndpoints.healthSync,
        body: <String, dynamic>{
          'days': chunk
              .map((HealthDailySummary day) => day.toJson())
              .toList(growable: false),
        },
      );
      final int? synced = (response['synced'] as num?)?.toInt();
      if (synced != chunk.length || response['days'] is! List) {
        throw const ApiException(
          message: 'The health sync response was incomplete. Please try again.',
          code: 'BAD_ENVELOPE',
        );
      }
    }
  }
}

abstract interface class HealthSyncStore {
  Map<String, dynamic>? read();
  Future<void> write(Map<String, dynamic> value);
}

class LocalHealthSyncStore implements HealthSyncStore {
  const LocalHealthSyncStore();

  @override
  Map<String, dynamic>? read() =>
      StorageService.instance.getJson(StorageKeys.healthSyncState);

  @override
  Future<void> write(Map<String, dynamic> value) =>
      StorageService.instance.setJson(StorageKeys.healthSyncState, value);
}

class DeviceHealthSyncRepository implements HealthSyncRepository {
  DeviceHealthSyncRepository({
    HealthGateway? gateway,
    HealthSyncUploader? uploader,
    HealthSyncStore? store,
    String? Function()? accountId,
    DateTime Function()? clock,
  })  : _gateway = gateway ?? PlatformHealthGateway(),
        _uploader = uploader ?? ApiHealthSyncUploader(),
        _store = store ?? const LocalHealthSyncStore(),
        _accountId = accountId ?? (() => AppStore.instance.user?.id),
        _clock = clock ?? DateTime.now;

  static const Duration _reconciliationWindow = Duration(days: 29);
  static const int _maxChangePages = 100;

  final HealthGateway _gateway;
  final HealthSyncUploader _uploader;
  final HealthSyncStore _store;
  final String? Function() _accountId;
  final DateTime Function() _clock;

  @override
  Future<HealthProviderAvailability> availability() => _gateway.availability();

  Map<String, dynamic> _currentState() {
    final String? id = _accountId();
    if (id == null || id.isEmpty) {
      throw const ApiException(
        message: 'Sign in before connecting health data.',
        statusCode: 401,
        code: 'NO_SESSION',
      );
    }
    final Map<String, dynamic>? stored = _store.read();
    if (stored?['accountId'] == id) return Map<String, dynamic>.from(stored!);
    return <String, dynamic>{
      'accountId': id,
      'consentAttempted': false,
      'consented': false,
      'backgroundEnabled': false,
      'tokens': <String, dynamic>{},
      'cursors': <String, dynamic>{},
    };
  }

  @override
  Future<HealthAccessStatus> accessStatus() async {
    final Map<String, dynamic> state = _currentState();
    if (state['consented'] != true) {
      return state['consentAttempted'] == true
          ? HealthAccessStatus.denied
          : HealthAccessStatus.notRequested;
    }
    final bool? native = await _gateway.hasReadPermissions();
    return native == false
        ? HealthAccessStatus.denied
        : HealthAccessStatus.authorized;
  }

  @override
  Future<bool> requestAccess() async {
    final Map<String, dynamic> state = _currentState();
    final bool granted = await _gateway.requestReadPermissions();
    state['consentAttempted'] = true;
    state['consented'] = granted;
    state['backgroundEnabled'] = false;
    if (granted) {
      // This is a separate Health Connect grant. A denial does not revoke
      // foreground reads; it only keeps the periodic task disabled. Treat a
      // platform/plugin failure the same way: foreground health remains
      // connected and the UI can honestly show that background sync is off.
      try {
        state['backgroundEnabled'] = await _gateway.requestBackgroundAccess();
      } catch (_) {
        state['backgroundEnabled'] = false;
      }
    }
    await _store.write(state);
    return granted;
  }

  @override
  Future<void> installProvider() => _gateway.installProvider();

  @override
  Future<void> openSettings() => _gateway.openSettings();

  @override
  Future<HealthSyncResult?> cachedResult() async {
    final Map<String, dynamic> state = _currentState();
    final DateTime? checkedAt =
        DateTime.tryParse((state['lastCheckedAt'] ?? '').toString());
    final Object? rawToday = state['today'];
    if (checkedAt == null && rawToday is! Map) return null;
    return HealthSyncResult(
      today: rawToday is Map
          ? HealthDailySummary.fromJson(Map<String, dynamic>.from(rawToday))
          : null,
      checkedAt: checkedAt ?? _clock(),
      uploadedDays: 0,
      backgroundEnabled: state['backgroundEnabled'] == true,
    );
  }

  @override
  Future<HealthSyncResult> synchronize({bool forceFull = false}) async {
    final Map<String, dynamic> state = _currentState();
    if (state['consented'] != true) {
      throw const ApiException(
        message: 'Connect your health provider before syncing.',
        code: 'HEALTH_NOT_CONNECTED',
      );
    }
    final HealthProviderAvailability provider = await availability();
    if (provider != HealthProviderAvailability.available) {
      throw const ApiException(
        message: 'Your health provider is not available.',
        code: 'HEALTH_UNAVAILABLE',
      );
    }
    if (await _gateway.hasReadPermissions() == false) {
      state['consented'] = false;
      state['consentAttempted'] = true;
      await _store.write(state);
      throw const ApiException(
        message: 'Health permission was removed in system settings.',
        code: 'HEALTH_PERMISSION_REMOVED',
      );
    }

    final DateTime checkedAt = _clock();
    bool needsUpload = forceFull;
    final Map<String, dynamic> nextTokens = Map<String, dynamic>.from(
      state['tokens'] is Map
          ? state['tokens'] as Map
          : const <String, dynamic>{},
    );

    if (_gateway.supportsChangeTokens) {
      final _TokenPoll poll = await _pollChanges(nextTokens);
      needsUpload = needsUpload || poll.needsReconciliation;
      nextTokens
        ..clear()
        ..addAll(poll.tokens);
    } else {
      final DateTime? lastFull =
          DateTime.tryParse((state['lastFullSyncAt'] ?? '').toString());
      // The health package does not expose HealthKit anchored queries. Use a
      // short overlap normally, and periodically reconcile the full window.
      needsUpload = true;
      if (lastFull == null || checkedAt.difference(lastFull).inDays >= 29) {
        forceFull = true;
      }
    }

    int uploadedDays = 0;
    HealthDailySummary? today;
    if (needsUpload) {
      final DateTime from = forceFull || _gateway.supportsChangeTokens
          ? healthStartOfDay(checkedAt.subtract(_reconciliationWindow))
          : _incrementalIosStart(state, checkedAt);
      final List<DeviceHealthSample> samples = await _gateway.readSamples(
        from: from,
        to: checkedAt,
      );
      final List<HealthDailySummary> days = aggregateHealthDays(
        samples: samples,
        from: from,
        to: checkedAt,
        source: _gateway.source,
      );
      if (days.isNotEmpty) {
        await _uploader.upload(days);
        uploadedDays = days.length;
        today = days.last;
      }
      if (forceFull || _gateway.supportsChangeTokens) {
        state['lastFullSyncAt'] = checkedAt.toUtc().toIso8601String();
      }
      if (!_gateway.supportsChangeTokens) {
        state['cursors'] = <String, dynamic>{
          for (final DeviceHealthMetric metric in DeviceHealthMetric.values)
            metric.storageName: checkedAt.toUtc().toIso8601String(),
        };
      }
    } else {
      final Object? raw = state['today'];
      if (raw is Map) {
        today = HealthDailySummary.fromJson(Map<String, dynamic>.from(raw));
      }
    }

    state['tokens'] = nextTokens;
    state['lastCheckedAt'] = checkedAt.toUtc().toIso8601String();
    if (today != null) state['today'] = today.toCacheJson();
    await _store.write(state);
    return HealthSyncResult(
      today: today,
      checkedAt: checkedAt,
      uploadedDays: uploadedDays,
      backgroundEnabled: state['backgroundEnabled'] == true,
    );
  }

  DateTime _incrementalIosStart(
    Map<String, dynamic> state,
    DateTime checkedAt,
  ) {
    final Object? rawCursors = state['cursors'];
    if (rawCursors is! Map || rawCursors.isEmpty) {
      return healthStartOfDay(checkedAt.subtract(_reconciliationWindow));
    }
    final Iterable<DateTime> cursors = rawCursors.values
        .map((Object? value) => DateTime.tryParse(value.toString()))
        .whereType<DateTime>();
    if (cursors.isEmpty) {
      return healthStartOfDay(checkedAt.subtract(_reconciliationWindow));
    }
    final DateTime earliest = cursors.reduce(
      (DateTime a, DateTime b) => a.isBefore(b) ? a : b,
    );
    return healthStartOfDay(
      earliest.toLocal().subtract(const Duration(days: 1)),
    );
  }

  Future<_TokenPoll> _pollChanges(Map<String, dynamic> stored) async {
    bool reconcile = false;
    final Map<String, dynamic> proposed = Map<String, dynamic>.from(stored);
    for (final DeviceHealthMetric metric in DeviceHealthMetric.values) {
      String? token = stored[metric.storageName] as String?;
      if (token == null || token.isEmpty) {
        token = await _gateway.createChangesToken(metric);
        if (token == null || token.isEmpty) {
          throw const ApiException(
            message: 'Health Connect could not start incremental sync.',
            code: 'HEALTH_TOKEN_FAILED',
          );
        }
        proposed[metric.storageName] = token;
        reconcile = true;
        continue;
      }

      bool finished = false;
      for (int pageIndex = 0; pageIndex < _maxChangePages; pageIndex += 1) {
        final HealthChangePage? page = await _gateway.readChanges(token!);
        if (page == null || page.tokenExpired) {
          final String? replacement = await _gateway.createChangesToken(metric);
          if (replacement == null || replacement.isEmpty) {
            throw const ApiException(
              message: 'Health Connect could not renew its sync cursor.',
              code: 'HEALTH_TOKEN_FAILED',
            );
          }
          proposed[metric.storageName] = replacement;
          reconcile = true;
          finished = true;
          break;
        }
        reconcile = reconcile || page.hasChanges;
        token = page.nextToken;
        proposed[metric.storageName] = token;
        if (!page.hasMore) {
          finished = true;
          break;
        }
      }
      if (!finished) {
        throw const ApiException(
          message: 'Health Connect returned too many change pages. Try again.',
          code: 'HEALTH_CHANGE_OVERFLOW',
        );
      }
    }
    return _TokenPoll(tokens: proposed, needsReconciliation: reconcile);
  }
}

class _TokenPoll {
  const _TokenPoll({required this.tokens, required this.needsReconciliation});

  final Map<String, dynamic> tokens;
  final bool needsReconciliation;
}
