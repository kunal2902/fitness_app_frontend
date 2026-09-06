import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;

import '../models/api_exception.dart';
import '../models/food_log.dart';
import '../models/nutrition_models.dart';
import '../models/nutrition_target_setup.dart';
import '../models/saved_meal.dart';
import '../utils/diary_date.dart';
import 'nutrition_repository.dart';
import 'nutrition_service.dart';

/// Session-local API implementation. No private nutrition data is persisted
/// globally and no failed write is presented as an offline success.
class ApiNutritionRepository implements NutritionRepository {
  ApiNutritionRepository({
    NutritionService? service,
    bool Function()? isSessionCurrent,
  })  : _service = service ?? NutritionService(),
        _isSessionCurrent = isSessionCurrent;

  final NutritionService _service;
  final bool Function()? _isSessionCurrent;
  final StreamController<NutritionChange> _changes =
      StreamController<NutritionChange>.broadcast();
  final Set<CancelToken> _requests = <CancelToken>{};
  bool _disposed = false;

  @override
  Stream<NutritionChange> get changes => _changes.stream;

  void _requireOpen() {
    if (_disposed || !(_isSessionCurrent?.call() ?? true)) {
      throw const ApiException(
        message: 'Nutrition session closed.',
        code: 'CANCELLED',
      );
    }
  }

  Future<T> _request<T>(
    Future<T> Function(CancelToken) run, {
    CancelToken? token,
  }) async {
    _requireOpen();
    final CancelToken request = token ?? CancelToken();
    _requests.add(request);
    try {
      final T result = await run(request);
      _requireOpen();
      if (request.isCancelled) {
        throw const ApiException(
          message: 'Nutrition request cancelled.',
          code: 'CANCELLED',
        );
      }
      return result;
    } finally {
      _requests.remove(request);
    }
  }

  void _changed(NutritionChange change) {
    if (!_disposed) _changes.add(change);
  }

  /// A dropped response may still have committed on the server. Reconcile
  /// reads while preserving the failed draft and its idempotency key.
  void _reconcileUncertain(Object error, NutritionChange change) {
    if (error is ApiException &&
        (error.code == 'NETWORK' ||
            error.code == 'BAD_ENVELOPE' ||
            error.code == 'TIMEOUT' ||
            (error.statusCode ?? 0) >= 500)) {
      _changed(change);
    }
  }

  @override
  String newClientId() {
    _requireOpen();
    return _service.newClientId();
  }

  @override
  Future<FoodSearchResult> searchFoods(
    String query, {
    int limit = 20,
    CancelToken? cancelToken,
  }) async {
    final String normalized = normalizeFoodQuery(query);
    final FoodSearchResult result = await _request(
      (CancelToken token) =>
          _service.searchFoods(normalized, limit: limit, cancelToken: token),
      token: cancelToken,
    );
    if (result.query != normalized) throw _badEcho('query');
    return (
      foods: List<Food>.unmodifiable(result.foods),
      query: result.query,
      catalogueEmpty: result.catalogueEmpty,
      globalLookupUnavailable: result.globalLookupUnavailable,
    );
  }

  @override
  Future<Food> getFood(String idOrExternalId) => _request(
        (CancelToken token) =>
            _service.getFood(idOrExternalId, cancelToken: token),
      );

  @override
  Future<List<FoodLog>> listLogs(String date) async {
    requireDiaryDate(date);
    final ({List<FoodLog> logs, String date}) result = await _request(
      (CancelToken token) => _service.listLogs(date, cancelToken: token),
    );
    if (result.date != date ||
        result.logs.any((FoodLog log) => log.date != date)) {
      throw _badEcho('date');
    }
    return List<FoodLog>.unmodifiable(result.logs);
  }

  @override
  Future<MealLogResult> createLog(MealLogDraft draft) async {
    final NutritionChange change = NutritionChange(dates: <String>{draft.date});
    try {
      final MealLogResult result = await _request(
        (CancelToken token) => _service.createLog(
          date: draft.date,
          mealType: draft.mealType,
          items: draft.items,
          clientId: draft.clientId,
          notes: draft.notes,
          cancelToken: token,
        ),
      );
      if (result.log.id.isEmpty ||
          !DiaryDate.isValid(result.log.date) ||
          result.log.clientId != draft.clientId) {
        throw _badEcho('saved meal identity');
      }
      _changed(NutritionChange(dates: <String>{draft.date, result.log.date}));
      return result;
    } catch (error) {
      _reconcileUncertain(error, change);
      rethrow;
    }
  }

  @override
  Future<FoodLog> updateLog(MealLogEdit edit) async {
    final NutritionChange change = NutritionChange(
      dates: <String>{edit.originalDate, if (edit.date != null) edit.date!},
    );
    try {
      final FoodLog log = await _request(
        (CancelToken token) => _service.updateLog(
          edit.logId,
          date: edit.date,
          mealType: edit.mealType,
          items: edit.items,
          notes: edit.notes,
          clearNotes: edit.clearNotes,
          cancelToken: token,
        ),
      );
      if (log.id != edit.logId || !DiaryDate.isValid(log.date)) {
        throw _badEcho('saved meal identity');
      }
      _changed(NutritionChange(dates: <String>{...change.dates, log.date}));
      return log;
    } catch (error) {
      _reconcileUncertain(error, change);
      rethrow;
    }
  }

