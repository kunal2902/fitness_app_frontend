import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The oversized readout that sits above the ruler on the height and
/// weight questions — e.g. **172** `cm`.
class MeasurementDisplayCard extends StatelessWidget {
  const MeasurementDisplayCard({
    required this.value,
    required this.unitLabel,
    this.caption,
    super.key,
  });

  /// Already formatted for the active unit (`172`, `5'8`, `70.5`, `155`).
  final String value;
  final String unitLabel;

  /// Optional secondary line, e.g. the same value in the other unit.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              value,
              style: context.text.displayLarge?.copyWith(
                fontSize: 64,
                height: 1,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              unitLabel,
              style: context.text.headlineSmall?.copyWith(
                color: palette.accent,
              ),
            ),
          ],
        ),
        if (caption != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            caption!,
            style: context.text.bodySmall?.copyWith(
              color: palette.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact stat chip used on the review/summary surface.
class StatChip extends StatelessWidget {
  const StatChip({
    required this.label,
    required this.value,
    this.icon,
    super.key,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: AppRadius.rPill,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: palette.accent),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            '$label ',
            style: context.text.bodySmall?.copyWith(
              color: palette.textTertiary,
            ),
          ),
          Text(
            value,
            style: context.text.bodySmall?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
