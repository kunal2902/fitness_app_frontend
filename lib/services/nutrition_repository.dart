import 'package:dio/dio.dart' show CancelToken;

import '../models/api_exception.dart';
import '../models/food_log.dart';
import '../models/nutrition_models.dart';
import '../models/nutrition_target_setup.dart';
import '../utils/diary_date.dart';
import 'nutrition_service.dart';

typedef FoodSearchResult = ({
  List<Food> foods,
  String query,

  /// True when the server has no searchable foods at all — an
  /// unimported catalogue, not a failed match.
  bool catalogueEmpty,

  /// The local catalogue missed and the server could not reach its global
  /// provider. This is operational, not a spelling/no-match result.
  bool globalLookupUnavailable,
});
typedef MealLogResult = ({FoodLog log, bool duplicate});

/// Create once per meal form. Keep the same draft/clientId for retries.
class MealLogDraft {
  MealLogDraft({
    required String clientId,
    required this.date,
    required this.mealType,
    required List<DraftLogItem> items,
    this.notes,
  })  : clientId = clientId.trim(),
        items = List<DraftLogItem>.unmodifiable(items) {
    requireDiaryDate(date);
    if (this.clientId.isEmpty || this.clientId.length > 64) {
      throw ArgumentError.value(clientId, 'clientId', 'Use a stable meal ID');
    }
  }

  final String clientId;
  final String date;
  final MealType mealType;
  final List<DraftLogItem> items;
  final String? notes;
}

/// Carries the old day too, so moving a log invalidates both diary days.
class MealLogEdit {
  MealLogEdit({
    required this.logId,
    required this.originalDate,
    this.date,
    this.mealType,
    List<DraftLogItem>? items,
    this.notes,
    this.clearNotes = false,
  }) : items = items == null ? null : List<DraftLogItem>.unmodifiable(items) {
    requireDiaryDate(originalDate);
    if (date != null) requireDiaryDate(date!);
  }

  final String logId;
  final String originalDate;
  final String? date;
  final MealType? mealType;
  final List<DraftLogItem>? items;
  final String? notes;
  final bool clearNotes;
}

class NutritionTargetEdit {
  const NutritionTargetEdit({
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.setup,
  });
  final double? kcal;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final NutritionTargetSetup? setup;
}

/// Invalidation, not an optimistic claim that a mutation was saved.
class NutritionChange {
  NutritionChange({
    Set<String> dates = const <String>{},
    this.targetsChanged = false,
  }) : dates = Set<String>.unmodifiable(dates);
  final Set<String> dates;
  final bool targetsChanged;
  bool affects(String date) => targetsChanged || dates.contains(date);
}

/// One instance per signed-in session, shared by all three nutrition Blocs.
/// A future local/API hybrid can implement this without changing the Blocs.
abstract interface class NutritionRepository {
  /// Publish affected dates after successful mutations. Ambiguous network
  /// failures should also invalidate reads so the diary can reconcile.
  Stream<NutritionChange> get changes;
  String newClientId();
  Future<FoodSearchResult> searchFoods(
    String query, {
    int limit = 20,
    CancelToken? cancelToken,
  });
  Future<Food> getFood(String idOrExternalId);
  Future<List<FoodLog>> listLogs(String date);
  Future<MealLogResult> createLog(MealLogDraft draft);
  Future<FoodLog> updateLog(MealLogEdit edit);
  Future<void> deleteLog(String logId, {required String date});
  Future<NutritionSummary> summary(String date);
  Future<NutritionTarget?> getTargets();
  Future<NutritionTarget> updateTargets(NutritionTargetEdit edit);
  Future<NutritionTargetRecommendation> recommendTargets(
    NutritionTargetSetup setup, {
    required bool eligibilityConfirmed,
    CancelToken? cancelToken,
  });
  void dispose();
}

String normalizeFoodQuery(String query) {
  final String trimmed = query.trim();
  return trimmed.length <= NutritionService.maxQueryLength
      ? trimmed
      : trimmed.substring(0, NutritionService.maxQueryLength);
}

void requireDiaryDate(String date) {
  if (!DiaryDate.isValid(date)) {
    throw ArgumentError.value(date, 'date', 'Use a valid YYYY-MM-DD diary day');
  }
}

ApiException nutritionFailure(Object error) {
  if (error is ApiException) return error;
  if (error is ArgumentError) {
    return ApiException(
      message:
          error.message?.toString() ?? 'Please check your nutrition entry.',
      code: 'INVALID_INPUT',
      fieldErrors: <String, String>{
        if (error.name != null)
          error.name!: error.message?.toString() ?? 'Invalid value',
      },
    );
  }
  return const ApiException.unknown();
}