  @override
  Future<void> deleteLog(String logId, {required String date}) async {
    requireDiaryDate(date);
    final NutritionChange change = NutritionChange(dates: <String>{date});
    try {
      await _request(
        (CancelToken token) => _service.deleteLog(logId, cancelToken: token),
      );
    } catch (error) {
      // A retry after a lost successful delete is already at the desired state.
      if (error is! ApiException ||
          !error.isNotFound ||
          error.code != 'NO_FOOD_LOG') {
        _reconcileUncertain(error, change);
        rethrow;
      }
    }
    _changed(change);
  }

  @override
  Future<List<SavedMeal>> listSavedMeals() async {
    final List<SavedMeal> meals = await _request(
      (CancelToken token) => _service.listSavedMeals(cancelToken: token),
    );
    if (meals.any((SavedMeal meal) => meal.id.isEmpty || meal.items.isEmpty)) {
      throw _badEcho('saved meal');
    }
    return List<SavedMeal>.unmodifiable(meals);
  }

  @override
  Future<SavedMeal> saveMealFromDiary({
    required String name,
    required String sourceDate,
    required MealType sourceMealType,
  }) async {
    requireDiaryDate(sourceDate);
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Enter a name for this meal');
    }
    final SavedMeal meal = await _request(
      (CancelToken token) => _service.saveMealFromDiary(
        name: name,
        sourceDate: sourceDate,
        sourceMealType: sourceMealType,
        cancelToken: token,
      ),
    );
    if (meal.id.isEmpty || meal.items.isEmpty) throw _badEcho('saved meal');
    return meal;
  }

  @override
  Future<void> deleteSavedMeal(String mealId) async {
    try {
      await _request(
        (CancelToken token) =>
            _service.deleteSavedMeal(mealId, cancelToken: token),
      );
    } catch (error) {
      // Deleting an already-deleted template has reached the desired state.
      if (error is! ApiException ||
          !error.isNotFound ||
          error.code != 'NO_SAVED_MEAL') {
        rethrow;
      }
    }
  }

  @override
  Future<MealLogResult> logSavedMeal({
    required String mealId,
    required String date,
    required MealType mealType,
    required String clientId,
  }) async {
    requireDiaryDate(date);
    final NutritionChange change = NutritionChange(dates: <String>{date});
    try {
      final MealLogResult result = await _request(
        (CancelToken token) => _service.logSavedMeal(
          mealId: mealId,
          date: date,
          mealType: mealType,
          clientId: clientId,
          cancelToken: token,
        ),
      );
      if (result.log.id.isEmpty ||
          result.log.date != date ||
          result.log.clientId != clientId) {
        throw _badEcho('saved meal log identity');
      }
      _changed(change);
      return result;
    } catch (error) {
      _reconcileUncertain(error, change);
      rethrow;
    }
  }

  @override
  Future<NutritionSummary> summary(String date) async {
    requireDiaryDate(date);
    final NutritionSummary summary = await _request(
      (CancelToken token) => _service.summary(date, cancelToken: token),
    );
    if (summary.date != date) throw _badEcho('date');
    return summary;
  }

  @override
  Future<NutritionTarget?> getTargets() => _request(
        (CancelToken token) => _service.getTargets(cancelToken: token),
      );

  @override
  Future<NutritionTarget> updateTargets(NutritionTargetEdit edit) async {
    final NutritionChange change = NutritionChange(targetsChanged: true);
    try {
      final NutritionTarget target = await _request(
        (CancelToken token) => _service.updateTargets(
          kcal: edit.kcal,
          proteinG: edit.proteinG,
          carbsG: edit.carbsG,
          fatG: edit.fatG,
          setup: edit.setup,
          cancelToken: token,
        ),
      );
      _changed(change);
      return target;
    } catch (error) {
      _reconcileUncertain(error, change);
      rethrow;
    }
  }

  static ApiException _badEcho(String field) => ApiException(
        message: 'The server returned a different $field. Please refresh.',
        code: 'BAD_ENVELOPE',
      );

  @override
  Future<NutritionTargetRecommendation> recommendTargets(
    NutritionTargetSetup setup, {
    required bool eligibilityConfirmed,
    CancelToken? cancelToken,
  }) async {
    final NutritionTargetRecommendation result = await _request(
      (CancelToken token) => _service.recommendTargets(
        setup,
        eligibilityConfirmed: eligibilityConfirmed,
        cancelToken: token,
      ),
      token: cancelToken,
    );
    if (result.setup != setup) throw _badEcho('recommendation inputs');
    return result;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final CancelToken token in _requests.toList()) {
      token.cancel('Nutrition session ended');
    }
    _requests.clear();
    unawaited(_changes.close());
  }
}
