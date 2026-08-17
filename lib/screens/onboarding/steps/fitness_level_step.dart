import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/onboarding/onboarding_bloc.dart';
import '../../../models/enums.dart';
import 'option_list_step.dart';

/// Q9 — Self-reported training experience. Combined with the rep answers
/// this is what seeds the starting programme.
class FitnessLevelStep extends StatelessWidget {
  const FitnessLevelStep({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingBloc, OnboardingState>(
      buildWhen: (OnboardingState a, OnboardingState b) =>
          a.data.fitnessLevel != b.data.fitnessLevel,
      builder: (BuildContext context, OnboardingState state) {
        return OptionListStep<FitnessLevel>(
          stepNumber: 9,
          title: 'How would you rate yourself?',
          subtitle: 'Be honest — we scale the programme from here.',
          options: FitnessLevel.values,
          selected: state.data.fitnessLevel,
          onSelect: (FitnessLevel level) => context
              .read<OnboardingBloc>()
              .add(OnboardingFitnessLevelSelected(level)),
        );
      },
    );
  }
}
