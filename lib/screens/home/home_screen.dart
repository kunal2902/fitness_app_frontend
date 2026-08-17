import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../cards/measurement_display_card.dart';
import '../../models/enums.dart';
import '../../models/onboarding_data.dart';
import '../../models/user_model.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../utils/unit_converter.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/primary_button.dart';

/// Phase-1 placeholder. It exists to prove the signup round-trip worked:
/// everything shown here came back from the server, not from local state.
///
/// Phase 2 replaces this with the real dashboard (today's workout, streak,
/// weekly plan, community feed).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return BlocBuilder<AuthBloc, AuthState>(
      builder: (BuildContext context, AuthState state) {
        final UserModel? user = state.user;
        final OnboardingData? profile = user?.fitnessProfile;

        return Scaffold(
          body: GlowBackground(
            alignment: const Alignment(0, -0.95),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        height: 52,
                        width: 52,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          gradient: AppColors.voltGradient,
                          borderRadius: AppRadius.rMd,
                        ),
                        child: Text(
                          user?.initials ?? '?',
                          style: context.text.titleLarge
                              ?.copyWith(color: palette.onAccent),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'WELCOME',
                              style: context.text.labelSmall
                                  ?.copyWith(color: palette.textTertiary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.firstName ?? 'Athlete',
                              style: context.text.headlineMedium,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sign out',
                        onPressed: () {
                          context
                              .read<AuthBloc>()
                              .add(const AuthLogoutRequested());
                          Navigator.of(context).pushNamedAndRemoveUntil(
                            AppRoutes.welcome,
                            (Route<dynamic> route) => false,
                          );
                        },
                        icon: const Icon(Icons.logout_rounded),
                        color: palette.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  if (profile != null) _ProfileSummary(profile: profile),

                  const SizedBox(height: AppSpacing.xl),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      gradient: palette.cardGradient,
                      borderRadius: AppRadius.rLg,
                      border: Border.all(color: palette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.construction_rounded,
                          color: palette.accent,
                          size: AppSize.iconLg,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text('Phase 2 lands here', style: context.text.titleLarge),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Workouts, weekly plans, tracking, coaching calls '
                          'and the community feed plug into this screen next.',
                          style: context.text.bodyMedium
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const PrimaryButton(
                    label: "Start today's session",
                    onPressed: null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.profile});

  final OnboardingData profile;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final double? bmi = profile.bmi;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'YOUR PROFILE',
            style: context.text.labelSmall?.copyWith(color: palette.accent),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              if (profile.gender != null)
                StatChip(label: 'Gender', value: profile.gender!.label),
              if (profile.heightCm != null)
                StatChip(
                  label: 'Height',
                  value: UnitConverter.formatHeight(
                    profile.heightCm!,
                    profile.heightUnit,
                  ),
                ),
              if (profile.weightKg != null)
                StatChip(
                  label: 'Weight',
                  value: UnitConverter.formatWeight(
                    profile.weightKg!,
                    profile.weightUnit,
                  ),
                ),
              if (bmi != null)
                StatChip(label: 'BMI', value: bmi.toStringAsFixed(1)),
              if (profile.fitnessLevel != null)
                StatChip(
                  label: 'Level',
                  value: profile.fitnessLevel!.label,
                  icon: Icons.bolt_rounded,
                ),
            ],
          ),
          if (profile.goals.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              'GOALS',
              style: context.text.labelSmall
                  ?.copyWith(color: palette.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: profile.goals
                  .map(
                    (FitnessGoal g) => StatChip(
                      label: '',
                      value: g.label,
                      icon: g.icon,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Divider(color: palette.border),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'BEST SETS',
            style:
                context.text.labelSmall?.copyWith(color: palette.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              if (profile.maxPullUps != null)
                StatChip(label: 'Pull-ups', value: profile.maxPullUps!.label),
              if (profile.maxPushUps != null)
                StatChip(label: 'Push-ups', value: profile.maxPushUps!.label),
              if (profile.maxSquats != null)
                StatChip(label: 'Squats', value: profile.maxSquats!.label),
              if (profile.maxDips != null)
                StatChip(label: 'Dips', value: profile.maxDips!.label),
            ],
          ),
        ],
      ),
    );
  }
}
