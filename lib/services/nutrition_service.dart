import 'dart:math' as math;

import 'package:dio/dio.dart' show CancelToken;

import '../config/api_endpoints.dart';
import '../models/api_exception.dart';
import '../models/food_log.dart';
import '../models/nutrition_models.dart';
import '../models/nutrition_target_setup.dart';
import '../models/saved_meal.dart';
import '../utils/diary_date.dart';
import '../utils/nutrition_math.dart';
import 'api_client.dart';

/// One food, ready to be sent as part of a log.
///
/// Constructed through [DraftLogItem.of] rather than by hand, because the
/// `grams` field is not free-form: the server recomputes it from
/// `quantity × serving.grams` and rejects anything outside a
/// `max(0.1, 1%)` window. Building the value from the same `FoodServing`
/// the picker displayed is what keeps the two in agreement.
class DraftLogItem {
  /// Private so [of] and [fromGrams] are the only ways in. A public
  /// constructor taking `grams`, `quantity` and `unitLabel` separately
  /// would let a caller assemble a combination the server rejects — which
  /// is precisely what this class exists to make impossible.
  const DraftLogItem._({
    required this.foodId,
    required this.grams,
    required this.quantity,
    required this.unitLabel,
  });

  /// The server caps both at 10 000 (`nutritionLogItemSchema`).
  static const double maxGrams = 10000;

  /// From a food and one of *its own* servings.
  ///
  /// [serving] must have come from `food.servings` — the server looks the
  /// label up against that list and rejects anything it cannot find.
  factory DraftLogItem.of({
    required Food food,
    required FoodServing serving,
    required double quantity,
  }) {
    final double grams = serving.gramsFor(quantity);
    _requireLoggable(food, grams, quantity);
    return DraftLogItem._(
      foodId: food.id,
      grams: grams,
      quantity: quantity,
      unitLabel: serving.label,
    );
  }

  /// Direct gram entry, for the "just type the weight" path. The server
  /// accepts `g` / `gram` / `grams` as a unit whose quantity *is* the
  /// gram count, so both fields carry the same number here by design.
  ///
  /// Named `fromGrams`, not `grams`: a named constructor sharing a name
  /// with a member of the same class is a needless trap even where the
  /// analyzer tolerates it.
  factory DraftLogItem.fromGrams({
    required Food food,
    required double grams,
  }) {
    final double rounded = NutritionMath.round(grams);
    _requireLoggable(food, rounded, rounded);
    return DraftLogItem._(
      foodId: food.id,
      grams: rounded,
      quantity: rounded,
      unitLabel: 'g',
    );
  }

  /// Rebuilds a draft from an item the server already accepted.
  ///
  /// `PATCH /nutrition/logs/:id` replaces the whole `items` array, so
  /// editing one food in a multi-food meal means resending the others
  /// untouched. There is no `Food` in hand for those — a `FoodLog` carries
  /// only a snapshot — and [of] needs one, hence this.
  ///
  /// Safe by construction rather than by validation: every value here came
  /// back from a request the server's own `expectedItemGrams` already
  /// checked, so the quantity/label/grams combination is one it accepts.
  /// Round-tripping it cannot invent an invalid portion.
  factory DraftLogItem.fromLogItem(FoodLogItem item) {
    return DraftLogItem._(
      foodId: item.foodId,
      grams: item.grams,
      quantity: item.quantity,
      unitLabel: item.unitLabel,
    );
  }

  /// The three ways an item is rejected server-side, checked here so the
  /// failure names the actual problem instead of arriving as a 422.
  ///
  /// The id check matters more than it looks: `Food.id` is `''` for a food
  /// parsed from a bundled corpus keyed on `externalId`. `GET /foods/:id`
  /// accepts either form, but `nutritionLogItemSchema.foodId` accepts only
  /// a 24-hex ObjectId — so such a food can be *fetched* and not *logged*,
  /// and the resulting error reads like corrupt data rather than a
  /// missing id.
  static final RegExp _objectId = RegExp(r'^[a-fA-F0-9]{24}$');

