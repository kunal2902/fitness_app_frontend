import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Coaching disciplines. Values mirror `PROFESSIONAL_SPECIALITIES` in
/// `src/models/professional.model.ts` — they must stay byte-identical.
enum Speciality {
  strength('strength', 'Strength', Icons.fitness_center_rounded),
  calisthenics('calisthenics', 'Calisthenics', Icons.sports_gymnastics_rounded),
  mobility('mobility', 'Mobility', Icons.self_improvement_rounded),
  nutrition('nutrition', 'Nutrition', Icons.restaurant_rounded),
  rehab('rehab', 'Rehab', Icons.healing_rounded),
  yoga('yoga', 'Yoga', Icons.spa_rounded),
  weightLoss('weight_loss', 'Weight loss', Icons.local_fire_department_rounded),
  muscleGain('muscle_gain', 'Muscle gain', Icons.trending_up_rounded);

  const Speciality(this.apiValue, this.label, this.icon);

  final String apiValue;
  final String label;
  final IconData icon;

  static Speciality? fromApi(String? raw) {
    for (final Speciality s in Speciality.values) {
      if (s.apiValue == raw) return s;
    }
    return null;
  }
}

class Certification extends Equatable {
  const Certification({
    required this.title,
    required this.issuer,
    required this.year,
    this.credentialUrl,
  });

  final String title;
  final String issuer;
  final int year;
  final String? credentialUrl;

  factory Certification.fromJson(Map<String, dynamic> json) {
    return Certification(
      title: (json['title'] ?? '') as String,
      issuer: (json['issuer'] ?? '') as String,
      year: (json['year'] as num?)?.toInt() ?? 0,
      credentialUrl: json['credentialUrl'] as String?,
    );
  }

  @override
  List<Object?> get props => <Object?>[title, issuer, year, credentialUrl];
}

class ClientTransformation extends Equatable {
  const ClientTransformation({
    required this.clientName,
    required this.durationLabel,
    required this.summary,
    this.beforeImageUrl,
    this.afterImageUrl,
    this.highlights = const <String>[],
  });

  final String clientName;
  final String durationLabel;
  final String summary;
  final String? beforeImageUrl;
  final String? afterImageUrl;
  final List<String> highlights;

  factory ClientTransformation.fromJson(Map<String, dynamic> json) {
    final Object? raw = json['highlights'];
    return ClientTransformation(
      clientName: (json['clientName'] ?? '') as String,
      durationLabel: (json['durationLabel'] ?? '') as String,
      summary: (json['summary'] ?? '') as String,
      beforeImageUrl: json['beforeImageUrl'] as String?,
      afterImageUrl: json['afterImageUrl'] as String?,
      highlights: raw is List
          ? raw.map((Object? e) => e.toString()).toList()
          : const <String>[],
    );
  }

  @override
  List<Object?> get props => <Object?>[
        clientName,
        durationLabel,
        summary,
        beforeImageUrl,
        afterImageUrl,
        highlights,
      ];
}

class Achievement extends Equatable {
  const Achievement({
    required this.title,
    required this.description,
    this.year,
  });

