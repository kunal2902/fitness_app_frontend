import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../config/socket_events.dart';
import '../../models/api_exception.dart';
import '../../models/professional.dart';
import '../../services/assistance_service.dart';
import '../../services/socket_service.dart';

part 'professionals_event.dart';
part 'professionals_state.dart';

/// The coach list, kept live.
///
/// Presence is pushed over the socket rather than polled, so an "Online"
/// dot is accurate to the second instead of up to a refresh-interval
/// stale — which matters when the dot is what makes someone decide to
/// press call.
class ProfessionalsBloc extends Bloc<ProfessionalsEvent, ProfessionalsState> {
  ProfessionalsBloc({
    AssistanceService? service,
    SocketService? socket,
  })  : _service = service ?? AssistanceService(),
        _socket = socket ?? SocketService.instance,
        super(const ProfessionalsState()) {
    on<ProfessionalsRequested>(_onRequested);
    on<ProfessionalSelected>(_onSelected);
    on<ProfessionalPresenceChanged>(_onPresenceChanged);
    on<ProfessionalsPresenceSnapshot>(_onPresenceSnapshot);
    on<ProfessionalsPresenceResubscribed>(_onPresenceResubscribed);

    _attachPresenceListeners();
    _watchConnection();
  }

  final AssistanceService _service;
  final SocketService _socket;

  void Function(dynamic)? _presenceUpdateHandler;
  void Function(dynamic)? _presenceSnapshotHandler;
  StreamSubscription<SocketStatus>? _statusSubscription;

  /// Presence subscriptions live in the server's *in-process* watcher
  /// registry, keyed by socket id. A reconnect gets a new socket id, so
  /// every subscription made before the drop is gone — the server keeps
  /// pushing nothing and the dots freeze at whatever they were when the
  /// connection died, forever. Re-subscribing on each connect is the only
  /// way the list recovers.
  void _watchConnection() {
    _statusSubscription = _socket.statusStream.listen((SocketStatus status) {
      if (status != SocketStatus.connected) return;
      if (isClosed) return;
      add(const ProfessionalsPresenceResubscribed());
    });
  }

