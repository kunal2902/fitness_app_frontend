import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/tracked_activity.dart';
import '../../services/tracking_activity_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/tracking_format.dart';
import '../../widgets/activity_route_map.dart';
import '../../widgets/section_card.dart';

class ActivityDetailArguments {
  const ActivityDetailArguments({
    required this.activity,
    required this.repository,
  });

  final TrackedActivity activity;
  final TrackingActivityRepository repository;
}

class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({
    required this.initialActivity,
    required this.repository,
    this.forceMapFallback = false,
    super.key,
  });

  final TrackedActivity initialActivity;
  final TrackingActivityRepository repository;
  final bool forceMapFallback;

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  late TrackedActivity _activity = widget.initialActivity;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final TrackedActivity activity =
          await widget.repository.get(widget.initialActivity.id);
      if (mounted) setState(() => _activity = activity);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'The latest activity details could not be loaded.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Delete activity?'),
            content: const Text(
              'This removes the saved workout and its route. This cannot be undone.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.danger,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.repository.delete(_activity.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiException
            ? error.message
            : 'The activity could not be deleted.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.bg,
      appBar: AppBar(
        title: Text(_activity.type.label),
        actions: <Widget>[
          IconButton(
            tooltip: 'Delete activity',
            onPressed: _loading ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.huge,
              ),
              children: <Widget>[
                Text(
                  formatActivityDate(_activity.startedAt),
                  style: context.text.bodyMedium?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
                if (_loading) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  const LinearProgressIndicator(),
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  _InlineError(message: _error!, onRetry: _refresh),
                ],
                const SizedBox(height: AppSpacing.lg),
                ActivityRouteMap(
                  encodedPolyline: _activity.encodedPolyline,
                  splits: _activity.routeSplits,
                  height: 300,
                  forceFallback: widget.forceMapFallback,
                ),
                const SizedBox(height: AppSpacing.md),
                _SummaryGrid(activity: _activity),
                const SizedBox(height: AppSpacing.md),
                _SplitsCard(splits: _activity.splits),
                const SizedBox(height: AppSpacing.md),
                _ElevationCard(activity: _activity),
                const SizedBox(height: AppSpacing.md),
                _HeartRateCard(activity: _activity),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.activity});

  final TrackedActivity activity;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: CardStatTile(
                  label: 'Distance',
                  value: formatTrackingDistance(activity.distanceM),
                  icon: Icons.route_rounded,
                ),
              ),
              Expanded(
                child: CardStatTile(
                  label: 'Duration',
                  value: formatTrackingDuration(
                    Duration(seconds: activity.durationSec),
                  ),
                  icon: Icons.timer_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: CardStatTile(
                  label: 'Average pace',
                  value: formatTrackingPace(activity.avgPaceSecPerKm),
                  icon: Icons.speed_rounded,
                ),
              ),
              Expanded(
                child: CardStatTile(
                  label: 'Active energy',
                  value: '${activity.calories.round()} kcal',
                  icon: Icons.local_fire_department_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SplitsCard extends StatelessWidget {
  const _SplitsCard({required this.splits});

  final List<TrackedActivitySplit> splits;

  @override
  Widget build(BuildContext context) {
    if (splits.isEmpty) {
      return const SectionCard(
        title: 'Splits',
        child: _DetailEmpty(
          icon: Icons.view_list_outlined,
          message: 'No complete distance split was recorded.',
        ),
      );
    }
    return SectionCard(
      title: 'Splits',
      child: Column(
        children: <Widget>[
          const _SplitRow(
            label: 'KM',
            time: 'TIME',
            pace: 'PACE',
            header: true,
          ),
          const Divider(),
          for (int index = 0; index < splits.length; index += 1) ...<Widget>[
            _SplitRow(
              label: splits[index].isPartial
                  ? '${splits[index].index} partial'
                  : '${splits[index].index}',
              time: formatTrackingDuration(
                Duration(seconds: splits[index].durationSec),
              ),
              pace: formatTrackingPace(splits[index].paceSecPerKm),
            ),
            if (index != splits.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.label,
    required this.time,
    required this.pace,
    this.header = false,
  });

  final String label;
  final String time;
  final String pace;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = header
        ? context.text.labelSmall?.copyWith(color: context.palette.textTertiary)
        : context.text.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Expanded(child: Text(time, style: style, textAlign: TextAlign.right)),
          Expanded(child: Text(pace, style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _ElevationCard extends StatelessWidget {
  const _ElevationCard({required this.activity});

  final TrackedActivity activity;

  @override
  Widget build(BuildContext context) {
    final List<ActivityChartPoint> points = activity.elevationProfile;
    return SectionCard(
      title: 'Elevation',
      child: points.length >= 2
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ActivityLineChart(
                  points: points,
                  color: context.palette.accent,
                  semanticLabel: 'Elevation profile',
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${activity.elevationGainM?.round() ?? 0} m gained',
                  style: context.text.labelLarge,
                ),
              ],
            )
          : activity.elevationGainM != null
              ? _AggregateMetric(
                  icon: Icons.terrain_outlined,
                  value: '${activity.elevationGainM!.round()} m',
                  label:
                      'Elevation gain is available; a sampled profile was not stored for this activity.',
                )
              : const _DetailEmpty(
                  icon: Icons.terrain_outlined,
                  message: 'No reliable elevation readings were recorded.',
                ),
    );
  }
}

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({required this.activity});

  final TrackedActivity activity;

  @override
  Widget build(BuildContext context) {
    final List<ActivityChartPoint> points = activity.heartRateSeries;
    return SectionCard(
      title: 'Heart rate',
      child: points.length >= 2
          ? Column(
              children: <Widget>[
                _ActivityLineChart(
                  points: points,
                  color: context.palette.accent,
                  semanticLabel: 'Heart-rate chart',
                ),
                const SizedBox(height: AppSpacing.sm),
                _HrAggregates(activity: activity),
              ],
            )
          : activity.avgHr != null || activity.maxHr != null
              ? Column(
                  children: <Widget>[
                    _HrAggregates(activity: activity),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Only summary heart-rate values were stored for this activity.',
                      style: context.text.bodySmall?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                )
              : const _DetailEmpty(
                  icon: Icons.monitor_heart_outlined,
                  message:
                      'No heart-rate data was recorded. A compatible wearable is required.',
                ),
    );
  }
}

class _HrAggregates extends StatelessWidget {
  const _HrAggregates({required this.activity});

  final TrackedActivity activity;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _AggregateMetric(
            icon: Icons.favorite_outline_rounded,
            value: activity.avgHr == null ? '—' : '${activity.avgHr!.round()}',
            label: 'Average bpm',
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _AggregateMetric(
            icon: Icons.favorite_rounded,
            value: activity.maxHr == null ? '—' : '${activity.maxHr!.round()}',
            label: 'Maximum bpm',
          ),
        ),
      ],
    );
  }
}

class _ActivityLineChart extends StatelessWidget {
  const _ActivityLineChart({
    required this.points,
    required this.color,
    required this.semanticLabel,
  });

  final List<ActivityChartPoint> points;
  final Color color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey<String>('activity-chart-$semanticLabel'),
      image: true,
      label: semanticLabel,
      child: SizedBox(
        height: 150,
        width: double.infinity,
        child: CustomPaint(
          painter: _LineChartPainter(
            points: points,
            line: color,
            grid: context.palette.border,
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({
    required this.points,
    required this.line,
    required this.grid,
  });

  final List<ActivityChartPoint> points;
  final Color line;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (int index = 1; index < 4; index += 1) {
      final double y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final double minimum =
        points.map((ActivityChartPoint point) => point.value).reduce(math.min);
    final double maximum =
        points.map((ActivityChartPoint point) => point.value).reduce(math.max);
    final double span = math.max(maximum - minimum, 1);
    final Path path = Path();
    for (int index = 0; index < points.length; index += 1) {
      final ActivityChartPoint point = points[index];
      final double x = point.progress * size.width;
      final double y =
          size.height - ((point.value - minimum) / span * size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.line != line ||
      oldDelegate.grid != grid;
}

class _AggregateMetric extends StatelessWidget {
  const _AggregateMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.surfaceHigh,
        borderRadius: AppRadius.rMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: context.palette.accent),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: context.text.headlineSmall),
          Text(
            label,
            style: context.text.bodySmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailEmpty extends StatelessWidget {
  const _DetailEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: context.palette.textTertiary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: context.text.bodySmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            color: context.palette.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
