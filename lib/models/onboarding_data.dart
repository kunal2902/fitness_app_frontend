import 'package:equatable/equatable.dart';

import '../config/app_config.dart';
import 'enums.dart';

/// Everything collected across the 9 onboarding questions.
///
/// Height and weight are always stored in **metric** internally — the unit
/// toggle only changes how the value is displayed and entered. That keeps
/// the backend contract simple and avoids rounding drift when the user
/// flips units back and forth.
class OnboardingData extends Equatable {
  const OnboardingData({
    this.gender,
    this.heightCm,
    this.heightUnit = HeightUnit.cm,
    this.weightKg,
    this.weightUnit = WeightUnit.kg,
    this.goals = const <FitnessGoal>[],
    this.maxPullUps,
    this.maxPushUps,
    this.maxSquats,
    this.maxDips,
    this.fitnessLevel,
  });

  final Gender? gender;

  /// Canonical height in centimetres.
  final double? heightCm;
  final HeightUnit heightUnit;

  /// Canonical weight in kilograms.
  final double? weightKg;
  final WeightUnit weightUnit;

  final List<FitnessGoal> goals;
  final PullUpRange? maxPullUps;
  final PushUpRange? maxPushUps;
  final SquatRange? maxSquats;
  final DipRange? maxDips;
  final FitnessLevel? fitnessLevel;

  static const int totalSteps = 9;

  OnboardingData copyWith({
    Gender? gender,
    double? heightCm,
    HeightUnit? heightUnit,
    double? weightKg,
    WeightUnit? weightUnit,
    List<FitnessGoal>? goals,
    PullUpRange? maxPullUps,
    PushUpRange? maxPushUps,
    SquatRange? maxSquats,
    DipRange? maxDips,
    FitnessLevel? fitnessLevel,
  }) {
    return OnboardingData(
      gender: gender ?? this.gender,
      heightCm: heightCm ?? this.heightCm,
      heightUnit: heightUnit ?? this.heightUnit,
      weightKg: weightKg ?? this.weightKg,
      weightUnit: weightUnit ?? this.weightUnit,
      goals: goals ?? this.goals,
      maxPullUps: maxPullUps ?? this.maxPullUps,
      maxPushUps: maxPushUps ?? this.maxPushUps,
      maxSquats: maxSquats ?? this.maxSquats,
      maxDips: maxDips ?? this.maxDips,
      fitnessLevel: fitnessLevel ?? this.fitnessLevel,
    );
  }

  // -------------------------------------------------------------------------
  // Completion
  // -------------------------------------------------------------------------

  /// Whether the question at [stepIndex] (0-based, matching the PageView)
  /// has an answer. Drives the "Continue" button's enabled state.
  bool isStepAnswered(int stepIndex) {
    switch (stepIndex) {
      case 0:
        return gender != null;
      case 1:
        return heightCm != null;
      case 2:
        return weightKg != null;
      case 3:
        return goals.isNotEmpty;
      case 4:
        return maxPullUps != null;
      case 5:
        return maxPushUps != null;
      case 6:
        return maxSquats != null;
      case 7:
        return maxDips != null;
      case 8:
        return fitnessLevel != null;
      default:
        return false;
    }
  }

  bool get isComplete =>
      List<int>.generate(totalSteps, (int i) => i).every(isStepAnswered);

  int get answeredCount => List<int>.generate(totalSteps, (int i) => i)
      .where(isStepAnswered)
      .length;

  // -------------------------------------------------------------------------
  // Derived
  // -------------------------------------------------------------------------

  /// Body mass index, if both height and weight are known.
  double? get bmi {
    final double? h = heightCm;
    final double? w = weightKg;
    if (h == null || w == null || h <= 0) return null;
    final double metres = h / 100;
    return w / (metres * metres);
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  /// Shape sent to `POST /auth/signup` under the `fitnessProfile` key.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'gender': gender?.apiValue,
      'heightCm': heightCm,
      'heightUnit': heightUnit.apiValue,
      'weightKg': weightKg,
      'weightUnit': weightUnit.apiValue,
      'goals': goals.map((FitnessGoal g) => g.apiValue).toList(),
      'maxPullUps': maxPullUps?.apiValue,
      'maxPushUps': maxPushUps?.apiValue,
      'maxSquats': maxSquats?.apiValue,
      'maxDips': maxDips?.apiValue,
      'fitnessLevel': fitnessLevel?.apiValue,
    };
  }

  factory OnboardingData.fromJson(Map<String, dynamic> json) {
    final Object? rawGoals = json['goals'];
    final List<FitnessGoal> parsedGoals = rawGoals is List
        ? rawGoals
            .map((Object? e) =>
                optionFromApi<FitnessGoal>(FitnessGoal.values, e as String?))
            .whereType<FitnessGoal>()
            .toList()
        : const <FitnessGoal>[];

    return OnboardingData(
      gender: optionFromApi<Gender>(Gender.values, json['gender'] as String?),
      heightCm: (json['heightCm'] as num?)?.toDouble(),
      heightUnit: HeightUnit.values.firstWhere(
        (HeightUnit u) => u.apiValue == json['heightUnit'],
        orElse: () => HeightUnit.cm,
      ),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      weightUnit: WeightUnit.values.firstWhere(
        (WeightUnit u) => u.apiValue == json['weightUnit'],
        orElse: () => WeightUnit.kg,
      ),
      goals: parsedGoals,
      maxPullUps:
          optionFromApi<PullUpRange>(PullUpRange.values, json['maxPullUps'] as String?),
      maxPushUps:
          optionFromApi<PushUpRange>(PushUpRange.values, json['maxPushUps'] as String?),
      maxSquats:
          optionFromApi<SquatRange>(SquatRange.values, json['maxSquats'] as String?),
      maxDips: optionFromApi<DipRange>(DipRange.values, json['maxDips'] as String?),
      fitnessLevel: optionFromApi<FitnessLevel>(
        FitnessLevel.values,
        json['fitnessLevel'] as String?,
      ),
    );
  }

  /// A sensible starting point so the pickers never open on a null value.
  static const OnboardingData initial = OnboardingData(
    heightUnit: HeightUnit.cm,
    weightUnit: WeightUnit.kg,
  );

  static double get defaultHeightCm => AppConfig.defaultHeightCm;
  static double get defaultWeightKg => AppConfig.defaultWeightKg;

  @override
  List<Object?> get props => <Object?>[
        gender,
        heightCm,
        heightUnit,
        weightKg,
        weightUnit,
        goals,
        maxPullUps,
        maxPushUps,
        maxSquats,
        maxDips,
        fitnessLevel,
      ];
}
