part of 'call_bloc.dart';

sealed class CallEvent extends Equatable {
  const CallEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

// ---------------------------------------------------------------------------
// Local intent
// ---------------------------------------------------------------------------

/// Start an outgoing call.
class CallDialRequested extends CallEvent {
  const CallDialRequested({
    required this.conversationId,
    required this.peer,
    required this.withVideo,
  });

  final String conversationId;
  final CallPeer peer;
  final bool withVideo;

  @override
  List<Object?> get props => <Object?>[conversationId, peer, withVideo];
}

/// Answer the call currently ringing.
class CallAcceptRequested extends CallEvent {
  const CallAcceptRequested();
}

/// Decline the call currently ringing.
class CallDeclineRequested extends CallEvent {
  const CallDeclineRequested();
}

/// Hang up, whatever phase we are in.
class CallHangUpRequested extends CallEvent {
  const CallHangUpRequested();
}

/// Clears a finished call so the UI can close and the next one can start.
class CallDismissed extends CallEvent {
  const CallDismissed();
}

// ---------------------------------------------------------------------------
// In-call controls
// ---------------------------------------------------------------------------

class CallMicToggled extends CallEvent {
  const CallMicToggled();
}

class CallCameraToggled extends CallEvent {
  const CallCameraToggled();
}

class CallSpeakerToggled extends CallEvent {
  const CallSpeakerToggled();
}

class CallCameraSwitched extends CallEvent {
  const CallCameraSwitched();
}

// ---------------------------------------------------------------------------
// From the socket
// ---------------------------------------------------------------------------

class CallInviteReceived extends CallEvent {
  const CallInviteReceived(this.call);
  final IncomingCall call;

  @override
  List<Object?> get props => <Object?>[call];
}

/// They picked up — time to send the offer.
class CallAcceptedByPeer extends CallEvent {
  const CallAcceptedByPeer(this.callId);
  final String callId;

  @override
  List<Object?> get props => <Object?>[callId];
}

/// The far end finished the call, one way or another.
class CallTerminatedRemotely extends CallEvent {
  const CallTerminatedRemotely({required this.callId, required this.reason});

  final String callId;
  final CallEndReason reason;

  @override
  List<Object?> get props => <Object?>[callId, reason];
}

class CallOfferReceived extends CallEvent {
  const CallOfferReceived({required this.callId, required this.sdp});

  final String callId;
  final Map<String, dynamic> sdp;

  @override
  List<Object?> get props => <Object?>[callId, sdp];
}

class CallAnswerReceived extends CallEvent {
  const CallAnswerReceived({required this.callId, required this.sdp});

  final String callId;
  final Map<String, dynamic> sdp;

  @override
  List<Object?> get props => <Object?>[callId, sdp];
}

class CallIceCandidateReceived extends CallEvent {
  const CallIceCandidateReceived({
    required this.callId,
    required this.candidate,
  });

  final String callId;
  final Map<String, dynamic> candidate;

  @override
  List<Object?> get props => <Object?>[callId, candidate];
}

// ---------------------------------------------------------------------------
// Internal
// ---------------------------------------------------------------------------

/// WebRTC reported a change in the underlying peer connection.
class CallConnectionStateChanged extends CallEvent {
  const CallConnectionStateChanged(this.state);
  final RTCPeerConnectionState state;

  @override
  List<Object?> get props => <Object?>[state];
}

/// Remote media attached — swap the placeholder for the video view.
class CallRemoteStreamArrived extends CallEvent {
  const CallRemoteStreamArrived();
}

/// One-second tick, for the in-call duration readout.
class CallTicked extends CallEvent {
  const CallTicked();
}

/// Nobody answered within the ring timeout.
class CallRingTimedOut extends CallEvent {
  const CallRingTimedOut(this.callId);
  final String callId;

  @override
  List<Object?> get props => <Object?>[callId];
}

/// Answered, but media never came up. Bounds the "Connecting…" phase,
/// which nothing else does — see `CallBloc._startConnectWatchdog`.
class CallConnectTimedOut extends CallEvent {
  const CallConnectTimedOut(this.callId);
  final String callId;

  @override
  List<Object?> get props => <Object?>[callId];
}
