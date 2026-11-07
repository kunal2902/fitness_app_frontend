typedef _Json = Map<String, dynamic>;

class TrainingMuscleGroup {
  const TrainingMuscleGroup({required this.id, required this.name});

  final String id;
  final String name;

  factory TrainingMuscleGroup.fromJson(Map<String, dynamic> json) =>
      TrainingMuscleGroup(
        id: _required(json, 'id'),
        name: _required(json, 'name'),
      );
}

class TrainingMuscle {
  const TrainingMuscle({
    required this.id,
    required this.name,
    required this.group,
    this.svgRegionIds = const [],
  });

  final String id;
  final String name;
  final String group;
  final List<String> svgRegionIds;

  factory TrainingMuscle.fromJson(Map<String, dynamic> json) => TrainingMuscle(
        id: _required(json, 'id'),
        name: _required(json, 'name'),
        group: _required(json, 'group'),
        svgRegionIds: _strings(json, 'svgRegionIds'),
      );
}

class TrainingEquipment {
  const TrainingEquipment({
    required this.id,
    required this.name,
    required this.category,
    this.aliases = const [],
  });

  final String id;
  final String name;
  final String category;
  final List<String> aliases;

  factory TrainingEquipment.fromJson(Map<String, dynamic> json) =>
      TrainingEquipment(
        id: _required(json, 'id'),
        name: _required(json, 'name'),
        category: _required(json, 'category'),
        aliases: _strings(json, 'aliases'),
      );
}

class TrainingTaxonomy {
  const TrainingTaxonomy({
    required this.catalogueVersion,
    required this.releaseId,
    required this.muscleGroups,
    required this.muscles,
    required this.equipment,
    this.movementPatternIds = const [],
    this.difficulties = const [],
    this.trainingTypes = const [],
  });

  final int catalogueVersion;
  final String releaseId;
  final List<TrainingMuscleGroup> muscleGroups;
  final List<TrainingMuscle> muscles;
  final List<TrainingEquipment> equipment;
  final List<String> movementPatternIds;
  final List<String> difficulties;
  final List<String> trainingTypes;

  factory TrainingTaxonomy.fromJson(Map<String, dynamic> json) =>
      TrainingTaxonomy(
        catalogueVersion: _required(json, 'catalogueVersion'),
        releaseId: _required(json, 'releaseId'),
        muscleGroups:
            _objects(json, 'muscleGroups', TrainingMuscleGroup.fromJson),
        muscles: _objects(json, 'muscles', TrainingMuscle.fromJson),
        equipment: _objects(json, 'equipment', TrainingEquipment.fromJson),
        movementPatternIds: _strings(json, 'movementPatternIds'),
        difficulties: _strings(json, 'difficulties'),
        trainingTypes: _strings(json, 'trainingTypes'),
      );
}

class TrainingEquipmentRequirement {
  const TrainingEquipmentRequirement({required this.anyOf});

  final List<String> anyOf;

  factory TrainingEquipmentRequirement.fromJson(Map<String, dynamic> json) =>
      TrainingEquipmentRequirement(anyOf: _strings(json, 'anyOf'));
}

class TrainingMedia {
  const TrainingMedia({
    required this.id,
    required this.type,
    required this.url,
    this.attribution,
  });

  final String id;
  final String type;
  final String url;
  final String? attribution;

  factory TrainingMedia.fromJson(Map<String, dynamic> json) {
    final String url = _required(json, 'url');
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('Invalid training media URL');
    }
    return TrainingMedia(
      id: _required(json, 'id'),
      type: _required(json, 'type'),
      url: url,
      attribution: _optional(json, 'attribution'),
    );
  }
}

class TrainingExercise {
  const TrainingExercise({
    required this.id,
    required this.version,
    required this.name,
    required this.primaryMuscleIds,
    required this.secondaryMuscleIds,
    required this.movementPatternIds,
    required this.equipmentStatus,
    required this.equipmentRequirementGroups,
    required this.optionalEquipmentIds,
    required this.difficulty,
    required this.trainingType,
    required this.loadingMode,
    required this.measurementType,
    required this.unilateral,
    this.catalogueVersion,
    this.releaseId,
    this.poster,
    this.aliases = const [],
    this.familyId,
    this.variationOfId,
    this.instructions = const [],
    this.formCues = const [],
    this.commonMistakes = const [],
    this.regressionIds = const [],
    this.progressionIds = const [],
    this.substitutionIds = const [],
    this.media = const [],
  });

  final String id;
  final int version;
  final String name;
  final List<String> primaryMuscleIds;
  final List<String> secondaryMuscleIds;
  final List<String> movementPatternIds;
  final String equipmentStatus;
  final List<TrainingEquipmentRequirement> equipmentRequirementGroups;
  final List<String> optionalEquipmentIds;
  final String difficulty;
  final String trainingType;
  final String loadingMode;
  final String measurementType;
  final bool unilateral;
  final int? catalogueVersion;
  final String? releaseId;
  final TrainingMedia? poster;
  final List<String> aliases;
  final String? familyId;
  final String? variationOfId;
  final List<String> instructions;
  final List<String> formCues;
  final List<String> commonMistakes;
  final List<String> regressionIds;
  final List<String> progressionIds;
  final List<String> substitutionIds;
  final List<TrainingMedia> media;

