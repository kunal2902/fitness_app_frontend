import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The flat page canvas. Existing page wrappers keep their constructor.
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
  Widget build(BuildContext context) =>
      ColoredBox(color: context.palette.bg, child: child);
}
