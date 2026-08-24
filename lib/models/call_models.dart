import 'package:equatable/equatable.dart';

/// Where a call is in its lifecycle, from this device's point of view.
enum CallPhase {
  /// No call.
  idle,

  /// We dialled; waiting for them to pick up.
  dialling,

  /// They dialled; we have not answered yet.
  ringing,

  /// Answered — negotiating media.
  connecting,

  /// Media flowing.
  connected,

  /// Media dropped but WebRTC is retrying.
  reconnecting,

  /// Over.
  ended,
}

/// Why a call finished — drives the message shown on the way out.
enum CallEndReason {
  completed,
  declined,
  cancelled,
  missed,
  busy,
  failed,
  answeredElsewhere,
}

extension CallEndReasonX on CallEndReason {
  String get message => switch (this) {
        CallEndReason.completed => 'Call ended',
        CallEndReason.declined => 'Call declined',
        CallEndReason.cancelled => 'Call cancelled',
        CallEndReason.missed => 'No answer',
        CallEndReason.busy => 'They are on another call',
        CallEndReason.failed => 'Could not connect',
        CallEndReason.answeredElsewhere => 'Answered on another device',
      };
}

/// The other end of a call.
class CallPeer extends Equatable {
  const CallPeer({
    required this.userId,
    required this.name,
    this.avatarUrl,
  });

  final String userId;
  final String name;
  final String? avatarUrl;

  String get initials {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory CallPeer.fromJson(Map<String, dynamic> json) {
    return CallPeer(
      userId: (json['id'] ?? json['userId'] ?? '').toString(),
      name: (json['name'] ?? json['displayName'] ?? 'Unknown') as String,
      avatarUrl: (json['avatarUrl'] as String?)?.isEmpty ?? true
          ? null
          : json['avatarUrl'] as String?,
    );
  }

  @override
  List<Object?> get props => <Object?>[userId, name, avatarUrl];
}

/// An invitation that arrived while we were not on a call.
class IncomingCall extends Equatable {
  const IncomingCall({
    required this.callId,
    required this.conversationId,
    required this.peer,
    required this.withVideo,
    this.receivedAt,
  });

  final String callId;
  final String conversationId;
  final CallPeer peer;
  final bool withVideo;
  final DateTime? receivedAt;

  factory IncomingCall.fromJson(Map<String, dynamic> json) {
    final Object? caller = json['caller'];
    return IncomingCall(
      callId: (json['callId'] ?? '').toString(),
      conversationId: (json['conversationId'] ?? '').toString(),
      peer: CallPeer.fromJson(
        caller is Map<String, dynamic> ? caller : const <String, dynamic>{},
      ),
      withVideo: json['withVideo'] as bool? ?? true,
      receivedAt: DateTime.now(),
    );
  }

  /// Built from an FCM data payload, where every value arrives as a string.
  factory IncomingCall.fromPushData(Map<String, dynamic> data) {
    return IncomingCall(
      callId: (data['callId'] ?? '').toString(),
      conversationId: (data['conversationId'] ?? '').toString(),
      peer: CallPeer(
        userId: (data['callerId'] ?? '').toString(),
        name: (data['callerName'] ?? 'Incoming call').toString(),
        avatarUrl: (data['callerAvatarUrl'] ?? '').toString().isEmpty
            ? null
            : data['callerAvatarUrl'].toString(),
      ),
      withVideo: '${data['withVideo']}' != 'false',
      receivedAt: DateTime.now(),
    );
  }

  @override
  List<Object?> get props => <Object?>[callId, conversationId, peer, withVideo];
}

/// STUN/TURN configuration, exactly as `RTCPeerConnection` expects it.
class IceServersConfig extends Equatable {
  const IceServersConfig({
    required this.servers,
    required this.turnAvailable,
  });

  final List<Map<String, dynamic>> servers;

  /// False when the backend has no TURN configured. Calls will still work
  /// on most home networks but fail behind symmetric NAT, so it is worth
  /// warning about rather than presenting as a mystery failure.
  final bool turnAvailable;

  static const IceServersConfig fallback = IceServersConfig(
    servers: <Map<String, dynamic>>[
      <String, dynamic>{
        'urls': <String>[
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ],
    turnAvailable: false,
  );

  Map<String, dynamic> toRtcConfiguration() => <String, dynamic>{
        'iceServers': servers,
        // Trickle ICE: send candidates as they are gathered instead of
        // waiting for the full set. Typically halves time-to-connect.
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize': 2,
      };

  factory IceServersConfig.fromJson(Map<String, dynamic> json) {
    final Object? raw = json['iceServers'];
    if (raw is! List) return fallback;

    // whereType<Map<String, dynamic>> is not safe here. Socket.IO decodes
    // nested JSON objects on Android as `_InternalLinkedHashMap<dynamic,
    // dynamic>`, which that filter silently DROPS — leaving an empty list,
    // the STUN-only fallback, and calls that fail behind symmetric NAT on
    // exactly the network TURN was configured for. Normalise instead of
    // filtering: a dropped ICE server is invisible until someone is on
    // mobile data.
    final List<Map<String, dynamic>> parsed = raw
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .where((Map<String, dynamic> server) => server['urls'] != null)
        .map((Map<String, dynamic> server) {
      final Object? urls = server['urls'];
      return <String, dynamic>{
        'urls': urls is List
            ? urls.map((Object? u) => u.toString()).toList()
            : <String>[urls.toString()],
        if (server['username'] != null)
          'username': server['username'].toString(),
        if (server['credential'] != null)
          'credential': server['credential'].toString(),
      };
    }).toList();

    if (parsed.isEmpty) return fallback;

    return IceServersConfig(
      servers: parsed,
      // The server sends a real bool, but a proxy or a re-encode can turn
      // it into "true". A wrong value here only changes which error
      // message the user sees, so coerce rather than fail.
      turnAvailable: json['turnAvailable'] == true ||
          json['turnAvailable'].toString() == 'true',
    );
  }

  @override
  List<Object?> get props => <Object?>[servers, turnAvailable];
}
