import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/onboarding/onboarding_bloc.dart';
import '../../../models/enums.dart';
import 'option_list_step.dart';

/// Q6 — Max push-ups in a single set.
class PushUpsStep extends StatelessWidget {
  const PushUpsStep({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingBloc, OnboardingState>(
      buildWhen: (OnboardingState a, OnboardingState b) =>
          a.data.maxPushUps != b.data.maxPushUps,
      builder: (BuildContext context, OnboardingState state) {
        return OptionListStep<PushUpRange>(
          stepNumber: 6,
          title: 'How many push-ups can you do?',
          subtitle: 'Chest to the floor, no resting at the top.',
          options: PushUpRange.values,
          selected: state.data.maxPushUps,
          onSelect: (PushUpRange range) => context
              .read<OnboardingBloc>()
              .add(OnboardingPushUpsSelected(range)),
        );
      },
    );
  }
}
