import 'package:equatable/equatable.dart';

/// Which set of days the calendar is showing.
enum CalendarMode {
  /// Sessions the user actually completed.
  previous('Previous workouts'),

  /// Sessions their plan says they should do.
  goal('Goal workouts');

  const CalendarMode(this.label);
  final String label;
}

enum WorkoutDayStatus {
  /// Trained, and it counted.
  completed,

  /// Scheduled by the plan, still ahead.
  planned,

  /// Scheduled but the day passed without a session.
  missed,

  /// A deliberate rest day in the plan.
  rest,
}

/// One dot on the calendar.
class WorkoutDay extends Equatable {
  const WorkoutDay({
    required this.date,
    required this.status,
    this.title,
    this.durationMinutes,
  });

  final DateTime date;
  final WorkoutDayStatus status;

  /// e.g. "Upper body — pull". Null for rest days.
  final String? title;
  final int? durationMinutes;

  /// Midnight-normalised, so two days on the same date compare equal and
  /// can key a map regardless of what time they were constructed with.
  static DateTime dayKey(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime get key => dayKey(date);

  @override
  List<Object?> get props => <Object?>[key, status, title, durationMinutes];
}

/// Streak counters shown on the streak card.
///
/// These count consecutive *scheduled sessions completed*, not consecutive
/// calendar days. A plan with rest days would otherwise reset the streak
/// every week for doing exactly what the plan asked.
class StreakStats extends Equatable {
  const StreakStats({
    required this.currentDays,
    required this.longestDays,
    required this.totalWorkouts,
    this.lastWorkoutAt,
    this.trainsToday = false,
    this.completedToday = false,
  });

  final int currentDays;
  final int longestDays;
  final int totalWorkouts;
  final DateTime? lastWorkoutAt;

  /// Whether today is a training day in the user's plan. Supplied by the
  /// repository, which is the only thing that knows the schedule.
  final bool trainsToday;

  final bool completedToday;

  static const StreakStats empty = StreakStats(
    currentDays: 0,
    longestDays: 0,
    totalWorkouts: 0,
  );

  bool get hasStreak => currentDays > 0;

  /// True only when there is a live streak, today is a *scheduled* day, and
  /// it has not been logged yet.
  ///
  /// Checking the schedule matters: nagging someone to train on a planned
  /// rest day is both wrong and, twice a week, actively annoying.
  bool get isAtRisk =>
      currentDays > 0 && trainsToday && !completedToday;

  StreakStats copyWith({
    int? currentDays,
    int? longestDays,
    int? totalWorkouts,
    DateTime? lastWorkoutAt,
    bool? trainsToday,
    bool? completedToday,
  }) {
    return StreakStats(
      currentDays: currentDays ?? this.currentDays,
      longestDays: longestDays ?? this.longestDays,
      totalWorkouts: totalWorkouts ?? this.totalWorkouts,
      lastWorkoutAt: lastWorkoutAt ?? this.lastWorkoutAt,
      trainsToday: trainsToday ?? this.trainsToday,
      completedToday: completedToday ?? this.completedToday,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        currentDays,
        longestDays,
        totalWorkouts,
        lastWorkoutAt,
        trainsToday,
        completedToday,
      ];
}
