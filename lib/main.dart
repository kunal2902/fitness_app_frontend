import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/health_background_scheduler.dart';
import 'services/push_service.dart';
import 'services/socket_service.dart';
import 'services/storage_service.dart';
import 'store/app_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local storage must be ready before the store rehydrates from it.
  await StorageService.instance.init();
  await AppStore.instance.bootstrap();
  try {
    await HealthBackgroundScheduler.instance.initialize();
  } catch (error, stackTrace) {
    // Background health is optional. A platform scheduler failure must not
    // prevent the rest of the app (including foreground sync) from opening.
    developer.log(
      'health background scheduler initialization failed',
      name: 'health',
      error: error,
      stackTrace: stackTrace,
    );
  }

  // Push has to be wired up before the first frame: a VoIP push can arrive
  // while the app is still starting, and the background handler must
  // already be registered when it does.
  await PushService.instance.initialize();

  // A stored session means we can open the realtime connection straight
  // away, so an incoming call rings without waiting for a screen to ask.
  if (AppStore.instance.isAuthenticated) {
    unawaited(SocketService.instance.connect());
  }

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  runApp(const FitnessApp());
}
