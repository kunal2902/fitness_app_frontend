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
    this.sessionExpired = false,
  });

  final AuthFlowStatus status;
  final UserModel? user;

  /// Message safe to show in a snackbar.
  final String? errorMessage;

  /// Per-field messages keyed by form field name (`username`, `email`, ...).
  final Map<String, String> fieldErrors;

  /// True for one emission right after signup, so the UI can route to a
  /// welcome screen instead of straight to home.
  ///
  /// One-shot: [copyWith] drops it unless it is passed again. Carrying it
  /// forward would make every later state look like a fresh signup.
  final bool justSignedUp;

  /// True for one emission when the session ended without the user asking
  /// — a refresh that could not be renewed.
  ///
  /// Nothing on screen initiated it, so nothing on screen will navigate
  /// away from the signed-in shell; the root listener watches this and
  /// does it. Also one-shot, so returning to the login screen later does
  /// not re-announce an expiry the user has already dealt with.
  final bool sessionExpired;

  bool get isSubmitting => status == AuthFlowStatus.submitting;
  bool get isAuthenticated => status == AuthFlowStatus.authenticated;

  AuthState copyWith({
    AuthFlowStatus? status,
    UserModel? user,
    String? errorMessage,
    Map<String, String>? fieldErrors,
    bool? justSignedUp,
    bool? sessionExpired,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      fieldErrors:
          clearError ? const <String, String>{} : (fieldErrors ?? this.fieldErrors),
      // Both flags default off rather than carrying forward: they describe
      // a single transition, not a lasting property of the session.
      justSignedUp: justSignedUp ?? false,
      sessionExpired: sessionExpired ?? false,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        status,
        user,
        errorMessage,
        fieldErrors,
        justSignedUp,
        sessionExpired,
      ];
}
