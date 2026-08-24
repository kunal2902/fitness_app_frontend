part of 'call_bloc.dart';

class CallState extends Equatable {
  const CallState({
    this.phase = CallPhase.idle,
    this.callId,
    this.conversationId,
    this.peer,
    this.withVideo = true,
    this.isOutgoing = false,
    this.isMicEnabled = true,
    this.isCameraEnabled = true,
    this.isSpeakerOn = true,
    this.isFrontCamera = true,
    this.hasRemoteVideo = false,
    this.elapsed = Duration.zero,
    this.endReason,
    this.errorMessage,
    this.turnAvailable = true,
  });

  final CallPhase phase;
  final String? callId;
  final String? conversationId;
  final CallPeer? peer;

  /// Whether this call started as video. A video call can continue with
  /// the camera off; a voice call can never turn video on mid-call
  /// (that would need renegotiation).
  final bool withVideo;
  final bool isOutgoing;

  final bool isMicEnabled;
  final bool isCameraEnabled;
  final bool isSpeakerOn;
  final bool isFrontCamera;

  /// True once the far end's track is attached to the remote renderer.
  final bool hasRemoteVideo;

  final Duration elapsed;
  final CallEndReason? endReason;
  final String? errorMessage;

  /// False when the backend has no TURN relay configured — worth warning
  /// about, because the call will fail on a meaningful minority of
  /// networks and the failure looks like a bug in the app.
  final bool turnAvailable;

  bool get isActive => phase != CallPhase.idle && phase != CallPhase.ended;
  bool get isRinging => phase == CallPhase.ringing;
  bool get isDialling => phase == CallPhase.dialling;
  bool get isInCall =>
      phase == CallPhase.connected || phase == CallPhase.reconnecting;
  bool get showsVideo => withVideo && isCameraEnabled;

  /// "0:42" / "1:03:15"
  String get elapsedLabel {
    final int seconds = elapsed.inSeconds;
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int rest = seconds % 60;
    final String mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
    final String ss = rest.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  String get statusLabel => switch (phase) {
        CallPhase.idle => '',
        CallPhase.dialling => 'Calling…',
        CallPhase.ringing => withVideo ? 'Incoming video call' : 'Incoming call',
        CallPhase.connecting => 'Connecting…',
        CallPhase.connected => elapsedLabel,
        CallPhase.reconnecting => 'Reconnecting…',
        CallPhase.ended => endReason?.message ?? 'Call ended',
      };

  CallState copyWith({
    CallPhase? phase,
    String? callId,
    String? conversationId,
    CallPeer? peer,
    bool? withVideo,
    bool? isOutgoing,
    bool? isMicEnabled,
    bool? isCameraEnabled,
    bool? isSpeakerOn,
    bool? isFrontCamera,
    bool? hasRemoteVideo,
    Duration? elapsed,
    CallEndReason? endReason,
    String? errorMessage,
    bool? turnAvailable,
    bool clearError = false,
  }) {
    return CallState(
      phase: phase ?? this.phase,
      callId: callId ?? this.callId,
      conversationId: conversationId ?? this.conversationId,
      peer: peer ?? this.peer,
      withVideo: withVideo ?? this.withVideo,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isMicEnabled: isMicEnabled ?? this.isMicEnabled,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      hasRemoteVideo: hasRemoteVideo ?? this.hasRemoteVideo,
      elapsed: elapsed ?? this.elapsed,
      endReason: endReason ?? this.endReason,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      turnAvailable: turnAvailable ?? this.turnAvailable,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        phase,
        callId,
        conversationId,
        peer,
        withVideo,
        isOutgoing,
        isMicEnabled,
        isCameraEnabled,
        isSpeakerOn,
        isFrontCamera,
        hasRemoteVideo,
        elapsed,
        endReason,
        errorMessage,
        turnAvailable,
      ];
}
