import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fitness_app/models/food_log.dart';
import 'package:fitness_app/models/nutrition_models.dart';
import 'package:fitness_app/models/nutrition_target_setup.dart';
import 'package:fitness_app/models/saved_meal.dart';
import 'package:fitness_app/services/nutrition_repository.dart';
import 'package:fitness_app/services/nutrition_service.dart';

const String diaryDay = '2026-09-04';
const String previousDiaryDay = '2026-09-03';
const String foodId = 'aaaaaaaaaaaaaaaaaaaaaaaa';
const String logId = 'bbbbbbbbbbbbbbbbbbbbbbbb';
const Macros sampleMacros = Macros(kcal: 130, proteinG: 3, carbsG: 28, fatG: 1);
const Food sampleFood = Food(
  id: foodId,
  externalId: 'test:rice',
  name: 'Test rice',
  group: 'Test',
  per100g: sampleMacros,
  servings: <FoodServing>[
    FoodServing(
      label: '100 g',
      grams: 100,
      isDefault: true,
      origin: ServingOrigin.fallback100g,
    ),
  ],
  sourceName: 'Synthetic test fixture',
  sourceVersion: '1',
  licence: 'Test only',
);
const NutritionTarget sampleTarget =
    NutritionTarget(kcal: 2000, proteinG: 100, carbsG: 250, fatG: 65);

SavedMeal sampleSavedMeal({String id = 'cccccccccccccccccccccccc'}) =>
    SavedMeal(
      id: id,
      name: 'Regular lunch',
      defaultMealType: MealType.lunch,
      items: sampleLog().items,
      totals: sampleMacros,
      useCount: 0,
    );

FoodLog sampleLog({String date = diaryDay, String clientId = 'meal-1'}) =>
    FoodLog(
      id: logId,
      date: date,
      clientId: clientId,
      mealType: MealType.lunch,
      items: const <FoodLogItem>[
        FoodLogItem(
          foodId: foodId,
          grams: 100,
          quantity: 100,
          unitLabel: 'g',
          snapshot: FoodSnapshot(
            externalId: 'test:rice',
            name: 'Test rice',
            per100g: sampleMacros,
            sourceVersion: '1',
          ),
          macros: sampleMacros,
        ),
      ],
    );

MealLogDraft sampleDraft({String clientId = 'meal-1'}) => MealLogDraft(
      clientId: clientId,
      date: diaryDay,
      mealType: MealType.lunch,
      items: <DraftLogItem>[
        DraftLogItem.fromGrams(food: sampleFood, grams: 100),
      ],
    );

/// Implements the repository contract without a transport. Overrides may
/// deliberately ignore cancellation to exercise the Blocs' stale guards.
class FakeNutritionRepository implements NutritionRepository {
  Future<NutritionTargetRecommendation> Function(NutritionTargetSetup)?
      onRecommend;
  final List<NutritionTargetSetup> recommendations = <NutritionTargetSetup>[];
  final List<CancelToken?> recommendationTokens = <CancelToken?>[];
  @override
  Future<NutritionTargetRecommendation> recommendTargets(
    NutritionTargetSetup setup, {
    required bool eligibilityConfirmed,
    CancelToken? cancelToken,
  }) async {
    recommendations.add(setup);
    recommendationTokens.add(cancelToken);
    return onRecommend!(setup);
  }

  final StreamController<NutritionChange> notifications =
      StreamController<NutritionChange>.broadcast();
  final List<String> searches = <String>[];
  final List<CancelToken?> searchTokens = <CancelToken?>[];
  final List<String> diaryReads = <String>[];
  final List<String> summaryReads = <String>[];
  final List<MealLogDraft> creates = <MealLogDraft>[];
  final List<MealLogEdit> updates = <MealLogEdit>[];
  final List<String> deletes = <String>[];
  final List<NutritionTargetEdit> targetUpdates = <NutritionTargetEdit>[];
  final List<String> savedMealReads = <String>[];
  final List<String> savedMealDeletes = <String>[];
  final List<({String name, String date, MealType mealType})> savedMealSaves =
      <({String name, String date, MealType mealType})>[];
  final List<({String mealId, String date, MealType mealType, String clientId})>
      savedMealLogs =
      <({String mealId, String date, MealType mealType, String clientId})>[];
  List<SavedMeal> savedMeals = <SavedMeal>[sampleSavedMeal()];
  Future<FoodSearchResult> Function(String)? onSearch;
  Future<List<FoodLog>> Function(String)? onList;
  Future<NutritionSummary> Function(String)? onSummary;
  Future<MealLogResult> Function(MealLogDraft)? onCreate;
  Future<FoodLog> Function(MealLogEdit)? onUpdate;
  Future<void> Function(String)? onDelete;
  Future<NutritionTarget> Function(NutritionTargetEdit)? onTargets;
  bool disposed = false;
  int _nextId = 0;

