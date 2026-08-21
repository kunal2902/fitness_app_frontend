import '../models/workout_day.dart';

/// Source of the calendar and streak data on the profile screen.
///
/// Phase 1 ships [DummyWorkoutCalendarRepository]. When the workout-log API
/// exists, add an `ApiWorkoutCalendarRepository` implementing this and swap
/// the instance passed to `ProfileBloc` — no widget or card changes.
abstract interface class WorkoutCalendarRepository {
  /// Every marked day in the month containing [month], for the given mode.
  Future<List<WorkoutDay>> daysForMonth(DateTime month, CalendarMode mode);

  Future<StreakStats> streak();
}

/// Deterministic placeholder history.
///
/// Deterministic matters: a generator using `Random()` would reshuffle the
/// calendar on every rebuild, which looks like a bug during development.
/// Here a given date always produces the same result, so the UI is stable
/// across hot reloads and screenshots.
class DummyWorkoutCalendarRepository implements WorkoutCalendarRepository {
  const DummyWorkoutCalendarRepository();

  /// The plan trains Mon, Tue, Thu, Fri, Sat. Wed and Sun are rest.
  static const Set<int> _scheduledWeekdays = <int>{
    DateTime.monday,
    DateTime.tuesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
  };

  static const List<String> _sessionTitles = <String>[
    'Upper body — push',
    'Upper body — pull',
    'Lower body',
    'Core & mobility',
    'Full body circuit',
    'Skill work',
  ];

  /// Roughly 8 sessions in 10 get done.
  static const int _adherencePercent = 82;

  /// How far back the fake history runs.
  ///
  /// Deliberately longer than any streak the generator can produce. A short
  /// window would make `longestDays` slide downwards day by day as the best
  /// run fell off the back of it — a personal best that shrinks is an
  /// obvious bug to anyone watching it.
  static const int _historyDays = 730;

  // -------------------------------------------------------------------------

  @override
  Future<List<WorkoutDay>> daysForMonth(
    DateTime month,
    CalendarMode mode,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 140));

    final DateTime first = DateTime(month.year, month.month);
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final DateTime today = WorkoutDay.dayKey(DateTime.now());

    final List<WorkoutDay> result = <WorkoutDay>[];

    for (int day = 1; day <= daysInMonth; day++) {
      final DateTime date = DateTime(first.year, first.month, day);
      if (!_scheduledWeekdays.contains(date.weekday)) continue;

      final bool isToday = date == today;
      final bool isPast = date.isBefore(today);
      final bool completed = (isPast || isToday) && _wasCompleted(date);

      // Today is never "missed" — the day is not over. It stays planned
      // until it is either completed or actually elapses, which is also
      // what keeps the calendar agreeing with the streak card's grace.
      final WorkoutDayStatus status = completed
          ? WorkoutDayStatus.completed
          : (isPast ? WorkoutDayStatus.missed : WorkoutDayStatus.planned);

      if (mode == CalendarMode.previous) {
        // History only: nothing beyond today.
        if (!isPast && !isToday) continue;
      }

      result.add(
        WorkoutDay(
          date: date,
          status: status,
          title: status == WorkoutDayStatus.missed ? null : _titleFor(date),
          durationMinutes:
              status == WorkoutDayStatus.missed ? null : _durationFor(date),
        ),
      );
    }

    return result;
  }

  @override
  Future<StreakStats> streak() async {
    await Future<void>.delayed(const Duration(milliseconds: 140));

    final DateTime today = WorkoutDay.dayKey(DateTime.now());
    final bool trainsToday = _scheduledWeekdays.contains(today.weekday);
    final bool completedToday = trainsToday && _wasCompleted(today);

    // Walk the schedule backwards. Rest days are skipped rather than
    // treated as breaks — missing a Wednesday you were never meant to
    // train would otherwise reset the streak every single week.
    int current = 0;
    bool countingCurrent = true;
    int longest = 0;
    int running = 0;
    int total = 0;
    DateTime? lastWorkout;

    for (int offset = 0; offset <= _historyDays; offset++) {
      // Built from calendar components rather than
      // `today.subtract(Duration(days: offset))`: a Duration is absolute
      // time, so across a daylight-saving boundary it skips or repeats a
      // calendar day, and the dates would stop lining up with the ones
      // daysForMonth generates.
      final DateTime date = DateTime(today.year, today.month, today.day - offset);
      if (!_scheduledWeekdays.contains(date.weekday)) continue;

      if (_wasCompleted(date)) {
        total++;
        running++;
        lastWorkout ??= date;
        if (countingCurrent) current++;
        if (running > longest) longest = running;
      } else {
        running = 0;
        // Today being unlogged must not kill a live streak — there are
        // still hours left to train.
        if (date != today) countingCurrent = false;
      }
    }

    return StreakStats(
      currentDays: current,
      longestDays: longest,
      totalWorkouts: total,
      lastWorkoutAt: lastWorkout,
      trainsToday: trainsToday,
      completedToday: completedToday,
    );
  }

  // -------------------------------------------------------------------------
  // Deterministic pseudo-randomness
  // -------------------------------------------------------------------------

  /// Stable hash of a date — same date in, same value out, every run.
  static int _hash(DateTime date) {
    int h = date.year * 10000 + date.month * 100 + date.day;
    h = (h ^ (h >> 15)) * 0x2c1b3c6d;
    h = (h ^ (h >> 12)) * 0x297a2d39;
    h = h ^ (h >> 15);
    return h.abs();
  }

  static bool _wasCompleted(DateTime date) =>
      _hash(date) % 100 < _adherencePercent;

  static String _titleFor(DateTime date) =>
      _sessionTitles[_hash(date) % _sessionTitles.length];

  static int _durationFor(DateTime date) => 30 + (_hash(date) % 7) * 5;
}
