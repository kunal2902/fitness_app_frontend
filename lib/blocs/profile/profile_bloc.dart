// `.wait` on a record of futures comes from dart:async.
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/api_exception.dart';
import '../../models/enrolled_activity.dart';
import '../../models/user_model.dart';
import '../../models/workout_day.dart';
import '../../services/activity_repository.dart';
import '../../services/user_service.dart';
import '../../services/workout_calendar_repository.dart';
import '../../store/app_store.dart';

part 'profile_event.dart';
part 'profile_state.dart';

/// Drives the profile tab: the calendar, the streak card, the activities
/// card, and every mutation of the user's own record.
///
/// Successful mutations are written into [AppStore], which persists them
/// and notifies every widget watching it — so the avatar in the header and
/// the name on any other screen update without extra plumbing.
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  ProfileBloc({
    UserService? userService,
    WorkoutCalendarRepository? calendarRepository,
    ActivityRepository? activityRepository,
    AppStore? store,
  })  : _users = userService ?? UserService(),
        _calendar =
            calendarRepository ?? const DummyWorkoutCalendarRepository(),
        _activities = activityRepository ?? const StubActivityRepository(),
        _store = store ?? AppStore.instance,
        super(ProfileState()) {
    on<ProfileStarted>(_onStarted);
    on<ProfileCalendarModeChanged>(_onModeChanged);
    on<ProfileMonthChanged>(_onMonthChanged);
    on<ProfileUpdateSubmitted>(_onUpdateSubmitted);
    on<ProfileAvatarSelected>(_onAvatarSelected);
    on<ProfileAvatarRemoved>(_onAvatarRemoved);
    on<ProfileMessageCleared>(_onMessageCleared);
  }

  final UserService _users;
  final WorkoutCalendarRepository _calendar;
  final ActivityRepository _activities;
  final AppStore _store;

  // -------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------

  Future<void> _onStarted(
    ProfileStarted event,
    Emitter<ProfileState> emit,
  ) async {
    emit(state.copyWith(isLoadingCalendar: true, isLoadingActivities: true));

    try {
      // The three loads are independent, so run them together rather than
      // making each wait on the one before it.
      final (List<WorkoutDay>, StreakStats, List<EnrolledActivity>) result =
          await (
        _calendar.daysForMonth(state.visibleMonth, state.calendarMode),
        _calendar.streak(),
        _activities.enrolledActivities(),
      ).wait;

      emit(
        state.copyWith(
          days: result.$1,
          streak: result.$2,
          activities: result.$3,
          isLoadingCalendar: false,
          isLoadingActivities: false,
        ),
      );
    } catch (_) {
      // Catch-all on purpose. A record `.wait` wraps failures in a
      // ParallelWaitError, so `on ApiException` would miss them and the tab
      // would sit on its loading state forever with no way to recover.
      emit(
        state.copyWith(
          isLoadingCalendar: false,
          isLoadingActivities: false,
          errorMessage: 'Could not load your profile. Pull down to retry.',
        ),
      );
    }
  }

  Future<void> _onModeChanged(
    ProfileCalendarModeChanged event,
    Emitter<ProfileState> emit,
  ) async {
    if (event.mode == state.calendarMode) return;
    emit(state.copyWith(calendarMode: event.mode, isLoadingCalendar: true));
    await _reloadCalendar(emit, month: state.visibleMonth, mode: event.mode);
  }

  Future<void> _onMonthChanged(
    ProfileMonthChanged event,
    Emitter<ProfileState> emit,
  ) async {
    final DateTime month = DateTime(event.month.year, event.month.month);
    if (month == state.visibleMonth) return;
    emit(state.copyWith(visibleMonth: month, isLoadingCalendar: true));
    await _reloadCalendar(emit, month: month, mode: state.calendarMode);
  }

  Future<void> _reloadCalendar(
    Emitter<ProfileState> emit, {
    required DateTime month,
    required CalendarMode mode,
  }) async {
    try {
      final List<WorkoutDay> days = await _calendar.daysForMonth(month, mode);
      emit(state.copyWith(days: days, isLoadingCalendar: false));
    } catch (_) {
      emit(
        state.copyWith(
          isLoadingCalendar: false,
          errorMessage: 'Could not load that month.',
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Mutations
  // -------------------------------------------------------------------------

  Future<void> _onUpdateSubmitted(
    ProfileUpdateSubmitted event,
    Emitter<ProfileState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearMessages: true));

    try {
      final UserModel user = await _users.updateProfile(
        fullName: event.fullName,
        username: event.username,
        email: event.email,
      );
      await _store.updateUser(user);
      emit(
        state.copyWith(isSaving: false, successMessage: 'Profile updated'),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: e.message,
          fieldErrors: e.fieldErrors,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  Future<void> _onAvatarSelected(
    ProfileAvatarSelected event,
    Emitter<ProfileState> emit,
  ) async {
    emit(state.copyWith(isUploadingAvatar: true, clearMessages: true));

    try {
      final UserModel user = await _users.uploadAvatar(event.filePath);
      await _store.updateUser(user);
      emit(
        state.copyWith(
          isUploadingAvatar: false,
          successMessage: 'Profile picture updated',
        ),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          isUploadingAvatar: false,
          errorMessage: e.message,
          fieldErrors: e.fieldErrors,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isUploadingAvatar: false,
          errorMessage: 'Could not upload that image. Please try again.',
        ),
      );
    }
  }

  Future<void> _onAvatarRemoved(
    ProfileAvatarRemoved event,
    Emitter<ProfileState> emit,
  ) async {
    emit(state.copyWith(isUploadingAvatar: true, clearMessages: true));

    try {
      final UserModel user = await _users.removeAvatar();
      await _store.updateUser(user);
      emit(
        state.copyWith(
          isUploadingAvatar: false,
          successMessage: 'Profile picture removed',
        ),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(isUploadingAvatar: false, errorMessage: e.message),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isUploadingAvatar: false,
          errorMessage: 'Could not remove that image. Please try again.',
        ),
      );
    }
  }

  void _onMessageCleared(
    ProfileMessageCleared event,
    Emitter<ProfileState> emit,
  ) {
    emit(state.copyWith(clearMessages: true));
  }
}
