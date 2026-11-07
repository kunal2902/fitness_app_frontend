import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/auth/auth_bloc.dart';
import '../routes/app_routes.dart';

/// Gets the user out of the signed-in app when the session dies under them.
///
/// Voluntary sign-out is navigated by the screen that asked for it. An
/// expiry has no such screen: the refresh failed deep inside whatever
/// request happened to be in flight, so nothing on screen knows to move.
/// Without this the user keeps looking at the signed-in shell while every
/// call returns 401, and only restarting the app gets them out.
///
/// It sits above [MaterialApp] — which is why it navigates through a
/// [navigatorKey] rather than `Navigator.of(context)`, as the context here
/// is above the navigator it needs to drive.
class AuthSessionGate extends StatelessWidget {
  const AuthSessionGate({
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// Login is pushed on top of Welcome rather than replacing the stack with
  /// Login alone: a root Login has nothing behind it, so its back button
  /// would pop the last route and leave a blank screen.
  static void returnToSignIn(GlobalKey<NavigatorState> navigatorKey) {
    final NavigatorState? navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushNamedAndRemoveUntil(
      AppRoutes.welcome,
      (Route<dynamic> route) => false,
    );
    navigator.pushNamed(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (AuthState before, AuthState after) => after.sessionExpired,
      listener: (BuildContext context, AuthState state) =>
          returnToSignIn(navigatorKey),
      child: child,
    );
  }
}