  static void _requireLoggable(Food food, double grams, double quantity) {
    if (!_objectId.hasMatch(food.id)) {
      throw ArgumentError.value(
        food.id,
        'food.id',
        'This food has no server id, so it cannot be logged '
            '(externalId: ${food.externalId})',
      );
    }
    for (final (String name, double value) in <(String, double)>[
      ('grams', grams),
      ('quantity', quantity),
    ]) {
      if (!value.isFinite || value <= 0 || value > maxGrams) {
        throw ArgumentError.value(
          value,
          name,
          'Must be greater than 0 and at most ${maxGrams.toInt()}',
        );
      }
    }
  }

  final String foodId;
  final double grams;
  final double quantity;
  final String unitLabel;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'foodId': foodId,
        'grams': grams,
        'quantity': quantity,
        'unitLabel': unitLabel,
      };
}

/// REST client for the nutrition feature.
///
/// Thin on purpose: it maps endpoints to models and nothing else. All
/// caching, debouncing and offline behaviour belongs in the repository and
/// blocs above it, so a bundled local corpus can be swapped in later
/// without this file changing.
class NutritionService {
  NutritionService({ApiClient? client})
      : _client = client ?? ApiClient.instance;

  final ApiClient _client;
  final math.Random _random = math.Random.secure();

  // -------------------------------------------------------------------------
  // Foods
  // -------------------------------------------------------------------------

  /// The server's own cap on `q` (`foodSearchQuerySchema`). Trimmed to it
  /// rather than sent long, because a paste into the search box is a
  /// normal thing for a user to do and a 422 is not a useful answer.
  static const int maxQueryLength = 80;

  /// Type-ahead search.
  ///
  /// Pass a [cancelToken] and cancel it on the next keystroke, or a slow
  /// early response will land after a fast later one and repaint stale
  /// results. The returned `query` is the server's echo of what it
  /// actually searched for — compare it against the live search field
  /// before rendering, as a second guard on the same race.
  Future<
      ({
        List<Food> foods,
        String query,
        bool catalogueEmpty,
        bool globalLookupUnavailable,
      })> searchFoods(
    String query, {
    int limit = 20,
    CancelToken? cancelToken,
  }) async {
    String trimmed = query.trim();
    // The server requires a non-empty `q` and would 422. An empty search
    // box is a normal UI state, not an error.
    if (trimmed.isEmpty) {
      return (
        foods: <Food>[],
        query: '',
        catalogueEmpty: false,
        globalLookupUnavailable: false,
      );
    }
    if (trimmed.length > maxQueryLength) {
      trimmed = trimmed.substring(0, maxQueryLength);
    }

    final Map<String, dynamic> json = await _client.get(
      ApiEndpoints.foodSearch,
      query: <String, dynamic>{
        'q': trimmed,
        'limit': limit.clamp(1, 50),
      },
      cancelToken: cancelToken,
    );

    final Object? raw = json['foods'];
    if (raw is! List) throw _badShape('foods');
    return (
      foods: raw.whereType<Map<String, dynamic>>().map(Food.fromJson).toList(),
      query: (json['query'] ?? trimmed).toString(),
      // Only sent when the result is empty. Distinguishes "no food data
      // has been imported" from "that word does not match anything",
      // which otherwise look identical to the user.
      catalogueEmpty: json['catalogueEmpty'] == true,
      globalLookupUnavailable: json['globalLookupUnavailable'] == true,
    );
  }

