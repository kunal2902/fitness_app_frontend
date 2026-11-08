import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../routes/app_routes.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';

/// First-run introduction to the training setup.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const List<(IconData, String, String)> _highlights = [
    (
      Icons.assignment_turned_in_outlined,
      'Built around you',
      'Nine quick questions shape your starting programme.',
    ),
    (
      Icons.trending_up_rounded,
      'Progress you can see',
      'Track every session and watch the numbers move.',
    ),
    (
      Icons.groups_outlined,
      'Train with others',
      'Share wins with a community that pushes back.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.lg,
                    ),
                    children: [
                      Row(
                        children: [
                          Container(
                            height: 40,
                            width: 40,
                            decoration: BoxDecoration(
                              border: Border.all(color: palette.borderStrong),
                              borderRadius: AppRadius.rSm,
                            ),
                            child: Icon(
                              Icons.bolt_rounded,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              AppConfig.appName.toUpperCase(),
                              style: context.text.labelSmall?.copyWith(
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      Text(
                        'Your training\nstarts here.',
                        style: context.text.displayLarge,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Tell us where you are today and we will build the plan '
                        'that gets you where you want to be.',
                        style: context.text.bodyLarge?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      for (final item in _highlights) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(item.$1, color: palette.textSecondary),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.$2,
                                      style: context.text.titleMedium,
                                    ),
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(
                                      item.$3,
                                      style: context.text.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.bg,
                    border: Border(top: BorderSide(color: palette.border)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.md,
                      AppSpacing.xl,
                      AppSpacing.xs,
                    ),
                    child: Column(
                      children: [
                        PrimaryButton(
                          label: 'Get started',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: () async {
                            await AppStore.instance.markWelcomeSeen();
                            if (!context.mounted) return;
                            Navigator.of(context)
                                .pushNamed(AppRoutes.onboarding);
                          },
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        GhostButton(
                          label: 'I already have an account',
                          onPressed: () =>
                              Navigator.of(context).pushNamed(AppRoutes.login),
                        ),
                      ],
                    ),
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
