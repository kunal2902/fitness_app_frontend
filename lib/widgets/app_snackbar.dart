import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum SnackKind { info, success, error }

/// One-liner feedback. Always call through this rather than building a
/// [SnackBar] inline, so tone and placement stay consistent.
class AppSnackbar {
  const AppSnackbar._();

  static void show(
    BuildContext context,
    String message, {
    SnackKind kind = SnackKind.info,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final AppPalette palette = context.palette;
    final (Color accent, IconData icon) = switch (kind) {
      SnackKind.success => (AppColors.success, Icons.check_circle_rounded),
      SnackKind.error => (AppColors.danger, Icons.error_rounded),
      SnackKind.info => (palette.accent, Icons.info_rounded),
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          backgroundColor: palette.surfaceHigh,
          content: Row(
            children: <Widget>[
              Icon(icon, color: accent, size: AppSize.iconMd),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: context.text.bodyMedium?.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          action: (actionLabel != null && onAction != null)
              ? SnackBarAction(
                  label: actionLabel,
                  textColor: palette.accent,
                  onPressed: onAction,
                )
              : null,
        ),
      );
  }

  static void success(BuildContext context, String message) =>
      show(context, message, kind: SnackKind.success);

  static void error(BuildContext context, String message) =>
      show(context, message, kind: SnackKind.error);
}
