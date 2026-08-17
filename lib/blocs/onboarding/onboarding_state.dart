part of 'onboarding_bloc.dart';

class OnboardingState extends Equatable {
  const OnboardingState({
    this.data = OnboardingData.initial,
    this.currentStep = 0,
    this.isHydrating = true,
  });

  /// All answers collected so far.
  final OnboardingData data;

  /// Index of the visible question, 0-based, matching the PageView.
  final int currentStep;

  /// True until the saved draft has been read back from SharedPreferences.
  final bool isHydrating;

  int get totalSteps => OnboardingData.totalSteps;

  bool get isFirstStep => currentStep == 0;
  bool get isLastStep => currentStep == totalSteps - 1;

  /// Whether the visible question has been answered — gates "Continue".
  bool get canAdvance => data.isStepAnswered(currentStep);

  /// 0.0 – 1.0 for the progress bar at the top of the flow.
  double get progress => (currentStep + 1) / totalSteps;

  OnboardingState copyWith({
    OnboardingData? data,
    int? currentStep,
    bool? isHydrating,
  }) {
    return OnboardingState(
      data: data ?? this.data,
      currentStep: currentStep ?? this.currentStep,
      isHydrating: isHydrating ?? this.isHydrating,
    );
  }

  @override
  List<Object?> get props => <Object?>[data, currentStep, isHydrating];
}