  /// Fetches one food by Mongo id or by `externalId` (`ifct:A011`).
  Future<Food> getFood(
    String idOrExternalId, {
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _client
        .get(ApiEndpoints.food(idOrExternalId), cancelToken: cancelToken);
    return Food.fromJson(_object(json, 'food'));
  }

  // -------------------------------------------------------------------------
  // Diary
  // -------------------------------------------------------------------------

  /// Every entry for one local calendar day, oldest first.
  ///
  /// The echoed `date` is returned alongside: the user can page to another
  /// day while this is in flight, and without checking the echo a late
  /// response repaints yesterday's meals onto today.
  Future<({List<FoodLog> logs, String date})> listLogs(
    String date, {
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _client.get(
      ApiEndpoints.nutritionLogs,
      query: <String, dynamic>{'date': date},
      cancelToken: cancelToken,
    );
    final Object? raw = json['logs'];
    if (raw is! List) throw _badShape('logs');
    return (
      logs:
          raw.whereType<Map<String, dynamic>>().map(FoodLog.fromJson).toList(),
      date: (json['date'] ?? date).toString(),
    );
  }

  /// Logs a meal.
  ///
  /// [clientId] defaults to a fresh one because idempotency is only useful
  /// if it is on by default. Mobile data drops responses, the user taps Add
  /// again, and without this the meal is logged twice — the same failure
  /// the chat feature solved with the same primitive (decision #23).
  ///
  /// `duplicate: true` means the server already had this entry and
  /// returned the original. That is a success, not an error: show the meal
  /// as logged, and do not log it again.
  Future<({FoodLog log, bool duplicate})> createLog({
    required String date,
    required MealType mealType,
    required List<DraftLogItem> items,
    String? clientId,
    String? notes,
    CancelToken? cancelToken,
  }) async {
    _requireItemCount(items);

    final Map<String, dynamic> json = await _client.post(
      ApiEndpoints.nutritionLogs,
      cancelToken: cancelToken,
      body: <String, dynamic>{
        'date': date,
        'mealType': mealType.apiValue,
        'items': items.map((DraftLogItem i) => i.toJson()).toList(),
        'clientId': clientId ?? newClientId(),
        if (notes != null) 'notes': _trimNotes(notes),
      },
    );

    return (
      log: FoodLog.fromJson(_object(json, 'log')),
      duplicate: json['duplicate'] as bool? ?? false,
    );
  }

  /// Partial update. Only the fields you pass are sent — the server
  /// rejects an empty body with "Nothing to update", and sending unchanged
  /// values would let a stale copy clobber an edit made elsewhere
  /// (decision #8).
  ///
  /// [clearNotes] is the usual optional-argument problem: `notes: null`
  /// cannot be told from "not passed", so erasing a note needs its own
  /// flag.
  Future<FoodLog> updateLog(
    String logId, {
    String? date,
    MealType? mealType,
    List<DraftLogItem>? items,
    String? notes,
    bool clearNotes = false,
    CancelToken? cancelToken,
  }) async {
    if (items != null) _requireItemCount(items);

    final Map<String, dynamic> body = <String, dynamic>{
      if (date != null) 'date': date,
      if (mealType != null) 'mealType': mealType.apiValue,
      if (items != null)
        'items': items.map((DraftLogItem i) => i.toJson()).toList(),
      if (clearNotes)
        'notes': null
      else if (notes != null)
        'notes': _trimNotes(notes),
    };

    if (body.isEmpty) {
      throw ArgumentError('updateLog needs at least one field to change');
    }

    final Map<String, dynamic> json = await _client.patch(
      ApiEndpoints.nutritionLog(logId),
      body: body,
      cancelToken: cancelToken,
    );
    return FoodLog.fromJson(_object(json, 'log'));
  }

  Future<void> deleteLog(String logId, {CancelToken? cancelToken}) async {
    await _client.delete(
      ApiEndpoints.nutritionLog(logId),
      cancelToken: cancelToken,
    );
  }

  // -------------------------------------------------------------------------
  // Saved meals
  // -------------------------------------------------------------------------

  Future<List<SavedMeal>> listSavedMeals({CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _client.get(
      ApiEndpoints.savedMeals,
      cancelToken: cancelToken,
    );
    final Object? raw = json['meals'];
    if (raw is! List) throw _badShape('meals');
    return raw
        .whereType<Map<String, dynamic>>()
        .map(SavedMeal.fromJson)
        .toList();
  }

  Future<SavedMeal> saveMealFromDiary({
    required String name,
    required String sourceDate,
    required MealType sourceMealType,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _client.post(
      ApiEndpoints.savedMeals,
      cancelToken: cancelToken,
      body: <String, dynamic>{
        'name': name.trim(),
        'sourceDate': sourceDate,
        'sourceMealType': sourceMealType.apiValue,
      },
    );
    return SavedMeal.fromJson(_object(json, 'meal'));
  }

  Future<void> deleteSavedMeal(
    String mealId, {
    CancelToken? cancelToken,
  }) async {
    await _client.delete(
      ApiEndpoints.savedMeal(mealId),
      cancelToken: cancelToken,
    );
  }

  Future<({FoodLog log, bool duplicate})> logSavedMeal({
    required String mealId,
    required String date,
    required MealType mealType,
    required String clientId,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _client.post(
      ApiEndpoints.logSavedMeal(mealId),
      cancelToken: cancelToken,
      body: <String, dynamic>{
        'date': date,
        'mealType': mealType.apiValue,
        'clientId': clientId,
      },
    );
    return (
      log: FoodLog.fromJson(_object(json, 'log')),
      duplicate: json['duplicate'] as bool? ?? false,
    );
  }

  /// The whole day: totals, per-meal breakdown and the active target.
  Future<NutritionSummary> summary(
    String date, {
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> json = await _client.get(
      ApiEndpoints.nutritionSummary,
      query: <String, dynamic>{'date': date},
      cancelToken: cancelToken,
    );
    return NutritionSummary.fromJson(_object(json, 'summary'));
  }

  // -------------------------------------------------------------------------
  // Targets
  // -------------------------------------------------------------------------

  /// Null until the member explicitly saves goals — not a failure.
  Future<NutritionTarget?> getTargets({CancelToken? cancelToken}) async {
    final Map<String, dynamic> json = await _client
        .get(ApiEndpoints.nutritionTargets, cancelToken: cancelToken);

    // The key must be *present*; its value may legitimately be null. That
    // distinction is the whole point — an absent key means the envelope
    // changed, and treating that as "no target set" would quietly wipe a
    // user's goals off the summary screen.
    if (!json.containsKey('target')) throw _badShape('target');

    final Object? raw = json['target'];
    if (raw == null) return null;
    return NutritionTarget.fromJson(_object(json, 'target'));
  }

  /// Sets or adjusts the daily goals.
  ///
  /// The **first** call must supply all four — the server has nothing to
  /// merge a partial update into and returns a field-level validation
  /// error naming what is missing. After that, any subset is fine.
  ///
  /// API bounds are checked locally as well as server-side. These are
  /// validation limits, not a claim that every accepted intake is suitable.
  Future<NutritionTarget> updateTargets({
    double? kcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
    NutritionTargetSetup? setup,
    CancelToken? cancelToken,
  }) async {
    if (setup != null && setup.errors.isNotEmpty) {
      throw ApiException(
        message: 'Please check your target setup.',
        code: 'INVALID_INPUT',
        fieldErrors: setup.errors,
      );
    }
    if (kcal != null && !NutritionTarget.isSafeKcal(kcal)) {
      throw ArgumentError.value(
        kcal,
        'kcal',
        'Daily energy targets must be between '
            '${NutritionTarget.minKcal.toInt()} and '
            '${NutritionTarget.maxKcal.toInt()} kcal',
      );
    }
    // The macro ceilings the server enforces. Checked here too so an
    // out-of-range goal fails with a message naming the field rather than
    // as a 422 on the whole request.
    _requireInRange('proteinG', proteinG, NutritionTarget.maxProteinG);
    _requireInRange('carbsG', carbsG, NutritionTarget.maxCarbsG);
    _requireInRange('fatG', fatG, NutritionTarget.maxFatG);

    final Map<String, dynamic> body = <String, dynamic>{
      if (kcal != null) 'kcal': kcal,
      if (proteinG != null) 'proteinG': proteinG,
      if (carbsG != null) 'carbsG': carbsG,
      if (fatG != null) 'fatG': fatG,
      if (setup != null) 'setup': setup.toJson(),
    };

    if (body.isEmpty) {
      throw ArgumentError('updateTargets needs at least one field to change');
    }

    final Map<String, dynamic> json = await _client.patch(
      ApiEndpoints.nutritionTargets,
      body: body,
      cancelToken: cancelToken,
    );
    return NutritionTarget.fromJson(_object(json, 'target'));
  }

  Future<NutritionTargetRecommendation> recommendTargets(
    NutritionTargetSetup setup, {
    required bool eligibilityConfirmed,
    CancelToken? cancelToken,
  }) async {
    if (setup.errors.isNotEmpty || !eligibilityConfirmed) {
      throw ApiException(
        message: 'Please check your target setup.',
        code: 'INVALID_INPUT',
        fieldErrors: <String, String>{
          ...setup.errors,
          if (!eligibilityConfirmed)
            'eligibilityConfirmed':
                'Please confirm this estimate is suitable for you.',
        },
      );
    }
    final Map<String, dynamic> json = await _client.post(
      ApiEndpoints.nutritionRecommendation,
      body: <String, dynamic>{
        'setup': setup.toJson(),
        'eligibilityConfirmed': eligibilityConfirmed,
      },
      cancelToken: cancelToken,
    );
    try {
      return NutritionTargetRecommendation.fromJson(
        _object(json, 'recommendation'),
      );
    } on FormatException {
      throw _badShape('recommendation');
    } on StateError {
      throw _badShape('recommendation');
    }
  }

  // -------------------------------------------------------------------------

  /// Pulls a required object out of a response envelope.
  ///
  /// Throws rather than falling back to the envelope itself. The tempting
  /// `raw is Map ? raw : json` reads as defensive and is the opposite: a
  /// renamed or missing key would then be parsed as the model, and because
  /// every `fromJson` here coalesces absent fields to defaults, the result
  /// is not an error but a confident, empty, plausible object — a blank
  /// diary day, or a saved meal that quietly vanishes. Failing loudly is
  /// the only way a future contract break reaches anyone.
  static Map<String, dynamic> _object(Map<String, dynamic> json, String key) {
    final Object? raw = json[key];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw _badShape(key);
  }

  static ApiException _badShape(String key) => ApiException(
        message: 'The server sent something we did not understand.',
        code: 'BAD_ENVELOPE',
        fieldErrors: <String, String>{key: 'missing from the response'},
      );

  /// `nutritionLogItemSchema` allows 1–50 items. An empty list slips past
  /// the "nothing to update" guard — the body map is non-empty even when
  /// the items list is — and would arrive as a 422.
  static void _requireItemCount(List<DraftLogItem> items) {
    if (items.isEmpty || items.length > 50) {
      throw ArgumentError.value(
        items.length,
        'items',
        'A meal must contain between 1 and 50 foods',
      );
    }
  }

  /// The server caps notes at 500 characters and rejects the whole
  /// request past it — which would lose the meal the user just entered
  /// over a long note. Truncating is the kinder failure.
  static const int maxNotesLength = 500;

  static String _trimNotes(String notes) => notes.length <= maxNotesLength
      ? notes
      : notes.substring(0, maxNotesLength);

  static void _requireInRange(String field, double? value, double max) {
    if (value == null) return;
    if (!value.isFinite || value < 0 || value > max) {
      throw ArgumentError.value(
        value,
        field,
        'Must be between 0 and ${max.toInt()}',
      );
    }
  }

  /// Same shape as the chat bloc's: a microsecond stamp plus random salt.
  /// Unique per device without pulling in a uuid dependency.
  String newClientId() {
    final int stamp = DateTime.now().microsecondsSinceEpoch;
    final int salt = _random.nextInt(0xFFFFFF);
    return '$stamp-${salt.toRadixString(16)}';
  }

  /// Convenience for "log this now" — today's diary day, on the device's
  /// own clock. See `DiaryDate` for why this is not an ISO substring.
  String get today => DiaryDate.today();
}
