import 'package:equatable/equatable.dart';

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

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final Object? tokens = json['tokens'];
    final Map<String, dynamic> t =
        tokens is Map<String, dynamic> ? tokens : json;
    return AuthSession(
      accessToken: (t['accessToken'] ?? '') as String,
      refreshToken: (t['refreshToken'] ?? '') as String,
      user: UserModel.fromJson(
        (json['user'] ?? const <String, dynamic>{}) as Map<String, dynamic>,
      ),
    );
  }

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

  factory AvailabilityResult.fromJson(Map<String, dynamic> json) {
    return AvailabilityResult(
      usernameAvailable: json['usernameAvailable'] as bool? ?? true,
      emailAvailable: json['emailAvailable'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => <Object?>[usernameAvailable, emailAvailable];
}
