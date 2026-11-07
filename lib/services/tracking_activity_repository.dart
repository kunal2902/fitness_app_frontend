import '../config/api_endpoints.dart';
import '../config/app_config.dart';
import '../models/api_exception.dart';
import '../models/route_models.dart';
import '../models/tracked_activity.dart';
import 'api_client.dart';

abstract interface class TrackingActivityRepository {
  Future<List<TrackedActivity>> listRecent({int limit = 10});
  Future<TrackedActivity> get(String id);
  Future<TrackedActivity> saveProcessed({
    required ProcessedRoute route,
    required String clientId,
    TrackedActivityType type = TrackedActivityType.run,
    double calories = 0,
  });
  Future<void> delete(String id);
}

class ApiTrackingActivityRepository implements TrackingActivityRepository {
  ApiTrackingActivityRepository({ApiClient? client})
      : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  @override
  Future<List<TrackedActivity>> listRecent({int limit = 10}) async {
    final Map<String, dynamic> response = await _client.get(
      ApiEndpoints.activities,
      query: <String, dynamic>{'limit': limit.clamp(1, 100)},
    );
    final Object? raw = response['activities'];
    if (raw is! List) {
      throw const ApiException(
        message: 'Recent activities could not be read. Please try again.',
        code: 'BAD_ENVELOPE',
      );
    }
    return raw
        .whereType<Map>()
        .map(
          (Map value) => TrackedActivity.fromJson(
            Map<String, dynamic>.from(value),
            resolveMediaUrl: AppConfig.resolveMediaUrl,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<TrackedActivity> get(String id) async {
    final Map<String, dynamic> response =
        await _client.get(ApiEndpoints.activity(id));
    final Object? raw = response['activity'];
    if (raw is! Map) {
      throw const ApiException(
        message: 'That activity could not be read. Please try again.',
        code: 'BAD_ENVELOPE',
      );
    }
    return TrackedActivity.fromJson(
      Map<String, dynamic>.from(raw),
      resolveMediaUrl: AppConfig.resolveMediaUrl,
    );
  }

  @override
  Future<TrackedActivity> saveProcessed({
    required ProcessedRoute route,
    required String clientId,
    TrackedActivityType type = TrackedActivityType.run,
    double calories = 0,
  }) async {
    final DateTime? startedAt = route.startedAt;
    final DateTime? endedAt = route.endedAt;
    if (startedAt == null ||
        endedAt == null ||
        !endedAt.isAfter(startedAt) ||
        route.coordinates.length < 2) {
      throw const ApiException(
        message:
            'This workout is too short to save. Record at least two reliable GPS points.',
        code: 'ACTIVITY_TOO_SHORT',
      );
    }
    final Map<String, dynamic> response = await _client.post(
      ApiEndpoints.activities,
      body: <String, dynamic>{
        'type': type.wireName,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt.toUtc().toIso8601String(),
        'durationSec': route.wallClock.inSeconds,
        'movingSec': route.moving.inSeconds,
        'distanceM': route.distanceM,
        'elevationGainM': route.elevation?.gainM,
        'avgPaceSecPerKm': route.avgPaceSecPerKm,
        'encodedPolyline': route.encodedPolyline,
        'splits': route.splits
            .map(
              (RouteSplit split) => <String, dynamic>{
                'index': split.index,
                'distanceM': split.distanceM,
                'durationSec': split.duration.inSeconds,
                'movingSec': split.moving.inSeconds,
                'paceSecPerKm': split.paceSecPerKm,
                'isPartial': split.isPartial,
              },
            )
            .toList(growable: false),
        'calories': calories.isFinite && calories > 0 ? calories : 0,
        'avgHr': null,
        'maxHr': null,
        'source': TrackedActivitySource.app.name,
        'clientId': clientId,
      },
    );
    final Object? raw = response['activity'];
    if (raw is! Map) {
      throw const ApiException(
        message: 'The saved activity response was incomplete. Please retry.',
        code: 'BAD_ENVELOPE',
      );
    }
    return TrackedActivity.fromJson(
      Map<String, dynamic>.from(raw),
      resolveMediaUrl: AppConfig.resolveMediaUrl,
    );
  }

  @override
  Future<void> delete(String id) async {
    final Map<String, dynamic> response =
        await _client.delete(ApiEndpoints.activity(id));
    if (response['deleted'] != true) {
      throw const ApiException(
        message: 'The activity could not be deleted. Please try again.',
        code: 'BAD_ENVELOPE',
      );
    }
  }
}
