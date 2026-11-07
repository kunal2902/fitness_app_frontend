import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../blocs/tracking/health_sync_cubit.dart';
import '../models/health_models.dart';
import '../theme/app_theme.dart';
import 'section_card.dart';

class HealthConnectCard extends StatelessWidget {
  const HealthConnectCard({
    required this.state,
    required this.onConnect,
    required this.onInstall,
    required this.onOpenSettings,
    required this.onRefresh,
    super.key,
  });

  final HealthSyncState state;
  final VoidCallback onConnect;
  final VoidCallback onInstall;
  final VoidCallback onOpenSettings;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (state.availability == HealthProviderAvailability.checking) {
      return const _HealthMessage(
        icon: Icons.health_and_safety_outlined,
        title: 'Checking device health',
        message:
            'Fitness App is checking whether a supported health provider is available.',
      );
    }
    if (state.availability == HealthProviderAvailability.installRequired) {
      return _HealthMessage(
        icon: Icons.health_and_safety_outlined,
        title: 'Health Connect is needed',
        message:
            'Install or update Health Connect to bring steps and health metrics into Fitness App.',
        buttonKey: const ValueKey<String>('health-install'),
        buttonLabel: 'Install Health Connect',
        busy: state.busy,
        onPressed: onInstall,
      );
    }
    if (state.availability == HealthProviderAvailability.unsupported) {
      return const _HealthMessage(
        icon: Icons.devices_other_rounded,
        title: 'Device health is unavailable',
        message:
            'Health sync requires Health Connect on Android 9 or later, or Apple Health on iOS 15 or later.',
      );
    }
    if (state.access == HealthAccessStatus.notRequested ||
        state.access == HealthAccessStatus.unknown) {
      return _HealthRationale(
        busy: state.busy,
        onConnect: onConnect,
        bmi: state.bmi,
      );
    }
    if (state.access == HealthAccessStatus.denied) {
      return _HealthMessage(
        icon: Icons.lock_outline_rounded,
        title: 'Health access is off',
        message:
            'Nothing is read until you allow it. Reconnect here, or review Fitness App in your health provider settings.',
        buttonKey: const ValueKey<String>('health-retry'),
        buttonLabel: 'Try again',
        secondaryLabel: 'Open health settings',
        busy: state.busy,
        onPressed: onConnect,
        onSecondaryPressed: onOpenSettings,
      );
    }
    return _ConnectedHealth(
      state: state,
      onRefresh: onRefresh,
    );
  }
}

class _HealthRationale extends StatelessWidget {
  const _HealthRationale({
    required this.busy,
    required this.onConnect,
    required this.bmi,
  });

