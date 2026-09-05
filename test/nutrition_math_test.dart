import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/models/food_log.dart';
import 'package:fitness_app/models/nutrition_models.dart';
import 'package:fitness_app/services/nutrition_service.dart';
import 'package:fitness_app/utils/diary_date.dart';
import 'package:fitness_app/utils/nutrition_math.dart';

/// Every expected value below was produced by **running the server's own
/// `src/nutrition/nutrition-math.ts`**, not by re-deriving the arithmetic
/// here. That is the point of the file: if the two implementations ever
/// drift, portion validation starts rejecting perfectly good logs with a
/// message the user cannot act on, and nothing else would catch it.
void main() {
  group('servingQuantityToGrams', () {
    // The server recomputes grams from quantity x serving.grams and
    // rejects a mismatch. These are the cases where naive float maths
    // diverges: 7.7 * 1.3 is 10.009999999999998 before rounding.
    const List<(double, double, double)> vectors = <(double, double, double)>[
      (150, 1, 150),
      (150, 1.5, 225),
      (35, 2, 70),
      (35, 3, 105),
      (100, 0.5, 50),
      (12.5, 3, 37.5),
      (33.33, 3, 99.99),
      (7.7, 1.3, 10.01),
      (0.01, 1, 0.01),
      (10000, 1, 10000),
    ];

    test('matches the server for every vector', () {
      for (final (double grams, double quantity, double expected) in vectors) {
        expect(
          NutritionMath.servingQuantityToGrams(grams, quantity),
          expected,
          reason: '$grams x $quantity',
        );
      }
    });

    test('rejects non-positive input rather than returning nonsense', () {
      expect(
        () => NutritionMath.servingQuantityToGrams(0, 1),
        throwsArgumentError,
      );
      expect(
        () => NutritionMath.servingQuantityToGrams(150, 0),
        throwsArgumentError,
      );
      expect(
        () => NutritionMath.servingQuantityToGrams(double.nan, 1),
        throwsArgumentError,
      );
    });
  });

  group('macrosForGrams', () {
    const Macros poha =
        Macros(kcal: 346, proteinG: 6.6, carbsG: 77.3, fatG: 1.2);
    const Macros ghee = Macros(kcal: 900, proteinG: 0, carbsG: 0, fatG: 100);
    const Macros paneer =
        Macros(kcal: 296, proteinG: 18.3, carbsG: 1.2, fatG: 25.1);

    test('one katori of poha', () {
      expect(
        poha.forGrams(150),
        const Macros(kcal: 519, proteinG: 9.9, carbsG: 115.95, fatG: 1.8),
      );
    });

    test('a fractional portion rounds as the server does', () {
      expect(
        poha.forGrams(37.5),
        const Macros(kcal: 129.75, proteinG: 2.47, carbsG: 28.99, fatG: 0.45),
      );
      expect(
        paneer.forGrams(33.33),
        const Macros(kcal: 98.66, proteinG: 6.1, carbsG: 0.4, fatG: 8.37),
      );
    });

    test('a teaspoon of ghee is not zero calories', () {
      // The IFCT corpus ships all 14 edible oils with enerc = 0; the
      // import repairs them from Atwater factors. If that repair ever
      // regresses, this is what catches it downstream.
      expect(ghee.forGrams(5).kcal, 45);
    });

    test('a trace amount does not round away to nothing', () {
      expect(
        poha.forGrams(0.01),
        const Macros(kcal: 0.03, proteinG: 0, carbsG: 0.01, fatG: 0),
      );
    });
  });

  group('sumMacros', () {
    test('rounds at every step, like the server', () {
      const Macros poha =
          Macros(kcal: 346, proteinG: 6.6, carbsG: 77.3, fatG: 1.2);
      const Macros ghee = Macros(kcal: 900, proteinG: 0, carbsG: 0, fatG: 100);
      const Macros dal =
          Macros(kcal: 343, proteinG: 22.5, carbsG: 57.2, fatG: 1.3);
      const Macros paneer =
          Macros(kcal: 296, proteinG: 18.3, carbsG: 1.2, fatG: 25.1);

      final Macros total = NutritionMath.sumMacros(<Macros>[
        poha.forGrams(150),
        ghee.forGrams(5),
        dal.forGrams(100),
        paneer.forGrams(33.33),
      ]);

      expect(
        total,
        const Macros(
          kcal: 1005.66,
          proteinG: 38.5,
          carbsG: 173.55,
          fatG: 16.47,
        ),
      );
    });

    test('an empty day is zero, not null', () {
      expect(NutritionMath.sumMacros(<Macros>[]), Macros.zero);
    });
  });

  group('isMatchingGramAmount', () {
    // Mirrors the server's acceptance window: max(0.1, 1%).
    test('accepts inside the window and rejects outside it', () {
      expect(NutritionMath.isMatchingGramAmount(150, 150), isTrue);
      expect(NutritionMath.isMatchingGramAmount(150.1, 150), isTrue);
      expect(NutritionMath.isMatchingGramAmount(151.5, 150), isTrue);
      expect(NutritionMath.isMatchingGramAmount(151.6, 150), isFalse);
    });

    test('the 0.1 floor covers tiny portions', () {
      expect(NutritionMath.isMatchingGramAmount(0.05, 0.01), isTrue);
      expect(NutritionMath.isMatchingGramAmount(0.2, 0.01), isFalse);
    });
  });

  group('labelKey', () {
    test('normalises the way the server matches servings', () {
      expect(NutritionMath.labelKey('1 Katori'), '1 katori');
      expect(NutritionMath.labelKey('  1   katori '), '1 katori');
      expect(NutritionMath.labelKey('100 G'), '100 g');
    });

    test('recognises the direct-gram unit labels', () {
      expect(NutritionMath.isGramUnitLabel('g'), isTrue);
      expect(NutritionMath.isGramUnitLabel('Grams'), isTrue);
      expect(NutritionMath.isGramUnitLabel('katori'), isFalse);
    });
  });

  group('DiaryDate', () {
    test('formats and validates a calendar day', () {
      expect(DiaryDate.format(2026, 9, 4), '2026-09-04');
      expect(DiaryDate.isValid('2026-09-04'), isTrue);
      expect(DiaryDate.isValid('2026-02-30'), isFalse);
      expect(DiaryDate.isValid('2026-13-01'), isFalse);
      expect(DiaryDate.isValid('26-09-04'), isFalse);
      expect(DiaryDate.isValid(''), isFalse);
    });

    test('uses local fields, so a late-evening log is not filed yesterday', () {
      // 23:30 local. Anything that normalises through UTC first would
      // roll this back a day for every user east of Greenwich.
      final DateTime lateEvening = DateTime(2026, 9, 4, 23, 30);
      expect(DiaryDate.of(lateEvening), '2026-09-04');
    });

    test('steps by calendar days, not by 24-hour durations', () {
      expect(DiaryDate.next('2026-09-04'), '2026-09-05');
      expect(DiaryDate.previous('2026-09-01'), '2026-08-31');
      // Month and year boundaries.
      expect(DiaryDate.next('2026-12-31'), '2027-01-01');
      expect(DiaryDate.previous('2028-03-01'), '2028-02-29');
    });
  });

  group('DraftLogItem and the wire shape', () {
    const FoodServing katori = FoodServing(
      label: '1 katori',
      grams: 150,
      isDefault: true,
      origin: ServingOrigin.curated,
    );

    final Food poha = Food(
      id: '507f1f77bcf86cd799439011',
      externalId: 'ifct:A011',
      name: 'Rice flakes',
      group: 'Cereals and Millets',
      per100g: const Macros(
        kcal: 346,
        proteinG: 6.6,
        carbsG: 77.3,
        fatG: 1.2,
      ),
      servings: const <FoodServing>[katori],
      source: FoodSource.ifct2017,
      sourceName: 'IFCT 2017',
      sourceVersion: '2017',
      licence: 'NIN',
      energySource: EnergySource.sourceKj,
    );

    test('an item built from a serving agrees with the server', () {
      final DraftLogItem item = DraftLogItem.of(
        food: poha,
        serving: katori,
        quantity: 1.5,
      );

      expect(item.grams, 225);
      expect(item.quantity, 1.5);
      expect(item.unitLabel, '1 katori');
      // The server recomputes grams from quantity x serving.grams and
      // rejects anything outside max(0.1, 1%). This is that check, run
      // locally against the same inputs the server will use.
      expect(
        NutritionMath.isMatchingGramAmount(
          item.grams,
          NutritionMath.servingQuantityToGrams(katori.grams, item.quantity),
        ),
        isTrue,
      );
    });

    test('direct gram entry sends quantity == grams with a "g" unit', () {
      // The server's expectedItemGrams treats g/gram/grams as "the
      // quantity IS the gram count", so these two fields must agree or
      // the log is rejected.
      final DraftLogItem item =
          DraftLogItem.fromGrams(food: poha, grams: 37.456);
      expect(item.grams, 37.46);
      expect(item.quantity, 37.46);
      expect(NutritionMath.isGramUnitLabel(item.unitLabel), isTrue);
    });

    test('a food with no server id is refused before it can 422', () {
      // Reachable via a bundled corpus keyed on externalId: GET /foods/:id
      // accepts either form, but nutritionLogItemSchema.foodId accepts
      // only a 24-hex ObjectId. Failing here names the real problem.
      final Food localOnly = Food(
        id: '',
        externalId: 'ifct:A011',
        name: 'Rice flakes',
        group: 'Cereals and Millets',
        per100g: const Macros(
          kcal: 346,
          proteinG: 6.6,
          carbsG: 77.3,
          fatG: 1.2,
        ),
        servings: const <FoodServing>[katori],
        sourceName: 'IFCT 2017',
        sourceVersion: '2017',
        licence: 'NIN',
      );

      expect(
        () => DraftLogItem.of(food: localOnly, serving: katori, quantity: 1),
        throwsArgumentError,
      );
    });

    test('portions outside the server bounds are refused locally', () {
      expect(
        () => DraftLogItem.fromGrams(food: poha, grams: 0),
        throwsArgumentError,
      );
      expect(
        () => DraftLogItem.fromGrams(food: poha, grams: -5),
        throwsArgumentError,
      );
      expect(
        () => DraftLogItem.fromGrams(food: poha, grams: 10001),
        throwsArgumentError,
      );
      // The server's own ceiling is fine.
      expect(DraftLogItem.fromGrams(food: poha, grams: 10000).grams, 10000);
    });

    test('the request body carries only what the server accepts', () {
      final Map<String, dynamic> json =
          DraftLogItem.of(food: poha, serving: katori, quantity: 1).toJson();
      // nutritionLogItemSchema takes exactly these four. Sending a
      // snapshot or macros would be ignored at best, spoofable at worst.
      expect(
        json.keys.toSet(),
        <String>{'foodId', 'grams', 'quantity', 'unitLabel'},
      );
      expect(json['foodId'], '507f1f77bcf86cd799439011');
    });
  });

  group('Food', () {
    Food buildFood(List<FoodServing> servings) => Food(
          id: 'abc',
          externalId: 'ifct:A011',
          name: 'Rice flakes',
          group: 'Cereals and Millets',
          per100g: const Macros(
            kcal: 346,
            proteinG: 6.6,
            carbsG: 77.3,
            fatG: 1.2,
          ),
          servings: servings,
          source: FoodSource.ifct2017,
          sourceName: 'IFCT 2017',
          sourceVersion: '2017',
          licence: 'NIN',
          energySource: EnergySource.sourceKj,
        );

    test('picks the flagged default serving', () {
      final Food food = buildFood(const <FoodServing>[
        FoodServing(
          label: '100 g',
          grams: 100,
          isDefault: false,
          origin: ServingOrigin.fallback100g,
        ),
        FoodServing(
          label: '1 katori',
          grams: 150,
          isDefault: true,
          origin: ServingOrigin.curated,
        ),
      ]);
      expect(food.defaultServing?.label, '1 katori');
      expect(food.kcalPerDefaultServing, 519);
    });

    test('falls back to the 100 g row when no default is flagged', () {
      final Food food = buildFood(const <FoodServing>[
        FoodServing(
          label: '100 g',
          grams: 100,
          isDefault: false,
          origin: ServingOrigin.fallback100g,
        ),
      ]);
      expect(food.defaultServing?.label, '100 g');
    });

    test('a food with no servings cannot be logged, and says so', () {
      // Never synthesize a "100 g" serving here: the label has to match
      // one the server holds, and its schema permits the spelling "100g"
      // with no space. An invented label fails portion validation with a
      // message that reads like corrupt data.
      final Food food = buildFood(const <FoodServing>[]);
      expect(food.hasServings, isFalse);
      expect(food.defaultServing, isNull);
      expect(food.kcalPerDefaultServing, isNull);
    });

    test('finds a serving by label the way the server does', () {
      final Food food = buildFood(const <FoodServing>[
        FoodServing(
          label: '1 Katori',
          grams: 150,
          isDefault: true,
          origin: ServingOrigin.curated,
        ),
      ]);
      expect(food.servingByLabel('1 katori')?.grams, 150);
      expect(food.servingByLabel('1  KATORI')?.grams, 150);
      expect(food.servingByLabel('1 roti'), isNull);
    });
  });

  group('parsing', () {
    test('a summary with no target is a valid state', () {
      final NutritionSummary summary =
          NutritionSummary.fromJson(<String, dynamic>{
        'date': '2026-09-04',
        'totals': <String, dynamic>{
          'kcal': 519,
          'proteinG': 9.9,
          'carbsG': 115.95,
          'fatG': 1.8,
        },
        'meals': <dynamic>[
          <String, dynamic>{
            'mealType': 'breakfast',
            'totals': <String, dynamic>{
              'kcal': 519,
              'proteinG': 9.9,
              'carbsG': 115.95,
              'fatG': 1.8,
            },
            'logCount': 1,
            'itemCount': 1,
          },
        ],
        'target': null,
      });

      expect(summary.hasTarget, isFalse);
      expect(summary.kcalRemaining, isNull);
      expect(summary.mealFor(MealType.breakfast)?.itemCount, 1);
      expect(summary.mealFor(MealType.dinner), isNull);
      // No target must not divide by zero.
      expect(summary.progress.kcal, 0);
    });

    test('progress clamps for the ring but not for the overshoot check', () {
      final NutritionSummary summary = NutritionSummary(
        date: '2026-09-04',
        totals: const Macros(kcal: 2400, proteinG: 90, carbsG: 300, fatG: 60),
        meals: const <MealSummary>[],
        target: const NutritionTarget(
          kcal: 2000,
          proteinG: 150,
          carbsG: 250,
          fatG: 60,
        ),
      );

      expect(summary.progress.kcal, 1.0);
      expect(summary.rawProgress.kcal, 1.2);
      expect(summary.progress.protein, closeTo(0.6, 1e-9));
      expect(summary.kcalRemaining, -400);
    });

    test('an empty summary carries all four meals', () {
      final NutritionSummary summary = NutritionSummary.empty('2026-09-04');
      expect(summary.meals.length, 4);
      expect(summary.meals.first.mealType, MealType.breakfast);
      expect(summary.isEmpty, isTrue);
    });

    test('a log item computes macros when the server omits them', () {
      final FoodLogItem item = FoodLogItem.fromJson(<String, dynamic>{
        'foodId': 'abc',
        'grams': 150,
        'quantity': 1,
        'unitLabel': '1 katori',
        'snapshot': <String, dynamic>{
          'externalId': 'ifct:A011',
          'name': 'Rice flakes',
          'per100g': <String, dynamic>{
            'kcal': 346,
            'proteinG': 6.6,
            'carbsG': 77.3,
            'fatG': 1.2,
          },
          'source': 'ifct2017',
          'sourceVersion': '2017',
        },
      });

      expect(item.macros.kcal, 519);
      expect(item.portionLabel, '1 × 1 katori');
    });

    test('an unknown enum value stays unknown rather than aliasing', () {
      expect(MealType.fromApi('brunch'), isNull);
      expect(FoodSource.fromApi(null), isNull);

      final FoodLog log = FoodLog.fromJson(<String, dynamic>{
        'id': 'x',
        'date': '2026-09-04',
        'mealType': 'brunch',
        'items': <dynamic>[],
      });
      // Not MealType.snack. Defaulting would file the entry under a real
      // meal the user did not pick, and the diary would then show two
      // indistinguishable "Snack" groups.
      expect(log.mealType, isNull);
    });

    test('an unknown meal in a summary never masquerades as a known one', () {
      final NutritionSummary summary =
          NutritionSummary.fromJson(<String, dynamic>{
        'date': '2026-09-04',
        'totals': <String, dynamic>{
          'kcal': 100,
          'proteinG': 0,
          'carbsG': 0,
          'fatG': 0,
        },
        'meals': <dynamic>[
          <String, dynamic>{
            'mealType': 'brunch',
            'totals': <String, dynamic>{
              'kcal': 100,
              'proteinG': 0,
              'carbsG': 0,
              'fatG': 0,
            },
            'logCount': 1,
            'itemCount': 1,
          },
        ],
        'target': null,
      });

      // The row is kept so its totals still reconcile with the day...
      expect(summary.meals.length, 1);
      expect(summary.meals.first.mealType, isNull);
      // ...but mealFor must not hand it back for any real meal.
      for (final MealType type in MealType.values) {
        expect(summary.mealFor(type), isNull, reason: type.apiValue);
      }
    });

    test('an unknown food source is not attributed to the user', () {
      final Food food = Food.fromJson(<String, dynamic>{
        'id': 'abc',
        'externalId': 'nin:X1',
        'name': 'Something new',
        'group': 'Misc',
        'per100g': <String, dynamic>{
          'kcal': 10,
          'proteinG': 0,
          'carbsG': 0,
          'fatG': 0,
        },
        'servings': <dynamic>[],
        'source': 'nin2024',
        'sourceName': 'NIN',
        'sourceVersion': '2024',
        'licence': 'NIN',
        'energySource': 'bomb_calorimetry',
      });

      // "Added by you" and "As published" are both claims about
      // provenance. Neither is safe as a default.
      expect(food.source, isNull);
      expect(food.energySource, isNull);
    });
  });

  group('NutritionTarget safety floor', () {
    test('rejects targets below the safe threshold', () {
      expect(NutritionTarget.isSafeKcal(800), isFalse);
      expect(NutritionTarget.isSafeKcal(1000), isTrue);
      expect(NutritionTarget.isSafeKcal(10001), isFalse);
      expect(NutritionTarget.isSafeKcal(double.nan), isFalse);
    });
  });
}
