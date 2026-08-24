import 'package:equatable/equatable.dart';

/// Mirrors `MESSAGE_KINDS` on the backend.
enum MessageKind {
  text('text'),
  system('system'),
  call('call');

  const MessageKind(this.apiValue);
  final String apiValue;

  static MessageKind fromApi(String? raw) {
    for (final MessageKind k in MessageKind.values) {
      if (k.apiValue == raw) return k;
    }
    return MessageKind.text;
  }
}

enum CallOutcome {
  completed('completed'),
  missed('missed'),
  declined('declined'),
  cancelled('cancelled'),
  failed('failed');

  const CallOutcome(this.apiValue);
  final String apiValue;

  static CallOutcome? fromApi(String? raw) {
    if (raw == null) return null;
    for (final CallOutcome o in CallOutcome.values) {
      if (o.apiValue == raw) return o;
    }
    return null;
  }
}

/// How far along a message is on its way to the server.
///
/// A bubble appears the instant you hit send — [sending] — and only its
/// status ticks change afterwards. Waiting for the round trip before
/// showing anything makes a chat feel broken on a slow connection.
enum MessageDelivery { sending, sent, failed }

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.kind = MessageKind.text,
    this.clientId,
    this.callId,
    this.callOutcome,
    this.callDurationSeconds,
    this.callWithVideo,
    this.readBy = const <String>[],
    this.delivery = MessageDelivery.sent,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final MessageKind kind;

  /// Locally generated id, echoed by the server. Used to reconcile the
  /// optimistic bubble with the persisted row instead of duplicating it.
  final String? clientId;

  final String? callId;
  final CallOutcome? callOutcome;
  final int? callDurationSeconds;
  final bool? callWithVideo;

  final List<String> readBy;
  final MessageDelivery delivery;

  bool isMine(String? userId) => userId != null && senderId == userId;

  bool isReadBy(String userId) => readBy.contains(userId);

  bool get isCallEntry => kind == MessageKind.call;

  /// Optimistic bubble for a message that has not reached the server yet.
  factory ChatMessage.pending({
    required String conversationId,
    required String senderId,
    required String body,
    required String clientId,
  }) {
    return ChatMessage(
      // Temporary id; replaced when the server's copy lands.
      id: 'pending:$clientId',
      conversationId: conversationId,
      senderId: senderId,
      body: body,
      createdAt: DateTime.now(),
      clientId: clientId,
      readBy: <String>[senderId],
      delivery: MessageDelivery.sending,
    );
  }

  ChatMessage copyWith({
    MessageDelivery? delivery,
    List<String>? readBy,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      body: body,
      createdAt: createdAt,
      kind: kind,
      clientId: clientId,
      callId: callId,
      callOutcome: callOutcome,
      callDurationSeconds: callDurationSeconds,
      callWithVideo: callWithVideo,
      readBy: readBy ?? this.readBy,
      delivery: delivery ?? this.delivery,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final Object? rawRead = json['readBy'];
    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      conversationId: (json['conversationId'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      body: (json['body'] ?? '') as String,
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
              DateTime.now(),
      kind: MessageKind.fromApi(json['kind'] as String?),
      clientId: json['clientId'] as String?,
      callId: json['callId'] as String?,
      callOutcome: CallOutcome.fromApi(json['callOutcome'] as String?),
      callDurationSeconds: (json['callDurationSeconds'] as num?)?.toInt(),
      callWithVideo: json['callWithVideo'] as bool?,
      readBy: rawRead is List
          ? rawRead.map((Object? e) => e.toString()).toList()
          : const <String>[],
    );
  }

  @override
  List<Object?> get props => <Object?>[id, clientId, delivery, readBy, body];
}

/// A thread in the conversations list.
class ConversationSummary extends Equatable {
  const ConversationSummary({
    required this.id,
    required this.otherPartyId,
    required this.otherPartyName,
    this.otherPartyAvatarUrl,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String id;
  final String otherPartyId;
  final String otherPartyName;
  final String? otherPartyAvatarUrl;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final Object? other = json['otherParty'];
    final Map<String, dynamic> party =
        other is Map<String, dynamic> ? other : const <String, dynamic>{};

    return ConversationSummary(
      id: (json['id'] ?? '').toString(),
      otherPartyId: (party['id'] ?? '').toString(),
      otherPartyName: (party['displayName'] ?? 'Unknown') as String,
      otherPartyAvatarUrl: party['avatarUrl'] as String?,
      lastMessagePreview: json['lastMessagePreview'] as String?,
      lastMessageAt:
          DateTime.tryParse((json['lastMessageAt'] ?? '').toString()),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[id, lastMessageAt, unreadCount, lastMessagePreview];
}
