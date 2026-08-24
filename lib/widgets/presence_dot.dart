import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Online indicator.
///
/// Sits on the avatar's corner with a ring in the surface colour, so it
/// reads as a separate object rather than a smudge on the photo.
class PresenceDot extends StatelessWidget {
  const PresenceDot({
    required this.isOnline,
    this.size = 14,
    this.ringColor,
    super.key,
  });

  final bool isOnline;
  final double size;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return AnimatedContainer(
      duration: AppDuration.normal,
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOnline ? AppColors.success : palette.textTertiary,
        border: Border.all(
          color: ringColor ?? palette.surface,
          width: size * 0.2,
        ),
      ),
    );
  }
}

/// Text form — "Online", "Last seen 3h ago".
class PresenceLabel extends StatelessWidget {
  const PresenceLabel({
    required this.isOnline,
    required this.label,
    super.key,
  });

  final bool isOnline;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PresenceDot(isOnline: isOnline, size: 8, ringColor: Colors.transparent),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(
              color: isOnline ? AppColors.success : palette.textTertiary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
