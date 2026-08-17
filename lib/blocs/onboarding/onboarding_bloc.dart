import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../config/app_config.dart';
import '../../models/enums.dart';
import '../../models/onboarding_data.dart';
import '../../store/app_store.dart';

part 'onboarding_event.dart';
part 'onboarding_state.dart';

/// Owns the 9-question flow.
///
/// Every answer is written straight through to SharedPreferences (via
/// [AppStore] → `StorageService`), so if the user backgrounds the app on
/// question 7 and the OS kills it, they come back to question 7 with all
/// seven answers intact.
class OnboardingBloc extends Bloc<OnboardingEvent, OnboardingState> {
  OnboardingBloc({AppStore? store})
      : _store = store ?? AppStore.instance,
        super(const OnboardingState()) {
    on<OnboardingStarted>(_onStarted);
    on<OnboardingGenderSelected>(_onGender);
    on<OnboardingHeightChanged>(_onHeight);
    on<OnboardingHeightUnitChanged>(_onHeightUnit);
    on<OnboardingWeightChanged>(_onWeight);
    on<OnboardingWeightUnitChanged>(_onWeightUnit);
    on<OnboardingGoalToggled>(_onGoalToggled);
    on<OnboardingPullUpsSelected>(_onPullUps);
    on<OnboardingPushUpsSelected>(_onPushUps);
    on<OnboardingSquatsSelected>(_onSquats);
    on<OnboardingDipsSelected>(_onDips);
    on<OnboardingFitnessLevelSelected>(_onFitnessLevel);
    on<OnboardingStepChanged>(_onStepChanged);
    on<OnboardingNextRequested>(_onNext);
    on<OnboardingBackRequested>(_onBack);
    on<OnboardingReset>(_onReset);
  }

  final AppStore _store;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  Future<void> _onStarted(
    OnboardingStarted event,
    Emitter<OnboardingState> emit,
  ) async {
    final OnboardingData draft = _store.onboardingDraft;

    // Resume on the first unanswered question rather than always at 0.
    int resumeAt = 0;
    for (int i = 0; i < OnboardingData.totalSteps; i++) {
      if (!draft.isStepAnswered(i)) {
        resumeAt = i;
        break;
      }
      resumeAt = i;
    }

    emit(
      state.copyWith(
        data: draft,
        currentStep: resumeAt,
        isHydrating: false,
      ),
    );
  }

  /// Single funnel for every answer: update state, then persist.
  Future<void> _commit(
    OnboardingData next,
    Emitter<OnboardingState> emit,
  ) async {
    emit(state.copyWith(data: next));
    await _store.saveOnboardingDraft(next);
  }

  // -------------------------------------------------------------------------
  // Answers
  // -------------------------------------------------------------------------

  Future<void> _onGender(
    OnboardingGenderSelected event,
    Emitter<OnboardingState> emit,
  ) =>
      _commit(state.data.copyWith(gender: event.gender), emit);

  Future<void> _onHeight(
    OnboardingHeightChanged event,
    Emitter<OnboardingState> emit,
  ) {
    final double clamped = event.centimetres
        .clamp(AppConfig.minHeightCm, AppConfig.maxHeightCm)
        .toDouble();
    return _commit(state.data.copyWith(heightCm: clamped), emit);
  }

  Future<void> _onHeightUnit(
    OnboardingHeightUnitChanged event,
    Emitter<OnboardingState> emit,
  ) {
    // Only the display unit changes — heightCm stays canonical, so
    // toggling back and forth never loses precision.
    return _commit(
      state.data.copyWith(
        heightUnit: event.unit,
        heightCm: state.data.heightCm ?? AppConfig.defaultHeightCm,
      ),
      emit,
    );
  }

  Future<void> _onWeight(
    OnboardingWeightChanged event,
    Emitter<OnboardingState> emit,
  ) {
    final double clamped = event.kilograms
        .clamp(AppConfig.minWeightKg, AppConfig.maxWeightKg)
        .toDouble();
    return _commit(state.data.copyWith(weightKg: clamped), emit);
  }

  Future<void> _onWeightUnit(
    OnboardingWeightUnitChanged event,
    Emitter<OnboardingState> emit,
  ) {
    return _commit(
      state.data.copyWith(
        weightUnit: event.unit,
        weightKg: state.data.weightKg ?? AppConfig.defaultWeightKg,
      ),
      emit,
    );
  }

  Future<void> _onGoalToggled(
    OnboardingGoalToggled event,
    Emitter<OnboardingState> emit,
  ) {
    final List<FitnessGoal> next = List<FitnessGoal>.from(state.data.goals);
    if (next.contains(event.goal)) {
      next.remove(event.goal);
    } else {
      if (next.length >= AppConfig.maxGoalSelections) return Future<void>.value();
      next.add(event.goal);
    }
    return _commit(state.data.copyWith(goals: next), emit);
  }

  Future<void> _onPullUps(
    OnboardingPullUpsSelected event,
    Emitter<OnboardingState> emit,
  ) =>
      _commit(state.data.copyWith(maxPullUps: event.range), emit);

  Future<void> _onPushUps(
    OnboardingPushUpsSelected event,
    Emitter<OnboardingState> emit,
  ) =>
      _commit(state.data.copyWith(maxPushUps: event.range), emit);

  Future<void> _onSquats(
    OnboardingSquatsSelected event,
    Emitter<OnboardingState> emit,
  ) =>
      _commit(state.data.copyWith(maxSquats: event.range), emit);

  Future<void> _onDips(
    OnboardingDipsSelected event,
    Emitter<OnboardingState> emit,
  ) =>
      _commit(state.data.copyWith(maxDips: event.range), emit);

  Future<void> _onFitnessLevel(
    OnboardingFitnessLevelSelected event,
    Emitter<OnboardingState> emit,
  ) =>
      _commit(state.data.copyWith(fitnessLevel: event.level), emit);

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  void _onStepChanged(
    OnboardingStepChanged event,
    Emitter<OnboardingState> emit,
  ) {
    final int clamped =
        event.stepIndex.clamp(0, OnboardingData.totalSteps - 1).toInt();
    if (clamped == state.currentStep) return;
    emit(state.copyWith(currentStep: clamped));
  }

  void _onNext(OnboardingNextRequested event, Emitter<OnboardingState> emit) {
    if (state.isLastStep || !state.canAdvance) return;
    emit(state.copyWith(currentStep: state.currentStep + 1));
  }

  void _onBack(OnboardingBackRequested event, Emitter<OnboardingState> emit) {
    if (state.isFirstStep) return;
    emit(state.copyWith(currentStep: state.currentStep - 1));
  }

  Future<void> _onReset(
    OnboardingReset event,
    Emitter<OnboardingState> emit,
  ) async {
    emit(const OnboardingState(isHydrating: false));
    await _store.clearOnboardingDraft();
  }
}
