import 'package:equatable/equatable.dart';

import 'json_coercion.dart';
import 'onboarding_data.dart';
import 'user_model.dart';

/// Body of `POST /auth/signup` — account details plus the answers gathered
/// during onboarding, submitted together in one call.
class SignupRequest extends Equatable {
  const SignupRequest({
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

  Map<String, dynamic> toJson() => <String, dynamic>{
        'username': username.trim(),
        'fullName': fullName.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
        'fitnessProfile': fitnessProfile.toJson(),
      };

  @override
  List<Object?> get props =>
      <Object?>[username, fullName, email, password, fitnessProfile];
}

/// Body of `POST /auth/login`.
class LoginRequest extends Equatable {
  const LoginRequest({required this.identifier, required this.password});

  /// Email or username — the backend accepts either.
  final String identifier;
  final String password;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'identifier': identifier.trim(),
        'password': password,
      };

  @override
  List<Object?> get props => <Object?>[identifier, password];
}

/// Tokens + user returned by signup, login and refresh.
class AuthSession extends Equatable {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final UserModel user;

  /// Tolerates every shape the backend has been seen to send: tokens at
  /// the top level or nested under `tokens`, and a user object that decoded
  /// as `Map<dynamic, dynamic>`. Anything it cannot read becomes empty, and
  /// [isUsable] is what decides whether that is acceptable.
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> tokens = asStringMap(json['tokens']) ?? json;
    return AuthSession(
      accessToken: asString(tokens['accessToken']),
      refreshToken: asString(tokens['refreshToken']),
      user: UserModel.fromJson(
        asStringMap(json['user']) ?? const <String, dynamic>{},
      ),
    );
  }

  /// Whether this session can actually authorise a request and say whom it
  /// belongs to.
  ///
  /// A 200 carrying an empty access token is the worst possible outcome to
  /// accept: `AppStore` would flip to authenticated, the UI would route to
  /// Home, and every request from then on would go out with no
  /// `Authorization` header and no path back short of reinstalling. A
  /// missing refresh token is nearly as bad — the session would die at the
  /// first expiry with nothing to renew it — and a user with no id cannot
  /// be cached or re-fetched.
  bool get isUsable =>
      accessToken.isNotEmpty && refreshToken.isNotEmpty && user.id.isNotEmpty;

  @override
  List<Object?> get props => <Object?>[accessToken, refreshToken, user];
}

/// Result of `GET /auth/check-availability?username=&email=`.
class AvailabilityResult extends Equatable {
  const AvailabilityResult({
    required this.usernameAvailable,
    required this.emailAvailable,
  });

  final bool usernameAvailable;
  final bool emailAvailable;

  /// Defaults to available on anything unreadable: this only drives an
  /// inline hint while the user types, and signup validates server-side
  /// regardless. Blocking the form over a malformed convenience response
  /// would be worse than showing the hint late.
  factory AvailabilityResult.fromJson(Map<String, dynamic> json) {
    return AvailabilityResult(
      usernameAvailable: json['usernameAvailable'] as bool? ?? true,
      emailAvailable: json['emailAvailable'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => <Object?>[usernameAvailable, emailAvailable];
}
