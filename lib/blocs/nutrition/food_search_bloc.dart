import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/api_exception.dart';
import '../../models/nutrition_models.dart';
import '../../services/nutrition_repository.dart';

part 'food_search_event.dart';
part 'food_search_state.dart';

class FoodSearchBloc extends Bloc<FoodSearchEvent, FoodSearchState> {
  FoodSearchBloc({
    required NutritionRepository repository,
    this.debounceDuration = const Duration(milliseconds: 250),
  })  : _repository = repository,
        super(const FoodSearchState()) {
    on<FoodSearchChanged>(_onChanged, transformer: restartable());
  }

  final NutritionRepository _repository;
  final Duration debounceDuration;
  CancelToken? _request;
  Timer? _timer;
  Completer<void>? _debounce;
  bool _closing = false;

  void _cancelActive() {
    _request?.cancel('Search superseded');
    _request = null;
    _timer?.cancel();
    _timer = null;
    if (_debounce != null && !_debounce!.isCompleted) _debounce!.complete();
    _debounce = null;
  }

  Future<void> _onChanged(
    FoodSearchChanged event,
    Emitter<FoodSearchState> emit,
  ) async {
    if (_closing) return;
    _cancelActive();
    final String query = normalizeFoodQuery(event.query);
    if (query.isEmpty) {
      emit(const FoodSearchState());
      return;
    }

    final CancelToken token = CancelToken();
    _request = token;
    emit(FoodSearchState(query: query, status: FoodSearchStatus.debouncing));
    // Debounce INSIDE the restartable handler: every keystroke cancels the
    // previous HTTP request immediately, not after another debounce window.
    final Completer<void> ready = Completer<void>();
    _debounce = ready;
    _timer = Timer(debounceDuration, ready.complete);
    await ready.future;
    if (_closing || emit.isDone) return;

    emit(FoodSearchState(query: query, status: FoodSearchStatus.loading));
    try {
      final FoodSearchResult result =
          await _repository.searchFoods(query, cancelToken: token);
      if (_closing || emit.isDone) return;
      if (result.query != query) {
        throw const ApiException(
          message: 'Search results did not match your query. Please retry.',
          code: 'BAD_ENVELOPE',
        );
      }
      emit(
        FoodSearchState(
          query: query,
          status: FoodSearchStatus.success,
          foods: List<Food>.unmodifiable(result.foods),
          catalogueEmpty: result.catalogueEmpty,
          globalLookupUnavailable: result.globalLookupUnavailable,
        ),
      );
    } catch (error) {
      if (_closing || emit.isDone) return;
      final ApiException failure = nutritionFailure(error);
      emit(
        FoodSearchState(
          query: query,
          status: failure.isCancelled
              ? FoodSearchStatus.initial
              : FoodSearchStatus.failure,
          error: failure.isCancelled ? null : failure,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    _cancelActive();
    return super.close();
  }
}
