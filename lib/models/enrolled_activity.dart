import 'package:equatable/equatable.dart';

/// A programme, challenge or coaching plan the user has joined.
///
/// Phase 1 has no enrolment backend, so this is populated from a stub
/// repository. The shape is deliberately close to what the API will return
/// so the swap is a repository change and nothing else.
class EnrolledActivity extends Equatable {
  const EnrolledActivity({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.completedSessions,
    required this.totalSessions,
    this.coachName,
    this.accentTag,
  });

  final String id;
  final String title;

  /// e.g. "8 weeks · 4 days a week".
  final String subtitle;

  final int completedSessions;
  final int totalSessions;

  final String? coachName;

  /// Short label for the corner chip, e.g. "STRENGTH".
  final String? accentTag;

  /// 0.0 – 1.0 for the progress bar.
  double get progress {
    if (totalSessions <= 0) return 0;
    return (completedSessions / totalSessions).clamp(0, 1).toDouble();
  }

  int get percentComplete => (progress * 100).round();

  factory EnrolledActivity.fromJson(Map<String, dynamic> json) {
    return EnrolledActivity(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '') as String,
      subtitle: (json['subtitle'] ?? '') as String,
      completedSessions: (json['completedSessions'] as num?)?.toInt() ?? 0,
      totalSessions: (json['totalSessions'] as num?)?.toInt() ?? 0,
      coachName: json['coachName'] as String?,
      accentTag: json['accentTag'] as String?,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        title,
        subtitle,
        completedSessions,
        totalSessions,
        coachName,
        accentTag,
      ];
}
