import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/api_exception.dart';
import '../../models/route_models.dart';
import '../../models/tracking_models.dart';
import '../../services/tracking_activity_repository.dart';
import '../../services/tracking_recorder.dart';
import '../../utils/route_processor.dart';

class TrackingRecorderState extends Equatable {
  const TrackingRecorderState({
    this.initialized = false,
    this.busy = false,
    this.permission = const TrackingPermissionSnapshot.unsupported(),
    this.session = const TrackingSessionSnapshot.idle(),
    this.liveRoute,
    this.error,
    this.notice,
    this.revision = 0,
  });

  final bool initialized;
  final bool busy;
  final TrackingPermissionSnapshot permission;
  final TrackingSessionSnapshot session;
  final ProcessedRoute? liveRoute;
  final String? error;
  final String? notice;
  final int revision;

  TrackingRecorderState copyWith({
    bool? initialized,
    bool? busy,
    TrackingPermissionSnapshot? permission,
    TrackingSessionSnapshot? session,
    ProcessedRoute? liveRoute,
    bool clearLiveRoute = false,
    String? error,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
    bool bumpRevision = false,
  }) {
    return TrackingRecorderState(
      initialized: initialized ?? this.initialized,
      busy: busy ?? this.busy,
      permission: permission ?? this.permission,
      session: session ?? this.session,
      liveRoute: clearLiveRoute ? null : (liveRoute ?? this.liveRoute),
      error: clearError ? null : error ?? this.error,
      notice: clearNotice ? null : notice ?? this.notice,
      revision: bumpRevision ? revision + 1 : revision,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        initialized,
        busy,
        permission,
        session,
        liveRoute,
        error,
        notice,
        revision,
      ];
}

class TrackingRecorderCubit extends Cubit<TrackingRecorderState> {
  TrackingRecorderCubit({
    required TrackingRecorder recorder,
    TrackingActivityRepository? activityRepository,
    void Function()? onActivitySaved,
  })  : _activityRepository = activityRepository,
        _onActivitySaved = onActivitySaved,
        _recorder = recorder,
        super(const TrackingRecorderState());

  final TrackingRecorder _recorder;
  final TrackingActivityRepository? _activityRepository;
  final void Function()? _onActivitySaved;
  Timer? _poller;
  bool _refreshing = false;

  Future<void> initialize() => refresh(showBusy: true);

