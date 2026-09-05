part of 'meal_log_bloc.dart';

sealed class MealLogEvent extends Equatable {
  const MealLogEvent();
}

final class MealLogsRequested extends MealLogEvent {
  const MealLogsRequested(this.date);
  final String date;
  @override
  List<Object?> get props => <Object?>[date];
}

sealed class MealLogMutation extends MealLogEvent {
  const MealLogMutation();
}

final class MealLogCreateRequested extends MealLogMutation {
  const MealLogCreateRequested(this.draft);
  final MealLogDraft draft;
  @override
  List<Object?> get props => <Object?>[draft];
}

final class MealLogUpdateRequested extends MealLogMutation {
  const MealLogUpdateRequested(this.edit);
  final MealLogEdit edit;
  @override
  List<Object?> get props => <Object?>[edit];
}

final class MealLogDeleteRequested extends MealLogMutation {
  const MealLogDeleteRequested({required this.logId, required this.date});
  final String logId;
  final String date;
  @override
  List<Object?> get props => <Object?>[logId, date];
}

/// Replays a retained failure (the latest by default), preserving its clientId.
final class MealLogRetryRequested extends MealLogMutation {
  const MealLogRetryRequested({this.operation});
  final MealLogMutation? operation;
  @override
  List<Object?> get props => <Object?>[operation];
}
