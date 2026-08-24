import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../config/app_config.dart';
import '../../config/socket_events.dart';
import '../../models/api_exception.dart';
import '../../models/chat_message.dart';
import '../../services/assistance_service.dart';
import '../../services/socket_service.dart';
import '../../store/app_store.dart';

part 'chat_event.dart';
part 'chat_state.dart';

/// One conversation thread.
///
/// Sending is optimistic: the bubble appears instantly and only its status
/// tick changes once the server confirms. Every send carries a
/// client-generated id, which the server treats as an idempotency key — so
/// a retry after a dropped socket can never post the message twice.
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc({
    AssistanceService? service,
    SocketService? socket,
    AppStore? store,
  })  : _service = service ?? AssistanceService(),
        _socket = socket ?? SocketService.instance,
        _store = store ?? AppStore.instance,
        super(const ChatState()) {
    on<ChatOpened>(_onOpened);
    on<ChatHistoryRequested>(_onHistoryRequested);
    on<ChatMessageSent>(_onMessageSent);
    on<ChatMessageReceived>(_onMessageReceived);
    on<ChatMessageRetried>(_onMessageRetried);
    on<ChatComposerChanged>(_onComposerChanged);
    on<ChatPeerTypingChanged>(_onPeerTypingChanged);
    on<ChatReadReceiptReceived>(_onReadReceipt);
    on<ChatMarkedRead>(_onMarkedRead);
    on<ChatReconnected>(_onReconnected);
    on<ChatRefreshRequested>(_onRefreshRequested);
    on<ChatOpenRetried>(_onOpenRetried);

    _watchConnection();
  }

  final AssistanceService _service;
  final SocketService _socket;
  final AppStore _store;

  final math.Random _random = math.Random();

  void Function(dynamic)? _messageHandler;
  void Function(dynamic)? _typingHandler;
  void Function(dynamic)? _readHandler;

  void Function(dynamic)? _deliveredHandler;
  StreamSubscription<SocketStatus>? _statusSub;

  Timer? _typingExpiry;
  DateTime? _lastTypingEmit;

  /// The last open request, replayed by [ChatOpenRetried].
  ChatOpened? _lastOpen;

  Timer? _joinRetry;
  int _joinAttempts = 0;
  static const int _maxJoinAttempts = 3;

  /// Rejoins the conversation room whenever the socket comes back.
  ///
  /// Room membership lives on the server *per connection*. The handlers
  /// survive a reconnect but the membership does not, so without this the
  /// thread goes permanently silent after the first network switch — with
  /// no error anywhere.
  void _watchConnection() {
    _statusSub = _socket.statusStream.listen((SocketStatus status) {
      if (status != SocketStatus.connected) return;
      if (isClosed) return;
      add(const ChatReconnected());
    });
  }

  String? get _selfId => _store.user?.id;

  // -------------------------------------------------------------------------

  @override
  Future<void> close() {
    _typingExpiry?.cancel();
    _joinRetry?.cancel();
    unawaited(_statusSub?.cancel());
    _detachListeners();
    final String? id = state.conversationId;
    if (id != null) {
      _socket.emit(SocketEvents.chatLeave, <String, dynamic>{
        'conversationId': id,
      });
    }
    return super.close();
  }

  void _detachListeners() {
    if (_messageHandler != null) {
      _socket.off(SocketEvents.chatMessage, _messageHandler);
    }
    if (_typingHandler != null) {
      _socket.off(SocketEvents.chatTyping, _typingHandler);
    }
    if (_readHandler != null) {
      _socket.off(SocketEvents.chatRead, _readHandler);
    }
    if (_deliveredHandler != null) {
      _socket.off(SocketEvents.chatDelivered, _deliveredHandler);
    }
  }

  void _attachListeners() {
    _detachListeners();

    _messageHandler = _socket.on(SocketEvents.chatMessage, (dynamic data) {
      final ChatMessage message = ChatMessage.fromJson(socketPayload(data));
      if (message.conversationId != state.conversationId) return;
      add(ChatMessageReceived(message));
    });

    _typingHandler = _socket.on(SocketEvents.chatTyping, (dynamic data) {
      final Map<String, dynamic> payload = socketPayload(data);
      if ((payload['conversationId'] ?? '') != state.conversationId) return;
      if ((payload['userId'] ?? '') == _selfId) return;
      add(ChatPeerTypingChanged(payload['isTyping'] as bool? ?? false));
    });

    // The server sends chat:delivered to the recipient's *user* room, and
    // uses it with `refresh: true` to announce a call entry written into
    // the thread after a call ends. Without this listener the "Video call
    // · 3m 12s" row never appears until the screen is reopened.
    _deliveredHandler = _socket.on(SocketEvents.chatDelivered, (dynamic data) {
      final Map<String, dynamic> payload = socketPayload(data);
      if ((payload['conversationId'] ?? '') != state.conversationId) return;

      if (payload['refresh'] == true) {
        add(const ChatRefreshRequested());
        return;
      }
      final Object? raw = payload['message'];
      if (raw == null) return;
      add(ChatMessageReceived(ChatMessage.fromJson(socketPayload(raw))));
    });

    _readHandler = _socket.on(SocketEvents.chatRead, (dynamic data) {
      final Map<String, dynamic> payload = socketPayload(data);
      if ((payload['conversationId'] ?? '') != state.conversationId) return;
      final String userId = (payload['userId'] ?? '').toString();
      if (userId == _selfId) return;
      add(ChatReadReceiptReceived(userId));
    });
  }

  // -------------------------------------------------------------------------
  // Opening
  // -------------------------------------------------------------------------

  Future<void> _onOpened(ChatOpened event, Emitter<ChatState> emit) async {
    // Remembered so the error state can offer a retry. Without it a
    // failure here is terminal: conversationId stays null, so the
    // composer is disabled and the thread renders as "no messages yet" —
    // a dead screen whose only escape is backing out and returning.
    _lastOpen = event;
    emit(state.copyWith(isLoadingHistory: true, clearError: true));

    try {
      // Resolve the thread first: the caller usually only knows which
      // coach they tapped, not which conversation that maps to.
      final String conversationId = event.conversationId ??
          await _service.openConversation(event.professionalId!);

      emit(state.copyWith(conversationId: conversationId));
      _attachListeners();

      // Join the room before loading history, so a message that lands
      // mid-fetch is delivered rather than missed in the gap.
      await _ensureJoined(conversationId);

      final ({List<ChatMessage> messages, bool hasMore}) page =
          await _service.history(
        conversationId: conversationId,
        limit: AppConfig.chatPageSize,
      );

      emit(
        state.copyWith(
          messages: page.messages,
          hasMore: page.hasMore,
          isLoadingHistory: false,
        ),
      );

      add(const ChatMarkedRead());
    } on ApiException catch (e) {
      emit(state.copyWith(isLoadingHistory: false, errorMessage: e.message));
    } catch (_) {
      emit(
        state.copyWith(
          isLoadingHistory: false,
          errorMessage: 'Could not open this conversation.',
        ),
      );
    }
  }

  Future<void> _onHistoryRequested(
    ChatHistoryRequested event,
    Emitter<ChatState> emit,
  ) async {
    final String? conversationId = state.conversationId;
    if (conversationId == null || state.isLoadingMore || !state.hasMore) return;
    if (state.messages.isEmpty) return;

    emit(state.copyWith(isLoadingMore: true));

    try {
      final ({List<ChatMessage> messages, bool hasMore}) page =
          await _service.history(
        conversationId: conversationId,
        limit: AppConfig.chatPageSize,
        before: state.messages.first.createdAt,
      );

      emit(
        state.copyWith(
          messages: <ChatMessage>[...page.messages, ...state.messages],
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isLoadingMore: false,
          errorMessage: 'Could not load older messages.',
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Sending
  // -------------------------------------------------------------------------

  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<ChatState> emit,
  ) async {
    final String? conversationId = state.conversationId;
    final String? selfId = _selfId;
    final String body = event.body.trim();
    if (conversationId == null || selfId == null || body.isEmpty) return;

    final String clientId = _newClientId();
    final ChatMessage pending = ChatMessage.pending(
      conversationId: conversationId,
      senderId: selfId,
      body: body,
      clientId: clientId,
    );

    emit(
      state.copyWith(
        messages: <ChatMessage>[...state.messages, pending],
        isSending: true,
      ),
    );

    // Stop the "typing" indicator immediately — they just sent.
    _emitTyping(conversationId, isTyping: false, force: true);

    await _deliver(emit, conversationId, clientId, body);
  }

  Future<void> _onMessageRetried(
    ChatMessageRetried event,
    Emitter<ChatState> emit,
  ) async {
    final String? conversationId = state.conversationId;
    if (conversationId == null) return;

    final int index = state.messages.indexWhere(
      (ChatMessage m) => m.clientId == event.clientId,
    );
    if (index == -1) return;

    final ChatMessage message = state.messages[index];
    emit(
      state.copyWith(
        messages: _replaceAt(
          state.messages,
          index,
          message.copyWith(delivery: MessageDelivery.sending),
        ),
      ),
    );

    await _deliver(emit, conversationId, event.clientId, message.body);
  }

  Future<void> _deliver(
    Emitter<ChatState> emit,
    String conversationId,
    String clientId,
    String body,
  ) async {
    try {
      Map<String, dynamic> response;

      if (_socket.isConnected) {
        response = await _socket.request(
          SocketEvents.chatSend,
          data: <String, dynamic>{
            'conversationId': conversationId,
            'body': body,
            'clientId': clientId,
          },
        );
      } else {
        // Socket down — fall back to HTTP. Same clientId, so the server
        // deduplicates if the socket send actually got through first.
        final ChatMessage saved = await _service.sendMessage(
          conversationId: conversationId,
          body: body,
          clientId: clientId,
        );
        response = <String, dynamic>{
          'ok': true,
          'message': <String, dynamic>{
            'id': saved.id,
            'conversationId': saved.conversationId,
            'senderId': saved.senderId,
            'body': saved.body,
            'createdAt': saved.createdAt.toIso8601String(),
            'clientId': saved.clientId,
          },
        };
      }

      if (response['ok'] == true) {
        final ChatMessage confirmed =
            ChatMessage.fromJson(socketPayload(response['message']));
        emit(
          state.copyWith(
            messages: _reconcile(state.messages, confirmed),
            isSending: false,
          ),
        );
      } else {
        emit(
          state.copyWith(
            messages: _markDelivery(
              state.messages,
              clientId,
              MessageDelivery.failed,
            ),
            isSending: false,
            errorMessage: (response['message'] ?? 'Message not sent').toString(),
          ),
        );
      }
    } catch (_) {
      emit(
        state.copyWith(
          messages:
              _markDelivery(state.messages, clientId, MessageDelivery.failed),
          isSending: false,
          errorMessage: 'Message not sent. Tap to retry.',
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Receiving
  // -------------------------------------------------------------------------

  void _onMessageReceived(
    ChatMessageReceived event,
    Emitter<ChatState> emit,
  ) {
    emit(
      state.copyWith(
        messages: _reconcile(state.messages, event.message),
        isPeerTyping: event.message.senderId == _selfId
            ? state.isPeerTyping
            // A message arriving means they finished typing.
            : false,
      ),
    );

    if (event.message.senderId != _selfId) {
      add(const ChatMarkedRead());
    }
  }

  void _onPeerTypingChanged(
    ChatPeerTypingChanged event,
    Emitter<ChatState> emit,
  ) {
    emit(state.copyWith(isPeerTyping: event.isTyping));

    _typingExpiry?.cancel();
    if (!event.isTyping) return;

    // Expire locally. A "typing…" left behind by a dropped socket would
    // otherwise sit there forever.
    _typingExpiry = Timer(AppConfig.typingIndicatorTimeout, () {
      if (isClosed) return;
      add(const ChatPeerTypingChanged(false));
    });
  }

  void _onComposerChanged(
    ChatComposerChanged event,
    Emitter<ChatState> emit,
  ) {
    final String? conversationId = state.conversationId;
    if (conversationId == null) return;
    _emitTyping(conversationId, isTyping: event.text.trim().isNotEmpty);
  }

  void _onReadReceipt(
    ChatReadReceiptReceived event,
    Emitter<ChatState> emit,
  ) {
    // Everything we sent is now read by them.
    emit(
      state.copyWith(
        messages: state.messages.map((ChatMessage m) {
          if (m.senderId != _selfId) return m;
          if (m.readBy.contains(event.userId)) return m;
          return m.copyWith(
            readBy: <String>[...m.readBy, event.userId],
          );
        }).toList(),
      ),
    );
  }

  Future<void> _onMarkedRead(
    ChatMarkedRead event,
    Emitter<ChatState> emit,
  ) async {
    final String? conversationId = state.conversationId;
    if (conversationId == null || state.messages.isEmpty) return;

    final ChatMessage newest = state.messages.last;
    if (newest.id.startsWith('pending:')) return;

    if (_socket.isConnected) {
      _socket.emit(SocketEvents.chatRead, <String, dynamic>{
        'conversationId': conversationId,
        'messageId': newest.id,
      });
      return;
    }

    // Socket down: emit() would drop this silently and the unread badge
    // would never clear.
    try {
      await _service.markRead(
        conversationId: conversationId,
        messageId: newest.id,
      );
    } catch (_) {
      // Best effort — it will clear on the next successful read.
    }
  }

  /// Re-joins after a reconnect and pulls anything missed while away.
  Future<void> _onReconnected(
    ChatReconnected event,
    Emitter<ChatState> emit,
  ) async {
    final String? conversationId = state.conversationId;
    if (conversationId == null) return;

    if (!await _ensureJoined(conversationId)) return;

    // Messages sent while we were offline were never delivered to us, so
    // rejoining alone is not enough — the tail has to be re-fetched.
    add(const ChatRefreshRequested());
  }

  /// Joins the conversation room, retrying a failure a few times.
  ///
  /// A failed join is invisible: the thread renders perfectly and simply
  /// never receives another live message. The reconnect listener covers
  /// the case where the socket dropped, but not this one — a join
  /// rejected or timed out on a *live* socket produces no further status
  /// transition to hang a retry off, so it would never be retried at all.
  Future<bool> _ensureJoined(String conversationId) async {
    _joinRetry?.cancel();

    final Map<String, dynamic> ack = await _socket.request(
      SocketEvents.chatJoin,
      data: <String, dynamic>{'conversationId': conversationId},
    );

    if (ack['ok'] == true) {
      _joinAttempts = 0;
      return true;
    }

    // Offline is not worth retrying on a timer — the reconnect listener
    // will re-join the moment the socket is back.
    if ((ack['code'] ?? '') == 'OFFLINE') return false;

    if (_joinAttempts >= _maxJoinAttempts) {
      developer.log(
        'chat:join failed (${ack['code']}) — giving up until reconnect',
        name: 'chat',
      );
      return false;
    }

    final int attempt = ++_joinAttempts;
    developer.log(
      'chat:join failed (${ack['code']}) — retry $attempt',
      name: 'chat',
    );
    _joinRetry = Timer(Duration(seconds: attempt * 3), () {
      if (isClosed) return;
      if (state.conversationId != conversationId) return;
      add(const ChatReconnected());
    });
    return false;
  }

  /// The user asked to try opening the thread again.
  Future<void> _onOpenRetried(
    ChatOpenRetried event,
    Emitter<ChatState> emit,
  ) async {
    final ChatOpened? last = _lastOpen;
    if (last == null) return;
    await _onOpened(last, emit);
  }

  Future<void> _onRefreshRequested(
    ChatRefreshRequested event,
    Emitter<ChatState> emit,
  ) async {
    final String? conversationId = state.conversationId;
    if (conversationId == null) return;

    try {
      final ({List<ChatMessage> messages, bool hasMore}) page =
          await _service.history(
        conversationId: conversationId,
        limit: AppConfig.chatPageSize,
      );

      // Merge into everything already on screen.
      //
      // Not `where(delivery != sent)` — that keeps only the in-flight
      // bubbles and throws away every confirmed message, so a thread the
      // user had scrolled back through would silently collapse to the
      // newest page. `_reconcile` matches on clientId then id, so
      // re-merging messages we already hold is a no-op.
      // Copied: _reconcile returns a new list, but an empty page skips the
      // loop entirely and the sort below would then mutate the list held
      // by the emitted state in place.
      List<ChatMessage> merged = List<ChatMessage>.of(state.messages);
      for (final ChatMessage message in page.messages) {
        merged = _reconcile(merged, message);
      }
      merged.sort(
        (ChatMessage a, ChatMessage b) => a.createdAt.compareTo(b.createdAt),
      );

      // hasMore describes what is above the OLDEST message we hold, and
      // this page only covers the newest. Keeping paged-in history means
      // there is still more above it, whatever this page says.
      final bool hasMore = merged.length > page.messages.length
          ? state.hasMore
          : page.hasMore;

      emit(state.copyWith(messages: merged, hasMore: hasMore));
    } catch (_) {
      // A failed refresh is not worth surfacing — the thread still shows
      // everything it had.
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Throttled so a fast typist does not emit on every keystroke.
  void _emitTyping(
    String conversationId, {
    required bool isTyping,
    bool force = false,
  }) {
    final DateTime now = DateTime.now();
    if (!force && isTyping && _lastTypingEmit != null) {
      if (now.difference(_lastTypingEmit!) < AppConfig.typingThrottle) return;
    }
    _lastTypingEmit = isTyping ? now : null;

    _socket.emit(SocketEvents.chatTyping, <String, dynamic>{
      'conversationId': conversationId,
      'isTyping': isTyping,
    });
  }

  String _newClientId() {
    final int stamp = DateTime.now().microsecondsSinceEpoch;
    final int salt = _random.nextInt(0xFFFFFF);
    return '$stamp-${salt.toRadixString(16)}';
  }

  /// Inserts [incoming], replacing the optimistic bubble it confirms.
  ///
  /// Matching is by `clientId` first (our own send coming back), then by
  /// `id` (the same message arriving twice, which happens when the socket
  /// broadcast races the ack).
  static List<ChatMessage> _reconcile(
    List<ChatMessage> messages,
    ChatMessage incoming,
  ) {
    final int byClientId = incoming.clientId == null
        ? -1
        : messages.indexWhere(
            (ChatMessage m) => m.clientId == incoming.clientId,
          );
    if (byClientId != -1) {
      return _replaceAt(messages, byClientId, incoming);
    }

    final int byId = messages.indexWhere((ChatMessage m) => m.id == incoming.id);
    if (byId != -1) {
      return _replaceAt(messages, byId, incoming);
    }

    // Keep the list ordered oldest-first even if events arrive late.
    final List<ChatMessage> next = <ChatMessage>[...messages, incoming];
    next.sort(
      (ChatMessage a, ChatMessage b) => a.createdAt.compareTo(b.createdAt),
    );
    return next;
  }

  static List<ChatMessage> _replaceAt(
    List<ChatMessage> messages,
    int index,
    ChatMessage replacement,
  ) {
    final List<ChatMessage> next = List<ChatMessage>.from(messages);
    next[index] = replacement;
    return next;
  }

  static List<ChatMessage> _markDelivery(
    List<ChatMessage> messages,
    String clientId,
    MessageDelivery delivery,
  ) {
    return messages
        .map(
          (ChatMessage m) =>
              m.clientId == clientId ? m.copyWith(delivery: delivery) : m,
        )
        .toList();
  }
}
