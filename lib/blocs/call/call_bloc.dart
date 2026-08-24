import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../config/app_config.dart';
import '../../config/socket_events.dart';
import '../../models/call_models.dart';
import '../../services/assistance_service.dart';
import '../../services/push_service.dart';
import '../../services/socket_service.dart';
import '../../services/webrtc_service.dart';

part 'call_event.dart';
part 'call_state.dart';

/// The call state machine.
///
/// Owns exactly one call at a time and is the only thing that talks to
/// both the signalling socket and [WebRtcService]. Splitting those two
/// apart is what keeps the ordering rules in one readable place:
///
///  * the **caller** dials, waits for `call:accepted`, then sends the offer;
///  * the **callee** accepts, opens its media, then answers the offer.
///
/// Sending an offer before the far end has accepted would arrive at a peer
/// that has not opened its camera yet — the SDP would be answered with no
/// media and the call would connect to a black screen.
class CallBloc extends Bloc<CallEvent, CallState> {
  CallBloc({
    SocketService? socket,
    AssistanceService? service,
    WebRtcService? webrtc,
    PushService? push,
  })  : _socket = socket ?? SocketService.instance,
        _service = service ?? AssistanceService(),
        _webrtc = webrtc ?? WebRtcService(),
        _push = push ?? PushService.instance,
        super(const CallState()) {
    on<CallDialRequested>(_onDial);
    on<CallAcceptRequested>(_onAccept);
    on<CallDeclineRequested>(_onDecline);
    on<CallHangUpRequested>(_onHangUp);
    on<CallDismissed>(_onDismissed);

    on<CallMicToggled>(_onMicToggled);
    on<CallCameraToggled>(_onCameraToggled);
    on<CallSpeakerToggled>(_onSpeakerToggled);
    on<CallCameraSwitched>(_onCameraSwitched);

    on<CallInviteReceived>(_onInviteReceived);
    on<CallAcceptedByPeer>(_onAcceptedByPeer);
    on<CallTerminatedRemotely>(_onTerminatedRemotely);
    on<CallOfferReceived>(_onOfferReceived);
    on<CallAnswerReceived>(_onAnswerReceived);
    on<CallIceCandidateReceived>(_onIceCandidateReceived);

    on<CallConnectionStateChanged>(_onConnectionStateChanged);
    on<CallRemoteStreamArrived>(_onRemoteStreamArrived);
    on<CallTicked>(_onTicked);
    on<CallRingTimedOut>(_onRingTimedOut);
    on<CallConnectTimedOut>(_onConnectTimedOut);

    _attachSocketListeners();
    _attachWebRtcListeners();
    _attachPushListeners();

    // A VoIP push can be answered before this bloc is constructed — the
    // accept stream is broadcast, so that event would be lost. PushService
    // holds the last one for exactly this handover.
    final IncomingCall? pending = _push.takePendingAccept();
    if (pending != null) {
      add(CallInviteReceived(pending));
      add(const CallAcceptRequested());
    }
  }

  final SocketService _socket;
  final AssistanceService _service;
  final WebRtcService _webrtc;
  final PushService _push;

  final math.Random _random = math.Random.secure();

  /// Renderers, handed straight to the call screen's video views.
  RTCVideoRenderer get localRenderer => _webrtc.localRenderer;
  RTCVideoRenderer get remoteRenderer => _webrtc.remoteRenderer;

  final Map<String, void Function(dynamic)> _socketHandlers =
      <String, void Function(dynamic)>{};
  StreamSubscription<RTCIceCandidate>? _candidateSub;
  StreamSubscription<RTCPeerConnectionState>? _connectionSub;
  StreamSubscription<bool>? _remoteStreamSub;
  StreamSubscription<IncomingCall>? _pushAcceptSub;
  StreamSubscription<String>? _pushDeclineSub;

  Timer? _ticker;
  Timer? _ringTimer;
  Timer? _reconnectTimer;

  /// Bounds the `connecting` phase — see [_startConnectWatchdog].
  Timer? _connectTimer;

  /// An offer that arrived before our peer connection was ready.
  Map<String, dynamic>? _bufferedOffer;

