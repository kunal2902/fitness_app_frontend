import 'package:flutter/material.dart';

import '../models/workout_day.dart';
import '../theme/app_theme.dart';

/// Current and all-time-best streaks.
///
/// Sits directly under the calendar inside the same card, because the two
/// answer the same question — "how consistent have I been?" — and reading
/// them together is what makes either one meaningful.
class StreakCard extends StatelessWidget {
  const StreakCard({required this.streak, super.key});

  final StreakStats streak;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _StreakStat(
                  icon: Icons.local_fire_department_rounded,
                  tint: AppColors.ember,
                  value: streak.currentDays,
                  label: 'Current streak',
                ),
              ),
              Container(
                width: 1,
                height: 52,
                color: palette.border,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              Expanded(
                child: _StreakStat(
                  icon: Icons.emoji_events_rounded,
                  tint: palette.accent,
                  value: streak.longestDays,
                  label: 'Longest streak',
                ),
              ),
            ],
          ),
          if (streak.totalWorkouts > 0 || streak.isAtRisk) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Divider(color: palette.border, height: 1),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Icon(
                  streak.isAtRisk
                      ? Icons.bolt_rounded
                      : Icons.check_circle_rounded,
                  size: AppSize.iconSm,
                  color: streak.isAtRisk ? AppColors.warning : palette.accent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    streak.isAtRisk
                        ? 'Train today to keep your streak alive.'
                        : '${streak.totalWorkouts} sessions logged so far.',
                    style: context.text.bodySmall?.copyWith(
                      color: streak.isAtRisk
                          ? AppColors.warning
                          : palette.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StreakStat extends StatelessWidget {
  const _StreakStat({
    required this.icon,
    required this.tint,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color tint;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Three digits at a 1.3 text scale overflows a half-width column
        // on a 360dp screen, so shrink rather than clip.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Icon(icon, size: AppSize.iconMd, color: tint),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '$value',
                style: context.text.displaySmall?.copyWith(
                  color: palette.textPrimary,
                  height: 1,
                ),
              ),
              const SizedBox(width: 3),
              // Counts completed sessions, not calendar days — rest days
              // are part of the plan and must not break a streak.
              Text(
                value == 1 ? 'session' : 'sessions',
                style: context.text.bodySmall
                    ?.copyWith(color: palette.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: context.text.labelSmall
              ?.copyWith(color: palette.textTertiary, fontSize: 10),
        ),
      ],
    );
  }
}
