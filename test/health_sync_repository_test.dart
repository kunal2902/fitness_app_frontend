import 'package:fitness_app/models/api_exception.dart';
import 'package:fitness_app/models/health_models.dart';
import 'package:fitness_app/services/health_gateway.dart';
import 'package:fitness_app/services/health_sync_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHealthGateway implements HealthGateway {
  HealthProviderAvailability provider = HealthProviderAvailability.available;
  bool? permissions = true;
  bool requestGranted = true;
  bool backgroundGranted = true;
  Object? backgroundFailure;
  bool tokensSupported = true;
  HealthSource platformSource = HealthSource.healthconnect;
  int reads = 0;
  int installs = 0;
  int settings = 0;
  final List<DeviceHealthSample> samples = <DeviceHealthSample>[];
  final Map<DeviceHealthMetric, int> tokenCreates = <DeviceHealthMetric, int>{};
  final Map<String, HealthChangePage?> changes = <String, HealthChangePage?>{};

  @override
  HealthSource get source => platformSource;

  @override
  bool get supportsChangeTokens => tokensSupported;

  @override
  Future<HealthProviderAvailability> availability() async => provider;

  @override
  Future<bool?> hasReadPermissions() async => permissions;

  @override
  Future<bool> requestReadPermissions() async => requestGranted;

  @override
  Future<bool> requestBackgroundAccess() async {
    if (backgroundFailure != null) throw backgroundFailure!;
    return backgroundGranted;
  }

  @override
  Future<void> installProvider() async => installs += 1;

  @override
  Future<void> openSettings() async => settings += 1;

  @override
  Future<List<DeviceHealthSample>> readSamples({
    required DateTime from,
    required DateTime to,
  }) async {
    reads += 1;
    return List<DeviceHealthSample>.from(samples);
  }

  @override
  Future<String?> createChangesToken(DeviceHealthMetric metric) async {
    final int generation = (tokenCreates[metric] ?? 0) + 1;
    tokenCreates[metric] = generation;
    return '${metric.name}-token-$generation';
  }

  @override
  Future<HealthChangePage?> readChanges(String token) async =>
      changes[token] ??
      HealthChangePage(
        nextToken: '$token-next',
        hasMore: false,
        tokenExpired: false,
        hasChanges: false,
      );
}

class MemoryHealthStore implements HealthSyncStore {
  MemoryHealthStore([Map<String, dynamic>? initial])
      : value = initial == null ? null : Map<String, dynamic>.from(initial);

  Map<String, dynamic>? value;

  @override
  Map<String, dynamic>? read() =>
      value == null ? null : Map<String, dynamic>.from(value!);

  @override
  Future<void> write(Map<String, dynamic> next) async {
    value = Map<String, dynamic>.from(next);
  }
}

class RecordingUploader implements HealthSyncUploader {
  final List<List<HealthDailySummary>> uploads = <List<HealthDailySummary>>[];
  Object? failure;

  @override
  Future<void> upload(List<HealthDailySummary> days) async {
    if (failure != null) throw failure!;
    uploads.add(List<HealthDailySummary>.from(days));
  }
}

Map<String, dynamic> connectedState({Map<String, dynamic>? tokens}) =>
    <String, dynamic>{
      'accountId': 'user-1',
      'consentAttempted': true,
      'consented': true,
      'backgroundEnabled': true,
      'tokens': tokens ?? <String, dynamic>{},
      'cursors': <String, dynamic>{},
    };

DeviceHealthSyncRepository repository({
  required FakeHealthGateway gateway,
  required MemoryHealthStore store,
  required RecordingUploader uploader,
}) {
  return DeviceHealthSyncRepository(
    gateway: gateway,
    store: store,
    uploader: uploader,
    accountId: () => 'user-1',
    clock: () => DateTime(2026, 9, 12, 12),
  );
}

