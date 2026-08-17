import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/onboarding/onboarding_bloc.dart';
import '../../../models/enums.dart';
import 'option_list_step.dart';

/// Q7 — Max bodyweight squats in a single set.
class SquatsStep extends StatelessWidget {
  const SquatsStep({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingBloc, OnboardingState>(
      buildWhen: (OnboardingState a, OnboardingState b) =>
          a.data.maxSquats != b.data.maxSquats,
      builder: (BuildContext context, OnboardingState state) {
        return OptionListStep<SquatRange>(
          stepNumber: 7,
          title: 'How many squats can you do?',
          subtitle: 'Bodyweight, thighs parallel or lower.',
          options: SquatRange.values,
          selected: state.data.maxSquats,
          onSelect: (SquatRange range) => context
              .read<OnboardingBloc>()
              .add(OnboardingSquatsSelected(range)),
        );
      },
    );
  }
}