  final String title;
  final String description;
  final int? year;

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      year: (json['year'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => <Object?>[title, description, year];
}

/// A coach, with everything the detail screen renders.
class Professional extends Equatable {
  const Professional({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.headline,
    required this.bio,
    this.avatarUrl,
    this.specialities = const <Speciality>[],
    this.languages = const <String>[],
    this.yearsExperience = 0,
    this.certifications = const <Certification>[],
    this.transformations = const <ClientTransformation>[],
    this.achievements = const <Achievement>[],
    this.sessionRateMinor = 0,
    this.currency = 'INR',
    this.ratingAverage = 0,
    this.ratingCount = 0,
    this.clientsCoached = 0,
    this.isAcceptingClients = true,
    this.isOnline = false,
    this.lastSeenAt,
  });

  /// Professional profile id — used for `/professionals/:id`.
  final String id;

  /// The underlying login id — used for presence and conversations.
  final String userId;

  final String displayName;
  final String headline;
  final String bio;
  final String? avatarUrl;

  final List<Speciality> specialities;
  final List<String> languages;
  final int yearsExperience;

  final List<Certification> certifications;
  final List<ClientTransformation> transformations;
  final List<Achievement> achievements;

  /// Minor units — paise for INR, cents for USD. Never a float.
  final int sessionRateMinor;
  final String currency;

  final double ratingAverage;
  final int ratingCount;
  final int clientsCoached;

  final bool isAcceptingClients;
  final bool isOnline;
  final DateTime? lastSeenAt;

  /// Two-letter monogram for the avatar fallback.
  String get initials {
    final List<String> parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get firstName {
    final List<String> parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return displayName;
    return parts.first;
  }

  /// e.g. "₹1,500". Stored minor, rendered major.
  String get formattedRate {
    final double major = sessionRateMinor / 100;
    final String symbol = switch (currency) {
      'INR' => '₹',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '$currency ',
    };
    final String amount = major
        .toStringAsFixed(major == major.roundToDouble() ? 0 : 2)
        .replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
    return '$symbol$amount';
  }

  /// "Online" / "Last seen 3h ago" / "Offline".
  String get presenceLabel {
    if (isOnline) return 'Online';
    final DateTime? seen = lastSeenAt;
    if (seen == null) return 'Offline';

    final Duration ago = DateTime.now().difference(seen);
    if (ago.inMinutes < 1) return 'Just now';
    if (ago.inMinutes < 60) return 'Last seen ${ago.inMinutes}m ago';
    if (ago.inHours < 24) return 'Last seen ${ago.inHours}h ago';
    if (ago.inDays < 7) return 'Last seen ${ago.inDays}d ago';
    return 'Offline';
  }

  /// [clearLastSeenAt] exists because `lastSeenAt: null` is
  /// indistinguishable from "not passed" in Dart's optional-argument
  /// model. Without it a coach who comes online keeps the timestamp from
  /// the last time they went offline, and the moment they drop again the
  /// UI shows that stale "Last seen 6h ago" instead of the truth.
  Professional copyWith({
    bool? isOnline,
    DateTime? lastSeenAt,
    bool clearLastSeenAt = false,
  }) {
    return Professional(
      id: id,
      userId: userId,
      displayName: displayName,
      headline: headline,
      bio: bio,
      avatarUrl: avatarUrl,
      specialities: specialities,
      languages: languages,
      yearsExperience: yearsExperience,
      certifications: certifications,
      transformations: transformations,
      achievements: achievements,
      sessionRateMinor: sessionRateMinor,
      currency: currency,
      ratingAverage: ratingAverage,
      ratingCount: ratingCount,
      clientsCoached: clientsCoached,
      isAcceptingClients: isAcceptingClients,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: clearLastSeenAt ? null : (lastSeenAt ?? this.lastSeenAt),
    );
  }

  factory Professional.fromJson(Map<String, dynamic> json) {
    List<T> listOf<T>(String key, T Function(Map<String, dynamic>) parse) {
      final Object? raw = json[key];
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(parse)
          .toList();
    }

    final Object? rawSpecialities = json['specialities'];
    final Object? rawLanguages = json['languages'];

    return Professional(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      displayName: (json['displayName'] ?? '') as String,
      headline: (json['headline'] ?? '') as String,
      bio: (json['bio'] ?? '') as String,
      avatarUrl: json['avatarUrl'] as String?,
      specialities: rawSpecialities is List
          ? rawSpecialities
              .map((Object? e) => Speciality.fromApi(e as String?))
              .whereType<Speciality>()
              .toList()
          : const <Speciality>[],
      languages: rawLanguages is List
          ? rawLanguages.map((Object? e) => e.toString()).toList()
          : const <String>[],
      yearsExperience: (json['yearsExperience'] as num?)?.toInt() ?? 0,
      certifications: listOf('certifications', Certification.fromJson),
      transformations: listOf('transformations', ClientTransformation.fromJson),
      achievements: listOf('achievements', Achievement.fromJson),
      sessionRateMinor: (json['sessionRateMinor'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] ?? 'INR') as String,
      ratingAverage: (json['ratingAverage'] as num?)?.toDouble() ?? 0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      clientsCoached: (json['clientsCoached'] as num?)?.toInt() ?? 0,
      isAcceptingClients: json['isAcceptingClients'] as bool? ?? true,
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeenAt: DateTime.tryParse((json['lastSeenAt'] ?? '').toString()),
    );
  }

  @override
  List<Object?> get props => <Object?>[id, userId, isOnline, lastSeenAt];
}