  /// Set when the far end accepts before `webrtc.start()` has finished.
  ///
  /// bloc's default transformer is concurrent, so `call:accepted` can be
  /// processed while `_onDial` is still awaiting getUserMedia — which on
  /// first run includes the OS permission dialog. Without this flag the
  /// offer would be attempted against a peer that does not exist yet and
  /// the call would be torn down as failed.
  bool _peerAccepted = false;

  /// Latch for [_finish] — see the comment there.
  bool _finishing = false;

  /// Candidates that arrived before the peer connection existed at all.
  /// [WebRtcService] buffers once a peer exists; this covers the window
  /// before that.
  final List<Map<String, dynamic>> _bufferedCandidates =
      <Map<String, dynamic>>[];

  // -------------------------------------------------------------------------
  // Wiring
  // -------------------------------------------------------------------------

  void _listen(String event, void Function(Map<String, dynamic>) handler) {
    _socketHandlers[event] = _socket.on(event, (dynamic data) {
      handler(socketPayload(data));
    });
  }

  void _attachSocketListeners() {
    _listen(SocketEvents.callIncoming, (Map<String, dynamic> payload) {
      add(CallInviteReceived(IncomingCall.fromJson(payload)));
    });

    _listen(SocketEvents.callAccepted, (Map<String, dynamic> payload) {
      add(CallAcceptedByPeer((payload['callId'] ?? '').toString()));
    });

    _listen(SocketEvents.callRejected, (Map<String, dynamic> payload) {
      add(
        CallTerminatedRemotely(
          callId: (payload['callId'] ?? '').toString(),
          // "No answer" and "Declined" are not the same message to show
          // someone who just tried to reach their coach.
          reason: switch ((payload['reason'] ?? '').toString()) {
            'busy' => CallEndReason.busy,
            'missed' => CallEndReason.missed,
            _ => CallEndReason.declined,
          },
        ),
      );
    });

    _listen(SocketEvents.callCancelled, (Map<String, dynamic> payload) {
      final String reason = (payload['reason'] ?? '').toString();
      add(
        CallTerminatedRemotely(
          callId: (payload['callId'] ?? '').toString(),
          reason: switch (reason) {
            'answered_elsewhere' ||
            'handled_elsewhere' =>
              CallEndReason.answeredElsewhere,
            'missed' => CallEndReason.missed,
            _ => CallEndReason.cancelled,
          },
        ),
      );
    });

    _listen(SocketEvents.callEnded, (Map<String, dynamic> payload) {
      add(
        CallTerminatedRemotely(
          callId: (payload['callId'] ?? '').toString(),
          // The server sends this for every ending it did not route
          // through call:rejected — including the sweeper's `failed` and
          // the HTTP fallback's `cancelled`. Collapsing them all to
          // "Call ended" tells the user a connection that never came up
          // completed normally.
          reason: switch ((payload['reason'] ?? '').toString()) {
            'missed' => CallEndReason.missed,
            'cancelled' => CallEndReason.cancelled,
            'failed' => CallEndReason.failed,
            'busy' => CallEndReason.busy,
            'declined' => CallEndReason.declined,
            _ => CallEndReason.completed,
          },
        ),
      );
    });

    _listen(SocketEvents.callOffer, (Map<String, dynamic> payload) {
      add(
        CallOfferReceived(
          callId: (payload['callId'] ?? '').toString(),
          sdp: socketPayload(payload['sdp']),
        ),
      );
    });

    _listen(SocketEvents.callAnswer, (Map<String, dynamic> payload) {
      add(
        CallAnswerReceived(
          callId: (payload['callId'] ?? '').toString(),
          sdp: socketPayload(payload['sdp']),
        ),
      );
    });

    _listen(SocketEvents.callIce, (Map<String, dynamic> payload) {
      add(
        CallIceCandidateReceived(
          callId: (payload['callId'] ?? '').toString(),
          candidate: socketPayload(payload['candidate']),
        ),
      );
    });
  }