  @override
  Stream<NutritionChange> get changes => notifications.stream;
  void notify(NutritionChange change) {
    if (!disposed) notifications.add(change);
  }

  @override
  String newClientId() => 'test-${++_nextId}';
  @override
  Future<FoodSearchResult> searchFoods(
    String query, {
    int limit = 20,
    CancelToken? cancelToken,
  }) async {
    searches.add(query);
    searchTokens.add(cancelToken);
    return onSearch == null
        ? (
            foods: <Food>[sampleFood],
            query: query,
            catalogueEmpty: false,
            globalLookupUnavailable: false,
          )
        : await onSearch!(query);
  }

  @override
  Future<Food> getFood(String idOrExternalId) async => sampleFood;
  @override
  Future<List<FoodLog>> listLogs(String date) async {
    diaryReads.add(date);
    return onList == null ? <FoodLog>[] : await onList!(date);
  }

  @override
  Future<NutritionSummary> summary(String date) async {
    summaryReads.add(date);
    return onSummary == null
        ? NutritionSummary.empty(date)
        : await onSummary!(date);
  }

  @override
  Future<MealLogResult> createLog(MealLogDraft draft) async {
    creates.add(draft);
    final MealLogResult result = onCreate == null
        ? (
            log: sampleLog(date: draft.date, clientId: draft.clientId),
            duplicate: false
          )
        : await onCreate!(draft);
    notify(NutritionChange(dates: <String>{draft.date, result.log.date}));
    return result;
  }

  @override
  Future<FoodLog> updateLog(MealLogEdit edit) async {
    updates.add(edit);
    final FoodLog log = onUpdate == null
        ? sampleLog(date: edit.date ?? edit.originalDate)
        : await onUpdate!(edit);
    notify(NutritionChange(dates: <String>{edit.originalDate, log.date}));
    return log;
  }

  @override
  Future<void> deleteLog(String logId, {required String date}) async {
    deletes.add(logId);
    if (onDelete != null) await onDelete!(logId);
    notify(NutritionChange(dates: <String>{date}));
  }

  @override
  Future<List<SavedMeal>> listSavedMeals() async {
    savedMealReads.add('list');
    return List<SavedMeal>.unmodifiable(savedMeals);
  }

  @override
  Future<SavedMeal> saveMealFromDiary({
    required String name,
    required String sourceDate,
    required MealType sourceMealType,
  }) async {
    savedMealSaves.add(
      (
        name: name,
        date: sourceDate,
        mealType: sourceMealType,
      ),
    );
    final SavedMeal meal = SavedMeal(
      id: 'saved-${savedMealSaves.length}',
      name: name,
      defaultMealType: sourceMealType,
      items: sampleLog().items,
      totals: sampleMacros,
      useCount: 0,
    );
    savedMeals = <SavedMeal>[meal, ...savedMeals];
    return meal;
  }

  @override
  Future<void> deleteSavedMeal(String mealId) async {
    savedMealDeletes.add(mealId);
    savedMeals =
        savedMeals.where((SavedMeal meal) => meal.id != mealId).toList();
  }

  @override
  Future<MealLogResult> logSavedMeal({
    required String mealId,
    required String date,
    required MealType mealType,
    required String clientId,
  }) async {
    savedMealLogs.add(
      (
        mealId: mealId,
        date: date,
        mealType: mealType,
        clientId: clientId,
      ),
    );
    final FoodLog log = FoodLog(
      id: 'saved-log-${savedMealLogs.length}',
      date: date,
      mealType: mealType,
      clientId: clientId,
      items: sampleLog().items,
    );
    notify(NutritionChange(dates: <String>{date}));
    return (log: log, duplicate: false);
  }

  @override
  Future<NutritionTarget?> getTargets() async => null;
  @override
  Future<NutritionTarget> updateTargets(NutritionTargetEdit edit) async {
    targetUpdates.add(edit);
    final NutritionTarget target =
        onTargets == null ? sampleTarget : await onTargets!(edit);
    notify(NutritionChange(targetsChanged: true));
    return target;
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    unawaited(notifications.close());
  }
}
