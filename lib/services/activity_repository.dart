import '../models/enrolled_activity.dart';

/// Source of the "activities you are enrolled in" card.
///
/// Phase 1 ships [StubActivityRepository]; when the enrolment API lands,
/// add an `ApiActivityRepository` implementing this and swap the instance
/// in `ProfileBloc` — no widget changes.
abstract interface class ActivityRepository {
  Future<List<EnrolledActivity>> enrolledActivities();
}

/// Placeholder data.
///
/// Flip [returnEmpty] to true to exercise the "Explore activities" empty
/// state — worth doing before you ship, since a brand-new user always sees
/// that branch first.
class StubActivityRepository implements ActivityRepository {
  const StubActivityRepository({this.returnEmpty = false});

  final bool returnEmpty;

  @override
  Future<List<EnrolledActivity>> enrolledActivities() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));

    if (returnEmpty) return const <EnrolledActivity>[];

    return const <EnrolledActivity>[
      EnrolledActivity(
        id: 'prog_calisthenics_foundations',
        title: 'Calisthenics Foundations',
        subtitle: '8 weeks · 4 days a week',
        completedSessions: 11,
        totalSessions: 32,
        coachName: 'Coach Aria',
        accentTag: 'SKILL',
      ),
      EnrolledActivity(
        id: 'prog_pull_strength',
        title: 'Pull Strength Block',
        subtitle: '6 weeks · 3 days a week',
        completedSessions: 4,
        totalSessions: 18,
        coachName: 'Coach Mateo',
        accentTag: 'STRENGTH',
      ),
    ];
  }
}