  void _attachWebRtcListeners() {
    _candidateSub = _webrtc.localCandidates.listen((RTCIceCandidate candidate) {
      final String? callId = state.callId;
      if (callId == null) return;
      _socket.emit(SocketEvents.callIce, <String, dynamic>{
        'callId': callId,
        'candidate': WebRtcService.candidateToJson(candidate),
      });
    });

    _connectionSub = _webrtc.connectionState.listen(
      (RTCPeerConnectionState s) => add(CallConnectionStateChanged(s)),
    );

    _remoteStreamSub = _webrtc.remoteStreamArrived.listen(
      (_) => add(const CallRemoteStreamArrived()),
    );
  }

  void _attachPushListeners() {
    // Answering from the native ringer while the app was backgrounded.
    _pushAcceptSub = _push.callAccepted.listen((IncomingCall call) {
      if (state.callId != call.callId) {
        add(CallInviteReceived(call));
      }
      add(const CallAcceptRequested());
    });

    _pushDeclineSub = _push.callDeclined.listen((String callId) {
      if (state.callId != callId) return;
      add(const CallDeclineRequested());
    });
  }

  @override
  Future<void> close() async {
    _ticker?.cancel();
    _ringTimer?.cancel();
    _reconnectTimer?.cancel();
    _connectTimer?.cancel();

    _socketHandlers.forEach(_socket.off);
    _socketHandlers.clear();

    await _candidateSub?.cancel();
    await _connectionSub?.cancel();
    await _remoteStreamSub?.cancel();
    await _pushAcceptSub?.cancel();
    await _pushDeclineSub?.cancel();

    await _webrtc.dispose();
    return super.close();
  }

  // -------------------------------------------------------------------------
  // Outgoing
  // -------------------------------------------------------------------------

  Future<void> _onDial(
    CallDialRequested event,
    Emitter<CallState> emit,
  ) async {
    if (state.isActive) return;

    final String callId = _newCallId();
    _resetForNewCall();

    emit(
      CallState(
        phase: CallPhase.dialling,
        callId: callId,
        conversationId: event.conversationId,
        peer: event.peer,
        withVideo: event.withVideo,
        isOutgoing: true,
        isCameraEnabled: event.withVideo,
        isSpeakerOn: event.withVideo,
      ),
    );

    try {
      // Invite first: the acknowledgement carries fresh TURN credentials,
      // so there is no second round trip and no risk of using expired ones.
      final Map<String, dynamic> ack = await _socket.request(
        SocketEvents.callInvite,
        data: <String, dynamic>{
          'conversationId': event.conversationId,
          'callId': callId,
          'withVideo': event.withVideo,
        },
      );

      if (ack['ok'] != true) {
        final String code = (ack['code'] ?? '').toString();
        // alreadySignalled: the server refused to create the session, so
        // there is nothing to end. Signalling here would emit `call:cancel`
        // for an id with no CallSession — a wasted NO_CALL over the socket,
        // and a guaranteed 404 on every offline dial over the HTTP
        // fallback. On a CALL_EXISTS collision it would cancel a live call.
        await _finish(
          emit,
          code == 'CALLEE_BUSY' ? CallEndReason.busy : CallEndReason.failed,
          message: (ack['message'] ?? 'Could not start the call').toString(),
          alreadySignalled: true,
        );
        return;
      }

      final IceServersConfig ice = IceServersConfig.fromJson(ack);
      emit(state.copyWith(turnAvailable: ice.turnAvailable));

      // Armed here, not after getUserMedia: the OS permission dialog can
      // sit open indefinitely on first run, and until this timer exists
      // nothing on the client bounds the call at all.
      _startRingTimer(callId);

      await _webrtc.start(withVideo: event.withVideo, ice: ice);

      // The call can have ended while getUserMedia was open. Without this
      // check the camera and mic stay live after the call screen closes.
      if (state.callId != callId || state.phase == CallPhase.ended) {
        await _webrtc.hangUp();
        return;
      }

      await _flushBufferedCandidates();

      // They may already have accepted while we were opening the camera.
      if (_peerAccepted) {
        _peerAccepted = false;
        _ringTimer?.cancel();
        emit(state.copyWith(phase: CallPhase.connecting));
        _startConnectWatchdog(callId);
        await _sendOffer(emit, callId);
      }
    } catch (error) {
      developer.log('dial failed: $error', name: 'call');
      await _finish(
        emit,
        CallEndReason.failed,
        message: 'Could not access your camera or microphone.',
      );
    }
  }

