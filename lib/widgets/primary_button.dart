import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's main call-to-action.
///
/// Uses an inverted fill and shows a progress indicator while [isLoading].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final bool enabled = onPressed != null && !isLoading;

    final Widget child = isLoading
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: palette.textSecondary,
              semanticsLabel: '$label, loading',
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              if (icon != null) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                Icon(icon, size: AppSize.iconSm),
              ],
            ],
          );

    final Widget button = ElevatedButton(
      onPressed: enabled ? onPressed : null,
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Low-emphasis action — "Skip", "Maybe later", "Back".
class GhostButton extends StatelessWidget {
  const GhostButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: context.palette.textSecondary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: AppSize.iconSm),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

/// Circular icon button used for the back chevron in the onboarding header.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: palette.surfaceAlt,
        shape: CircleBorder(side: BorderSide(color: palette.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 44,
            width: 44,
            child: Icon(
              icon,
              size: AppSize.iconMd,
              color: onPressed == null
                  ? palette.textTertiary
                  : palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
