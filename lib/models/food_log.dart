import 'package:equatable/equatable.dart';

import '../utils/nutrition_math.dart';
import 'nutrition_models.dart';
import 'nutrition_target_setup.dart';

/// The frozen copy of a food's composition, taken when it was logged.
///
/// Mirrors `IFoodSnapshot`. This is the one place denormalising is
/// correct: if a food's macros are corrected later — and they will be,
/// the import pipeline already repairs 24 of 542 IFCT records — a
/// historical day must not silently change underneath the user. What they
/// ate on Tuesday is what Tuesday's numbers were.
class FoodSnapshot extends Equatable {
  const FoodSnapshot({
    required this.externalId,
    required this.name,
    required this.per100g,
    required this.sourceVersion,
    this.source,
  });

  final String externalId;
  final String name;
  final Macros per100g;

  /// Null when unrecognised — never defaulted to `user`, which would
  /// claim the user authored data that came from IFCT or USDA.
  final FoodSource? source;

  final String sourceVersion;

  factory FoodSnapshot.fromJson(Map<String, dynamic> json) {
    final Object? raw = json['per100g'];
    return FoodSnapshot(
      externalId: (json['externalId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      per100g: raw is Map<String, dynamic> ? Macros.fromJson(raw) : Macros.zero,
      source: FoodSource.fromApi(json['source'] as String?),
      sourceVersion: (json['sourceVersion'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[externalId, name, per100g, source, sourceVersion];
}

/// One food inside a log entry. Mirrors `PublicFoodLogItem`.
class FoodLogItem extends Equatable {
  const FoodLogItem({
    required this.foodId,
    required this.grams,
    required this.quantity,
    required this.unitLabel,
    required this.snapshot,
    required this.macros,
  });

  final String foodId;

  /// Metric is canonical (decision #3). Grams is what is stored and sent;
  /// katori and roti are an input and display layer over it, exactly like
  /// cm/in and kg/lbs elsewhere in the app.
  final double grams;

  /// How many of [unitLabel] the user picked — 1.5 katori, 2 rotis.
  final double quantity;
  final String unitLabel;

  final FoodSnapshot snapshot;

  /// Computed by the server from the snapshot. Trusted rather than
  /// recomputed so the client and server can never disagree on a number
  /// the user is looking at.
  final Macros macros;

  String get name => snapshot.name;

  /// What the portion picker showed: "1.5 × 1 katori", or "150 g".
  String get portionLabel {
    return NutritionMath.isGramUnitLabel(unitLabel)
        ? '${_trim(quantity)} g'
        : '${_trim(quantity)} × $unitLabel';
  }

  /// Two decimals at most, and no trailing zeroes — "1", "1.5", "0.25".
  /// The second replace catches "3.00" collapsing to a bare "3.".
  static String _trim(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  /// Builds the request body for `nutritionLogItemSchema`.
  ///
  /// Deliberately omits the snapshot and macros — the server rebuilds both
  /// from its own copy of the food, so sending them would be ignored at
  /// best and a spoofing surface at worst.
  Map<String, dynamic> toRequestJson() => <String, dynamic>{
        'foodId': foodId,
        'grams': grams,
        'quantity': quantity,
        'unitLabel': unitLabel,
      };

  factory FoodLogItem.fromJson(Map<String, dynamic> json) {
    final Object? rawSnapshot = json['snapshot'];
    final Object? rawMacros = json['macros'];
    final FoodSnapshot snapshot = rawSnapshot is Map<String, dynamic>
        ? FoodSnapshot.fromJson(rawSnapshot)
        : const FoodSnapshot(
            externalId: '',
            name: '',
            per100g: Macros.zero,
            sourceVersion: '',
          );
    final double grams = _num(json['grams']);

    return FoodLogItem(
      foodId: (json['foodId'] ?? '').toString(),
      grams: grams,
      quantity: _num(json['quantity']),
      unitLabel: (json['unitLabel'] ?? '').toString(),
      snapshot: snapshot,
      // Fall back to computing it: `macros` is present on every response
      // today, but a locally cached or optimistic entry may not carry one,
      // and a zeroed row on the summary screen looks like lost data.
      macros: rawMacros is Map<String, dynamic>
          ? Macros.fromJson(rawMacros)
          : snapshot.per100g.forGrams(grams),
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[foodId, grams, quantity, unitLabel, snapshot, macros];
}

/// One meal entry — a set of foods logged together against a diary day.
/// Mirrors `PublicFoodLog`.
class FoodLog extends Equatable {
  const FoodLog({
    required this.id,
    required this.date,
    required this.mealType,
    required this.items,
    this.clientId,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// `YYYY-MM-DD`, the user's local calendar day. See `DiaryDate`.
  final String date;

  /// Null when the server sends a meal type this build does not know.
  ///
  /// The tempting default is `snack`, and it is the wrong one: it files
  /// the entry under a real meal the user did not choose, and the diary
  /// then shows two "Snack" groups whose contents cannot be told apart.
  /// A null lands in an explicit "Other" bucket instead, which is honest
  /// and recoverable.
  final MealType? mealType;

  final List<FoodLogItem> items;

  /// Idempotency key (decision #23). A retry after a dropped response
  /// returns the original entry instead of logging the meal twice.
  final String? clientId;

  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Rounded at every step, matching the server's `sumMacros`.
  Macros get totals =>
      NutritionMath.sumMacros(items.map((FoodLogItem i) => i.macros));

  factory FoodLog.fromJson(Map<String, dynamic> json) {
    final Object? rawItems = json['items'];
    return FoodLog(
      id: (json['id'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      mealType: MealType.fromApi(json['mealType'] as String?),
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(FoodLogItem.fromJson)
              .toList()
          : const <FoodLogItem>[],
      clientId: json['clientId'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[id, date, mealType, items, clientId, notes, updatedAt];
}

/// One meal's slice of the day. Mirrors `MealSummary`.
class MealSummary extends Equatable {
  const MealSummary({
    required this.mealType,
    required this.totals,
    required this.logCount,
    required this.itemCount,
  });

  /// Null when unrecognised. The row is kept rather than dropped so its
  /// totals still reconcile with the day total, but [mealFor] will never
  /// hand it back in place of a known meal.
  final MealType? mealType;

  final Macros totals;
  final int logCount;
  final int itemCount;

  bool get isEmpty => itemCount == 0;

  factory MealSummary.fromJson(Map<String, dynamic> json) {
    final Object? raw = json['totals'];
    return MealSummary(
      mealType: MealType.fromApi(json['mealType'] as String?),
      totals: raw is Map<String, dynamic> ? Macros.fromJson(raw) : Macros.zero,
      logCount: (json['logCount'] as num?)?.toInt() ?? 0,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => <Object?>[mealType, totals, logCount, itemCount];
}

/// A user's daily goals. Mirrors `PublicNutritionTarget`.
///
/// Null on the client means "not set yet", which is a real state — the
/// server returns `target: null` until onboarding computes one.
class NutritionTarget extends Equatable {
  const NutritionTarget({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.updatedAt,
    this.setup,
  });

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final DateTime? updatedAt;

  /// Saved calculator inputs only; reopening never recalculates silently.
  final NutritionTargetSetup? setup;

  /// The server's own bounds, mirrored so the client can reject an unsafe
  /// value before sending it rather than surfacing a 422. The kcal floor
  /// is not arbitrary: a goal screen that accepts 800 kcal/day is a
  /// wellbeing problem first and a Play policy problem second.
  static const double minKcal = 1000;
  static const double maxKcal = 10000;
  static const double maxProteinG = 1000;
  static const double maxCarbsG = 1500;
  static const double maxFatG = 500;

  static bool isSafeKcal(double value) =>
      value.isFinite && value >= minKcal && value <= maxKcal;

  Macros get asMacros =>
      Macros(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG);

  factory NutritionTarget.fromJson(Map<String, dynamic> json) {
    return NutritionTarget(
      kcal: _num(json['kcal']),
      proteinG: _num(json['proteinG']),
      carbsG: _num(json['carbsG']),
      fatG: _num(json['fatG']),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
      setup: json['setup'] is Map<String, dynamic>
          ? NutritionTargetSetup.fromJson(json['setup'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[kcal, proteinG, carbsG, fatG, updatedAt, setup];
}

/// The whole day in one object — what the summary screen renders.
/// Mirrors the `summary` payload built by `nutritionService.summary`.
class NutritionSummary extends Equatable {
  const NutritionSummary({
    required this.date,
    required this.totals,
    required this.meals,
    this.target,
  });

  final String date;
  final Macros totals;

  /// Always all four meal types, in chronological order, including the
  /// empty ones — the server builds it by mapping over `MEAL_TYPES`, so
  /// the summary screen can lay out its sections without null checks.
  final List<MealSummary> meals;

  final NutritionTarget? target;

  bool get hasTarget => target != null;
  bool get isEmpty => totals.isZero;

  /// Energy still available against the target. Negative once over.
  double? get kcalRemaining =>
      target == null ? null : target!.kcal - totals.kcal;

  /// Progress on each of the four rings or bars, clamped to `[0, 1]`.
  ///
  /// Clamped because a progress indicator fed 1.4 either overflows its
  /// track or wraps, and neither reads as "you have gone over". Use
  /// [rawProgress] to decide whether to show an over-target treatment,
  /// and this to draw the fill.
  ({double kcal, double protein, double carbs, double fat}) get progress {
    final ({double kcal, double protein, double carbs, double fat}) raw =
        rawProgress;
    return (
      kcal: raw.kcal.clamp(0.0, 1.0),
      protein: raw.protein.clamp(0.0, 1.0),
      carbs: raw.carbs.clamp(0.0, 1.0),
      fat: raw.fat.clamp(0.0, 1.0),
    );
  }

  /// Unclamped progress — greater than 1 once the target is exceeded.
  /// Zero throughout when no target is set, rather than a divide by zero.
  ({double kcal, double protein, double carbs, double fat}) get rawProgress {
    final NutritionTarget? goal = target;
    if (goal == null) {
      return (kcal: 0.0, protein: 0.0, carbs: 0.0, fat: 0.0);
    }
    double share(double consumed, double against) =>
        against <= 0 ? 0 : consumed / against;
    return (
      kcal: share(totals.kcal, goal.kcal),
      protein: share(totals.proteinG, goal.proteinG),
      carbs: share(totals.carbsG, goal.carbsG),
      fat: share(totals.fatG, goal.fatG),
    );
  }

  MealSummary? mealFor(MealType type) {
    for (final MealSummary meal in meals) {
      if (meal.mealType == type) return meal;
    }
    return null;
  }

  /// An empty day, for the initial state before the first fetch lands.
  factory NutritionSummary.empty(String date, {NutritionTarget? target}) {
    return NutritionSummary(
      date: date,
      totals: Macros.zero,
      meals: MealType.values
          .map(
            (MealType type) => MealSummary(
              mealType: type,
              totals: Macros.zero,
              logCount: 0,
              itemCount: 0,
            ),
          )
          .toList(),
      target: target,
    );
  }

  factory NutritionSummary.fromJson(Map<String, dynamic> json) {
    final Object? rawTotals = json['totals'];
    final Object? rawMeals = json['meals'];
    final Object? rawTarget = json['target'];

    return NutritionSummary(
      date: (json['date'] ?? '').toString(),
      totals: rawTotals is Map<String, dynamic>
          ? Macros.fromJson(rawTotals)
          : Macros.zero,
      meals: rawMeals is List
          ? rawMeals
              .whereType<Map<String, dynamic>>()
              .map(MealSummary.fromJson)
              .toList()
          : const <MealSummary>[],
      target: rawTarget is Map<String, dynamic>
          ? NutritionTarget.fromJson(rawTarget)
          : null,
    );
  }

  @override
  List<Object?> get props => <Object?>[date, totals, meals, target];
}

double _num(Object? value) => (value as num?)?.toDouble() ?? 0;
