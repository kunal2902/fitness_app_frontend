import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../models/api_exception.dart';
import '../models/health_models.dart';
import '../store/app_store.dart';
import 'health_sync_repository.dart';
import 'storage_service.dart';

const String healthSyncUniqueName = 'com.fitnessapp.health.sync';
const String healthSyncTaskName = 'health-daily-sync';

@pragma('vm:entry-point')
void healthSyncCallbackDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    if (task != healthSyncTaskName && task != healthSyncUniqueName) return true;
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await StorageService.instance.init();
      await AppStore.instance.bootstrap();
      if (!AppStore.instance.isAuthenticated) return true;

      final DeviceHealthSyncRepository repository =
          DeviceHealthSyncRepository();
      if (await repository.accessStatus() != HealthAccessStatus.authorized) {
        return true;
      }
      await repository.synchronize();
      return true;
    } on ApiException catch (error) {
      // Permission/session failures require foreground user action. Network
      // and server failures return false so WorkManager applies backoff.
      return error.code == 'HEALTH_PERMISSION_REMOVED' ||
          error.code == 'HEALTH_NOT_CONNECTED' ||
          error.code == 'NO_SESSION';
    } catch (_) {
      return false;
    }
  });
}

abstract interface class HealthSyncScheduler {
  Future<void> initialize();
  Future<void> enable();
  Future<void> disable();
}

class HealthBackgroundScheduler implements HealthSyncScheduler {
  HealthBackgroundScheduler._();

  static final HealthBackgroundScheduler instance =
      HealthBackgroundScheduler._();

  bool _initialized = false;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<void> initialize() async {
    if (!_supported || _initialized) return;
    await Workmanager().initialize(healthSyncCallbackDispatcher);
    _initialized = true;
  }

  @override
  Future<void> enable() async {
    if (!_supported) return;
    await initialize();
    await Workmanager().registerPeriodicTask(
      healthSyncUniqueName,
      healthSyncTaskName,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  @override
  Future<void> disable() async {
    if (!_supported) return;
    await initialize();
    await Workmanager().cancelByUniqueName(healthSyncUniqueName);
  }
}
