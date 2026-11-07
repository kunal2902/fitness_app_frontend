import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/api_exception.dart';
import '../../models/tracked_activity.dart';
import '../../services/tracking_activity_repository.dart';

class ActivityFeedState extends Equatable {
  const ActivityFeedState({
    this.loading = false,
    this.activities = const <TrackedActivity>[],
    this.error,
  });

  final bool loading;
  final List<TrackedActivity> activities;
  final String? error;

  @override
  List<Object?> get props => <Object?>[loading, activities, error];
}

class ActivityFeedCubit extends Cubit<ActivityFeedState> {
  ActivityFeedCubit({required TrackingActivityRepository repository})
      : _repository = repository,
        super(const ActivityFeedState());

  final TrackingActivityRepository _repository;
  bool _refreshing = false;

  Future<void> initialize() => refresh(showLoading: true);

  Future<void> refresh({bool showLoading = false}) async {
    if (_refreshing || isClosed) return;
    _refreshing = true;
    if (showLoading && state.activities.isEmpty) {
      emit(ActivityFeedState(loading: true, activities: state.activities));
    }
    try {
      final List<TrackedActivity> activities =
          await _repository.listRecent(limit: 10);
      if (!isClosed) emit(ActivityFeedState(activities: activities));
    } catch (error) {
      if (!isClosed) {
        emit(
          ActivityFeedState(
            activities: state.activities,
            error: error is ApiException
                ? error.message
                : 'Recent activities could not be loaded.',
          ),
        );
      }
    } finally {
      _refreshing = false;
    }
  }
}