  Future<void> refresh({bool showBusy = false}) async {
    if (_refreshing || isClosed) return;
    // A one-second poll must not clear the busy flag a control command is
    // holding — that would re-enable the buttons and let a second tap dispatch
    // the same command to the service twice.
    if (state.busy) return;
    _refreshing = true;
    if (showBusy) emit(state.copyWith(busy: true, clearError: true));
    try {
      final TrackingPermissionSnapshot permission =
          await _recorder.permissionStatus();
      final TrackingSessionSnapshot session = await _recorder.currentSession();
      ProcessedRoute? liveRoute = state.liveRoute;
      if (session.isActive &&
          session.sessionId != null &&
          (liveRoute == null ||
              session.pointCount != state.session.pointCount)) {
        try {
          final List<TrackingPoint> points =
              await _recorder.points(session.sessionId!);
          liveRoute = RouteProcessor.process(points);
        } catch (_) {
          // The preview is supplementary. A transient point-read failure must
          // not stop the clock, controls, or native state from refreshing.
        }
      }
      if (isClosed) return;
      emit(
        state.copyWith(
          initialized: true,
          busy: false,
          permission: permission,
          session: session,
          liveRoute: liveRoute,
          clearLiveRoute: !session.isActive,
          clearError: true,
        ),
      );
      _syncPolling(session.isActive);
    } catch (error) {
      if (!isClosed) {
        emit(
          state.copyWith(
            initialized: true,
            busy: false,
            error: _message(error),
            bumpRevision: true,
          ),
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> requestPermissions() async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, clearError: true, clearNotice: true));
    try {
      final TrackingPermissionSnapshot permission =
          await _recorder.requestPermissions();
      if (!isClosed) {
        emit(
          state.copyWith(
            initialized: true,
            busy: false,
            permission: permission,
            clearError: true,
          ),
        );
      }
    } catch (error) {
      _failure(error);
    }
  }

  Future<void> start() => _control(
        _recorder.start,
        notice: 'Workout recorder started',
      );

  Future<void> pause() => _control(
        _recorder.pause,
        notice: 'Workout paused',
      );

  Future<void> resume() => _control(
        _recorder.resume,
        notice: 'Workout resumed',
      );

  Future<void> stop() async {
    if (state.busy) return;
    final TrackingSessionSnapshot active = state.session;
    final String? sessionId = active.sessionId;
    if (!active.isActive || sessionId == null) return;

    // Without an API repository (mainly recorder-only tests), keep the Step 1
    // local-stop behavior. Production always supplies the repository below.
    if (_activityRepository == null) {
      return _control(
        _recorder.stop,
        notice: 'Workout saved on this device',
      );
    }

    emit(state.copyWith(busy: true, clearError: true, clearNotice: true));
    try {
      // Freeze the route before reading its append-only points. If upload
      // fails the paused native session remains recoverable and Finish can be
      // retried with the same client id; the backend deduplicates that retry.
      if (active.isRecording) await _recorder.pause();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final List<TrackingPoint> points = await _recorder.points(sessionId);
      final ProcessedRoute route = RouteProcessor.process(points);
      await _activityRepository.saveProcessed(
        route: route,
        clientId: sessionId,
      );
      await _recorder.stop();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (isClosed) return;
      emit(
        state.copyWith(
          busy: false,
          session: const TrackingSessionSnapshot.idle(),
          clearLiveRoute: true,
          notice: 'Workout saved to your activities',
          clearError: true,
          bumpRevision: true,
        ),
      );
      _syncPolling(false);
      _onActivitySaved?.call();
    } catch (error) {
      TrackingSessionSnapshot session = active;
      try {
        session = await _recorder.currentSession();
      } catch (_) {
        // Preserve the last known state; the next poll can recover it.
      }
      if (!isClosed) {
        emit(
          state.copyWith(
            busy: false,
            session: session,
            error: _message(error),
            clearNotice: true,
            bumpRevision: true,
          ),
        );
        _syncPolling(session.isActive);
      }
    }
  }

  Future<void> discard() => _control(
        _recorder.discard,
        notice: 'Workout discarded',
      );

  Future<void> openAppSettings() => _open(_recorder.openAppSettings);

  Future<void> openLocationSettings() => _open(_recorder.openLocationSettings);

  Future<void> _open(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      _failure(error);
    }
  }

  Future<void> _control(
    Future<void> Function() action, {
    required String notice,
  }) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, clearError: true, clearNotice: true));
    try {
      await action();
      // Native service commands are asynchronous. This brief hand-off lets the
      // service persist its state before the UI reads it back.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final TrackingSessionSnapshot session = await _recorder.currentSession();
      if (isClosed) return;
      emit(
        state.copyWith(
          busy: false,
          session: session,
          notice: notice,
          clearError: true,
          bumpRevision: true,
        ),
      );
      _syncPolling(session.isActive);
    } catch (error) {
      _failure(error);
    }
  }

  void _failure(Object error) {
    if (isClosed) return;
    emit(
      state.copyWith(
        busy: false,
        error: _message(error),
        clearNotice: true,
        bumpRevision: true,
      ),
    );
  }

  void _syncPolling(bool active) {
    if (!active) {
      _poller?.cancel();
      _poller = null;
      return;
    }
    _poller ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(refresh()),
    );
  }

  static String _message(Object error) {
    if (error is TrackingRecorderException) return error.message;
    if (error is ApiException) return error.message;
    return 'The workout recorder could not complete that action.';
  }

  @override
  Future<void> close() {
    _poller?.cancel();
    return super.close();
  }
}
