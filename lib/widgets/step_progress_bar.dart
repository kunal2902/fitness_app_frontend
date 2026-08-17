import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Segmented progress indicator across the top of the onboarding flow —
/// one bar per question, filled as the user advances.
class StepProgressBar extends StatelessWidget {
  const StepProgressBar({
    required this.currentStep,
    required this.totalSteps,
    this.height = 4,
    super.key,
  });

  final int currentStep;
  final int totalSteps;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Semantics(
      label: 'Question ${currentStep + 1} of $totalSteps',
      child: Row(
        children: List<Widget>.generate(totalSteps, (int i) {
          final bool filled = i <= currentStep;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 4),
              child: AnimatedContainer(
                duration: AppDuration.normal,
                curve: Curves.easeOut,
                height: height,
                decoration: BoxDecoration(
                  color: filled ? palette.accent : palette.border,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
