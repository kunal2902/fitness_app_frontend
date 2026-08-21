part of 'profile_bloc.dart';

sealed class ProfileEvent extends Equatable {
  const ProfileEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Loads the calendar, streak and enrolled activities for the first time.
class ProfileStarted extends ProfileEvent {
  const ProfileStarted();
}

/// Toggles between "Previous workouts" and "Goal workouts".
class ProfileCalendarModeChanged extends ProfileEvent {
  const ProfileCalendarModeChanged(this.mode);
  final CalendarMode mode;

  @override
  List<Object?> get props => <Object?>[mode];
}

/// Steps the calendar to another month.
class ProfileMonthChanged extends ProfileEvent {
  const ProfileMonthChanged(this.month);
  final DateTime month;

  @override
  List<Object?> get props => <Object?>[month];
}

/// Saves edited profile fields. Pass only what changed.
class ProfileUpdateSubmitted extends ProfileEvent {
  const ProfileUpdateSubmitted({this.fullName, this.username, this.email});

  final String? fullName;
  final String? username;
  final String? email;

  @override
  List<Object?> get props => <Object?>[fullName, username, email];
}

/// The user picked an image; [filePath] is a local file ready to upload.
class ProfileAvatarSelected extends ProfileEvent {
  const ProfileAvatarSelected(this.filePath);
  final String filePath;

  @override
  List<Object?> get props => <Object?>[filePath];
}

class ProfileAvatarRemoved extends ProfileEvent {
  const ProfileAvatarRemoved();
}

/// Dismisses a surfaced error or success message.
class ProfileMessageCleared extends ProfileEvent {
  const ProfileMessageCleared();
}
