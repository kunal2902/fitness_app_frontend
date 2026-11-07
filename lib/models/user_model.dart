import 'package:equatable/equatable.dart';

import 'json_coercion.dart';
import 'onboarding_data.dart';

/// The authenticated user as returned by the backend.
class UserModel extends Equatable {
  const UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.email,
    this.avatarUrl,
    this.isEmailVerified = false,
    this.fitnessProfile,
    this.createdAt,
  });

  final String id;
  final String username;
  final String fullName;
  final String email;
  final String? avatarUrl;
  final bool isEmailVerified;
  final OnboardingData? fitnessProfile;
  final DateTime? createdAt;

  /// First name, for greetings. Falls back to the username.
  String get firstName {
    final String trimmed = fullName.trim();
    if (trimmed.isEmpty) return username;
    return trimmed.split(RegExp(r'\s+')).first;
  }

  /// Two-letter monogram for the avatar placeholder.
  String get initials {
    final List<String> parts =
        fullName.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return username.isEmpty ? '?' : username[0].toUpperCase();
    }
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? fullName,
    String? email,
    String? avatarUrl,
    bool? isEmailVerified,
    OnboardingData? fitnessProfile,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      fitnessProfile: fitnessProfile ?? this.fitnessProfile,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Coerced rather than cast throughout. This parses both `/auth/me` and
  /// the copy cached in SharedPreferences, so one unexpected type — a
  /// numeric username, a legacy cache written by an older build — would
  /// otherwise throw a `TypeError` during bootstrap and brick the launch.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? profile = asStringMap(json['fitnessProfile']);
    final String avatar = asString(json['avatarUrl']);
    return UserModel(
      id: asString(json['id'] ?? json['_id']),
      username: asString(json['username']),
      fullName: asString(json['fullName']),
      email: asString(json['email']),
      avatarUrl: avatar.isEmpty ? null : avatar,
      isEmailVerified: json['isEmailVerified'] == true,
      fitnessProfile:
          profile != null ? OnboardingData.fromJson(profile) : null,
      createdAt: DateTime.tryParse(asString(json['createdAt'])),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'username': username,
      'fullName': fullName,
      'email': email,
      'avatarUrl': avatarUrl,
      'isEmailVerified': isEmailVerified,
      'fitnessProfile': fitnessProfile?.toJson(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        username,
        fullName,
        email,
        avatarUrl,
        isEmailVerified,
        fitnessProfile,
        createdAt,
      ];
}
