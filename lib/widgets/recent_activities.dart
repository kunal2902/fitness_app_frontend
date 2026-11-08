import 'package:flutter/material.dart';

import '../blocs/tracking/activity_feed_cubit.dart';
import '../models/tracked_activity.dart';
import '../theme/app_theme.dart';
import '../utils/tracking_format.dart';
import 'activity_route_map.dart';
import 'section_card.dart';

class RecentActivities extends StatelessWidget {
  const RecentActivities({
    required this.state,
    required this.onRetry,
    required this.onOpen,
    super.key,
  });

  final ActivityFeedState state;
  final VoidCallback onRetry;
  final ValueChanged<TrackedActivity> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Recent activities', style: context.text.titleLarge),
            ),
            if (state.activities.isNotEmpty)
              IconButton(
                key: const ValueKey<String>('activities-refresh'),
                tooltip: 'Refresh activities',
                onPressed: state.loading ? null : onRetry,
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (state.loading && state.activities.isEmpty)
          const _FeedMessage(
            icon: Icons.route_outlined,
            title: 'Loading activities',
            message: 'Bringing in your latest saved workouts.',
            loading: true,
          )
        else if (state.error != null && state.activities.isEmpty)
          _FeedMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Activities are unavailable',
            message: state.error!,
            actionLabel: 'Try again',
            onAction: onRetry,
          )
        else if (state.activities.isEmpty)
          const _FeedMessage(
            icon: Icons.directions_run_rounded,
            title: 'No activities yet',
            message:
                'Finish your first outdoor workout and its route will appear here.',
          )
        else ...<Widget>[
          for (int index = 0; index < state.activities.length; index += 1) ...[
            _ActivityCard(
              activity: state.activities[index],
              onTap: () => onOpen(state.activities[index]),
            ),
            if (index != state.activities.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
          if (state.error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Showing saved results. ${state.error}',
              style: context.text.bodySmall?.copyWith(
                color: context.palette.textTertiary,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity, required this.onTap});

  final TrackedActivity activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          '${activity.type.label}, ${formatTrackingDistance(activity.distanceM)}, ${formatActivityDate(activity.startedAt)}',
      child: InkWell(
        key: ValueKey<String>('activity-${activity.id}'),
        onTap: onTap,
        borderRadius: AppRadius.rMd,
        child: SectionCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ActivityRouteThumbnail(
                thumbnailUrl: activity.thumbnailUrl,
                encodedPolyline: activity.encodedPolyline,
                splits: activity.routeSplits,
                height: 132,
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            activity.type.label,
                            style: context.text.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            formatActivityDate(activity.startedAt),
                            style: context.text.bodySmall?.copyWith(
                              color: context.palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _CompactStat(
                      value: formatTrackingDistance(activity.distanceM),
                      label: 'Distance',
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _CompactStat(
                      value: formatTrackingPace(activity.avgPaceSecPerKm),
                      label: 'Pace',
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactStat extends StatelessWidget {
  const _CompactStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(value, style: context.text.labelLarge),
        Text(
          label,
          style: context.text.labelSmall?.copyWith(
            color: context.palette.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _FeedMessage extends StatelessWidget {
  const _FeedMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (loading)
            const SizedBox.square(
              dimension: AppSize.iconLg,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, color: context.palette.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: context.text.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  message,
                  style: context.text.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
                if (actionLabel != null && onAction != null)
                  TextButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
