import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Energy consumed against the day's target.
///
/// The **number is the reading**; the ring is a secondary encoding of the
/// same value. That ordering matters — a ring alone tells you "roughly two
/// thirds" when what the user actually wants is "1,240 of 2,000". So the
/// figure sits in the middle at display size and the arc reinforces it.
///
/// One series, so no legend: the label under the number names it.
class KcalRing extends StatelessWidget {
  const KcalRing({
    required this.consumed,
    required this.target,
    this.diameter = 168,
    this.thickness = 12,
    super.key,
  });

  final double consumed;

  /// Null when no goal is set. The ring then shows an empty track and the
  /// number stands alone — an honest "here is what you ate, against
  /// nothing" rather than a full ring implying success.
  final double? target;

  final double diameter;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final double? goal = target;
    final bool hasGoal = goal != null && goal > 0;
    final double progress = hasGoal ? consumed / goal : 0;
    final bool isOver = hasGoal && consumed > goal;

    // Over target is a *state*, so it takes a status colour — and it is
    // never colour alone: the caption below spells out how far over.
    final Color arc = isOver ? AppColors.warning : palette.accent;

    final double remaining = hasGoal ? goal - consumed : 0;

    return SizedBox(
      height: diameter,
      width: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // Repaint boundary: the arc animates on every diary change while
          // the text below it does not.
          RepaintBoundary(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
              duration: AppDuration.slow,
              curve: Curves.easeOutCubic,
              builder: (BuildContext context, double value, Widget? child) {
                return CustomPaint(
                  size: Size.square(diameter),
                  painter: _RingPainter(
                    progress: value,
                    track: palette.border,
                    arc: arc,
                    thickness: thickness,
                  ),
                );
              },
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // FittedBox because the app allows up to 1.3x text scaling
              // and a four-digit kcal figure at that size overflows a
              // fixed-diameter ring.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: thickness * 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _round(consumed),
                    style: context.text.displaySmall?.copyWith(
                      color: palette.textPrimary,
                      height: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                hasGoal ? 'of ${_round(goal)} kcal' : 'kcal',
                style: context.text.bodySmall
                    ?.copyWith(color: palette.textTertiary),
              ),
              if (hasGoal) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  isOver
                      ? '${_round(remaining.abs())} over'
                      : '${_round(remaining)} left',
                  style: context.text.labelSmall?.copyWith(color: arc),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _round(double value) => value.round().toString();
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.track,
    required this.arc,
    required this.thickness,
  });

  final double progress;
  final Color track;
  final Color arc;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final double radius = (size.shortestSide - thickness) / 2;
    final Rect box = Rect.fromCircle(center: centre, radius: radius);

    final Paint trackPaint = Paint()
      ..color = track
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(centre, radius, trackPaint);

    if (progress <= 0) return;

    final Paint arcPaint = Paint()
      ..color = arc
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      // Rounded data-end, anchored at 12 o'clock.
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      box,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  // `covariant` is required: CustomPainter declares
  // `shouldRepaint(CustomPainter)`, and narrowing an override's parameter
  // without it is an invalid_override error, not a lint.
  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.arc != arc ||
      old.track != track ||
      old.thickness != thickness;
}
