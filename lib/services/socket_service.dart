import 'dart:async';
import 'dart:developer' as developer;

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';
import '../config/socket_events.dart';
import 'storage_service.dart';

/// Connection state, surfaced so the UI can show a "reconnecting" banner
/// rather than silently dropping messages.
enum SocketStatus { disconnected, connecting, connected, unauthorized }

/// One authenticated socket for the whole app.
///
/// Chat and WebRTC signalling share it deliberately: two connections would
/// mean two auth paths, two reconnect strategies, and a window where chat
/// is live but a call cannot be answered. One socket, one source of truth
/// about whether we are online.
class SocketService {
  SocketService._();

  static final SocketService instance = SocketService._();

  io.Socket? _socket;
  SocketStatus _status = SocketStatus.disconnected;

  final StreamController<SocketStatus> _statusController =
      StreamController<SocketStatus>.broadcast();

  /// Handlers registered before the socket exists, replayed on connect.
  final Map<String, List<void Function(dynamic)>> _listeners =
      <String, List<void Function(dynamic)>>{};

  SocketStatus get status => _status;
  Stream<SocketStatus> get statusStream => _statusController.stream;
  bool get isConnected => _status == SocketStatus.connected;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Opens the connection. Safe to call repeatedly — a live socket is
  /// reused rather than replaced.
  Future<void> connect() async {
    if (_socket?.connected ?? false) return;

    final String? token = await StorageService.instance.readAccessToken();
    if (token == null || token.isEmpty) {
      _setStatus(SocketStatus.unauthorized);
      return;
    }

    // Tear down any half-open socket before building a new one, or the old
    // one keeps firing handlers into a screen that has moved on.
    _socket?.dispose();

    _setStatus(SocketStatus.connecting);

    final io.Socket socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          // WebSocket only: the HTTP long-poll fallback adds latency that
          // shows up directly as call setup time.
          .setTransports(<String>['websocket'])
          .setAuth(<String, dynamic>{'token': token})
          // No setReconnectionAttempts: the default is infinite. Passing 0
          // means literally zero attempts — the socket would never come
          // back after the first network blip.
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .setTimeout(15000)
          .disableAutoConnect()
          .build(),
    );

    socket.onConnect((_) {
      _setStatus(SocketStatus.connected);
      developer.log('connected', name: 'socket');
    });

    socket.onDisconnect((Object? reason) {
      _setStatus(SocketStatus.disconnected);
      developer.log('disconnected: $reason', name: 'socket');
    });

    socket.onConnectError((Object? error) {
      final String message = error.toString();
      // The server sends exactly "UNAUTHORIZED" for any auth failure.
      // Retrying with the same dead token would loop forever, so stop and
      // let the app refresh the token and call connect() again.
      if (message.contains('UNAUTHORIZED')) {
        _setStatus(SocketStatus.unauthorized);
        socket.disconnect();
      } else {
        _setStatus(SocketStatus.disconnected);
      }
      developer.log('connect error: $message', name: 'socket');
    });

    socket.onError((Object? error) {
      developer.log('error: $error', name: 'socket');
    });

    // Re-attach everything registered while we were disconnected.
    _listeners.forEach((String event, List<void Function(dynamic)> handlers) {
      for (final void Function(dynamic) handler in handlers) {
        socket.on(event, handler);
      }
    });

    _socket = socket;
    socket.connect();
  }

  /// Reconnects with a fresh token — call this after a token refresh.
  Future<void> reauthenticate() async {
    _socket?.dispose();
    _socket = null;
    await connect();
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _setStatus(SocketStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _listeners.clear();
    unawaited(_statusController.close());
  }

  // -------------------------------------------------------------------------
  // Events
  // -------------------------------------------------------------------------

  /// Subscribes to [event]. Survives reconnects.
  ///
  /// Returns the handler so it can be passed back to [off] — an anonymous
  /// closure cannot be removed, and a screen that subscribes on every
  /// build without removing leaks a handler per rebuild.
  void Function(dynamic) on(String event, void Function(dynamic data) handler) {
    _listeners.putIfAbsent(event, () => <void Function(dynamic)>[]).add(handler);
    _socket?.on(event, handler);
    return handler;
  }

  void off(String event, [void Function(dynamic)? handler]) {
    if (handler == null) {
      _listeners.remove(event);
      _socket?.off(event);
      return;
    }
    _listeners[event]?.remove(handler);
    _socket?.off(event, handler);
  }

  /// Fire-and-forget emit. Dropped silently when offline — used for
  /// typing indicators and presence, where a lost event is harmless.
  void emit(String event, [Object? data]) {
    if (!isConnected) return;
    _socket?.emit(event, data);
  }

  /// Emit and wait for the server's acknowledgement.
  ///
  /// Every handler that can fail acknowledges with `{ok: false, ...}`
  /// rather than throwing, because Socket.IO has no status codes. The
  /// timeout guards against a server that never answers at all — without
  /// it, a lost ack hangs the caller forever.
  Future<Map<String, dynamic>> request(
    String event, {
    Object? data,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final io.Socket? socket = _socket;
    if (socket == null || !isConnected) {
      return <String, dynamic>{
        'ok': false,
        'code': 'OFFLINE',
        'message': 'You are offline. Check your connection and try again.',
      };
    }

    final Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();

    socket.emitWithAck(
      event,
      data ?? <String, dynamic>{},
      ack: (Object? response) {
        if (completer.isCompleted) return;
        completer.complete(_asMap(response));
      },
    );

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return <String, dynamic>{
        'ok': false,
        'code': 'TIMEOUT',
        'message': 'The server did not respond. Please try again.',
      };
    }
  }

  // -------------------------------------------------------------------------
  // Convenience wrappers
  // -------------------------------------------------------------------------

  void subscribeToPresence(List<String> userIds) {
    if (userIds.isEmpty) return;
    emit(SocketEvents.presenceSubscribe, <String, dynamic>{
      'userIds': userIds,
    });
  }

  void unsubscribeFromPresence(List<String> userIds) {
    emit(SocketEvents.presenceUnsubscribe, <String, dynamic>{
      'userIds': userIds,
    });
  }

  // -------------------------------------------------------------------------

  void _setStatus(SocketStatus next) {
    if (_status == next) return;
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  static Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{'ok': false, 'code': 'BAD_RESPONSE'};
  }
}

/// Normalises whatever a socket handler receives into a map.
///
/// Socket.IO hands over `dynamic`; on Android a JSON object arrives as
/// `Map<String, dynamic>` but nested values can come through as
/// `_InternalLinkedHashMap<dynamic, dynamic>`, which a plain cast rejects.
Map<String, dynamic> socketPayload(Object? data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  if (data is List && data.isNotEmpty) return socketPayload(data.first);
  return <String, dynamic>{};
}
