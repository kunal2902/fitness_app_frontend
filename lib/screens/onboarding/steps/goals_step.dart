import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/onboarding/onboarding_bloc.dart';
import '../../../cards/goal_card.dart';
import '../../../config/app_config.dart';
import '../../../models/enums.dart';
import '../../../models/onboarding_data.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/onboarding_step_layout.dart';

/// Q4 — Goals. Multi-select, capped at [AppConfig.maxGoalSelections] so the
/// programme generator has a clear priority rather than "everything".
class GoalsStep extends StatelessWidget {
  const GoalsStep({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingBloc, OnboardingState>(
      buildWhen: (OnboardingState a, OnboardingState b) =>
          a.data.goals != b.data.goals,
      builder: (BuildContext context, OnboardingState state) {
        final List<FitnessGoal> selected = state.data.goals;
        final bool atCap = selected.length >= AppConfig.maxGoalSelections;

        return OnboardingStepLayout(
          stepNumber: 4,
          totalSteps: OnboardingData.totalSteps,
          scrollable: true,
          title: 'What are you training for?',
          subtitle:
              'Pick up to ${AppConfig.maxGoalSelections}. '
              '${selected.length} of ${AppConfig.maxGoalSelections} selected.',
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: FitnessGoal.values.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.98,
            ),
            itemBuilder: (BuildContext context, int i) {
              final FitnessGoal goal = FitnessGoal.values[i];
              final bool isSelected = selected.contains(goal);
              return GoalCard(
                goal: goal,
                isSelected: isSelected,
                isDisabled: atCap && !isSelected,
                onTap: () => context
                    .read<OnboardingBloc>()
                    .add(OnboardingGoalToggled(goal)),
              );
            },
          ),
        );
      },
    );
  }
}
