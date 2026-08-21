part of 'profile_bloc.dart';

class ProfileState extends Equatable {
  ProfileState({
    this.isLoadingCalendar = true,
    this.isLoadingActivities = true,
    this.isSaving = false,
    this.isUploadingAvatar = false,
    this.calendarMode = CalendarMode.previous,
    DateTime? visibleMonth,
    this.days = const <WorkoutDay>[],
    this.streak = StreakStats.empty,
    this.activities = const <EnrolledActivity>[],
    this.errorMessage,
    this.successMessage,
    this.fieldErrors = const <String, String>{},
  }) : visibleMonth = visibleMonth ?? _thisMonth();

  final bool isLoadingCalendar;
  final bool isLoadingActivities;
  final bool isSaving;
  final bool isUploadingAvatar;

  final CalendarMode calendarMode;

  /// Always the first of the month being displayed.
  final DateTime visibleMonth;

  final List<WorkoutDay> days;
  final StreakStats streak;
  final List<EnrolledActivity> activities;

  final String? errorMessage;
  final String? successMessage;
  final Map<String, String> fieldErrors;

  bool get hasActivities => activities.isNotEmpty;
  bool get isBusy => isSaving || isUploadingAvatar;

  /// Days keyed by midnight-normalised date, for O(1) cell lookup while
  /// painting the grid.
  Map<DateTime, WorkoutDay> get dayLookup => <DateTime, WorkoutDay>{
        for (final WorkoutDay day in days) day.key: day,
      };

  static DateTime _thisMonth() {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  ProfileState copyWith({
    bool? isLoadingCalendar,
    bool? isLoadingActivities,
    bool? isSaving,
    bool? isUploadingAvatar,
    CalendarMode? calendarMode,
    DateTime? visibleMonth,
    List<WorkoutDay>? days,
    StreakStats? streak,
    List<EnrolledActivity>? activities,
    String? errorMessage,
    String? successMessage,
    Map<String, String>? fieldErrors,
    bool clearMessages = false,
  }) {
    return ProfileState(
      isLoadingCalendar: isLoadingCalendar ?? this.isLoadingCalendar,
      isLoadingActivities: isLoadingActivities ?? this.isLoadingActivities,
      isSaving: isSaving ?? this.isSaving,
      isUploadingAvatar: isUploadingAvatar ?? this.isUploadingAvatar,
      calendarMode: calendarMode ?? this.calendarMode,
      visibleMonth: visibleMonth ?? this.visibleMonth,
      days: days ?? this.days,
      streak: streak ?? this.streak,
      activities: activities ?? this.activities,
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage:
          clearMessages ? null : (successMessage ?? this.successMessage),
      fieldErrors: clearMessages
          ? const <String, String>{}
          : (fieldErrors ?? this.fieldErrors),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        isLoadingCalendar,
        isLoadingActivities,
        isSaving,
        isUploadingAvatar,
        calendarMode,
        visibleMonth,
        days,
        streak,
        activities,
        errorMessage,
        successMessage,
        fieldErrors,
      ];
}
