part of 'auth_bloc.dart';

enum AuthFlowStatus {
  /// Still reading the session off disk.
  initial,

  /// A signup / login request is in flight.
  submitting,

  /// Signed in.
  authenticated,

  /// No session.
  unauthenticated,

  /// The last request failed — see [AuthState.errorMessage].
  failure,
}

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthFlowStatus.initial,
    this.user,
    this.errorMessage,
    this.fieldErrors = const <String, String>{},
    this.justSignedUp = false,
  });

  final AuthFlowStatus status;
  final UserModel? user;

  /// Message safe to show in a snackbar.
  final String? errorMessage;

  /// Per-field messages keyed by form field name (`username`, `email`, ...).
  final Map<String, String> fieldErrors;

  /// True for one emission right after signup, so the UI can route to a
  /// welcome screen instead of straight to home.
  final bool justSignedUp;

  bool get isSubmitting => status == AuthFlowStatus.submitting;
  bool get isAuthenticated => status == AuthFlowStatus.authenticated;

  AuthState copyWith({
    AuthFlowStatus? status,
    UserModel? user,
    String? errorMessage,
    Map<String, String>? fieldErrors,
    bool? justSignedUp,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      fieldErrors:
          clearError ? const <String, String>{} : (fieldErrors ?? this.fieldErrors),
      justSignedUp: justSignedUp ?? this.justSignedUp,
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[status, user, errorMessage, fieldErrors, justSignedUp];
}
