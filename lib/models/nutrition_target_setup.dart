import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'food_log.dart';

enum NutritionActivityLevel {
  sedentary('sedentary', 'Mostly seated; little exercise'),
  light('light', 'Light activity; exercise 1–3 days/week'),
  moderate('moderate', 'Moderate activity; exercise 3–5 days/week'),
  veryActive('very_active', 'Very active; demanding daily activity');

  const NutritionActivityLevel(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

enum NutritionWeightGoal {
  maintain('maintain', 'Maintain weight'),
  loseFat('lose_fat', 'Lose fat'),
  gainWeight('gain_weight', 'Gain weight');

  const NutritionWeightGoal(this.apiValue, this.label);
  final String apiValue;
  final String label;

  /// Conflicting or missing onboarding goals require an explicit choice.
  static NutritionWeightGoal? fromFitnessGoals(List<FitnessGoal> goals) {
    if (goals.isEmpty) return null;
    final bool lose = goals.contains(FitnessGoal.loseFat);
    final bool gain = goals.contains(FitnessGoal.weightGain) ||
        goals.contains(FitnessGoal.buildMuscle);
    if (lose && gain) return null;
    return lose
        ? loseFat
        : gain
            ? gainWeight
            : maintain;
  }
}

/// Explicit, confirmed calculator inputs. Never infer daily activity from
/// exercise skill/fitnessLevel. Age is an entered age, not an invented DOB.
class NutritionTargetSetup extends Equatable {
  const NutritionTargetSetup({
    required this.age,
    required this.gender,
    required this.heightCm,
    required this.weightKg,
    required this.activityLevel,
    required this.goal,
  });
  final int age;
  final Gender gender;
  final double heightCm;
  final double weightKg;
  final NutritionActivityLevel activityLevel;
  final NutritionWeightGoal goal;

  Map<String, String> get errors => <String, String>{
        if (age < 18 || age > 78) 'age': 'Estimates support ages 18–78 only.',
        if (!heightCm.isFinite || heightCm < 120 || heightCm > 230)
          'heightCm': 'Enter a height between 120 and 230 cm.',
        if (!weightKg.isFinite || weightKg < 30 || weightKg > 200)
          'weightKg': 'Enter a weight between 30 and 200 kg.',
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'age': age,
        'gender': gender.apiValue,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'activityLevel': activityLevel.apiValue,
        'goal': goal.apiValue,
      };

  factory NutritionTargetSetup.fromJson(Map<String, dynamic> json) {
    final Object? age = json['age'];
    final Object? height = json['heightCm'];
    final Object? weight = json['weightKg'];
    if (age is! num ||
        !age.isFinite ||
        age != age.roundToDouble() ||
        height is! num ||
        weight is! num) {
      throw const FormatException('Invalid nutrition setup inputs');
    }
    final NutritionTargetSetup setup = NutritionTargetSetup(
      age: age.toInt(),
      gender: Gender.values
          .firstWhere((Gender value) => value.apiValue == json['gender']),
      heightCm: height.toDouble(),
      weightKg: weight.toDouble(),
      activityLevel: NutritionActivityLevel.values.firstWhere(
        (NutritionActivityLevel value) =>
            value.apiValue == json['activityLevel'],
      ),
      goal: NutritionWeightGoal.values.firstWhere(
        (NutritionWeightGoal value) => value.apiValue == json['goal'],
      ),
    );
    if (setup.errors.isNotEmpty) {
      throw const FormatException('Invalid nutrition setup inputs');
    }
    return setup;
  }

  @override
  List<Object?> get props =>
      <Object?>[age, gender, heightCm, weightKg, activityLevel, goal];
}

class NutritionTargetRecommendation {
  const NutritionTargetRecommendation({
    required this.setup,
    required this.target,
    required this.bmrKcal,
    required this.tdeeKcal,
    required this.policyVersion,
    required this.reviewed,
    required this.warnings,
  });
  final NutritionTargetSetup setup;
  final NutritionTarget target;
  final double bmrKcal;
  final double tdeeKcal;
  final String policyVersion;
  final bool reviewed;
  final List<String> warnings;

  factory NutritionTargetRecommendation.fromJson(Map<String, dynamic> json) {
    final Object? rawTarget = json['target'];
    final Object? rawSetup = json['setup'];
    final Object? warnings = json['warnings'];
    if (rawTarget is! Map<String, dynamic> ||
        rawSetup is! Map<String, dynamic> ||
        warnings is! List ||
        warnings.any((Object? value) => value is! String) ||
        json['reviewed'] is! bool ||
        json['policyVersion'] is! String ||
        (json['policyVersion'] as String).isEmpty) {
      throw const FormatException('Invalid recommendation');
    }
    for (final String key in <String>['kcal', 'proteinG', 'carbsG', 'fatG']) {
      final Object? value = rawTarget[key];
      if (value is! num || !value.isFinite || value < 0) {
        throw const FormatException('Invalid recommended target');
      }
    }
    for (final String key in <String>['bmrKcal', 'tdeeKcal']) {
      final Object? value = json[key];
      if (value is! num || !value.isFinite || value <= 0) {
        throw const FormatException('Invalid energy estimate');
      }
    }
    final NutritionTarget target = NutritionTarget.fromJson(rawTarget);
    if (!NutritionTarget.isSafeKcal(target.kcal) ||
        target.proteinG > NutritionTarget.maxProteinG ||
        target.carbsG > NutritionTarget.maxCarbsG ||
        target.fatG > NutritionTarget.maxFatG) {
      throw const FormatException(
        'Recommended target outside supported bounds',
      );
    }
    return NutritionTargetRecommendation(
      setup: NutritionTargetSetup.fromJson(rawSetup),
      target: target,
      bmrKcal: (json['bmrKcal'] as num).toDouble(),
      tdeeKcal: (json['tdeeKcal'] as num).toDouble(),
      policyVersion: json['policyVersion'] as String,
      reviewed: json['reviewed'] as bool,
      warnings: List<String>.unmodifiable(warnings.cast<String>()),
    );
  }
}
