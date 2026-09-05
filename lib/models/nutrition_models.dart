import 'package:equatable/equatable.dart';

import '../utils/nutrition_math.dart';

// ---------------------------------------------------------------------------
// Enum vocabularies
//
// Decision #5: every `apiValue` below must stay byte-identical to the
// `as const` array it names. They are the wire contract — a typo here is a
// runtime failure with no compiler to catch it.
// ---------------------------------------------------------------------------

/// Mirrors `FOOD_SOURCES` in `src/nutrition/food.schema.ts`.
enum FoodSource {
  ifct2017('ifct2017', 'IFCT 2017'),
  indb('indb', 'INDB'),
  usda('usda', 'USDA'),
  openFoodFacts('openfoodfacts', 'Open Food Facts'),
  user('user', 'Added by you');

  const FoodSource(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static FoodSource? fromApi(String? raw) {
    for (final FoodSource value in FoodSource.values) {
      if (value.apiValue == raw) return value;
    }
    return null;
  }
}

/// Mirrors `ENERGY_SOURCES`. Kept on the client because it is the audit
/// trail for the import-time energy repair: `atwater_repair` means the
/// dataset's own kcal figure was wrong (all 14 edible oils report zero)
/// and the value shown was recomputed from the macros.
enum EnergySource {
  sourceKj('source_kj', 'Converted from kJ'),
  sourceKcal('source_kcal', 'As published'),
  atwaterRepair('atwater_repair', 'Recalculated from macros');

  const EnergySource(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// True when the published energy figure was not usable and the value
  /// was derived. Worth surfacing on the food detail screen — it is the
  /// difference between a measured number and a computed one.
  bool get isDerived => this == EnergySource.atwaterRepair;

  static EnergySource? fromApi(String? raw) {
    for (final EnergySource value in EnergySource.values) {
      if (value.apiValue == raw) return value;
    }
    return null;
  }
}

/// Mirrors `SERVING_ORIGINS`. Says where a household portion came from —
/// the dataset, a curated NIN-backed figure, or the plain 100 g fallback.
enum ServingOrigin {
  fallback100g('fallback_100g', 'Standard'),
  sourceDataset('source_dataset', 'From dataset'),
  curated('curated', 'Curated');

  const ServingOrigin(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ServingOrigin? fromApi(String? raw) {
    for (final ServingOrigin value in ServingOrigin.values) {
      if (value.apiValue == raw) return value;
    }
    return null;
  }
}

/// Mirrors `MEAL_TYPES` in `src/models/foodLog.model.ts`.
///
/// Declaration order is the order meals are displayed and the order the
/// server returns them in `summary.meals`, so keep it chronological.
enum MealType {
  breakfast('breakfast', 'Breakfast'),
  lunch('lunch', 'Lunch'),
  dinner('dinner', 'Dinner'),
  snack('snack', 'Snack');

  const MealType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MealType? fromApi(String? raw) {
    for (final MealType value in MealType.values) {
      if (value.apiValue == raw) return value;
    }
    return null;
  }