  /// They answered — now the offer can go.
  Future<void> _onAcceptedByPeer(
    CallAcceptedByPeer event,
    Emitter<CallState> emit,
  ) async {
    if (event.callId != state.callId) return;

    _ringTimer?.cancel();
    emit(state.copyWith(phase: CallPhase.connecting));
    _startConnectWatchdog(event.callId);

    if (!_webrtc.hasPeer) {
      // Still opening the camera — _onDial sends the offer when it lands.
      _peerAccepted = true;
      return;
    }

    await _sendOffer(emit, event.callId);
  }

  /// Creates the offer and waits for the server to confirm the relay.
  ///
  /// Sent as a request rather than a bare emit: a dropped offer leaves the
  /// peer connection in `new` forever, which never reaches `failed`, so no
  /// state callback would ever fire and the call would sit on
  /// "Connecting…" with the camera on until the user gave up.
  Future<void> _sendOffer(Emitter<CallState> emit, String callId) async {
    try {
      final Map<String, dynamic> offer = await _webrtc.createOffer();
      final Map<String, dynamic> ack = await _socket.request(
        SocketEvents.callOffer,
        data: <String, dynamic>{'callId': callId, 'sdp': offer},
      );
      if (ack['ok'] != true) {
        await _finish(
          emit,
          CallEndReason.failed,
          message: 'Could not reach them. Check your connection.',
        );
      }
    } catch (error) {
      developer.log('offer failed: $error', name: 'call');
      await _finish(emit, CallEndReason.failed,
          message: 'Could not negotiate the call.');
    }
  }

  // -------------------------------------------------------------------------
  // Incoming
  // -------------------------------------------------------------------------

  Future<void> _onInviteReceived(
    CallInviteReceived event,
    Emitter<CallState> emit,
  ) async {
    // Already busy — tell them rather than silently ignoring it.
    //
    // Through _signalEnd, not a bare emit: emit() drops silently when the
    // socket is down, and a flaky connection is exactly when a second
    // call arrives during the first. Without the HTTP fallback the other
    // person rings for the full 45 seconds and is told nothing.
    if (state.isActive && state.callId != event.call.callId) {
      _signalEnd(
        event.call.callId,
        event: SocketEvents.callReject,
        reason: 'busy',
        httpReason: 'busy',
      );
      return;
    }

    _resetForNewCall();
    _push.rememberPending(event.call);

    emit(
      CallState(
        phase: CallPhase.ringing,
        callId: event.call.callId,
        conversationId: event.call.conversationId,
        peer: event.call.peer,
        withVideo: event.call.withVideo,
        isOutgoing: false,
        isCameraEnabled: event.call.withVideo,
        isSpeakerOn: event.call.withVideo,
      ),
    );

    _startRingTimer(event.call.callId);
  }

