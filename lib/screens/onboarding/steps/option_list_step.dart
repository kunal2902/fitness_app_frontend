import 'package:flutter/material.dart';

import '../../../cards/option_card.dart';
import '../../../models/enums.dart';
import '../../../models/onboarding_data.dart';
import '../../../widgets/onboarding_step_layout.dart';

/// Shared body for every single-select question (Q5–Q9).
///
/// Those five screens differ only in their copy and their option set, so
/// they all render through this and stay pixel-identical.
class OptionListStep<T extends SelectableOption> extends StatelessWidget {
  const OptionListStep({
    required this.stepNumber,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.subtitle,
    super.key,
  });

  final int stepNumber;
  final String title;
  final String? subtitle;
  final List<T> options;
  final T? selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return OnboardingStepLayout(
      stepNumber: stepNumber,
      totalSteps: OnboardingData.totalSteps,
      title: title,
      subtitle: subtitle,
      scrollable: true,
      child: Column(
        children: options
            .map(
              (T option) => OptionCard(
                option: option,
                isSelected: selected == option,
                onTap: () => onSelect(option),
              ),
            )
            .toList(),
      ),
    );
  }
}