  void _attachPresenceListeners() {
    _presenceUpdateHandler = _socket.on(
      SocketEvents.presenceUpdate,
      (dynamic data) {
        final Map<String, dynamic> payload = socketPayload(data);
        add(
          ProfessionalPresenceChanged(
            userId: (payload['userId'] ?? '').toString(),
            isOnline: payload['isOnline'] as bool? ?? false,
            lastSeenAt:
                DateTime.tryParse((payload['lastSeenAt'] ?? '').toString()),
          ),
        );
      },
    );

    _presenceSnapshotHandler = _socket.on(
      SocketEvents.presenceSnapshot,
      (dynamic data) {
        final Map<String, dynamic> payload = socketPayload(data);
        final Object? users = payload['users'];
        if (users is! List) return;
        add(
          ProfessionalsPresenceSnapshot(
            users
                .map(socketPayload)
                .map(
                  (Map<String, dynamic> entry) => (
                    userId: (entry['userId'] ?? '').toString(),
                    isOnline: entry['isOnline'] as bool? ?? false,
                    lastSeenAt: DateTime.tryParse(
                      (entry['lastSeenAt'] ?? '').toString(),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  @override
  Future<void> close() {
    unawaited(_statusSubscription?.cancel());
    if (_presenceUpdateHandler != null) {
      _socket.off(SocketEvents.presenceUpdate, _presenceUpdateHandler);
    }
    if (_presenceSnapshotHandler != null) {
      _socket.off(SocketEvents.presenceSnapshot, _presenceSnapshotHandler);
    }
    // Includes `selected`: the detail screen subscribes on its own for
    // coaches reached by push or deep link, and the server's watcher
    // registry is additive, so anything left out here stays watched until
    // the socket itself drops.
    _socket.unsubscribeFromPresence(_watchedUserIds().toList());
    return super.close();
  }

  // -------------------------------------------------------------------------

  Future<void> _onRequested(
    ProfessionalsRequested event,
    Emitter<ProfessionalsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));

    try {
      final List<Professional> professionals =
          await _service.listProfessionals();

      emit(
        state.copyWith(
          professionals: professionals,
          isLoading: false,
        ),
      );

      // Ask the server to keep us posted about exactly these people.
      _socket.subscribeToPresence(
        professionals.map((Professional p) => p.userId).toList(),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.message));
    } catch (_) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Could not load our coaches. Pull down to retry.',
        ),
      );
    }
  }

  Future<void> _onSelected(
    ProfessionalSelected event,
    Emitter<ProfessionalsState> emit,
  ) async {
    emit(state.copyWith(isLoadingDetail: true, clearError: true));

    try {
      final Professional detail =
          await _service.getProfessional(event.professionalId);
      emit(state.copyWith(selected: detail, isLoadingDetail: false));

      // Subscribe explicitly rather than relying on the list having done
      // it. The detail screen is reachable from a push notification and
      // from a deep link, neither of which loads the list first — and
      // without a subscription the header's dot shows whatever the
      // profile fetch happened to return and then never changes, so a
      // coach who goes offline still looks callable.
      _socket.subscribeToPresence(<String>[detail.userId]);
    } on ApiException catch (e) {
      emit(state.copyWith(isLoadingDetail: false, errorMessage: e.message));
    } catch (_) {
      emit(
        state.copyWith(
          isLoadingDetail: false,
          errorMessage: 'Could not load that profile.',
        ),
      );
    }
  }

  /// Re-arms the server-side watch after a reconnect. No-op before the
  /// list has loaded — `_onRequested` subscribes for us in that case.
  void _onPresenceResubscribed(
    ProfessionalsPresenceResubscribed event,
    Emitter<ProfessionalsState> emit,
  ) {
    final Set<String> ids = _watchedUserIds();
    if (ids.isEmpty) return;
    _socket.subscribeToPresence(ids.toList());
  }

  /// Everyone whose presence this bloc is watching — the list, plus the
  /// coach on the open detail screen, who may not be in the list at all
  /// (opened from a push, or the list never loaded).
  Set<String> _watchedUserIds() => <String>{
        for (final Professional p in state.professionals) p.userId,
        if (state.selected != null) state.selected!.userId,
      };

  void _onPresenceChanged(
    ProfessionalPresenceChanged event,
    Emitter<ProfessionalsState> emit,
  ) {
    // Coming online drops the old timestamp rather than keeping it, so a
    // later disconnect cannot resurrect a "Last seen 6h ago" from the
    // previous session.
    Professional apply(Professional p) => p.copyWith(
          isOnline: event.isOnline,
          lastSeenAt: event.lastSeenAt,
          clearLastSeenAt: event.isOnline && event.lastSeenAt == null,
        );

    emit(
      state.copyWith(
        professionals: state.professionals
            .map((Professional p) => p.userId == event.userId ? apply(p) : p)
            .toList(),
        selected: state.selected?.userId == event.userId
            ? apply(state.selected!)
            : state.selected,
      ),
    );
  }

  void _onPresenceSnapshot(
    ProfessionalsPresenceSnapshot event,
    Emitter<ProfessionalsState> emit,
  ) {
    final Map<String, ({bool isOnline, DateTime? lastSeenAt})> byId =
        <String, ({bool isOnline, DateTime? lastSeenAt})>{
      for (final ({String userId, bool isOnline, DateTime? lastSeenAt}) entry
          in event.users)
        entry.userId: (isOnline: entry.isOnline, lastSeenAt: entry.lastSeenAt),
    };

    Professional apply(Professional p) {
      final ({bool isOnline, DateTime? lastSeenAt})? update = byId[p.userId];
      if (update == null) return p;
      return p.copyWith(
        isOnline: update.isOnline,
        lastSeenAt: update.lastSeenAt,
        clearLastSeenAt: update.isOnline && update.lastSeenAt == null,
      );
    }

    emit(
      state.copyWith(
        professionals: state.professionals.map(apply).toList(),
        // The detail screen holds its own copy. A snapshot that only
        // refreshed the list would leave the open profile showing the
        // pre-reconnect dot.
        selected: state.selected == null ? null : apply(state.selected!),
      ),
    );
  }
}