  /// A sensible default for the "log something now" button, from the
  /// device clock. Breakfast before 11, lunch before 16, dinner before 22.
  static MealType suggestedFor(DateTime moment) {
    final int hour = moment.hour;
    if (hour < 11) return MealType.breakfast;
    if (hour < 16) return MealType.lunch;
    if (hour < 22) return MealType.dinner;
    return MealType.snack;
  }
}

// ---------------------------------------------------------------------------
// Macros
// ---------------------------------------------------------------------------

/// Energy and the three macronutrients.
///
/// Doubles as both the per-100 g composition and a computed total — the
/// server uses one shape for both (`FoodMacros` and `MacroTotals` are
/// structurally identical), so one class here keeps the mapping honest.
class Macros extends Equatable {
  const Macros({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  static const Macros zero =
      Macros(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0);

  bool get isZero => kcal == 0 && proteinG == 0 && carbsG == 0 && fatG == 0;

  /// Scales a per-100 g composition to a mass. Delegates so there is
  /// exactly one implementation of the rounding rule.
  Macros forGrams(double grams) => NutritionMath.macrosForGrams(this, grams);

  /// Energy implied by the macros using Atwater factors (4/4/9).
  ///
  /// Not a replacement for [kcal] — it is the cross-check the import
  /// pipeline uses, exposed so a UI can flag a food whose published energy
  /// disagrees with its own composition.
  double get atwaterKcal =>
      NutritionMath.round(proteinG * 4 + carbsG * 4 + fatG * 9);

  /// Share of energy from each macro, for a split bar. Sums to ~1.
  /// Falls back to zeroes rather than dividing by zero for water, spices
  /// and anything else with no energy at all.
  ({double protein, double carbs, double fat}) get energySplit {
    final double total = proteinG * 4 + carbsG * 4 + fatG * 9;
    if (total <= 0) return (protein: 0.0, carbs: 0.0, fat: 0.0);
    return (
      protein: proteinG * 4 / total,
      carbs: carbsG * 4 / total,
      fat: fatG * 9 / total,
    );
  }

  factory Macros.fromJson(Map<String, dynamic> json) {
    return Macros(
      kcal: _num(json['kcal']),
      proteinG: _num(json['proteinG']),
      carbsG: _num(json['carbsG']),
      fatG: _num(json['fatG']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kcal': kcal,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
      };

  @override
  List<Object?> get props => <Object?>[kcal, proteinG, carbsG, fatG];
}

double _num(Object? value) => (value as num?)?.toDouble() ?? 0;

// ---------------------------------------------------------------------------
// Food
// ---------------------------------------------------------------------------

/// A name for a food in one Indian language. Mirrors `FoodAlias`.
///
/// This is the search feature, not decoration: the IFCT `lang` field
/// yields ~11 aliases per food, which is how `poha` finds "Rice flakes"
/// and `bhindi` finds "Ladies finger". An English-only index finds neither.
class FoodAlias extends Equatable {
  const FoodAlias({required this.lang, required this.name});

  final String lang;
  final String name;

  factory FoodAlias.fromJson(Map<String, dynamic> json) => FoodAlias(
        lang: (json['lang'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
      );

  @override
  List<Object?> get props => <Object?>[lang, name];
}

/// Where a curated portion figure came from. Mirrors `ServingEvidence`.
class ServingEvidence extends Equatable {
  const ServingEvidence({
    required this.sourceName,
    required this.sourceUrl,
    required this.sourceLocator,
    this.notes = '',
  });

  final String sourceName;
  final String sourceUrl;
  final String sourceLocator;
  final String notes;

  factory ServingEvidence.fromJson(Map<String, dynamic> json) =>
      ServingEvidence(
        sourceName: (json['sourceName'] ?? '').toString(),
        sourceUrl: (json['sourceUrl'] ?? '').toString(),
        sourceLocator: (json['sourceLocator'] ?? '').toString(),
        notes: (json['notes'] ?? '').toString(),
      );

  @override
  List<Object?> get props =>
      <Object?>[sourceName, sourceUrl, sourceLocator, notes];
}

/// A household portion — "1 katori", "1 roti", "100 g".
class FoodServing extends Equatable {
  const FoodServing({
    required this.label,
    required this.grams,
    required this.isDefault,
    required this.origin,
    this.evidence,
  });

  final String label;
  final double grams;
  final bool isDefault;

  /// Null when the server sends an origin this build does not know.
  ///
  /// Not defaulted to `fallback100g`: that would label an unrecognised
  /// origin "Standard", which is a provenance claim rather than a
  /// harmless placeholder. Null makes the gap visible to the UI.
  final ServingOrigin? origin;

  /// Null for the plain 100 g fallback; required for anything else. The
  /// server enforces that asymmetry, so it is not worth re-checking here.
  final ServingEvidence? evidence;

  /// Grams for [quantity] of this serving — the *only* correct way to
  /// produce the `grams` field of a log item.
  double gramsFor(double quantity) =>
      NutritionMath.servingQuantityToGrams(grams, quantity);

  /// Normalised label, as the server matches it.
  String get key => NutritionMath.labelKey(label);

  /// True for the 100 g row every food is guaranteed to carry.
  bool get isHundredGrams =>
      (grams - 100).abs() < 0.001 && key.replaceAll(' ', '') == '100g';

  factory FoodServing.fromJson(Map<String, dynamic> json) {
    final Object? rawEvidence = json['evidence'];
    return FoodServing(
      label: (json['label'] ?? '').toString(),
      grams: _num(json['grams']),
      isDefault: json['isDefault'] as bool? ?? false,
      origin: ServingOrigin.fromApi(json['origin'] as String?),
      evidence: rawEvidence is Map<String, dynamic>
          ? ServingEvidence.fromJson(rawEvidence)
          : null,
    );
  }

  @override
  List<Object?> get props => <Object?>[label, grams, isDefault, origin];
}

/// A food as the API returns it. Mirrors `PublicFood`.
class Food extends Equatable {
  const Food({
    required this.id,
    required this.externalId,
    required this.name,
    required this.group,
    required this.per100g,
    required this.servings,
    required this.sourceName,
    required this.sourceVersion,
    required this.licence,
    this.source,
    this.energySource,
    this.scientificName,
    this.aliases = const <FoodAlias>[],
    this.dietaryTags = const <String>[],
    this.sourceAttribution,
    this.verified = false,
    this.isRecipe = false,
  });

  /// Mongo id. Log items reference the food by this, not by [externalId].
  final String id;

  /// Stable cross-import identity, e.g. `ifct:A011`. Also accepted by
  /// `GET /foods/:id`, which is what makes a bundled local corpus and the
  /// server interchangeable.
  final String externalId;

  final String name;
  final String? scientificName;
  final List<FoodAlias> aliases;
  final String group;
  final List<String> dietaryTags;
  final Macros per100g;
  final List<FoodServing> servings;

  /// Null when this build does not recognise the source string.
  ///
  /// Defaulting to `FoodSource.user` would render an IFCT or USDA food as
  /// "Added by you" — an attribution claim about data we did not create.
  final FoodSource? source;

  final String sourceName;
  final String sourceVersion;
  final String? sourceAttribution;
  final String licence;

  /// Null when unrecognised. Emphatically not defaulted to `sourceKcal`:
  /// this field is the audit trail for the import-time energy repair, and
  /// silently labelling an unknown value "As published" inverts the exact
  /// signal it exists to carry.
  final EnergySource? energySource;

  final bool verified;

  /// True for INDB's cooked dishes, false for IFCT's raw ingredients.
  /// Recipes are what people log; ingredients are the reference underneath.
  final bool isRecipe;

  bool get hasServings => servings.isNotEmpty;

  /// The serving to preselect in the portion picker, or null if the food
  /// carries none and therefore cannot be logged at all.
  ///
  /// Null rather than a synthesized "100 g": that label has to match one
  /// the *server* holds for this food, and the schema only guarantees a
  /// row normalising to `100g` — which permits the spelling "100g" with no
  /// space. Sending an invented `unitLabel` fails portion validation with
  /// "100 g is not a serving for X", which reads as corrupt data rather
  /// than as the missing-servings bug it is.
  FoodServing? get defaultServing {
    for (final FoodServing serving in servings) {
      if (serving.isDefault) return serving;
    }
    for (final FoodServing serving in servings) {
      if (serving.isHundredGrams) return serving;
    }
    return servings.isNotEmpty ? servings.first : null;
  }

  /// Looks up a serving the way the server does — by normalised label.
  FoodServing? servingByLabel(String label) {
    final String wanted = NutritionMath.labelKey(label);
    for (final FoodServing serving in servings) {
      if (serving.key == wanted) return serving;
    }
    return null;
  }

  /// Energy in one of the default serving, for a search-result subtitle.
  /// Null when the food has no servings — see [defaultServing].
  double? get kcalPerDefaultServing {
    final FoodServing? serving = defaultServing;
    return serving == null ? null : per100g.forGrams(serving.grams).kcal;
  }

  /// Non-English names worth showing under the title, deduplicated and
  /// excluding anything that is just the English name again.
  List<String> get displayAliases {
    final Set<String> seen = <String>{name.toLowerCase()};
    final List<String> out = <String>[];
    for (final FoodAlias alias in aliases) {
      final String key = alias.name.toLowerCase();
      if (seen.add(key)) out.add(alias.name);
    }
    return out;
  }

  factory Food.fromJson(Map<String, dynamic> json) {
    final Object? rawAliases = json['aliases'];
    final Object? rawServings = json['servings'];
    final Object? rawTags = json['dietaryTags'];
    final Object? rawPer100g = json['per100g'];

    return Food(
      id: (json['id'] ?? '').toString(),
      externalId: (json['externalId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      scientificName: json['scientificName'] as String?,
      aliases: rawAliases is List
          ? rawAliases
              .whereType<Map<String, dynamic>>()
              .map(FoodAlias.fromJson)
              .toList()
          : const <FoodAlias>[],
      group: (json['group'] ?? '').toString(),
      dietaryTags: rawTags is List
          ? rawTags.map((Object? e) => e.toString()).toList()
          : const <String>[],
      per100g: rawPer100g is Map<String, dynamic>
          ? Macros.fromJson(rawPer100g)
          : Macros.zero,
      servings: rawServings is List
          ? rawServings
              .whereType<Map<String, dynamic>>()
              .map(FoodServing.fromJson)
              .toList()
          : const <FoodServing>[],
      source: FoodSource.fromApi(json['source'] as String?),
      sourceName: (json['sourceName'] ?? '').toString(),
      sourceVersion: (json['sourceVersion'] ?? '').toString(),
      sourceAttribution: json['sourceAttribution'] as String?,
      licence: (json['licence'] ?? '').toString(),
      energySource: EnergySource.fromApi(json['energySource'] as String?),
      verified: json['verified'] as bool? ?? false,
      isRecipe: json['isRecipe'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => <Object?>[id, externalId, name, per100g, servings];
}
