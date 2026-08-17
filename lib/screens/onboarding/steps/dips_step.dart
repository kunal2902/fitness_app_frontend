import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/onboarding/onboarding_bloc.dart';
import '../../../models/enums.dart';
import 'option_list_step.dart';

/// Q8 — Max dips in a single set.
class DipsStep extends StatelessWidget {
  const DipsStep({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingBloc, OnboardingState>(
      buildWhen: (OnboardingState a, OnboardingState b) =>
          a.data.maxDips != b.data.maxDips,
      builder: (BuildContext context, OnboardingState state) {
        return OptionListStep<DipRange>(
          stepNumber: 8,
          title: 'How many dips can you do?',
          subtitle: 'Parallel bars, full range of motion.',
          options: DipRange.values,
          selected: state.data.maxDips,
          onSelect: (DipRange range) =>
              context.read<OnboardingBloc>().add(OnboardingDipsSelected(range)),
        );
      },
    );
  }
}
