import 'package:dio/dio.dart' show CancelToken;

import '../config/api_endpoints.dart';
import '../models/api_exception.dart';
import '../models/training_models.dart';
import 'api_client.dart';

abstract interface class TrainingRepository {
  Future<TrainingTaxonomy> loadTaxonomy({CancelToken? cancelToken});

  Future<TrainingExercisePage> searchExercises({
    String query = '',
    Set<String> muscleIds = const {},
    String? muscleGroup,
    String muscleRole = 'any',
    String? equipmentMode,
    Set<String>? equipmentIds,
    String? equipmentProfileId,
    String? difficulty,
    String? movementPattern,
    String? loadingMode,
    String? trainingType,
    String? sort,
    String? cursor,
    int limit = 20,
    CancelToken? cancelToken,
  });

  Future<TrainingExercise> loadExercise(String id, {CancelToken? cancelToken});

  Future<TrainingPreferences> loadPreferences({CancelToken? cancelToken});

  Future<TrainingPreferences> saveEquipmentPreferences({
    required int revision,
    required List<TrainingEquipmentProfile> equipmentProfiles,
    required String? activeEquipmentProfileId,
    CancelToken? cancelToken,
  });
}

/// One repository per signed-in training route. Requests are cancelled when
/// the route closes and private results are held only by that route.
class ApiTrainingRepository implements TrainingRepository {
  ApiTrainingRepository({required bool Function() isSessionCurrent})
      : _isSessionCurrent = isSessionCurrent;

  final bool Function() _isSessionCurrent;
  final ApiClient _client = ApiClient.instance;
  final Set<CancelToken> _requests = <CancelToken>{};
  bool _disposed = false;

  @override
  Future<TrainingTaxonomy> loadTaxonomy({CancelToken? cancelToken}) => _get(
        ApiEndpoints.trainingTaxonomy,
        TrainingTaxonomy.fromJson,
        cancelToken: cancelToken,
      );

  @override
  Future<TrainingExercisePage> searchExercises({
    String query = '',
    Set<String> muscleIds = const {},
    String? muscleGroup,
    String muscleRole = 'any',
    String? equipmentMode,
    Set<String>? equipmentIds,
    String? equipmentProfileId,
    String? difficulty,
    String? movementPattern,
    String? loadingMode,
    String? trainingType,
    String? sort,
    String? cursor,
    int limit = 20,
    CancelToken? cancelToken,
  }) {
    final String search = query.trim();
    return _get(
      ApiEndpoints.exercises,
      TrainingExercisePage.fromJson,
      query: <String, dynamic>{
        if (search.isNotEmpty) 'q': search,
        if (muscleIds.isNotEmpty) 'muscles': _csv(muscleIds),
        if (muscleGroup != null && muscleIds.isEmpty)
          'muscleGroups': muscleGroup,
        'muscleRole': muscleRole,
        if (equipmentMode != null) 'equipmentMode': equipmentMode,
        // An explicit empty list means the member has no equipment.
        if (equipmentIds != null) 'equipmentIds': _csv(equipmentIds),
        if (equipmentProfileId != null)
          'equipmentProfileId': equipmentProfileId,
        if (difficulty != null) 'difficulty': difficulty,
        if (movementPattern != null) 'movementPattern': movementPattern,
        if (loadingMode != null) 'loadingMode': loadingMode,
        if (trainingType != null) 'trainingType': trainingType,
        if (sort != null) 'sort': sort,
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
      cancelToken: cancelToken,
    );
  }

  @override
  Future<TrainingExercise> loadExercise(
    String id, {
    CancelToken? cancelToken,
  }) =>
      _get(
        ApiEndpoints.exercise(id),
        (Map<String, dynamic> data) {
          final Object? catalogueVersion = data['catalogueVersion'];
          final Object? releaseId = data['releaseId'];
          if (catalogueVersion is! int || releaseId is! String) {
            throw const FormatException('Missing exercise catalogue version');
          }
          final TrainingExercise exercise = TrainingExercise.fromJson(
            _object(data, 'exercise'),
            detail: true,
            catalogueVersion: catalogueVersion,
            releaseId: releaseId,
          );
          if (exercise.id != id) {
            throw const FormatException('Exercise ID mismatch');
          }
          return exercise;
        },
        cancelToken: cancelToken,
      );

  @override
  Future<TrainingPreferences> loadPreferences({CancelToken? cancelToken}) =>
      _get(
        ApiEndpoints.trainingPreferences,
        _preferences,
        cancelToken: cancelToken,
      );

  @override
  Future<TrainingPreferences> saveEquipmentPreferences({
    required int revision,
    required List<TrainingEquipmentProfile> equipmentProfiles,
    required String? activeEquipmentProfileId,
    CancelToken? cancelToken,
  }) =>
      _request(
        (CancelToken token) => _client.patch(
          ApiEndpoints.trainingPreferences,
          body: <String, dynamic>{
            'revision': revision,
            'equipmentProfiles': equipmentProfiles
                .map((TrainingEquipmentProfile profile) => profile.toJson())
                .toList(),
            'activeEquipmentProfileId': activeEquipmentProfileId,
          },
          cancelToken: token,
          isSessionCurrent: _isSessionCurrent,
        ),
        _preferences,
        cancelToken,
      );

  Future<T> _get<T>(
    String path,
    T Function(Map<String, dynamic>) parse, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _request(
        (CancelToken token) => _client.get(
          path,
          query: query,
          cancelToken: token,
          isSessionCurrent: _isSessionCurrent,
        ),
        parse,
        cancelToken,
      );

  Future<T> _request<T>(
    Future<Map<String, dynamic>> Function(CancelToken) send,
    T Function(Map<String, dynamic>) parse,
    CancelToken? cancelToken,
  ) async {
    final CancelToken token = cancelToken ?? CancelToken();
    _requireOpen(token);
    _requests.add(token);
    try {
      final Map<String, dynamic> data = await send(token);
      _requireOpen(token);
      return parse(data);
    } on FormatException {
      throw const ApiException(
        message: 'The training service sent unexpected data. Try again.',
        code: 'BAD_ENVELOPE',
      );
    } finally {
      _requests.remove(token);
    }
  }

  void _requireOpen(CancelToken token) {
    if (_disposed || !_isSessionCurrent() || token.isCancelled) {
      throw const ApiException(
        message: 'Training request cancelled.',
        code: 'CANCELLED',
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final CancelToken token in _requests) {
      token.cancel('Training route closed');
    }
    _requests.clear();
  }

  static String _csv(Set<String> ids) => (ids.toList()..sort()).join(',');

  static TrainingPreferences _preferences(Map<String, dynamic> data) =>
      TrainingPreferences.fromJson(_object(data, 'preferences'));

  static Map<String, dynamic> _object(Map<String, dynamic> data, String key) {
    final Object? value = data[key];
    if (value is Map<String, dynamic>) return value;
    throw FormatException('Invalid training response: $key');
  }
}
