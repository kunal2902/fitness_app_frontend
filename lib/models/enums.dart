import 'package:flutter/material.dart';

/// Contract every selectable onboarding option satisfies, so one generic
/// card widget can render all of them.
abstract interface class SelectableOption {
  /// Human-facing text.
  String get label;

  /// Value sent to the backend. Must match the backend enum exactly.
  String get apiValue;

  /// Optional supporting line under the label.
  String? get subtitle;

  /// Optional leading glyph.
  IconData? get icon;
}

/// Small helper for parsing an api value back into an enum safely.
T? optionFromApi<T extends SelectableOption>(List<T> values, String? raw) {
  if (raw == null) return null;
  for (final T v in values) {
    if (v.apiValue == raw) return v;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Q1 — Gender
// ---------------------------------------------------------------------------

enum Gender implements SelectableOption {
  male('male', 'Male', Icons.male_rounded),
  female('female', 'Female', Icons.female_rounded);

  const Gender(this.apiValue, this.label, this.icon);

  @override
  final String apiValue;
  @override
  final String label;
  @override
  final IconData? icon;
  @override
  String? get subtitle => null;
}

// ---------------------------------------------------------------------------
// Q2 / Q3 — Units
// ---------------------------------------------------------------------------

enum HeightUnit {
  cm('cm', 'cm'),
  inches('in', 'ft / in');

  const HeightUnit(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

enum WeightUnit {
  kg('kg', 'kg'),
  lbs('lbs', 'lbs');

  const WeightUnit(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

// ---------------------------------------------------------------------------
// Q4 — Goals (multi-select)
// ---------------------------------------------------------------------------

enum FitnessGoal implements SelectableOption {
  buildStrength(
    'build_strength',
    'Build Strength',
    'Move heavier, generate more force',
    Icons.fitness_center_rounded,
  ),
  buildMuscle(
    'build_muscle',
    'Build Muscle',
    'Add lean size through hypertrophy',
    Icons.accessibility_new_rounded,
  ),
  loseFat(
    'lose_fat',
    'Lose Fat',
    'Cut body fat, keep your muscle',
    Icons.local_fire_department_rounded,
  ),
  learnCalisthenics(
    'learn_calisthenics',
    'Learn Calisthenics',
    'Master bodyweight skills',
    Icons.sports_gymnastics_rounded,
  ),
  weightGain(
    'weight_gain',
    'Weight Gain',
    'Eat and train to scale up',
    Icons.trending_up_rounded,
  ),
  basicFitness(
    'basic_fitness',
    'Basic Fitness',
    'Feel healthier day to day',
    Icons.favorite_rounded,
  ),
  yoga(
    'yoga',
    'Yoga',
    'Balance, breath and control',
    Icons.self_improvement_rounded,
  ),
  stretching(
    'stretching',
    'Stretching',
    'Open up range of motion',
    Icons.airline_seat_flat_rounded,
  );

  const FitnessGoal(this.apiValue, this.label, this.subtitle, this.icon);

  @override
  final String apiValue;
  @override
  final String label;
  @override
  final String? subtitle;
  @override
  final IconData? icon;
}

// ---------------------------------------------------------------------------
// Q5–Q8 — Rep capacity ranges
// ---------------------------------------------------------------------------

enum PullUpRange implements SelectableOption {
  under6('lt_6', 'Less than 6'),
  from6to10('6_10', '6 - 10'),
  from11to15('11_15', '11 - 15'),
  over15('gt_15', 'More than 15');

  const PullUpRange(this.apiValue, this.label);
  @override
  final String apiValue;
  @override
  final String label;
  @override
  String? get subtitle => null;
  @override
  IconData? get icon => null;
}

enum PushUpRange implements SelectableOption {
  under11('lt_11', 'Less than 11'),
  from11to20('11_20', '11 - 20'),
  from21to30('21_30', '21 - 30'),
  over30('gt_30', 'More than 30');

  const PushUpRange(this.apiValue, this.label);
  @override
  final String apiValue;
  @override
  final String label;
  @override
  String? get subtitle => null;
  @override
  IconData? get icon => null;
}

enum SquatRange implements SelectableOption {
  under21('lt_21', 'Less than 21'),
  from21to30('21_30', '21 - 30'),
  from31to40('31_40', '31 - 40'),
  over40('gt_40', 'More than 40');

  const SquatRange(this.apiValue, this.label);
  @override
  final String apiValue;
  @override
  final String label;
  @override
  String? get subtitle => null;
  @override
  IconData? get icon => null;
}

enum DipRange implements SelectableOption {
  under9('lt_9', 'Less than 9'),
  from9to15('9_15', '9 - 15'),
  from16to25('16_25', '16 - 25'),
  over25('gt_25', 'More than 25');

  const DipRange(this.apiValue, this.label);
  @override
  final String apiValue;
  @override
  final String label;
  @override
  String? get subtitle => null;
  @override
  IconData? get icon => null;
}

// ---------------------------------------------------------------------------
// Q9 — Self-reported fitness level
// ---------------------------------------------------------------------------

enum FitnessLevel implements SelectableOption {
  newbie(
    'newbie',
    'Newbie',
    'Brand new to structured training',
    Icons.emoji_people_rounded,
  ),
  beginner(
    'beginner',
    'Beginner',
    'Training on and off for a while',
    Icons.directions_walk_rounded,
  ),
  intermediate(
    'intermediate',
    'Intermediate',
    'Consistent for 6+ months',
    Icons.directions_run_rounded,
  ),
  advanced(
    'advanced',
    'Advanced',
    'Years of dedicated training',
    Icons.bolt_rounded,
  );

  const FitnessLevel(this.apiValue, this.label, this.subtitle, this.icon);

  @override
  final String apiValue;
  @override
  final String label;
  @override
  final String? subtitle;
  @override
  final IconData? icon;
}
