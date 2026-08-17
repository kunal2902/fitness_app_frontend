import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Soft accent glow behind onboarding content. Purely decorative — keeps
/// the near-black canvas from feeling flat without competing with the UI.
class GlowBackground extends StatelessWidget {
  const GlowBackground({
    required this.child,
    this.alignment = const Alignment(0, -0.75),
    this.size = 420,
    super.key,
  });

  final Widget child;
  final Alignment alignment;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: alignment,
              child: Container(
                height: size,
                width: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      palette.accent.withValues(alpha: 0.16),
                      palette.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