void main() {
  test('first Android sync creates one token per type then reconciles 30 days',
      () async {
    final FakeHealthGateway gateway = FakeHealthGateway()
      ..samples.add(
        DeviceHealthSample(
          id: 'today-steps',
          metric: DeviceHealthMetric.steps,
          value: 8420,
          from: DateTime(2026, 9, 12, 9),
          to: DateTime(2026, 9, 12, 10),
        ),
      );
    final MemoryHealthStore store = MemoryHealthStore(connectedState());
    final RecordingUploader uploader = RecordingUploader();

    final HealthSyncResult result = await repository(
      gateway: gateway,
      store: store,
      uploader: uploader,
    ).synchronize();

    expect(gateway.tokenCreates.keys, containsAll(DeviceHealthMetric.values));
    expect(gateway.reads, 1);
    expect(uploader.uploads.single, hasLength(30));
    expect(result.today?.steps, 8420);
    expect(result.uploadedDays, 30);
    expect((store.value!['tokens'] as Map), hasLength(5));
  });

  test('unchanged tokens advance without re-reading or uploading', () async {
    final Map<String, dynamic> tokens = <String, dynamic>{
      for (final DeviceHealthMetric metric in DeviceHealthMetric.values)
        metric.name: '${metric.name}-old',
    };
    final FakeHealthGateway gateway = FakeHealthGateway();
    final MemoryHealthStore store =
        MemoryHealthStore(connectedState(tokens: tokens));
    final RecordingUploader uploader = RecordingUploader();

    final HealthSyncResult result = await repository(
      gateway: gateway,
      store: store,
      uploader: uploader,
    ).synchronize();

    expect(gateway.reads, 0);
    expect(uploader.uploads, isEmpty);
    expect(result.uploadedDays, 0);
    expect(
      (store.value!['tokens'] as Map)['steps'],
      'steps-old-next',
    );
  });

  test('expired token forces reconciliation and is replaced', () async {
    final Map<String, dynamic> tokens = <String, dynamic>{
      for (final DeviceHealthMetric metric in DeviceHealthMetric.values)
        metric.name: '${metric.name}-old',
    };
    final FakeHealthGateway gateway = FakeHealthGateway();
    gateway.changes['steps-old'] = const HealthChangePage(
      nextToken: '',
      hasMore: false,
      tokenExpired: true,
      hasChanges: false,
    );
    final MemoryHealthStore store =
        MemoryHealthStore(connectedState(tokens: tokens));
    final RecordingUploader uploader = RecordingUploader();

    await repository(
      gateway: gateway,
      store: store,
      uploader: uploader,
    ).synchronize();

    expect(gateway.tokenCreates[DeviceHealthMetric.steps], 1);
    expect((store.value!['tokens'] as Map)['steps'], 'steps-token-1');
    expect(uploader.uploads.single, hasLength(30));
  });

  test('tokens do not advance when the backend upload fails', () async {
    final Map<String, dynamic> tokens = <String, dynamic>{
      for (final DeviceHealthMetric metric in DeviceHealthMetric.values)
        metric.name: '${metric.name}-old',
    };
    final FakeHealthGateway gateway = FakeHealthGateway();
    gateway.changes['steps-old'] = const HealthChangePage(
      nextToken: 'steps-new',
      hasMore: false,
      tokenExpired: false,
      hasChanges: true,
    );
    final MemoryHealthStore store =
        MemoryHealthStore(connectedState(tokens: tokens));
    final RecordingUploader uploader = RecordingUploader()
      ..failure = const ApiException.network();

    await expectLater(
      repository(gateway: gateway, store: store, uploader: uploader)
          .synchronize(),
      throwsA(isA<ApiException>()),
    );
    expect((store.value!['tokens'] as Map)['steps'], 'steps-old');
  });

  test('consent is account-scoped and denial remains a visible state',
      () async {
    final FakeHealthGateway gateway = FakeHealthGateway()
      ..requestGranted = false;
    final MemoryHealthStore store = MemoryHealthStore(
      <String, dynamic>{...connectedState(), 'accountId': 'another-user'},
    );
    final RecordingUploader uploader = RecordingUploader();
    final DeviceHealthSyncRepository subject = repository(
      gateway: gateway,
      store: store,
      uploader: uploader,
    );

    expect(await subject.accessStatus(), HealthAccessStatus.notRequested);
    expect(await subject.requestAccess(), isFalse);
    expect(await subject.accessStatus(), HealthAccessStatus.denied);
    expect(store.value!['accountId'], 'user-1');
  });

  test('background authorization failure preserves foreground consent',
      () async {
    final FakeHealthGateway gateway = FakeHealthGateway()
      ..backgroundFailure = StateError('background API unavailable');
    final MemoryHealthStore store = MemoryHealthStore();
    final RecordingUploader uploader = RecordingUploader();
    final DeviceHealthSyncRepository subject = repository(
      gateway: gateway,
      store: store,
      uploader: uploader,
    );

    expect(await subject.requestAccess(), isTrue);
    expect(await subject.accessStatus(), HealthAccessStatus.authorized);
    expect(store.value!['consented'], isTrue);
    expect(store.value!['backgroundEnabled'], isFalse);
  });
}