  Future<void> _onAccept(
    CallAcceptRequested event,
    Emitter<CallState> emit,
  ) async {
    final String? callId = state.callId;
    if (callId == null || state.phase != CallPhase.ringing) return;

    _ringTimer?.cancel();
    emit(state.copyWith(phase: CallPhase.connecting));
    _startConnectWatchdog(callId);
    await PushService.dismissIncomingCall(callId);

    try {
      final Map<String, dynamic> ack = await _socket.request(
        SocketEvents.callAccept,
        data: <String, dynamic>{'callId': callId},
      );

      if (ack['ok'] != true) {
        // alreadySignalled, always. A failed accept means the server
        // already knows this call's fate — it never existed, it has
        // ended, or ANOTHER OF OUR OWN DEVICES won the atomic claim.
        // Ending it from here would tear down the call that device is
        // busy answering, and the caller would never be told: `call:end`
        // notifies the other participant, which is the caller, not the
        // sibling device still sitting on "Connecting…".
        final String code = (ack['code'] ?? '').toString();
        await _finish(
          emit,
          code == 'ALREADY_ANSWERED'
              ? CallEndReason.answeredElsewhere
              : CallEndReason.failed,
          message: (ack['message'] ?? 'Could not answer').toString(),
          alreadySignalled: true,
        );
        return;
      }

      final IceServersConfig ice = IceServersConfig.fromJson(ack);
      emit(state.copyWith(turnAvailable: ice.turnAvailable));

      await _webrtc.start(withVideo: state.withVideo, ice: ice);

      // The caller may have hung up while we were opening the camera.
      if (state.callId != callId || state.phase == CallPhase.ended) {
        await _webrtc.hangUp();
        return;
      }

      // The offer may already be waiting — the caller sends it the moment
      // it learns we accepted, which routinely beats getUserMedia.
      final Map<String, dynamic>? offer = _bufferedOffer;
      _bufferedOffer = null;
      if (offer != null && !await _answerOffer(callId, offer)) {
        await _finish(
          emit,
          CallEndReason.failed,
          message: 'Could not negotiate the call.',
        );
        return;
      }
      await _flushBufferedCandidates();
    } catch (error) {
      developer.log('accept failed: $error', name: 'call');
      await _finish(
        emit,
        CallEndReason.failed,
        message: 'Could not access your camera or microphone.',
      );
    }
  }

  Future<void> _onOfferReceived(
    CallOfferReceived event,
    Emitter<CallState> emit,
  ) async {
    if (event.callId != state.callId) return;

    if (!_webrtc.hasPeer) {
      // Not ready yet — hold it until accept() finishes opening media.
      _bufferedOffer = event.sdp;
      return;
    }
    if (!await _answerOffer(event.callId, event.sdp)) {
      await _finish(
        emit,
        CallEndReason.failed,
        message: 'Could not negotiate the call.',
      );
    }
  }

  /// Answers an offer. Returns false if the answer never reached the peer.
  ///
  /// The return value matters: a swallowed failure here is invisible.
  /// There is no local media event to react to, the peer connection stays
  /// in `new` rather than moving to `failed`, and both ends sit on
  /// "Connecting…" with the camera on until somebody gives up.
  Future<bool> _answerOffer(String callId, Map<String, dynamic> sdp) async {
    try {
      await _webrtc.setRemoteDescription(sdp);
      final Map<String, dynamic> answer = await _webrtc.createAnswer();
      final Map<String, dynamic> ack = await _socket.request(
        SocketEvents.callAnswer,
        data: <String, dynamic>{'callId': callId, 'sdp': answer},
      );
      if (ack['ok'] != true) {
        developer.log('answer not relayed: ${ack['code']}', name: 'call');
        return false;
      }
      return true;
    } catch (error) {
      developer.log('answer failed: $error', name: 'call');
      return false;
    }
  }

  Future<void> _onAnswerReceived(
    CallAnswerReceived event,
    Emitter<CallState> emit,
  ) async {
    if (event.callId != state.callId) return;
    try {
      await _webrtc.setRemoteDescription(event.sdp);
    } catch (error) {
      developer.log('set answer failed: $error', name: 'call');
    }
  }

  Future<void> _onIceCandidateReceived(
    CallIceCandidateReceived event,
    Emitter<CallState> emit,
  ) async {
    if (event.callId != state.callId) return;
    // A candidate arriving after the call ended must not repopulate the
    // buffer — _resetBuffers has already run, and anything added now
    // survives into the *next* call, where it would be replayed against a
    // different peer connection.
    if (state.phase == CallPhase.ended || state.phase == CallPhase.idle) {
      return;
    }

    if (!_webrtc.hasPeer) {
      _bufferedCandidates.add(event.candidate);
      return;
    }
    await _webrtc.addRemoteCandidate(event.candidate);
  }

  Future<void> _flushBufferedCandidates() async {
    if (_bufferedCandidates.isEmpty) return;
    final List<Map<String, dynamic>> pending =
        List<Map<String, dynamic>>.from(_bufferedCandidates);
    _bufferedCandidates.clear();
    for (final Map<String, dynamic> candidate in pending) {
      await _webrtc.addRemoteCandidate(candidate);
    }
  }

