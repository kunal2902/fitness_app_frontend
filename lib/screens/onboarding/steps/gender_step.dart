import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/onboarding/onboarding_bloc.dart';
import '../../../cards/gender_card.dart';
import '../../../models/enums.dart';
import '../../../models/onboarding_data.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/onboarding_step_layout.dart';

/// Q1 — Gender.
class GenderStep extends StatelessWidget {
  const GenderStep({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingBloc, OnboardingState>(
      buildWhen: (OnboardingState a, OnboardingState b) =>
          a.data.gender != b.data.gender,
      builder: (BuildContext context, OnboardingState state) {
        return OnboardingStepLayout(
          stepNumber: 1,
          totalSteps: OnboardingData.totalSteps,
          title: 'What is your gender?',
          subtitle:
              'We use this to calibrate calorie and volume recommendations.',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  for (final Gender gender in Gender.values) ...<Widget>[
                    Expanded(
                      child: GenderCard(
                        gender: gender,
                        isSelected: state.data.gender == gender,
                        onTap: () => context
                            .read<OnboardingBloc>()
                            .add(OnboardingGenderSelected(gender)),
                      ),
                    ),
                    if (gender != Gender.values.last)
                      const SizedBox(width: AppSpacing.md),
                  ],
                ],
              ),
              const Spacer(),
            ],
          ),
        );
      },
    );
  }
}
