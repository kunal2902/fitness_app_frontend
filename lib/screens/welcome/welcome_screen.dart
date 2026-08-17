import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/primary_button.dart';

/// First-run landing screen. Sets expectations before the questionnaire so
/// the nine questions feel purposeful rather than like a form wall.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const List<(IconData, String, String)> _highlights =
      <(IconData, String, String)>[
    (
      Icons.assignment_turned_in_rounded,
      'Built around you',
      'Nine quick questions shape your starting programme.',
    ),
    (
      Icons.trending_up_rounded,
      'Progress you can see',
      'Track every session and watch the numbers move.',
    ),
    (
      Icons.groups_rounded,
      'Train with others',
      'Share wins with a community that pushes back.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Scaffold(
      body: GlowBackground(
        alignment: const Alignment(0, -0.9),
        size: 480,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xxl,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 64,
                  width: 64,
                  decoration: BoxDecoration(
                    gradient: AppColors.voltGradient,
                    borderRadius: AppRadius.rLg,
                  ),
                  child: Icon(
                    Icons.bolt_rounded,
                    size: 36,
                    color: palette.onAccent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Your training\nstarts here.',
                  style: context.text.displayMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Tell us where you are today and we will build the plan '
                  'that gets you where you want to be.',
                  style: context.text.bodyLarge?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                for (final (IconData, String, String) item in _highlights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          height: 42,
                          width: 42,
                          decoration: BoxDecoration(
                            color: palette.surfaceAlt,
                            borderRadius: AppRadius.rSm,
                          ),
                          child: Icon(
                            item.$1,
                            size: AppSize.iconMd,
                            color: palette.accent,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(item.$2, style: context.text.titleMedium),
                              const SizedBox(height: 2),
                              Text(
                                item.$3,
                                style: context.text.bodySmall?.copyWith(
                                  color: palette.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                PrimaryButton(
                  label: 'Get started',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () async {
                    await AppStore.instance.markWelcomeSeen();
                    if (!context.mounted) return;
                    Navigator.of(context).pushNamed(AppRoutes.onboarding);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: GhostButton(
                    label: 'I already have an account',
                    onPressed: () =>
                        Navigator.of(context).pushNamed(AppRoutes.login),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