  // -------------------------------------------------------------------------
  // Ending
  // -------------------------------------------------------------------------

  /// Tells the server the call is over, with an HTTP fallback.
  ///
  /// Every locally-originated ending goes through here, and the HTTP
  /// fallback is the point of it. A bare `emit` is dropped silently when
  /// the socket is down — so declining a call on a flaky connection used
  /// to leave the caller ringing for the full 45 seconds, and a failed
  /// call told the server nothing at all. That last one is the worst bug
  /// this feature can have: the CallSession stays `connected` forever, and
  /// while it does, `activeCallFor` reports BOTH people busy, so every
  /// future call between them is refused. There is no way out of that
  /// state from inside the app.
  void _signalEnd(
    String callId, {
    required String event,
    String? reason,
    required String httpReason,
  }) {
    if (_socket.isConnected) {
      _socket.emit(event, <String, dynamic>{
        'callId': callId,
        if (reason != null) 'reason': reason,
      });
      return;
    }

    // Not awaited: the UI must tear down now, not in a round trip's time.
    unawaited(
      _service
          .endCall(callId, reason: httpReason)
          .catchError((Object error) {
        developer.log('http end-call fallback failed: $error', name: 'call');
      }),
    );
  }

  Future<void> _onDecline(
    CallDeclineRequested event,
    Emitter<CallState> emit,
  ) async {
    final String? callId = state.callId;
    // Only a ringing call can be declined. Without this guard the
    // "call ended" echo from the native ringer re-ends a finished call as
    // a decline, rewriting the chat row from "Video call · 5m 0s" to
    // "Video call declined".
    if (callId == null || state.phase != CallPhase.ringing) return;

    _signalEnd(
      callId,
      event: SocketEvents.callReject,
      reason: 'declined',
      httpReason: 'declined',
    );
    await _finish(emit, CallEndReason.declined, alreadySignalled: true);
  }

  Future<void> _onHangUp(
    CallHangUpRequested event,
    Emitter<CallState> emit,
  ) async {
    final String? callId = state.callId;
    if (callId == null) {
      // Nothing to hang up. Finishing anyway would emit `ended`, and
      // CallOverlay draws the call UI for `ended` — so a stray hang-up
      // (the reconnect timer firing after a dismiss, say) would flash a
      // full-screen "Call ended" over whatever the user was doing.
      if (!state.isActive) return;
      await _finish(emit, CallEndReason.completed, alreadySignalled: true);
      return;
    }

    final bool wasRinging =
        state.phase == CallPhase.dialling || state.phase == CallPhase.ringing;

    _signalEnd(
      callId,
      event: wasRinging ? SocketEvents.callCancel : SocketEvents.callEnd,
      httpReason: wasRinging ? 'cancelled' : 'completed',
    );

    await _finish(
      emit,
      wasRinging ? CallEndReason.cancelled : CallEndReason.completed,
      alreadySignalled: true,
    );
  }

  Future<void> _onTerminatedRemotely(
    CallTerminatedRemotely event,
    Emitter<CallState> emit,
  ) async {
    if (event.callId != state.callId) return;
    // The other side already told the server; echoing it back would
    // bounce between the two devices.
    await _finish(emit, event.reason, alreadySignalled: true);
  }

  Future<void> _onRingTimedOut(
    CallRingTimedOut event,
    Emitter<CallState> emit,
  ) async {
    if (event.callId != state.callId) return;
    if (state.phase != CallPhase.dialling && state.phase != CallPhase.ringing) {
      return;
    }

    _signalEnd(
      event.callId,
      event: state.isOutgoing ? SocketEvents.callCancel : SocketEvents.callReject,
      // Without an explicit reason the server records an unanswered call
      // as "declined", and the chat history reads "Video call declined"
      // for a call nobody ever saw.
      reason: state.isOutgoing ? null : 'missed',
      // Matched to the socket path: the caller giving up is a `cancelled`
      // call, the callee's phone giving up is a `missed` one. Sending
      // 'missed' for both would write a different chat row depending on
      // which transport happened to be up.
      httpReason: state.isOutgoing ? 'cancelled' : 'missed',
    );
    await _finish(emit, CallEndReason.missed, alreadySignalled: true);
  }

