import 'package:fitness_app/blocs/tracking/health_sync_cubit.dart';
import 'package:fitness_app/models/health_models.dart';
import 'package:fitness_app/services/health_background_scheduler.dart';
import 'package:fitness_app/services/health_sync_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository implements HealthSyncRepository {
  final HealthSyncResult result = HealthSyncResult(
    today: const HealthDailySummary(
      date: '2026-09-17',
      steps: 5200,
      activeKcal: 340,
      source: HealthSource.healthconnect,
    ),
    checkedAt: DateTime(2026, 9, 17, 12),
    uploadedDays: 30,
    backgroundEnabled: true,
  );

  @override
  Future<HealthProviderAvailability> availability() async =>
      HealthProviderAvailability.available;

  @override
  Future<HealthAccessStatus> accessStatus() async =>
      HealthAccessStatus.notRequested;

  @override
  Future<HealthSyncResult?> cachedResult() async => null;

  @override
  Future<void> installProvider() async {}

  @override
  Future<void> openSettings() async {}

  @override
  Future<bool> requestAccess() async => true;

  @override
  Future<HealthSyncResult> synchronize({bool forceFull = false}) async =>
      result;
}

class _FailingScheduler implements HealthSyncScheduler {
  @override
  Future<void> disable() async {}

  @override
  Future<void> enable() async => throw StateError('scheduler unavailable');

  @override
  Future<void> initialize() async {}
}

void main() {
  test('scheduler failure keeps foreground connection and data usable',
      () async {
    final HealthSyncCubit cubit = HealthSyncCubit(
      repository: _FakeRepository(),
      scheduler: _FailingScheduler(),
    );
    addTearDown(cubit.close);

    await cubit.initialize();
    await cubit.connect();

    expect(cubit.state.access, HealthAccessStatus.authorized);
    expect(cubit.state.result?.today?.steps, 5200);
    expect(cubit.state.result?.backgroundEnabled, isFalse);
    expect(cubit.state.error, isNull);
    expect(cubit.state.notice, contains('sync while the app is open'));
  });
}
