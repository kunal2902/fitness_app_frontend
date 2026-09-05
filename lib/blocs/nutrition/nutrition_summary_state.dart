part of 'nutrition_summary_bloc.dart';

class NutritionTargetSaveState extends Equatable {
  const NutritionTargetSaveState({
    this.status = NutritionWriteStatus.initial,
    this.edit,
    this.target,
    this.error,
    this.revision = 0,
  });
  final NutritionWriteStatus status;
  final NutritionTargetEdit? edit;
  final NutritionTarget? target;
  final ApiException? error;
  final int revision;
  bool get isSaving => status == NutritionWriteStatus.saving;
  @override
  List<Object?> get props => <Object?>[status, edit, target, error, revision];
}

class NutritionSummaryState extends Equatable {
  const NutritionSummaryState({
    this.date,
    this.summary,
    this.status = NutritionLoadStatus.initial,
    this.error,
    this.targetSave = const NutritionTargetSaveState(),
  });
  final String? date;
  final NutritionSummary? summary;
  final NutritionLoadStatus status;
  final ApiException? error;
  final NutritionTargetSaveState targetSave;
  bool get hasLoaded => summary != null;
  bool get isRefreshing => hasLoaded && status == NutritionLoadStatus.loading;

  NutritionSummaryState copyWith({
    NutritionSummary? summary,
    NutritionLoadStatus? status,
    ApiException? error,
    bool clearError = false,
    NutritionTargetSaveState? targetSave,
  }) =>
      NutritionSummaryState(
        date: date,
        summary: summary ?? this.summary,
        status: status ?? this.status,
        error: clearError ? null : error ?? this.error,
        targetSave: targetSave ?? this.targetSave,
      );

  @override
  List<Object?> get props =>
      <Object?>[date, summary, status, error, targetSave];
}
