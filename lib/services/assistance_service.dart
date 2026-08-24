import '../config/api_endpoints.dart';
import '../models/call_models.dart';
import '../models/chat_message.dart';
import '../models/professional.dart';
import 'api_client.dart';

/// REST half of the assistance feature.
///
/// The socket carries anything live — new messages, typing, signalling.
/// This carries everything that needs to survive a cold start: the coach
/// list, portfolios, chat history, ICE credentials, device registration.
class AssistanceService {
  AssistanceService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  // -------------------------------------------------------------------------
  // Professionals
  // -------------------------------------------------------------------------

  Future<List<Professional>> listProfessionals() async {
    final Map<String, dynamic> json =
        await _client.get(ApiEndpoints.professionals);
    final Object? raw = json['professionals'];
    if (raw is! List) return <Professional>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Professional.fromJson)
        .toList();
  }

  Future<Professional> getProfessional(String id) async {
    final Map<String, dynamic> json =
        await _client.get(ApiEndpoints.professional(id));
    final Object? raw = json['professional'];
    return Professional.fromJson(
      raw is Map<String, dynamic> ? raw : json,
    );
  }

  /// Opens (or reuses) the thread with this coach. Returns its id.
  Future<String> openConversation(String professionalId) async {
    final Map<String, dynamic> json = await _client.post(
      ApiEndpoints.professionalConversation(professionalId),
    );
    final Object? raw = json['conversation'];
    final Map<String, dynamic> conversation =
        raw is Map<String, dynamic> ? raw : json;
    return (conversation['id'] ?? '').toString();
  }

  // -------------------------------------------------------------------------
  // Chat
  // -------------------------------------------------------------------------

  Future<List<ConversationSummary>> listConversations() async {
    final Map<String, dynamic> json =
        await _client.get(ApiEndpoints.conversations);
    final Object? raw = json['conversations'];
    if (raw is! List) return <ConversationSummary>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ConversationSummary.fromJson)
        .toList();
  }

  /// A page of history, oldest-first.
  ///
  /// [before] is the `createdAt` of the oldest message already held — a
  /// timestamp cursor rather than an offset, so messages arriving at the
  /// live end cannot shift the page and duplicate rows.
  Future<({List<ChatMessage> messages, bool hasMore})> history({
    required String conversationId,
    int? limit,
    DateTime? before,
  }) async {
    final Map<String, dynamic> json = await _client.get(
      ApiEndpoints.conversationMessages(conversationId),
      query: <String, dynamic>{
        if (limit != null) 'limit': limit,
        if (before != null) 'before': before.toIso8601String(),
      },
    );

    final Object? raw = json['messages'];
    final List<ChatMessage> messages = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList()
        : <ChatMessage>[];

    return (messages: messages, hasMore: json['hasMore'] as bool? ?? false);
  }

  /// HTTP fallback for sending, used when the socket is down.
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String body,
    required String clientId,
  }) async {
    final Map<String, dynamic> json = await _client.post(
      ApiEndpoints.conversationMessages(conversationId),
      body: <String, dynamic>{'body': body, 'clientId': clientId},
    );
    final Object? raw = json['message'];
    return ChatMessage.fromJson(
      raw is Map<String, dynamic> ? raw : json,
    );
  }

  Future<void> markRead({
    required String conversationId,
    required String messageId,
  }) async {
    await _client.post(
      ApiEndpoints.conversationRead(conversationId),
      body: <String, dynamic>{'messageId': messageId},
    );
  }

  // -------------------------------------------------------------------------
  // Calls
  // -------------------------------------------------------------------------

  /// Fetched immediately before dialling — TURN credentials are
  /// short-lived, so caching them at login would hand out expired ones.
  Future<IceServersConfig> fetchIceServers() async {
    final Map<String, dynamic> json =
        await _client.get(ApiEndpoints.iceServers);
    return IceServersConfig.fromJson(json);
  }

  /// Best-effort cleanup when the socket died mid-call.
  /// Ends a call over HTTP.
  ///
  /// The fallback for when the socket is down — which is exactly when a
  /// call most needs ending, because nothing else will tell the other
  /// side to stop ringing, and while the session is live both people are
  /// reported "on another call" to everyone.
  Future<void> endCall(String callId, {String? reason}) async {
    await _client.post(
      ApiEndpoints.endCall(callId),
      body: reason == null ? null : <String, dynamic>{'reason': reason},
    );
  }

  // -------------------------------------------------------------------------
  // Devices
  // -------------------------------------------------------------------------

  Future<void> registerDevice({
    required String token,
    required String platform,
    required String kind,
    String? deviceId,
    String? appVersion,
  }) async {
    await _client.post(
      ApiEndpoints.devices,
      body: <String, dynamic>{
        'token': token,
        'platform': platform,
        'kind': kind,
        if (deviceId != null) 'deviceId': deviceId,
        if (appVersion != null) 'appVersion': appVersion,
      },
    );
  }

  Future<void> unregisterDevice(String token) async {
    await _client.delete(ApiEndpoints.device(token));
  }
}
