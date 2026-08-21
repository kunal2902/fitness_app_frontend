import 'package:flutter/material.dart';

import '../models/enrolled_activity.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_card.dart';

/// Third card on the profile: the programmes the user is currently doing.
///
/// The empty state is the one most new users see, so it gets a real
/// illustration-weight treatment and a clear action rather than a bare
/// "nothing here" line.
class EnrolledActivitiesCard extends StatelessWidget {
  const EnrolledActivitiesCard({
    required this.activities,
    required this.isLoading,
    required this.onExplore,
    this.onOpenActivity,
    super.key,
  });

  final List<EnrolledActivity> activities;
  final bool isLoading;
  final VoidCallback onExplore;
  final void Function(EnrolledActivity activity)? onOpenActivity;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Your activities',
      trailing: activities.isEmpty
          ? null
          : TextButton(
              onPressed: onExplore,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              ),
              child: const Text('Explore'),
            ),
      child: isLoading
          ? const _LoadingRows()
          : activities.isEmpty
              ? _EmptyState(onExplore: onExplore)
              : Column(
                  children: <Widget>[
                    for (int i = 0; i < activities.length; i++) ...<Widget>[
                      _ActivityTile(
                        activity: activities[i],
                        onTap: onOpenActivity == null
                            ? null
                            : () => onOpenActivity!(activities[i]),
                      ),
                      if (i != activities.length - 1)
                        const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, this.onTap});

  final EnrolledActivity activity;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Material(
      color: palette.surfaceAlt,
      borderRadius: AppRadius.rMd,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          activity.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activity.coachName == null
                              ? activity.subtitle
                              : '${activity.subtitle} · ${activity.coachName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall
                              ?.copyWith(color: palette.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  if (activity.accentTag != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.14),
                        borderRadius: AppRadius.rXs,
                      ),
                      child: Text(
                        activity.accentTag!,
                        style: context.text.labelSmall?.copyWith(
                          color: palette.accent,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: activity.progress,
                        minHeight: 6,
                        backgroundColor: palette.border,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(palette.accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${activity.completedSessions}/${activity.totalSessions}',
                    style: context.text.labelMedium
                        ?.copyWith(color: palette.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Column(
      children: <Widget>[
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: 64,
          width: 64,
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.explore_rounded,
            size: 32,
            color: palette.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'No activities yet',
          style: context.text.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Join a programme or challenge and it will show up here with your '
          'progress.',
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(color: palette.textTertiary),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Explore activities',
          icon: Icons.arrow_forward_rounded,
          onPressed: onExplore,
        ),
      ],
    );
  }
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Column(
      children: List<Widget>.generate(
        2,
        (int i) => Container(
          height: 86,
          margin: EdgeInsets.only(bottom: i == 1 ? 0 : AppSpacing.sm),
          decoration: BoxDecoration(
            color: palette.surfaceAlt,
            borderRadius: AppRadius.rMd,
          ),
        ),
      ),
    );
  }
}
