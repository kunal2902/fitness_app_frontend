part of 'professionals_bloc.dart';

sealed class ProfessionalsEvent extends Equatable {
  const ProfessionalsEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Loads the coach list and subscribes to their presence.
class ProfessionalsRequested extends ProfessionalsEvent {
  const ProfessionalsRequested();
}

/// Loads one coach's full portfolio for the detail screen.
class ProfessionalSelected extends ProfessionalsEvent {
  const ProfessionalSelected(this.professionalId);
  final String professionalId;

  @override
  List<Object?> get props => <Object?>[professionalId];
}

/// A single coach came online or went offline.
class ProfessionalPresenceChanged extends ProfessionalsEvent {
  const ProfessionalPresenceChanged({
    required this.userId,
    required this.isOnline,
    this.lastSeenAt,
  });

  final String userId;
  final bool isOnline;
  final DateTime? lastSeenAt;

  @override
  List<Object?> get props => <Object?>[userId, isOnline, lastSeenAt];
}

/// The socket reconnected — re-arm the server-side presence watch.
class ProfessionalsPresenceResubscribed extends ProfessionalsEvent {
  const ProfessionalsPresenceResubscribed();
}

/// The full presence picture, sent right after subscribing.
class ProfessionalsPresenceSnapshot extends ProfessionalsEvent {
  const ProfessionalsPresenceSnapshot(this.users);

  final List<({String userId, bool isOnline, DateTime? lastSeenAt})> users;

  @override
  List<Object?> get props => <Object?>[users];
}
