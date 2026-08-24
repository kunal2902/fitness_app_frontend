part of 'chat_bloc.dart';

class ChatState extends Equatable {
  const ChatState({
    this.conversationId,
    this.messages = const <ChatMessage>[],
    this.isLoadingHistory = false,
    this.isLoadingMore = false,
    this.isSending = false,
    this.hasMore = false,
    this.isPeerTyping = false,
    this.errorMessage,
  });

  final String? conversationId;

  /// Oldest first — the order a chat list renders top to bottom.
  final List<ChatMessage> messages;

  final bool isLoadingHistory;
  final bool isLoadingMore;
  final bool isSending;
  final bool hasMore;
  final bool isPeerTyping;
  final String? errorMessage;

  bool get isReady => conversationId != null && !isLoadingHistory;
  bool get isEmpty => isReady && messages.isEmpty;

  bool get hasFailedMessages => messages.any(
        (ChatMessage m) => m.delivery == MessageDelivery.failed,
      );

  ChatState copyWith({
    String? conversationId,
    List<ChatMessage>? messages,
    bool? isLoadingHistory,
    bool? isLoadingMore,
    bool? isSending,
    bool? hasMore,
    bool? isPeerTyping,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChatState(
      conversationId: conversationId ?? this.conversationId,
      messages: messages ?? this.messages,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSending: isSending ?? this.isSending,
      hasMore: hasMore ?? this.hasMore,
      isPeerTyping: isPeerTyping ?? this.isPeerTyping,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        conversationId,
        messages,
        isLoadingHistory,
        isLoadingMore,
        isSending,
        hasMore,
        isPeerTyping,
        errorMessage,
      ];
}
