import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../models/health_models.dart';

abstract interface class HealthGateway {
  HealthSource get source;
  bool get supportsChangeTokens;

  Future<HealthProviderAvailability> availability();
  Future<bool?> hasReadPermissions();
  Future<bool> requestReadPermissions();
  Future<bool> requestBackgroundAccess();
  Future<void> installProvider();
  Future<void> openSettings();
  Future<List<DeviceHealthSample>> readSamples({
    required DateTime from,
    required DateTime to,
  });
  Future<String?> createChangesToken(DeviceHealthMetric metric);
  Future<HealthChangePage?> readChanges(String token);
}

class PlatformHealthGateway implements HealthGateway {
  PlatformHealthGateway({Health? health}) : _health = health ?? Health();

  static const MethodChannel _support =
      MethodChannel('com.fitnessapp/health_support');

  static const Map<DeviceHealthMetric, HealthDataType> _types =
      <DeviceHealthMetric, HealthDataType>{
    DeviceHealthMetric.steps: HealthDataType.STEPS,
    DeviceHealthMetric.activeKcal: HealthDataType.ACTIVE_ENERGY_BURNED,
    DeviceHealthMetric.restingHr: HealthDataType.RESTING_HEART_RATE,
    DeviceHealthMetric.spo2: HealthDataType.BLOOD_OXYGEN,
    DeviceHealthMetric.weightKg: HealthDataType.WEIGHT,
  };

  final Health _health;
  bool _configured = false;

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  HealthSource get source =>
      _ios ? HealthSource.healthkit : HealthSource.healthconnect;

  @override
  bool get supportsChangeTokens => _android;

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  List<HealthDataType> get _availableTypes => _types.values
      .where((HealthDataType type) => _health.isDataTypeAvailable(type))
      .toList(growable: false);

  @override
  Future<HealthProviderAvailability> availability() async {
    if (!_android && !_ios) return HealthProviderAvailability.unsupported;
    if (_ios) return HealthProviderAvailability.available;

    // SDK availability is a lightweight native check and does not need the
    // device-id initialization used when records are materialized. Keeping
    // it separate also guarantees a missing plugin settles as unsupported
    // instead of leaving the UI on an indeterminate progress indicator.
    final HealthConnectSdkStatus? status =
        await _health.getHealthConnectSdkStatus();
    return switch (status) {
      HealthConnectSdkStatus.sdkAvailable =>
        HealthProviderAvailability.available,
      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
        HealthProviderAvailability.installRequired,
      _ => HealthProviderAvailability.unsupported,
    };
  }

  @override
  Future<bool?> hasReadPermissions() async {
    await _configure();
    return _health.hasPermissions(
      _availableTypes,
      permissions: List<HealthDataAccess>.filled(
        _availableTypes.length,
        HealthDataAccess.READ,
      ),
    );
  }

  @override
  Future<bool> requestReadPermissions() async {
    await _configure();
    if (_android) {
      final bool activityAllowed =
          await _support.invokeMethod<bool>('requestActivityRecognition') ??
              false;
      if (!activityAllowed) return false;
    }
    return _health.requestAuthorization(
      _availableTypes,
      permissions: List<HealthDataAccess>.filled(
        _availableTypes.length,
        HealthDataAccess.READ,
      ),
    );
  }

  @override
  Future<bool> requestBackgroundAccess() async {
    await _configure();
    if (_ios) return true;
    if (!_android) return false;
    if (!await _health.isHealthDataInBackgroundAvailable()) return false;
    if (await _health.isHealthDataInBackgroundAuthorized()) return true;
    return _health.requestHealthDataInBackgroundAuthorization();
  }

  @override
  Future<void> installProvider() async {
    await _configure();
    await _health.installHealthConnect();
  }

  @override
  Future<void> openSettings() async {
    if (!_android) return;
    await _support.invokeMethod<void>('openHealthSettings');
  }

  @override
  Future<List<DeviceHealthSample>> readSamples({
    required DateTime from,
    required DateTime to,
  }) async {
    await _configure();
    final List<HealthDataPoint> points = await _health.getHealthDataFromTypes(
      types: _availableTypes,
      startTime: from,
      endTime: to,
    );
    final List<HealthDataPoint> unique = _health.removeDuplicates(points);
    return unique
        .map(_toSample)
        .whereType<DeviceHealthSample>()
        .toList(growable: false);
  }

  DeviceHealthSample? _toSample(HealthDataPoint point) {
    final MapEntry<DeviceHealthMetric, HealthDataType>? mapped = _types.entries
        .where(
          (MapEntry<DeviceHealthMetric, HealthDataType> entry) =>
              entry.value == point.type,
        )
        .firstOrNull;
    final HealthValue value = point.value;
    if (mapped == null || value is! NumericHealthValue) return null;
    return DeviceHealthSample(
      id: point.uuid,
      metric: mapped.key,
      value: value.numericValue.toDouble(),
      from: point.dateFrom,
      to: point.dateTo,
    );
  }

  @override
  Future<String?> createChangesToken(DeviceHealthMetric metric) async {
    if (!supportsChangeTokens) return null;
    await _configure();
    final HealthDataType? type = _types[metric];
    if (type == null || !_health.isDataTypeAvailable(type)) return null;
    return _health.getChangesToken(types: <HealthDataType>[type]);
  }

  @override
  Future<HealthChangePage?> readChanges(String token) async {
    if (!supportsChangeTokens) return null;
    await _configure();
    final HealthChangesResponse? response =
        await _health.getChanges(changesToken: token);
    if (response == null) return null;
    return HealthChangePage(
      nextToken: response.nextChangesToken,
      hasMore: response.hasMore,
      tokenExpired: response.changesTokenExpired,
      hasChanges: response.changes.isNotEmpty,
    );
  }
}