  factory TrainingExercise.fromJson(
    Map<String, dynamic> json, {
    bool detail = false,
    int? catalogueVersion,
    String? releaseId,
  }) {
    final _Json? poster = _optional(json, 'poster');
    return TrainingExercise(
      id: _required(json, 'id'),
      version: _required(json, 'version'),
      name: _required(json, 'name'),
      primaryMuscleIds: _strings(json, 'primaryMuscleIds'),
      secondaryMuscleIds: _strings(json, 'secondaryMuscleIds'),
      movementPatternIds: _strings(json, 'movementPatternIds'),
      equipmentStatus: _required(json, 'equipmentStatus'),
      equipmentRequirementGroups: _objects(
        json,
        'equipmentRequirementGroups',
        TrainingEquipmentRequirement.fromJson,
      ),
      optionalEquipmentIds: _strings(json, 'optionalEquipmentIds'),
      difficulty: _required(json, 'difficulty'),
      trainingType: _required(json, 'trainingType'),
      loadingMode: _required(json, 'loadingMode'),
      measurementType: _required(json, 'measurementType'),
      unilateral: _required(json, 'unilateral'),
      catalogueVersion: catalogueVersion,
      releaseId: releaseId,
      poster: poster == null ? null : TrainingMedia.fromJson(poster),
      aliases: detail ? _strings(json, 'aliases') : const [],
      familyId: detail ? _required<String>(json, 'familyId') : null,
      variationOfId: _optional(json, 'variationOfId'),
      instructions: detail ? _strings(json, 'instructions') : const [],
      formCues: detail ? _strings(json, 'formCues') : const [],
      commonMistakes: detail ? _strings(json, 'commonMistakes') : const [],
      regressionIds: detail ? _strings(json, 'regressionIds') : const [],
      progressionIds: detail ? _strings(json, 'progressionIds') : const [],
      substitutionIds: detail ? _strings(json, 'substitutionIds') : const [],
      media:
          detail ? _objects(json, 'media', TrainingMedia.fromJson) : const [],
    );
  }
}

class TrainingExercisePage {
  const TrainingExercisePage({
    required this.catalogueVersion,
    required this.releaseId,
    required this.items,
    this.nextCursor,
  });

  final int catalogueVersion;
  final String releaseId;
  final List<TrainingExercise> items;
  final String? nextCursor;

  factory TrainingExercisePage.fromJson(Map<String, dynamic> json) {
    final int version = _required(json, 'catalogueVersion');
    final String releaseId = _required(json, 'releaseId');
    return TrainingExercisePage(
      catalogueVersion: version,
      releaseId: releaseId,
      items: _objects(
        json,
        'items',
        (_Json item) => TrainingExercise.fromJson(
          item,
          catalogueVersion: version,
          releaseId: releaseId,
        ),
      ),
      nextCursor: _optional(json, 'nextCursor'),
    );
  }
}

class TrainingEquipmentProfile {
  const TrainingEquipmentProfile({
    required this.id,
    required this.name,
    required this.equipmentIds,
  });

  final String id;
  final String name;
  final List<String> equipmentIds;

  factory TrainingEquipmentProfile.fromJson(Map<String, dynamic> json) =>
      TrainingEquipmentProfile(
        id: _required(json, 'id'),
        name: _required(json, 'name'),
        equipmentIds: _strings(json, 'equipmentIds'),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'equipmentIds': equipmentIds,
      };
}

class TrainingPreferences {
  const TrainingPreferences({
    required this.revision,
    required this.equipmentProfiles,
    this.activeEquipmentProfileId,
    this.level,
    this.sessionDurationMin,
    this.preferredLocation,
    this.timezone,
    this.currentGoalId,
  });

  final int revision;
  final List<TrainingEquipmentProfile> equipmentProfiles;
  final String? activeEquipmentProfileId;
  final String? level;
  final int? sessionDurationMin;
  final String? preferredLocation;
  final String? timezone;
  final String? currentGoalId;

  TrainingEquipmentProfile? get activeEquipmentProfile {
    for (final TrainingEquipmentProfile profile in equipmentProfiles) {
      if (profile.id == activeEquipmentProfileId) return profile;
    }
    return null;
  }

  factory TrainingPreferences.fromJson(Map<String, dynamic> json) =>
      TrainingPreferences(
        revision: _required(json, 'revision'),
        equipmentProfiles: _objects(
          json,
          'equipmentProfiles',
          TrainingEquipmentProfile.fromJson,
        ),
        activeEquipmentProfileId: _optional(json, 'activeEquipmentProfileId'),
        level: _optional(json, 'level'),
        sessionDurationMin: _optional(json, 'sessionDurationMin'),
        preferredLocation: _optional(json, 'preferredLocation'),
        timezone: _optional(json, 'timezone'),
        currentGoalId: _optional(json, 'currentGoalId'),
      );
}

T _required<T>(_Json json, String key) {
  final Object? value = json[key];
  if (value is T) return value;
  throw FormatException('Invalid training field: $key');
}

T? _optional<T>(_Json json, String key) =>
    json[key] == null ? null : _required<T>(json, key);

List<String> _strings(_Json json, String key) => List<String>.unmodifiable(
      _required<List<dynamic>>(json, key).map((Object? value) {
        if (value is String) return value;
        throw FormatException('Invalid training field: $key');
      }),
    );

List<T> _objects<T>(_Json json, String key, T Function(_Json) parse) =>
    List<T>.unmodifiable(
      _required<List<dynamic>>(json, key).map((Object? value) {
        if (value is _Json) return parse(value);
        throw FormatException('Invalid training field: $key');
      }),
    );
