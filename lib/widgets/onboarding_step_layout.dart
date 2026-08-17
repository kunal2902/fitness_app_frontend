import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared chrome for every one of the 9 questions: an eyebrow counter, a
/// headline, an optional supporting line, then the question's own content.
///
/// Keeping this in one place is what makes the flow feel like a single
/// screen with changing content rather than nine different screens.
class OnboardingStepLayout extends StatelessWidget {
  const OnboardingStepLayout({
    required this.stepNumber,
    required this.totalSteps,
    required this.title,
    required this.child,
    this.subtitle,
    this.scrollable = false,
    this.contentAlignment = CrossAxisAlignment.stretch,
    super.key,
  });

  final int stepNumber;
  final int totalSteps;
  final String title;
  final String? subtitle;
  final Widget child;

  /// Set for questions whose content can exceed the viewport (goals grid).
  final bool scrollable;

  final CrossAxisAlignment contentAlignment;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    final Widget header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'QUESTION $stepNumber OF $totalSteps',
          style: context.text.labelSmall?.copyWith(color: palette.accent),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(title, style: context.text.displaySmall),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: context.text.bodyMedium?.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ],
    );

    if (scrollable) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: contentAlignment,
          children: <Widget>[
            header,
            const SizedBox(height: AppSpacing.xl),
            child,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: contentAlignment,
        children: <Widget>[
          header,
          const SizedBox(height: AppSpacing.xl),
          Expanded(child: child),
        ],
      ),
    );
  }
}
