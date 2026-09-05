import 'package:flutter/material.dart';

import '../models/nutrition_models.dart';
import '../theme/app_theme.dart';
import '../theme/macro_palette.dart';

/// One macronutrient as a labelled meter.
///
/// Identity is carried by the **text**, not the colour: every row says
/// "Protein" and "62 / 150 g" in ink tokens, and the colour band beside it
/// reinforces. That is what makes the group readable without a legend, and
/// readable at all to someone who cannot separate the three hues.
class MacroMeter extends StatelessWidget {
  const MacroMeter({
    required this.kind,
    required this.consumed,
    this.target,
    this.showLabel = true,
    super.key,
  });

  final MacroKind kind;
  final double consumed;

  /// Null when no goal is set — the meter then shows the amount eaten with
  /// an empty track rather than pretending to be complete.
  final double? target;

  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color tint = MacroPalette.of(kind);
    final double? goal = target;
    final bool hasGoal = goal != null && goal > 0;
    final double ratio = hasGoal ? (consumed / goal).clamp(0.0, 1.0) : 0;
    final bool isOver = hasGoal && consumed > goal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showLabel) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  kind.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall
                      ?.copyWith(color: palette.textSecondary),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                hasGoal
                    ? '${_g(consumed)} / ${_g(goal)} g'
                    : '${_g(consumed)} g',
                style: context.text.bodySmall?.copyWith(
                  // Values wear ink, never the series colour.
                  color: isOver ? AppColors.warning : palette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
        ],
        _MeterTrack(ratio: ratio, tint: tint, track: palette.surfaceHigh),
      ],
    );
  }

  /// Grams to a sensible precision — whole numbers above 10, one decimal
  /// below, and never a trailing ".0".
  static String _g(double value) {
    if (value >= 10 || value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value
        .toStringAsFixed(1)
        .replaceAll(RegExp(r'\.0$'), '');
  }
}

class _MeterTrack extends StatelessWidget {
  const _MeterTrack({
    required this.ratio,
    required this.tint,
    required this.track,
  });

  final double ratio;
  final Color tint;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: ColoredBox(color: track)),
            // FractionallySizedBox rather than a measured width: the card
            // is inside a scroll view whose width is only known at layout.
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: ratio),
              duration: AppDuration.normal,
              curve: Curves.easeOut,
              builder: (BuildContext context, double value, Widget? child) {
                return FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The three meters as one block, in the fixed categorical order.
class MacroMeterGroup extends StatelessWidget {
  const MacroMeterGroup({
    required this.consumed,
    this.target,
    super.key,
  });

  final Macros consumed;
  final Macros? target;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final MacroKind kind in MacroPalette.order) ...<Widget>[
          if (kind != MacroPalette.order.first)
            const SizedBox(height: AppSpacing.sm),
          MacroMeter(
            kind: kind,
            consumed: kind.gramsIn(consumed),
            target: target == null ? null : kind.gramsIn(target!),
          ),
        ],
      ],
    );
  }
}

/// A compact split bar showing where a single food's energy comes from.
///
/// Used on the portion picker, where the question is "what is this made
/// of" rather than "how much of my day is left" — proportion, not progress.
class MacroSplitBar extends StatelessWidget {
  const MacroSplitBar({required this.macros, super.key});

  final Macros macros;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final ({double protein, double carbs, double fat}) split =
        macros.energySplit;
    final List<({MacroKind kind, double share})> parts =
        <({MacroKind kind, double share})>[
      (kind: MacroKind.protein, share: split.protein),
      (kind: MacroKind.carbs, share: split.carbs),
      (kind: MacroKind.fat, share: split.fat),
    ];

    if (split.protein + split.carbs + split.fat <= 0) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 8,
          child: Row(
            children: <Widget>[
              for (final (int i, ({MacroKind kind, double share}) part)
                  in parts.indexed)
                if (part.share > 0) ...<Widget>[
                  // A 2px surface gap between segments, so two adjacent
                  // fills never read as one longer bar.
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: (part.share * 1000).round().clamp(1, 1000),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: MacroPalette.of(part.kind),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xxs,
          children: <Widget>[
            for (final ({MacroKind kind, double share}) part in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    height: 8,
                    width: 8,
                    decoration: BoxDecoration(
                      color: MacroPalette.of(part.kind),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    '${part.kind.label} '
                    '${(part.share * 100).round()}%',
                    style: context.text.bodySmall
                        ?.copyWith(color: palette.textTertiary),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
