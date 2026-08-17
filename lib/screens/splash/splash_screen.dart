import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../config/app_config.dart';
import '../../routes/app_routes.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glow_background.dart';

/// Decides where a cold start lands: home if there is a valid session,
/// otherwise the welcome screen (or straight back into onboarding if the
/// user abandoned it partway through).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  bool _routed = false;

  @override
  void initState() {
    super.initState();
    final AuthBloc bloc = context.read<AuthBloc>()
      ..add(const AuthBootstrapRequested());

    // Belt and braces: if the bloc resolved before the listener below was
    // wired up, route from the current state instead of waiting forever.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final AuthFlowStatus status = bloc.state.status;
      if (status == AuthFlowStatus.authenticated ||
          status == AuthFlowStatus.unauthenticated) {
        _route(bloc.state);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _route(AuthState state) async {
    if (_routed) return;
    _routed = true;

    // Let the logo animation breathe before moving on.
    await Future<void>.delayed(AppDuration.splash);
    if (!mounted) return;

    if (state.isAuthenticated) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (Route<dynamic> route) => false,
      );
      return;
    }

    final AppStore store = AppStore.instance;
    final bool hasDraft = store.onboardingDraft.answeredCount > 0;

    Navigator.of(context).pushNamedAndRemoveUntil(
      hasDraft || store.hasSeenWelcome
          ? AppRoutes.onboarding
          : AppRoutes.welcome,
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (AuthState a, AuthState b) =>
          b.status == AuthFlowStatus.authenticated ||
          b.status == AuthFlowStatus.unauthenticated,
      listener: (BuildContext context, AuthState state) => _route(state),
      child: Scaffold(
        body: GlowBackground(
          alignment: Alignment.center,
          size: 520,
          child: Center(
            child: FadeTransition(
              opacity: _controller,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: Curves.easeOutBack,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      height: 96,
                      width: 96,
                      decoration: BoxDecoration(
                        gradient: AppColors.voltGradient,
                        borderRadius: AppRadius.rXl,
                      ),
                      child: Icon(
                        Icons.bolt_rounded,
                        size: 54,
                        color: palette.onAccent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      AppConfig.appName.toUpperCase(),
                      style: context.text.headlineMedium?.copyWith(
                        letterSpacing: 4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'TRAIN WITH INTENT',
                      style: context.text.labelSmall?.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
