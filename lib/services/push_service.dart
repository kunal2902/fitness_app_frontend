import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
// Prefixed deliberately: this package also exports a type called
// `CallEvent`, and so does our own call bloc. Unprefixed, any file that
// ever imports both fails to compile on an ambiguous name — and the
// two mean completely different things, which is worse than the
// compile error.
import 'package:flutter_callkit_incoming/entities/entities.dart' as ckit;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart'
    as ckit;

import '../config/app_config.dart';
import '../models/call_models.dart';
import 'assistance_service.dart';

/// Wakes the app for an incoming call and shows the native ringing UI.
///
/// Two mechanisms, because the platforms are not interchangeable:
///
///  * **Android** — a high-priority FCM *data* message reaches
///    [firebaseBackgroundHandler] even when the app is killed, which then
///    asks CallKit-Incoming to draw a full-screen ringer.
///  * **iOS** — the OS delivers a PushKit VoIP push straight to the
///    plugin, which reports it to CallKit natively. Dart may not run at
///    all until the user answers, so nothing here can be relied on to
///    fire first.
///
/// Everything degrades quietly: with no Firebase configured, in-app calls
/// still work over the socket. Only ringing-while-backgrounded is lost.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  final AssistanceService _api = AssistanceService();

  final StreamController<IncomingCall> _acceptedController =
      StreamController<IncomingCall>.broadcast();
  final StreamController<String> _declinedController =
      StreamController<String>.broadcast();

  /// Fires when the user answers from the native ringer. The app should
  /// open the call screen and accept over the socket.
  Stream<IncomingCall> get callAccepted => _acceptedController.stream;

  /// Fires with a callId when the user declines or the ringer times out.
  Stream<String> get callDeclined => _declinedController.stream;

  bool _initialised = false;
  bool _firebaseAvailable = false;
  String? _fcmToken;
  String? _voipToken;

  bool get isAvailable => _firebaseAvailable;

  /// Cached invites keyed by callId, so answering from the lock screen can
  /// reconstruct who is calling without another round trip.
  final Map<String, IncomingCall> _pending = <String, IncomingCall>{};

  // -------------------------------------------------------------------------

  /// Call once during bootstrap, before the first screen.
  ///
  /// Firebase being absent is not an error — the app runs fine without it,
  /// so a missing `google-services.json` must not stop startup.
  Future<void> initialize() async {
    if (_initialised) return;
    _initialised = true;

    try {
      await Firebase.initializeApp();
      _firebaseAvailable = true;
    } catch (error) {
      developer.log(
        'Firebase unavailable — background call ringing is off: $error',
        name: 'push',
      );
      _firebaseAvailable = false;
    }

    _listenToCallKit();

    if (!_firebaseAvailable) return;

    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  /// Asks for notification permission and registers this device.
  ///
  /// Deliberately separate from [initialize] so the prompt appears after
  /// sign-in, in context, rather than on the very first launch where it
  /// reads as a demand from an app the user has not used yet.
  Future<void> registerForCalls() async {
    if (!_firebaseAvailable) return;

    try {
      final NotificationSettings settings =
          await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        developer.log('notifications denied', name: 'push');
        // Still register the token: Android can ring via a full-screen
        // intent even when notifications are muted.
      }

      _fcmToken = await FirebaseMessaging.instance.getToken();
      if (_fcmToken != null && _fcmToken!.isNotEmpty) {
        await _api.registerDevice(
          token: _fcmToken!,
          platform: Platform.isIOS ? 'ios' : 'android',
          kind: 'fcm',
          appVersion: AppConfig.appName,
        );
      }

      // iOS additionally needs the PushKit token — an FCM token cannot
      // trigger CallKit.
      if (Platform.isIOS) {
        final String? voip =
            await ckit.FlutterCallkitIncoming.getDevicePushTokenVoIP();
        if (voip != null && voip.isNotEmpty) {
          _voipToken = voip;
          await _api.registerDevice(
            token: voip,
            platform: 'ios',
            kind: 'apns_voip',
          );
        }
      }

      // A token can be rotated by the OS at any time; a stale one on the
      // server means calls stop ringing with no visible cause.
      FirebaseMessaging.instance.onTokenRefresh.listen((String token) async {
        _fcmToken = token;
        try {
          await _api.registerDevice(
            token: token,
            platform: Platform.isIOS ? 'ios' : 'android',
            kind: 'fcm',
          );
        } catch (error) {
          developer.log('token refresh registration failed: $error',
              name: 'push');
        }
      });
    } catch (error) {
      developer.log('push registration failed: $error', name: 'push');
    }
  }

  /// Drops this device's tokens on sign-out, so the next person to use the
  /// phone is not rung for the previous account's calls.
  Future<void> unregister() async {
    for (final String? token in <String?>[_fcmToken, _voipToken]) {
      if (token == null || token.isEmpty) continue;
      try {
        await _api.unregisterDevice(token);
      } catch (error) {
        developer.log('unregister failed: $error', name: 'push');
      }
    }
    _fcmToken = null;
    _voipToken = null;
    await ckit.FlutterCallkitIncoming.endAllCalls();
  }

  // -------------------------------------------------------------------------
  // Ringing
  // -------------------------------------------------------------------------

  /// Shows the native incoming-call UI.
  static Future<void> showIncomingCall(IncomingCall call) async {
    final ckit.CallKitParams params = ckit.CallKitParams(
      id: call.callId,
      nameCaller: call.peer.name,
      appName: AppConfig.appName,
      avatar: call.peer.avatarUrl,
      handle: call.peer.name,
      // 0 = audio, 1 = video. Drives the icon CallKit shows.
      type: call.withVideo ? 1 : 0,
      duration: AppConfig.callRingTimeout.inMilliseconds,
      extra: <String, dynamic>{
        'callId': call.callId,
        'conversationId': call.conversationId,
        'callerId': call.peer.userId,
        'callerName': call.peer.name,
        'callerAvatarUrl': call.peer.avatarUrl ?? '',
        'withVideo': call.withVideo,
      },
      android: const ckit.AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#07090D',
        actionColor: '#C6FF3D',
        // Button labels live on AndroidParams in 3.x, not on CallKitParams.
        textAccept: 'Answer',
        textDecline: 'Decline',
        // Full-screen intent — this is what turns a notification into a
        // real ringing screen over the lock screen.
        isShowFullLockedScreen: true,
      ),
      ios: const ckit.IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await ckit.FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Call ids this app dismissed itself, so the resulting CallKit event
  /// can be told apart from the user pressing Decline.
  ///
  /// `endCall()` makes the plugin emit `CallEventActionCallEnded` — the
  /// *same* event a real decline produces. Every dismissal the app
  /// performs therefore echoes straight back as "the user declined". That
  /// is not a cosmetic problem: answering a call calls this to take the
  /// native ringer down, the echo arrives while the call is connecting,
  /// and the call is torn down a beat after the user answers it. Native
  /// ringing never works until this is filtered.
  static final Set<String> _selfDismissed = <String>{};

  /// Dismisses the ringer — the caller hung up, or we answered elsewhere.
  static Future<void> dismissIncomingCall(String callId) async {
    if (callId.isEmpty) return;
    _selfDismissed.add(callId);
    try {
      await ckit.FlutterCallkitIncoming.endCall(callId);
    } catch (error) {
      developer.log('endCall failed: $error', name: 'push');
    }
    // Belt and braces. If the plugin emitted nothing (it is a no-op when
    // no such call is showing), the id would sit in the set and swallow a
    // genuine decline of a *later* call with the same id. Ids are UUIDs so
    // that is near-impossible, but leaking entries into a static set is
    // its own bug.
    Timer(const Duration(seconds: 5), () => _selfDismissed.remove(callId));
  }

  static Future<void> dismissAll() async {
    try {
      await ckit.FlutterCallkitIncoming.endAllCalls();
    } catch (error) {
      developer.log('endAllCalls failed: $error', name: 'push');
    }
  }

  void rememberPending(IncomingCall call) {
    _pending[call.callId] = call;
  }

  // -------------------------------------------------------------------------

  /// The most recent accept, kept so a listener that attaches late still
  /// sees it.
  ///
  /// [callAccepted] is a broadcast stream, which drops events that have no
  /// subscriber. On a cold start from a VoIP push the user can answer
  /// before `CallBloc` has even been constructed — without this the call
  /// is answered natively and then never connects.
  IncomingCall? _lastAccepted;

  /// Consumes the pending accept, if any. Called by `CallBloc` on creation.
  IncomingCall? takePendingAccept() {
    final IncomingCall? call = _lastAccepted;
    _lastAccepted = null;
    return call;
  }

  void _listenToCallKit() {
    // flutter_callkit_incoming 3.x models events as a sealed class
    // hierarchy rather than the 2.x `Event` enum, so this is a pattern
    // match over the concrete event types.
    ckit.FlutterCallkitIncoming.onEvent.listen((ckit.CallEvent? event) {
      if (event == null) return;

      switch (event) {
        case ckit.CallEventActionCallAccept(
              :final ckit.CallKitParams callKitParams,
            ):
          final Map<String, dynamic> extra = _extraOf(callKitParams);
          final String callId =
              (extra['callId'] ?? callKitParams.id).toString();

          final IncomingCall call =
              _pending[callId] ?? IncomingCall.fromPushData(extra);
          _pending.remove(callId);
          _lastAccepted = call;
          if (!_acceptedController.isClosed) _acceptedController.add(call);

        case ckit.CallEventActionCallDecline(
              :final ckit.CallKitParams callKitParams,
            ) ||
              ckit.CallEventActionCallEnded(
                :final ckit.CallKitParams callKitParams,
              ):
          final Map<String, dynamic> extra = _extraOf(callKitParams);
          _declineCall(
            (extra['callId'] ?? callKitParams.id).toString(),
          );

        case ckit.CallEventActionCallTimeout(:final String id):
          _declineCall(id);

        default:
          // Mute, hold and DTMF are handled inside the call screen.
          break;
      }
    });
  }

  void _declineCall(String callId) {
    if (callId.isEmpty) return;

    // Our own dismissal coming back to us — not the user declining. See
    // [_selfDismissed]: without this the accept path tears down the call
    // it just answered.
    if (_selfDismissed.remove(callId)) {
      developer.log('ignoring self-dismiss echo for $callId', name: 'push');
      return;
    }

    _pending.remove(callId);
    if (_lastAccepted?.callId == callId) _lastAccepted = null;
    if (callId.isNotEmpty && !_declinedController.isClosed) {
      _declinedController.add(callId);
    }
  }

  static Map<String, dynamic> _extraOf(ckit.CallKitParams params) {
    final Object? extra = params.extra;
    if (extra is Map<String, dynamic>) return extra;
    if (extra is Map) return Map<String, dynamic>.from(extra);
    return <String, dynamic>{};
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // In the foreground the socket has already delivered `call:incoming`
    // and the in-app UI is showing, so a second native ringer would be
    // duplicate noise. Only cancellations are worth acting on.
    final String type = (message.data['type'] ?? '').toString();
    if (type == 'call_cancelled') {
      await dismissIncomingCall((message.data['callId'] ?? '').toString());
    }
  }
}

/// Runs in a separate isolate when a data message arrives with the app
/// backgrounded or killed.
///
/// Must be a top-level function annotated `vm:entry-point`, or the tree
/// shaker strips it from release builds and calls stop ringing in exactly
/// the configuration you cannot debug from the IDE.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final Map<String, dynamic> data = message.data;
  final String type = (data['type'] ?? '').toString();

  if (type == 'call_invite') {
    await PushService.showIncomingCall(IncomingCall.fromPushData(data));
  } else if (type == 'call_cancelled') {
    await PushService.dismissIncomingCall((data['callId'] ?? '').toString());
  }
}
