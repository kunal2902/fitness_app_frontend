import 'package:flutter/material.dart';

import '../screens/auth/account_details_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/main/main_shell_screen.dart';
import '../screens/onboarding/onboarding_flow_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/welcome/welcome_screen.dart';
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
