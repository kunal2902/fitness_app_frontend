import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/onboarding/onboarding_bloc.dart';
import '../../../models/enums.dart';
import 'option_list_step.dart';

/// Q5 — Max pull-ups in a single set.
class PullUpsStep extends StatelessWidget {
  const PullUpsStep({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingBloc, OnboardingState>(
      buildWhen: (OnboardingState a, OnboardingState b) =>
          a.data.maxPullUps != b.data.maxPullUps,
      builder: (BuildContext context, OnboardingState state) {
        return OptionListStep<PullUpRange>(
          stepNumber: 5,
          title: 'How many pull-ups can you do?',
          subtitle: 'Your best single set, strict form.',
          options: PullUpRange.values,
          selected: state.data.maxPullUps,
          onSelect: (PullUpRange range) => context
              .read<OnboardingBloc>()
              .add(OnboardingPullUpsSelected(range)),
        );
      },
    );
  }
}
