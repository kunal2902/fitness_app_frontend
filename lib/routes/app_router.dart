import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/auth/account_details_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/main/main_shell_screen.dart';
import '../screens/onboarding/onboarding_flow_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/tracking/activity_detail_screen.dart';
import '../screens/training/exercise_detail_screen.dart';
import '../screens/training/exercise_library_screen.dart';
import '../screens/training/training_equipment_screen.dart';
import '../screens/welcome/welcome_screen.dart';
import '../services/training_repository.dart';
import '../store/app_store.dart';
import 'app_routes.dart';

/// Central route generator. Add new screens here — never build a
/// [MaterialPageRoute] inline in a widget.
class AppRouter {
  const AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return _page(const SplashScreen(), settings);
      case AppRoutes.welcome:
        return _page(const WelcomeScreen(), settings);
      case AppRoutes.onboarding:
        return _page(const OnboardingFlowScreen(), settings);
      case AppRoutes.accountDetails:
        return _page(const AccountDetailsScreen(), settings);
      case AppRoutes.login:
        return _page(const LoginScreen(), settings);
      case AppRoutes.home:
        // The five-tab shell. `arguments` may carry an int to open a
        // specific tab (e.g. deep-linking straight to Profile).
        final Object? args = settings.arguments;
        return _page(
          MainShellScreen(initialIndex: args is int ? args : 0),
          settings,
        );
      case AppRoutes.exerciseLibrary:
        final Object? args = settings.arguments;
        final ExerciseLibraryArguments filters =
            args is ExerciseLibraryArguments
                ? args
                : const ExerciseLibraryArguments();
        return _page(
          _TrainingRoute(
            buildScreen: (TrainingRepository repository) =>
                ExerciseLibraryScreen(
              repository: repository,
              initialMuscleId: filters.initialMuscleId,
              initialMuscleGroup: filters.initialMuscleGroup,
              initialEquipmentId: filters.initialEquipmentId,
              initialAvailableEquipment: filters.initialAvailableEquipment,
            ),
          ),
          settings,
        );
      case AppRoutes.exerciseDetail:
        final Object? args = settings.arguments;
        if (args is String &&
            RegExp(r'^[a-z][a-z0-9_]{1,79}$').hasMatch(args)) {
          return _page(
            _TrainingRoute(
              buildScreen: (TrainingRepository repository) =>
                  ExerciseDetailScreen(
                repository: repository,
                exerciseId: args,
              ),
            ),
            settings,
          );
        }
        return _page(
          const _TrainingMessage('That exercise is unavailable.'),
          settings,
        );
      case AppRoutes.trainingEquipment:
        return _page(
          _TrainingRoute(
            buildScreen: (TrainingRepository repository) =>
                TrainingEquipmentScreen(repository: repository),
          ),
          settings,
        );
      case AppRoutes.activityDetail:
        final Object? args = settings.arguments;
        if (args is ActivityDetailArguments) {
          return _page(
            ActivityDetailScreen(
              initialActivity: args.activity,
              repository: args.repository,
            ),
            settings,
          );
        }
        return _page(
          const Scaffold(
            body: Center(child: Text('That activity is unavailable.')),
          ),
          settings,
        );
      default:
        return _page(
          Scaffold(
            body: Center(child: Text('No route for ${settings.name}')),
          ),
          settings,
        );
    }
  }

  /// Slide-and-fade transition used app-wide.
  static Route<dynamic> _page(Widget child, RouteSettings settings) {
    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => child,
      transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _TrainingRoute extends StatefulWidget {
  const _TrainingRoute({required this.buildScreen});

  final Widget Function(TrainingRepository) buildScreen;

  @override
  State<_TrainingRoute> createState() => _TrainingRouteState();
}

class _TrainingRouteState extends State<_TrainingRoute> {
  late final String? _accountId;
  late final String? _sessionToken;
  late final ApiTrainingRepository _repository;

  @override
  void initState() {
    super.initState();
    final AppStore store = context.read<AppStore>();
    _accountId = store.isAuthenticated ? store.user?.id : null;
    // AppStore keeps the original session token while ApiClient rotates the
    // network token. Its value changes on a new sign-in to the same account.
    _sessionToken = store.accessToken;
    _repository = ApiTrainingRepository(
      isSessionCurrent: () => _matchesSession(store),
    );
  }

  bool _matchesSession(AppStore store) =>
      _accountId != null &&
      store.isAuthenticated &&
      store.user?.id == _accountId &&
      store.accessToken == _sessionToken;

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppStore store = context.watch<AppStore>();
    if (!_matchesSession(store)) {
      _repository.dispose();
      return const _TrainingMessage('Sign in to open training.');
    }
    return widget.buildScreen(_repository);
  }
}

class _TrainingMessage extends StatelessWidget {
  const _TrainingMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Training')),
        body: Center(child: Text(message, textAlign: TextAlign.center)),
      );
}
