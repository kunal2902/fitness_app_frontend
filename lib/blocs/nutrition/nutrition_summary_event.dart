part of 'nutrition_summary_bloc.dart';

sealed class NutritionSummaryEvent extends Equatable {
  const NutritionSummaryEvent();
}

final class NutritionSummaryRequested extends NutritionSummaryEvent {
  const NutritionSummaryRequested(this.date);
  final String date;
  @override
  List<Object?> get props => <Object?>[date];
}

/// Reuse the same edit to retry; target patches are absolute values.
final class NutritionTargetsSubmitted extends NutritionSummaryEvent {
  const NutritionTargetsSubmitted(this.edit);
  final NutritionTargetEdit edit;
  @override
  List<Object?> get props => <Object?>[edit];
}
