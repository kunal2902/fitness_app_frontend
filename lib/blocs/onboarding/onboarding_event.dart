part of 'onboarding_bloc.dart';

sealed class OnboardingEvent extends Equatable {
  const OnboardingEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Rehydrate any draft the user left behind on a previous launch.
class OnboardingStarted extends OnboardingEvent {
  const OnboardingStarted();
}

class OnboardingGenderSelected extends OnboardingEvent {
  const OnboardingGenderSelected(this.gender);
  final Gender gender;

  @override
  List<Object?> get props => <Object?>[gender];
}

/// [centimetres] is always metric — the UI converts before dispatching.
class OnboardingHeightChanged extends OnboardingEvent {
  const OnboardingHeightChanged(this.centimetres);
  final double centimetres;

  @override
  List<Object?> get props => <Object?>[centimetres];
}

class OnboardingHeightUnitChanged extends OnboardingEvent {
  const OnboardingHeightUnitChanged(this.unit);
  final HeightUnit unit;

  @override
  List<Object?> get props => <Object?>[unit];
}

/// [kilograms] is always metric — the UI converts before dispatching.
class OnboardingWeightChanged extends OnboardingEvent {
  const OnboardingWeightChanged(this.kilograms);
  final double kilograms;

  @override
  List<Object?> get props => <Object?>[kilograms];
}

class OnboardingWeightUnitChanged extends OnboardingEvent {
  const OnboardingWeightUnitChanged(this.unit);
  final WeightUnit unit;

  @override
  List<Object?> get props => <Object?>[unit];
}

/// Goals are multi-select — this adds or removes one.
class OnboardingGoalToggled extends OnboardingEvent {
  const OnboardingGoalToggled(this.goal);
  final FitnessGoal goal;

  @override
  List<Object?> get props => <Object?>[goal];
}

class OnboardingPullUpsSelected extends OnboardingEvent {
  const OnboardingPullUpsSelected(this.range);
  final PullUpRange range;

  @override
  List<Object?> get props => <Object?>[range];
}

class OnboardingPushUpsSelected extends OnboardingEvent {
  const OnboardingPushUpsSelected(this.range);
  final PushUpRange range;

  @override
  List<Object?> get props => <Object?>[range];
}

class OnboardingSquatsSelected extends OnboardingEvent {
  const OnboardingSquatsSelected(this.range);
  final SquatRange range;

  @override
  List<Object?> get props => <Object?>[range];
}

class OnboardingDipsSelected extends OnboardingEvent {
  const OnboardingDipsSelected(this.range);
  final DipRange range;

  @override
  List<Object?> get props => <Object?>[range];
}

class OnboardingFitnessLevelSelected extends OnboardingEvent {
  const OnboardingFitnessLevelSelected(this.level);
  final FitnessLevel level;

  @override
  List<Object?> get props => <Object?>[level];
}

/// Fired when the PageView settles on a new page (swipe or button).
class OnboardingStepChanged extends OnboardingEvent {
  const OnboardingStepChanged(this.stepIndex);
  final int stepIndex;

  @override
  List<Object?> get props => <Object?>[stepIndex];
}

class OnboardingNextRequested extends OnboardingEvent {
  const OnboardingNextRequested();
}

class OnboardingBackRequested extends OnboardingEvent {
  const OnboardingBackRequested();
}

/// Wipes the draft — used after a successful signup.
class OnboardingReset extends OnboardingEvent {
  const OnboardingReset();
}
