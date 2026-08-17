import 'package:equatable/equatable.dart';

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

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final Object? profile = json['fitnessProfile'];
    return UserModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      username: (json['username'] ?? '') as String,
      fullName: (json['fullName'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      avatarUrl: json['avatarUrl'] as String?,
      isEmailVerified: json['isEmailVerified'] as bool? ?? false,
      fitnessProfile: profile is Map<String, dynamic>
          ? OnboardingData.fromJson(profile)
          : null,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
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