  /// Answered, but media never came up within the watchdog window.
  Future<void> _onConnectTimedOut(
    CallConnectTimedOut event,
    Emitter<CallState> emit,
  ) async {
    if (event.callId != state.callId) return;
    // Reconnecting is handled by its own grace timer; only a call that
    // never got off the ground belongs here.
    if (state.phase != CallPhase.connecting) return;

    await _finish(
      emit,
      CallEndReason.failed,
      message: state.turnAvailable
          ? 'Could not connect. Check your connection and try again.'
          : 'Could not connect. This network needs a TURN relay, which is '
              'not configured on the server.',
    );
  }

  /// The single exit path. Every way a call can end funnels through here,
  /// so the camera and microphone are released exactly once — and so the
  /// server always hears about it.
  ///
  /// [alreadySignalled] is for the paths that told the server themselves
  /// (hang-up, decline, timeout) and for endings the *other* side
  /// reported. Everything else — a failed peer connection, getUserMedia
  /// throwing, a rejected offer — reaches here having said nothing, and
  /// those are exactly the cases that used to strand a live CallSession on
  /// the server forever.
  Future<void> _finish(
    Emitter<CallState> emit,
    CallEndReason reason, {
    String? message,
    bool alreadySignalled = false,
  }) async {
    // Re-entrancy latch. `_finish` awaits the native teardown before it
    // emits `ended`, so for that whole window `state.phase` still says the
    // call is live — and `_webrtc.hangUp()` closing the peer connection
    // synthesises an `RTCPeerConnectionStateClosed` that lands right in
    // the middle of it. Without this, that callback re-enters, sends a
    // SECOND `call:end`, and overwrites endReason — so a call the other
    // side declined shows "Call declined" and then flips to "Call ended".
    // Checking `state.phase` instead is a race, not a guard.
    // `idle` is in the guard too: a stale connection-state callback
    // arriving after the user dismissed the ended card would otherwise
    // flash a full-screen "Call ended" over whatever they moved on to.
    if (_finishing ||
        state.phase == CallPhase.ended ||
        state.phase == CallPhase.idle) {
      return;
    }
    _finishing = true;

    _ticker?.cancel();
    _ringTimer?.cancel();
    _reconnectTimer?.cancel();
    _connectTimer?.cancel();

    final String? callId = state.callId;

    if (callId != null && !alreadySignalled) {
      final bool wasRinging = state.phase == CallPhase.dialling ||
          state.phase == CallPhase.ringing;
      _signalEnd(
        callId,
        event: wasRinging ? SocketEvents.callCancel : SocketEvents.callEnd,
        httpReason: reason == CallEndReason.failed ? 'failed' : 'completed',
      );
    }

    if (callId != null) {
      await PushService.dismissIncomingCall(callId);
    }

    await _webrtc.hangUp();
    _resetBuffers();

    emit(
      state
          // clearError first so a message of null actually clears a stale
          // error rather than being ignored by copyWith's ?? fallback.
          .copyWith(clearError: true)
          .copyWith(
            phase: CallPhase.ended,
            endReason: reason,
            errorMessage: message,
            hasRemoteVideo: false,
          ),
    );

    // Released only now: from here the `phase == ended` half of the guard
    // holds, and the next call resets it in _onDial/_onInviteReceived.
    _finishing = false;
  }

  void _onDismissed(CallDismissed event, Emitter<CallState> emit) {
    emit(const CallState());
  }

  // -------------------------------------------------------------------------
  // Connection health
  // -------------------------------------------------------------------------

