import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'blocs/auth/auth_bloc.dart';
import 'blocs/call/call_bloc.dart';
import 'blocs/onboarding/onboarding_bloc.dart';
import 'config/app_config.dart';
import 'models/call_models.dart';
import 'routes/app_router.dart';
import 'routes/app_routes.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';
import 'services/socket_service.dart';
import 'store/app_store.dart';
import 'theme/app_theme.dart';
import 'widgets/call_overlay.dart';

/// Root widget. Wires up the global store, the always-on BLoCs, the
/// realtime connection, and the call overlay that can appear over any
/// screen.
class FitnessApp extends StatefulWidget {
  const FitnessApp({super.key});

  @override
  State<FitnessApp> createState() => _FitnessAppState();
}

class _FitnessAppState extends State<FitnessApp> with WidgetsBindingObserver {
  final AuthBloc _authBloc = AuthBloc();

  /// Created once and kept for the app's lifetime: a call can arrive at
  /// any moment, so the thing that listens for invites cannot be scoped to
  /// a screen.
  late final CallBloc _callBloc = CallBloc();

  StreamSubscription<SocketStatus>? _socketStatusSub;
  bool _recoveringSocketAuth = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // A refresh failing deep inside a request has no BuildContext — the
    // API client calls back here and the AuthBloc handles the logout.
    ApiClient.instance.onSessionExpired =
        () => _authBloc.add(const AuthSessionExpired());

    _superviseSocket();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ApiClient.instance.onSessionExpired = null;
    unawaited(_socketStatusSub?.cancel());
    unawaited(_callBloc.close());
    unawaited(_authBloc.close());
    SocketService.instance.disconnect();
    super.dispose();
  }

  /// Keeps a call sane across backgrounding.
  ///
  /// Two separate problems this solves:
  ///
  ///  * **The camera keeps streaming when the app is not visible.** Android
  ///    stops delivering frames from a backgrounded app, so the far end
  ///    sees a frozen picture with no explanation. Pausing the video track
  ///    deliberately, and resuming on return, at least makes it the
  ///    behaviour every other calling app has.
  ///  * **A ringer left behind.** If the app was killed while ringing, the
  ///    native call UI can outlive the call it belongs to. Clearing on
  ///    resume means the user is never looking at a phantom incoming call.
  ///
  /// What this deliberately does NOT do is keep the call alive
  /// indefinitely in the background — that needs a foreground service with
  /// `microphone`/`camera` types on Android, which is a platform change,
  /// not a Dart one. See the backend's docs/REALTIME_SETUP.md.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final CallState call = _callBloc.state;
    if (!call.isActive) {
      // Cleared here, not only on resume-during-a-call. A call that ends
      // while the app is backgrounded never runs the resume branch below,
      // so the flag would survive into the NEXT call — where it would
      // switch on a camera the user had deliberately turned off.
      _cameraPausedByLifecycle = false;
      if (state == AppLifecycleState.resumed && call.phase == CallPhase.idle) {
        unawaited(PushService.dismissAll());
      }
      return;
    }

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (call.withVideo && call.isCameraEnabled) {
          _cameraPausedByLifecycle = true;
          _callBloc.add(const CallCameraToggled());
        }
      case AppLifecycleState.resumed:
        if (_cameraPausedByLifecycle) {
          _cameraPausedByLifecycle = false;
          if (!_callBloc.state.isCameraEnabled) {
            _callBloc.add(const CallCameraToggled());
          }
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Set only when *we* turned the camera off for backgrounding, so
  /// returning does not switch on a camera the user had muted themselves.
  bool _cameraPausedByLifecycle = false;

  /// Recovers the socket when its token has aged out.
  ///
  /// The handshake authenticates once, so a live socket survives token
  /// expiry — but a *reconnect* with a stale token is refused. Hitting an
  /// authenticated endpoint triggers the normal refresh path, after which
  /// the socket can reconnect with the new token.
  void _superviseSocket() {
    _socketStatusSub =
        SocketService.instance.statusStream.listen((SocketStatus status) async {
      if (status != SocketStatus.unauthorized) return;
      if (_recoveringSocketAuth) return;
      if (!AppStore.instance.isAuthenticated) return;

      _recoveringSocketAuth = true;
      try {
        await AuthService().me();
        await SocketService.instance.reauthenticate();
      } catch (error) {
        developer.log('socket auth recovery failed: $error', name: 'app');
      } finally {
        _recoveringSocketAuth = false;
      }
    });
  }

  Future<void> _onAuthChanged(BuildContext context, AuthState state) async {
    if (state.isAuthenticated) {
      await SocketService.instance.connect();
      // Asked for after sign-in rather than on first launch, so the
      // permission prompt arrives with context.
      await PushService.instance.registerForCalls();
    } else if (state.status == AuthFlowStatus.unauthenticated) {
      await PushService.instance.unregister();
      SocketService.instance.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppStore>.value(
      value: AppStore.instance,
      child: MultiBlocProvider(
        providers: <SingleChildWidget>[
          BlocProvider<AuthBloc>.value(value: _authBloc),
          BlocProvider<CallBloc>.value(value: _callBloc),
          BlocProvider<OnboardingBloc>(create: (_) => OnboardingBloc()),
        ],
        child: BlocListener<AuthBloc, AuthState>(
          listenWhen: (AuthState a, AuthState b) => a.status != b.status,
          listener: _onAuthChanged,
          // Only the theme mode needs to rebuild MaterialApp.
          child: Consumer<AppStore>(
            builder: (BuildContext context, AppStore store, Widget? child) {
              return MaterialApp(
                title: AppConfig.appName,
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: store.themeMode,
                initialRoute: AppRoutes.splash,
                onGenerateRoute: AppRouter.onGenerateRoute,
                builder: (BuildContext context, Widget? child) {
                  // Lock text scaling to a sane band so the onboarding and
                  // call layouts never break on aggressive accessibility
                  // settings.
                  final MediaQueryData mq = MediaQuery.of(context);
                  return MediaQuery(
                    data: mq.copyWith(
                      textScaler: mq.textScaler.clamp(
                        minScaleFactor: 0.85,
                        maxScaleFactor: 1.3,
                      ),
                    ),
                    child: CallOverlay(
                      child: child ?? const SizedBox.shrink(),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
