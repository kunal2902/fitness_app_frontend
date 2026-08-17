import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/onboarding/onboarding_bloc.dart';
import '../../models/onboarding_data.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/step_progress_bar.dart';
import 'steps/dips_step.dart';
import 'steps/fitness_level_step.dart';
import 'steps/gender_step.dart';
import 'steps/goals_step.dart';
import 'steps/height_step.dart';
import 'steps/pullups_step.dart';
import 'steps/pushups_step.dart';
import 'steps/squats_step.dart';
import 'steps/weight_step.dart';

/// The 9-question flow, presented as one screen with swipeable pages.
///
/// The BLoC is the single source of truth for which page is visible — the
/// [PageController] follows it. That keeps the "Continue" button, the
/// progress bar, the system back gesture and the swipe gesture all in sync
/// without any of them owning state.
class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  final PageController _pageController = PageController();

  static const List<Widget> _steps = <Widget>[
    GenderStep(),
    HeightStep(),
    WeightStep(),
    GoalsStep(),
    PullUpsStep(),
    PushUpsStep(),
    SquatsStep(),
    DipsStep(),
    FitnessLevelStep(),
  ];

  @override
  void initState() {
    super.initState();
    context.read<OnboardingBloc>().add(const OnboardingStarted());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _syncPage(int step) {
    if (!_pageController.hasClients) return;
    final int current = _pageController.page?.round() ?? 0;
    if (current == step) return;
    _pageController.animateToPage(
      step,
      duration: AppDuration.normal,
      curve: Curves.easeOutCubic,
    );
  }

  void _handleContinue(OnboardingState state) {
    final OnboardingBloc bloc = context.read<OnboardingBloc>();

    if (!state.isLastStep) {
      bloc.add(const OnboardingNextRequested());
      return;
    }

    // Last page: everything must be answered before we move to signup.
    // Swiping past a question is allowed, so catch the gap here.
    if (!state.data.isComplete) {
      final int missing = List<int>.generate(OnboardingData.totalSteps, (int i) => i)
          .firstWhere((int i) => !state.data.isStepAnswered(i));
      AppSnackbar.error(
        context,
        'Question ${missing + 1} still needs an answer.',
      );
      bloc.add(OnboardingStepChanged(missing));
      return;
    }

    Navigator.of(context).pushNamed(AppRoutes.accountDetails);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return BlocConsumer<OnboardingBloc, OnboardingState>(
      listenWhen: (OnboardingState a, OnboardingState b) =>
          a.currentStep != b.currentStep,
      listener: (BuildContext context, OnboardingState state) =>
          _syncPage(state.currentStep),
      builder: (BuildContext context, OnboardingState state) {
        if (state.isHydrating) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return PopScope(
          canPop: state.isFirstStep,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (didPop) return;
            context.read<OnboardingBloc>().add(const OnboardingBackRequested());
          },
          child: Scaffold(
            body: GlowBackground(
              child: SafeArea(
                child: Column(
                  children: <Widget>[
                    // ---- Header -------------------------------------------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      child: Row(
                        children: <Widget>[
                          AnimatedOpacity(
                            duration: AppDuration.fast,
                            opacity: state.isFirstStep ? 0 : 1,
                            child: IgnorePointer(
                              ignoring: state.isFirstStep,
                              child: CircleIconButton(
                                icon: Icons.arrow_back_rounded,
                                tooltip: 'Previous question',
                                onPressed: () => context
                                    .read<OnboardingBloc>()
                                    .add(const OnboardingBackRequested()),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: StepProgressBar(
                              currentStep: state.currentStep,
                              totalSteps: state.totalSteps,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          SizedBox(
                            width: 44,
                            child: Text(
                              '${state.currentStep + 1}/${state.totalSteps}',
                              textAlign: TextAlign.end,
                              style: context.text.labelMedium?.copyWith(
                                color: palette.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ---- Pages --------------------------------------------
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        onPageChanged: (int index) => context
                            .read<OnboardingBloc>()
                            .add(OnboardingStepChanged(index)),
                        children: _steps,
                      ),
                    ),

                    // ---- Footer -------------------------------------------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      child: PrimaryButton(
                        label: state.isLastStep ? 'Create account' : 'Continue',
                        icon: state.isLastStep
                            ? Icons.arrow_forward_rounded
                            : null,
                        onPressed: state.canAdvance
                            ? () => _handleContinue(state)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
