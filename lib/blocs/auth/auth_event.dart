part of 'auth_bloc.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// Cold-start check: is there a valid session on disk?
class AuthBootstrapRequested extends AuthEvent {
  const AuthBootstrapRequested();
}

/// The one call that creates the account. Carries the account fields plus
/// the answers buffered by [OnboardingBloc].
class AuthSignupSubmitted extends AuthEvent {
  const AuthSignupSubmitted({
    required this.username,
    required this.fullName,
    required this.email,
    required this.password,
    required this.fitnessProfile,
  });

  final String username;
  final String fullName;
  final String email;
  final String password;
  final OnboardingData fitnessProfile;

  @override
  List<Object?> get props =>
      <Object?>[username, fullName, email, password, fitnessProfile];
}

class AuthLoginSubmitted extends AuthEvent {
  const AuthLoginSubmitted({
    required this.identifier,
    required this.password,
  });

  final String identifier;
  final String password;

  @override
  List<Object?> get props => <Object?>[identifier, password];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

/// Raised by the API client when a refresh attempt fails.
class AuthSessionExpired extends AuthEvent {
  const AuthSessionExpired();
}

/// Clears a surfaced error so the form can be retried cleanly.
class AuthErrorCleared extends AuthEvent {
  const AuthErrorCleared();
}
