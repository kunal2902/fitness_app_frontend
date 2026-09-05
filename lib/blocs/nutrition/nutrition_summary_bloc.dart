import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/api_exception.dart';
import '../../models/food_log.dart';
import '../../services/nutrition_repository.dart';
import 'nutrition_status.dart';

part 'nutrition_summary_event.dart';
part 'nutrition_summary_state.dart';

class NutritionSummaryBloc
    extends Bloc<NutritionSummaryEvent, NutritionSummaryState> {
  NutritionSummaryBloc({required NutritionRepository repository})
      : _repository = repository,
        super(const NutritionSummaryState()) {
    on<NutritionSummaryRequested>(_onRequested, transformer: restartable());
    on<NutritionTargetsSubmitted>(_onTargets, transformer: sequential());
    _subscription = repository.changes.listen((NutritionChange change) {
      final String? date = state.date;
      if (!_closing && date != null && change.affects(date)) {
        add(NutritionSummaryRequested(date));
      }
    });
  }

  final NutritionRepository _repository;
  late final StreamSubscription<NutritionChange> _subscription;
  bool _closing = false;

  Future<void> _onRequested(
    NutritionSummaryRequested event,
    Emitter<NutritionSummaryState> emit,
  ) async {
    if (_closing) return;
    emit(
      NutritionSummaryState(
        date: event.date,
        summary: event.date == state.date ? state.summary : null,
        status: NutritionLoadStatus.loading,
        targetSave: state.targetSave,
      ),
    );
    try {
      requireDiaryDate(event.date);
      final NutritionSummary summary = await _repository.summary(event.date);
      if (_closing || emit.isDone) return;
      if (summary.date != event.date) {
        throw const ApiException(
          message: 'The summary response contained a different day.',
          code: 'BAD_ENVELOPE',
        );
      }
      emit(
        state.copyWith(
          summary: summary,
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

  Future<void> _onTargets(
    NutritionTargetsSubmitted event,
    Emitter<NutritionSummaryState> emit,
  ) async {
    if (_closing) return;
    final int revision = state.targetSave.revision + 1;
    emit(
      state.copyWith(
        targetSave: NutritionTargetSaveState(
          status: NutritionWriteStatus.saving,
          edit: event.edit,
          revision: revision,
        ),
      ),
    );
    try {
      final NutritionTarget target =
          await _repository.updateTargets(event.edit);
      if (_closing || emit.isDone) return;
      emit(
        state.copyWith(
          targetSave: NutritionTargetSaveState(
            status: NutritionWriteStatus.success,
            edit: event.edit,
            target: target,
            revision: revision,
          ),
        ),
      );
      // The repository invalidation refreshes the summary. Do not recompute
      // server totals or fabricate an empty day if that refresh fails.
    } catch (error) {
      if (_closing || emit.isDone) return;
      emit(
        state.copyWith(
          targetSave: NutritionTargetSaveState(
            status: NutritionWriteStatus.failure,
            edit: event.edit,
            error: nutritionFailure(error),
            revision: revision,
          ),
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
