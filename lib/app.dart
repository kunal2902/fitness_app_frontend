import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'blocs/auth/auth_bloc.dart';
import 'blocs/onboarding/onboarding_bloc.dart';
import 'config/app_config.dart';
import 'routes/app_router.dart';
import 'routes/app_routes.dart';
import 'services/api_client.dart';
import 'store/app_store.dart';
import 'theme/app_theme.dart';

/// Root widget. Wires up the three things every screen depends on:
/// the global [AppStore], the BLoCs, and the theme.
class FitnessApp extends StatefulWidget {
  const FitnessApp({super.key});

  @override
  State<FitnessApp> createState() => _FitnessAppState();
}

class _FitnessAppState extends State<FitnessApp> {
  final AuthBloc _authBloc = AuthBloc();

  @override
  void initState() {
    super.initState();
    // When a token refresh fails deep inside a request, the API client has
    // no BuildContext — it calls back here and the AuthBloc handles the
    // hard logout.
    ApiClient.instance.onSessionExpired =
        () => _authBloc.add(const AuthSessionExpired());
  }

  @override
  void dispose() {
    ApiClient.instance.onSessionExpired = null;
    _authBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppStore>.value(
      value: AppStore.instance,
      child: MultiBlocProvider(
        providers: <SingleChildWidget>[
          BlocProvider<AuthBloc>.value(value: _authBloc),
          BlocProvider<OnboardingBloc>(
            create: (_) => OnboardingBloc(),
          ),
        ],
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
                // Lock text scaling to a sane band so the onboarding
                // layouts never break on aggressive accessibility settings.
                final MediaQueryData mq = MediaQuery.of(context);
                return MediaQuery(
                  data: mq.copyWith(
                    textScaler: mq.textScaler.clamp(
                      minScaleFactor: 0.85,
                      maxScaleFactor: 1.3,
                    ),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
