part of 'chat_bloc.dart';

sealed class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Opens a thread. Pass whichever id you have — the coach's profile id
/// (the usual case, from the detail screen) or a known conversation id.
class ChatOpened extends ChatEvent {
  const ChatOpened({this.professionalId, this.conversationId})
      : assert(
          professionalId != null || conversationId != null,
          'Need a professionalId or a conversationId to open a chat',
        );

  final String? professionalId;
  final String? conversationId;

  @override
  List<Object?> get props => <Object?>[professionalId, conversationId];
}

/// Loads the previous page, triggered by scrolling to the top.
class ChatHistoryRequested extends ChatEvent {
  const ChatHistoryRequested();
}

class ChatMessageSent extends ChatEvent {
  const ChatMessageSent(this.body);
  final String body;

  @override
  List<Object?> get props => <Object?>[body];
}

/// Re-sends a message that failed. Reuses the original clientId, so the
/// server deduplicates if the first attempt actually landed.
class ChatMessageRetried extends ChatEvent {
  const ChatMessageRetried(this.clientId);
  final String clientId;

  @override
  List<Object?> get props => <Object?>[clientId];
}

class ChatMessageReceived extends ChatEvent {
  const ChatMessageReceived(this.message);
  final ChatMessage message;

  @override
  List<Object?> get props => <Object?>[message];
}

/// Fired as the user types, so we can emit a throttled typing ping.
class ChatComposerChanged extends ChatEvent {
  const ChatComposerChanged(this.text);
  final String text;

  @override
  List<Object?> get props => <Object?>[text];
}

class ChatPeerTypingChanged extends ChatEvent {
  const ChatPeerTypingChanged(this.isTyping);
  final bool isTyping;

  @override
  List<Object?> get props => <Object?>[isTyping];
}

class ChatReadReceiptReceived extends ChatEvent {
  const ChatReadReceiptReceived(this.userId);
  final String userId;

  @override
  List<Object?> get props => <Object?>[userId];
}

/// Tells the server everything up to the newest message has been seen.
class ChatMarkedRead extends ChatEvent {
  const ChatMarkedRead();
}

/// The socket came back — rejoin the room and re-sync the tail.
class ChatReconnected extends ChatEvent {
  const ChatReconnected();
}

/// Re-fetch the newest page, merging rather than replacing so in-flight
/// optimistic bubbles survive.
class ChatRefreshRequested extends ChatEvent {
  const ChatRefreshRequested();
}

/// Opening the thread failed; try the same request again. Without this
/// the failure is terminal — no conversation id means a disabled
/// composer and an empty thread, with no way back but leaving the screen.
class ChatOpenRetried extends ChatEvent {
  const ChatOpenRetried();
}
