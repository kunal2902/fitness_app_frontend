/// Mirror of `src/realtime/events.ts` on the backend.
///
/// Socket.IO matches events by string. A typo does not throw — the event
/// simply never arrives — so both sides read from a constants table and
/// neither ever types a literal inline.
class SocketEvents {
  const SocketEvents._();

  // --- connection lifecycle ---
  static const String connected = 'connected';
  static const String error = 'app:error';

  // --- presence ---
  static const String presenceSubscribe = 'presence:subscribe';
  static const String presenceUnsubscribe = 'presence:unsubscribe';
  static const String presenceUpdate = 'presence:update';
  static const String presenceSnapshot = 'presence:snapshot';

  // --- chat ---
  static const String chatJoin = 'chat:join';
  static const String chatLeave = 'chat:leave';
  static const String chatSend = 'chat:send';
  static const String chatMessage = 'chat:message';
  static const String chatDelivered = 'chat:delivered';
  static const String chatTyping = 'chat:typing';
  static const String chatRead = 'chat:read';

  // --- calls: control plane ---
  static const String callInvite = 'call:invite';
  static const String callIncoming = 'call:incoming';
  static const String callAccept = 'call:accept';
  static const String callAccepted = 'call:accepted';
  static const String callReject = 'call:reject';
  static const String callRejected = 'call:rejected';
  static const String callCancel = 'call:cancel';
  static const String callCancelled = 'call:cancelled';
  static const String callEnd = 'call:end';
  static const String callEnded = 'call:ended';
  static const String callBusy = 'call:busy';

  // --- calls: WebRTC signalling ---
  static const String callOffer = 'call:offer';
  static const String callAnswer = 'call:answer';
  static const String callIce = 'call:ice';
}
