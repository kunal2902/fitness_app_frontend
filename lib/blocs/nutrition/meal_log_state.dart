part of 'meal_log_bloc.dart';

class MealLogMutationState extends Equatable {
  const MealLogMutationState({
    this.status = NutritionWriteStatus.initial,
    this.operation,
    this.savedLog,
    this.deletedId,
    this.duplicate = false,
    this.error,
    this.revision = 0,
  });
  final NutritionWriteStatus status;
  final MealLogMutation? operation;
  final FoodLog? savedLog;
  final String? deletedId;
  final bool duplicate;
  final ApiException? error;

  /// Allows listeners to distinguish successive successes, even for one log.
  final int revision;
  bool get isSaving => status == NutritionWriteStatus.saving;
  bool get canRetry =>
      status == NutritionWriteStatus.failure && operation != null;
  @override
  List<Object?> get props => <Object?>[
        status,
        operation,
        savedLog,
        deletedId,
        duplicate,
        error,
        revision,
      ];
}

class MealLogState extends Equatable {
  const MealLogState({
    this.date,
    this.logs = const <FoodLog>[],
    this.hasLoaded = false,
    this.status = NutritionLoadStatus.initial,
    this.error,
    this.mutation = const MealLogMutationState(),
    this.failedMutations = const <MealLogMutationState>[],
  });
  final String? date;
  final List<FoodLog> logs;

  /// Distinguishes a confirmed empty diary from one we could not load.
  final bool hasLoaded;
  final NutritionLoadStatus status;
  final ApiException? error;
  final MealLogMutationState mutation;

  /// A later successful queued meal must not erase an earlier failed draft.
  final List<MealLogMutationState> failedMutations;
  bool get canRetry => failedMutations.isNotEmpty;
  bool get isEmpty => hasLoaded && logs.isEmpty;
  bool get isRefreshing => hasLoaded && status == NutritionLoadStatus.loading;

  MealLogState copyWith({
    List<FoodLog>? logs,
    bool? hasLoaded,
    NutritionLoadStatus? status,
    ApiException? error,
    bool clearError = false,
    MealLogMutationState? mutation,
    List<MealLogMutationState>? failedMutations,
  }) =>
      MealLogState(
        date: date,
        logs: logs ?? this.logs,
        hasLoaded: hasLoaded ?? this.hasLoaded,
        status: status ?? this.status,
        error: clearError ? null : error ?? this.error,
        mutation: mutation ?? this.mutation,
        failedMutations: failedMutations ?? this.failedMutations,
      );

  @override
  List<Object?> get props => <Object?>[
        date,
        logs,
        hasLoaded,
        status,
        error,
        mutation,
        failedMutations,
      ];
}
