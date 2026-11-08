import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Scrollable question panel below the fixed onboarding progress header.
class OnboardingStepLayout extends StatelessWidget {
  const OnboardingStepLayout({
    required this.stepNumber,
    required this.totalSteps,
    required this.title,
    required this.child,
    this.subtitle,
    super.key,
  });

  final int stepNumber;
  final int totalSteps;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'QUESTION $stepNumber OF $totalSteps',
              style: context.text.labelSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              header: true,
              child: Text(title, style: context.text.displayMedium),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle!, style: context.text.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.xl),
            child,
          ],
        ),
      );
}