  final bool busy;
  final VoidCallback onConnect;
  final double? bmi;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Connect device health',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Bring your steps, active calories, weight and supported wearable readings into one daily view.',
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _HealthFact(
            icon: Icons.visibility_outlined,
            text: 'Read-only access — Fitness App never edits device records.',
          ),
          const _HealthFact(
            icon: Icons.cloud_upload_outlined,
            text:
                'Only daily totals are uploaded, not individual sensor events.',
          ),
          const _HealthFact(
            icon: Icons.watch_outlined,
            text:
                'Heart rate and SpO₂ need a compatible wearable. VO₂ max sync is not available yet.',
          ),
          if (bmi != null)
            _HealthFact(
              icon: Icons.straighten_rounded,
              text:
                  'BMI ${bmi!.toStringAsFixed(1)} is calculated from your onboarding height and weight.',
            )
          else
            const _HealthFact(
              icon: Icons.straighten_rounded,
              text: 'Add height and weight to your profile to calculate BMI.',
            ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey<String>('health-connect'),
              onPressed: busy ? null : onConnect,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_link_rounded),
              label: const Text('Continue to permissions'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectedHealth extends StatelessWidget {
  const _ConnectedHealth({required this.state, required this.onRefresh});

  final HealthSyncState state;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final HealthDailySummary? today = state.result?.today;
    return SectionCard(
      title: 'Device health',
      trailing: IconButton(
        key: const ValueKey<String>('health-refresh'),
        tooltip: 'Sync now',
        onPressed: state.busy ? null : onRefresh,
        icon: state.busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.sync_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (today == null || !today.hasAnyData)
            const _EmptyMetric(
              icon: Icons.directions_walk_rounded,
              title: 'No health readings yet',
              message:
                  'Carry your phone for steps, then let your health provider finish syncing and tap refresh.',
            )
          else
            _TodayActivityRing(
              steps: today.steps,
              activeKcal: today.activeKcal,
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _MetricOrEmpty(
                  label: 'Resting HR',
                  value: today?.restingHr,
                  unit: 'bpm',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MetricOrEmpty(
                  label: 'SpO₂',
                  value: today?.spo2,
                  unit: '%',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: _MetricOrEmpty(
                  label: 'BMI',
                  value: state.bmi,
                  unit: 'profile',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: _MetricOrEmpty(
                  label: 'VO₂ max',
                  value: null,
                  unit: 'coming later',
                ),
              ),
            ],
          ),
          if (today == null || !today.hasWearableData) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            const _EmptyMetric(
              icon: Icons.watch_outlined,
              title: 'No wearable readings',
              message:
                  'This is expected without a compatible watch or band. Phone-based steps and calories still work.',
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            _syncCaption(state.result),
            style: context.text.bodySmall?.copyWith(
              color: context.palette.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  String _syncCaption(HealthSyncResult? result) {
    if (result == null) return 'Waiting for the first sync.';
    final DateTime local = result.checkedAt.toLocal();
    final String minute = local.minute.toString().padLeft(2, '0');
    final String background = result.backgroundEnabled
        ? 'Background sync is on.'
        : 'Background access is off; sync happens while the app is open.';
    return 'Checked ${local.hour}:$minute. $background';
  }
}

class _TodayActivityRing extends StatelessWidget {
  const _TodayActivityRing({required this.steps, required this.activeKcal});

  static const int _stepGuide = 10000;
  static const double _energyGuide = 500;

  final int steps;
  final double activeKcal;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Semantics(
      label:
          'Today, $steps steps and ${activeKcal.round()} active kilocalories',
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: 148,
            child: CustomPaint(
              painter: _ActivityRingPainter(
                stepProgress: steps / _stepGuide,
                energyProgress: activeKcal / _energyGuide,
                track: palette.border,
                steps: palette.accent,
                energy: AppColors.ember,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '$steps',
                      style: context.text.headlineMedium,
                    ),
                    Text(
                      'steps today',
                      style: context.text.labelSmall?.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _RingLegend(
                  color: palette.accent,
                  value: '$steps',
                  label: 'Steps',
                ),
                const SizedBox(height: AppSpacing.md),
                _RingLegend(
                  color: AppColors.ember,
                  value: '${activeKcal.round()} kcal',
                  label: 'Active energy',
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Rings use daily guides of 10,000 steps and 500 active kcal.',
                  style: context.text.bodySmall?.copyWith(
                    color: palette.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingLegend extends StatelessWidget {
  const _RingLegend({
    required this.color,
    required this.value,
    required this.label,
  });

  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: AppSpacing.xs,
          height: AppSpacing.xs,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(value, style: context.text.titleMedium),
              Text(
                label,
                style: context.text.bodySmall?.copyWith(
                  color: context.palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityRingPainter extends CustomPainter {
  const _ActivityRingPainter({
    required this.stepProgress,
    required this.energyProgress,
    required this.track,
    required this.steps,
    required this.energy,
  });

  final double stepProgress;
  final double energyProgress;
  final Color track;
  final Color steps;
  final Color energy;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    _drawRing(
      canvas,
      center: center,
      radius: size.shortestSide / 2 - 8,
      progress: stepProgress,
      color: steps,
    );
    _drawRing(
      canvas,
      center: center,
      radius: size.shortestSide / 2 - 25,
      progress: energyProgress,
      color: energy,
    );
  }

  void _drawRing(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double progress,
    required Color color,
  }) {
    final Rect bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..strokeWidth = 9
        ..style = PaintingStyle.stroke,
    );
    if (!progress.isFinite || progress <= 0) return;
    canvas.drawArc(
      bounds,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ActivityRingPainter oldDelegate) =>
      oldDelegate.stepProgress != stepProgress ||
      oldDelegate.energyProgress != energyProgress ||
      oldDelegate.track != track ||
      oldDelegate.steps != steps ||
      oldDelegate.energy != energy;
}

class _MetricValue extends StatelessWidget {
  const _MetricValue({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: context.text.labelSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(value, style: context.text.headlineSmall),
          Text(
            unit,
            style: context.text.bodySmall?.copyWith(
              color: context.palette.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricOrEmpty extends StatelessWidget {
  const _MetricOrEmpty({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final double? value;
  final String unit;

  @override
  Widget build(BuildContext context) => _MetricValue(
        label: label,
        value: value == null ? '—' : value!.toStringAsFixed(1),
        unit: value == null ? unit : unit,
      );
}

class _EmptyMetric extends StatelessWidget {
  const _EmptyMetric({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: context.palette.accent, size: AppSize.iconSm),
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
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthFact extends StatelessWidget {
  const _HealthFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: AppSize.iconSm, color: context.palette.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: context.text.bodySmall)),
        ],
      ),
    );
  }
}

class _HealthMessage extends StatelessWidget {
  const _HealthMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.buttonKey,
    this.buttonLabel,
    this.secondaryLabel,
    this.busy = false,
    this.onPressed,
    this.onSecondaryPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final Key? buttonKey;
  final String? buttonLabel;
  final String? secondaryLabel;
  final bool busy;
  final VoidCallback? onPressed;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: <Widget>[
          Icon(icon, size: 38, color: context.palette.accent),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: context.text.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
              height: 1.45,
            ),
          ),
          if (buttonLabel != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: buttonKey,
                onPressed: busy ? null : onPressed,
                child: Text(buttonLabel!),
              ),
            ),
          ],
          if (secondaryLabel != null)
            TextButton(
              onPressed: busy ? null : onSecondaryPressed,
              child: Text(secondaryLabel!),
            ),
        ],
      ),
    );
  }
}
