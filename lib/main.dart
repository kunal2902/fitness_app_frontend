import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/push_service.dart';
import 'services/socket_service.dart';
import 'services/storage_service.dart';
import 'store/app_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local storage must be ready before the store rehydrates from it.
  await StorageService.instance.init();
  await AppStore.instance.bootstrap();

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
