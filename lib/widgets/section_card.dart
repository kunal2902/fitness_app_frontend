import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A matte surface for sections across the app.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.gradient = false,
    super.key,
  });

  final Widget child;

  /// Small all-caps eyebrow above the content.
  final String? title;

  /// Action aligned to the right of [title] — a toggle, a button.
  final Widget? trailing;

  final EdgeInsets padding;

  /// Give an emphasized section a slightly raised surface.
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient ? palette.surfaceAlt : palette.surface,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title!.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall
                        ?.copyWith(color: palette.textSecondary),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          child,
        ],
      ),
    );
  }
}

/// Label/value row used inside cards.
class CardStatTile extends StatelessWidget {
  const CardStatTile({
    required this.label,
    required this.value,
    this.icon,
    this.accent,
    super.key,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color tint = accent ?? palette.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: AppSize.iconSm, color: tint),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall
                    ?.copyWith(color: palette.textTertiary),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: context.text.headlineMedium?.copyWith(color: tint),
        ),
      ],
    );
  }
}
