import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/api_exception.dart';
import '../../models/food_log.dart';
import '../../services/nutrition_repository.dart';
import 'nutrition_status.dart';

part 'meal_log_event.dart';
part 'meal_log_state.dart';

class MealLogBloc extends Bloc<MealLogEvent, MealLogState> {
  MealLogBloc({required NutritionRepository repository})
      : _repository = repository,
        super(const MealLogState()) {
    on<MealLogsRequested>(_onRequested, transformer: restartable());
    // One queue across create/edit/delete, not a separate concurrent queue
    // for each event type. Never drop a distinct meal while a save is pending.
    on<MealLogMutation>(_onMutation, transformer: sequential());
    _subscription = repository.changes.listen((NutritionChange change) {
      final String? date = state.date;
      if (!_closing && date != null && change.dates.contains(date)) {
        add(MealLogsRequested(date));
      }
    });
  }

  final NutritionRepository _repository;
  late final StreamSubscription<NutritionChange> _subscription;
  final Set<String> _savedClientIds = <String>{};
  bool _closing = false;

  bool _sameOperation(MealLogMutation? left, MealLogMutation right) {
    if (left is MealLogCreateRequested && right is MealLogCreateRequested) {
      return left.draft.clientId == right.draft.clientId;
    }
    return left == right;
  }

  Future<void> _onRequested(
    MealLogsRequested event,
    Emitter<MealLogState> emit,
  ) async {
    if (_closing) return;
    final bool sameDay = event.date == state.date;
    emit(
      MealLogState(
        date: event.date,
        logs: sameDay ? state.logs : const <FoodLog>[],
        hasLoaded: sameDay && state.hasLoaded,
        status: NutritionLoadStatus.loading,
        mutation: state.mutation,
        failedMutations: state.failedMutations,
      ),
    );
    try {
      requireDiaryDate(event.date);
      final List<FoodLog> logs = await _repository.listLogs(event.date);
      if (_closing || emit.isDone) return;
      if (logs.any((FoodLog log) => log.date != event.date)) {
        throw const ApiException(
          message: 'The diary response contained a different day.',
          code: 'BAD_ENVELOPE',
        );
      }
      emit(
        state.copyWith(
          logs: List<FoodLog>.unmodifiable(logs),
          hasLoaded: true,
          status: NutritionLoadStatus.success,
          clearError: true,
        ),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(
        state.copyWith(
          status: NutritionLoadStatus.failure,
          error: nutritionFailure(error),
        ),
      );
    }
  }

  Future<void> _onMutation(
    MealLogMutation event,
    Emitter<MealLogState> emit,
  ) async {
    if (_closing) return;
    final MealLogMutation? operation = event is MealLogRetryRequested
        ? (event.operation ??
            (state.failedMutations.isEmpty
                ? null
                : state.failedMutations.last.operation))
        : event;
    if (operation == null) return;
    if (event is MealLogRetryRequested &&
        !state.failedMutations.any(
          (MealLogMutationState failure) =>
              _sameOperation(failure.operation, operation),
        )) {
      return;
    }
    if (operation is MealLogCreateRequested &&
        _savedClientIds.contains(operation.draft.clientId)) {
      return;
    }

    final int revision = state.mutation.revision + 1;
    emit(
      state.copyWith(
        mutation: MealLogMutationState(
          status: NutritionWriteStatus.saving,
          operation: operation,
          revision: revision,
        ),
      ),
    );
    try {
      FoodLog? savedLog;
      String? deletedId;
      bool duplicate = false;
      switch (operation) {
        case MealLogCreateRequested(:final draft):
          final MealLogResult result = await _repository.createLog(draft);
          savedLog = result.log;
          duplicate = result.duplicate;
          if (!_closing && !emit.isDone) _savedClientIds.add(draft.clientId);
        case MealLogUpdateRequested(:final edit):
          savedLog = await _repository.updateLog(edit);
        case MealLogDeleteRequested(:final logId, :final date):
          requireDiaryDate(date);
          await _repository.deleteLog(logId, date: date);
          deletedId = logId;
        case MealLogRetryRequested():
          return;
      }
      if (_closing || emit.isDone) return;
      emit(
        state.copyWith(
          mutation: MealLogMutationState(
            status: NutritionWriteStatus.success,
            operation: operation,
            savedLog: savedLog,
            deletedId: deletedId,
            duplicate: duplicate,
            revision: revision,
          ),
          failedMutations: List<MealLogMutationState>.unmodifiable(
            state.failedMutations.where(
              (MealLogMutationState failure) =>
                  !_sameOperation(failure.operation, operation),
            ),
          ),
        ),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      final MealLogMutationState failure = MealLogMutationState(
        status: NutritionWriteStatus.failure,
        operation: operation,
        error: nutritionFailure(error),
        revision: revision,
      );
      emit(
        state.copyWith(
          mutation: failure,
          failedMutations:
              List<MealLogMutationState>.unmodifiable(<MealLogMutationState>[
            ...state.failedMutations.where(
              (MealLogMutationState previous) =>
                  !_sameOperation(previous.operation, operation),
            ),
            failure,
          ]),
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    unawaited(_subscription.cancel());
    return super.close();
  }
}