  Future<void> _onConnectionStateChanged(
    CallConnectionStateChanged event,
    Emitter<CallState> emit,
  ) async {
    switch (event.state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _reconnectTimer?.cancel();
        // Media is up — the connecting watchdog has done its job.
        _connectTimer?.cancel();
        if (state.phase != CallPhase.connected) {
          emit(state.copyWith(phase: CallPhase.connected));
          _startTicker();
        }

      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        // Not fatal — ICE frequently recovers from a network switch. Give
        // it a grace period before tearing the call down.
        if (state.phase == CallPhase.connected) {
          emit(state.copyWith(phase: CallPhase.reconnecting));
          _reconnectTimer?.cancel();
          _reconnectTimer = Timer(AppConfig.callReconnectGrace, () {
            if (isClosed) return;
            add(const CallHangUpRequested());
          });
        }

      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        await _finish(
          emit,
          CallEndReason.failed,
          message: state.turnAvailable
              ? 'The connection dropped.'
              : 'Could not connect. This network needs a TURN relay, which '
                  'is not configured on the server.',
        );

      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        if (state.isActive) {
          await _finish(emit, CallEndReason.completed);
        }

      default:
        break;
    }
  }

  void _onRemoteStreamArrived(
    CallRemoteStreamArrived event,
    Emitter<CallState> emit,
  ) {
    emit(state.copyWith(hasRemoteVideo: true));
  }

  void _onTicked(CallTicked event, Emitter<CallState> emit) {
    if (state.phase != CallPhase.connected) return;
    emit(state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1)));
  }

  // -------------------------------------------------------------------------
  // Controls
  // -------------------------------------------------------------------------

  Future<void> _onMicToggled(
    CallMicToggled event,
    Emitter<CallState> emit,
  ) async {
    final bool next = !state.isMicEnabled;
    await _webrtc.setMicEnabled(next);
    emit(state.copyWith(isMicEnabled: next));
  }

  Future<void> _onCameraToggled(
    CallCameraToggled event,
    Emitter<CallState> emit,
  ) async {
    if (!state.withVideo) return;
    final bool next = !state.isCameraEnabled;
    await _webrtc.setCameraEnabled(next);
    emit(state.copyWith(isCameraEnabled: next));
  }

  Future<void> _onSpeakerToggled(
    CallSpeakerToggled event,
    Emitter<CallState> emit,
  ) async {
    final bool next = !state.isSpeakerOn;
    await _webrtc.setSpeaker(next);
    emit(state.copyWith(isSpeakerOn: next));
  }

  Future<void> _onCameraSwitched(
    CallCameraSwitched event,
    Emitter<CallState> emit,
  ) async {
    if (!state.withVideo) return;
    await _webrtc.switchCamera();
    emit(state.copyWith(isFrontCamera: _webrtc.isFrontCamera));
  }

  // -------------------------------------------------------------------------
  // Timers and ids
  // -------------------------------------------------------------------------

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      add(const CallTicked());
    });
  }

  void _startRingTimer(String callId) {
    _ringTimer?.cancel();
    _ringTimer = Timer(AppConfig.callRingTimeout, () {
      if (isClosed) return;
      add(CallRingTimedOut(callId));
    });
  }

  /// Bounds the `connecting` phase.
  ///
  /// Nothing else does. The ring timer is cancelled the moment either
  /// side leaves `ringing`, and a peer connection that never receives an
  /// offer sits in `new` — it never reaches `failed`, so no connection
  /// state callback ever fires. Without this the callee waits on
  /// "Connecting…" with the camera LED on until they notice, and the
  /// server-side session is stuck too.
  void _startConnectWatchdog(String callId) {
    _connectTimer?.cancel();
    _connectTimer = Timer(AppConfig.callConnectTimeout, () {
      if (isClosed) return;
      add(CallConnectTimedOut(callId));
    });
  }

  void _resetBuffers() {
    _bufferedOffer = null;
    _peerAccepted = false;
    _bufferedCandidates.clear();
  }

  /// Clears per-call state at the start of a new call.
  ///
  /// Separate from [_resetBuffers] because that one also runs *inside*
  /// `_finish`, where clearing the latch would defeat it.
  void _resetForNewCall() {
    _resetBuffers();
    _finishing = false;
  }

  /// A UUID-shaped id. Uniqueness is all that matters — it becomes the
  /// signalling room name and the server rejects a collision.
  String _newCallId() {
    String hex(int bytes) => List<String>.generate(
          bytes,
          (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    return '${hex(4)}-${hex(2)}-${hex(2)}-${hex(2)}-${hex(6)}';
  }
}
