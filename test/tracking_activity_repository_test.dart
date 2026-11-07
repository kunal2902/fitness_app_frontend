import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fitness_app/config/api_endpoints.dart';
import 'package:fitness_app/models/route_models.dart';
import 'package:fitness_app/models/tracked_activity.dart';
import 'package:fitness_app/services/api_client.dart';
import 'package:fitness_app/services/tracking_activity_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> activityJson({
  String id = 'activity-1',
  String clientId = 'session-1',
}) =>
    <String, dynamic>{
      'id': id,
      'type': 'run',
      'startedAt': '2026-09-17T06:00:00.000Z',
      'endedAt': '2026-09-17T06:01:00.000Z',
      'durationSec': 60,
      'movingSec': 55,
      'distanceM': 250,
      'elevationGainM': 4.5,
      'avgPaceSecPerKm': 220,
      'encodedPolyline': '_p~iF~ps|U_ulLnnqC',
      'thumbnailUrl': '/uploads/routes/$id.png',
      'splits': <Map<String, dynamic>>[
        <String, dynamic>{
          'index': 1,
          'distanceM': 250,
          'durationSec': 60,
          'movingSec': 55,
          'paceSecPerKm': 220,
          'isPartial': true,
        },
      ],
      'calories': 0,
      'avgHr': null,
      'maxHr': null,
      'source': 'app',
      'clientId': clientId,
    };

ResponseBody envelope(Map<String, dynamic> data) => ResponseBody.fromString(
      jsonEncode(<String, dynamic>{'success': true, 'data': data}),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );

class ActivityHttpAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return switch ((options.method, options.path)) {
      ('GET', ApiEndpoints.activities) => envelope(<String, dynamic>{
          'activities': <Map<String, dynamic>>[activityJson()],
        }),
      ('GET', '/activities/activity-1') => envelope(<String, dynamic>{
          'activity': activityJson(),
        }),
      ('POST', ApiEndpoints.activities) => envelope(<String, dynamic>{
          'activity': activityJson(
            id: 'saved-activity',
            clientId:
                (options.data as Map<String, dynamic>)['clientId'] as String,
          ),
          'duplicate': false,
        }),
      ('DELETE', '/activities/activity-1') =>
        envelope(<String, dynamic>{'deleted': true}),
      _ => throw StateError('${options.method} ${options.path}'),
    };
  }

  @override
  void close({bool force = false}) {}
}

ProcessedRoute processedRoute() => ProcessedRoute(
      coordinates: const <RouteCoordinate>[
        RouteCoordinate(28.6139, 77.2090),
        RouteCoordinate(28.6149, 77.2100),
      ],
      encodedPolyline: '_p~iF~ps|U_ulLnnqC',
      distanceM: 250,
      recorded: const Duration(seconds: 60),
      moving: const Duration(seconds: 55),
      wallClock: const Duration(seconds: 60),
      splits: const <RouteSplit>[
        RouteSplit(
          index: 1,
          distanceM: 250,
          duration: Duration(seconds: 60),
          moving: Duration(seconds: 55),
          isPartial: true,
        ),
      ],
      filter: const RouteFilterReport(
        total: 2,
        accepted: 2,
        rejected: <RoutePointRejection, int>{},
      ),
      startedAt: DateTime.utc(2026, 9, 17, 6),
      endedAt: DateTime.utc(2026, 9, 17, 6, 1),
    );

void main() {
  late HttpClientAdapter originalAdapter;
  late List<Interceptor> originalInterceptors;
  late ActivityHttpAdapter adapter;
  late ApiTrackingActivityRepository repository;

  setUp(() {
    final Dio dio = ApiClient.instance.raw;
    originalAdapter = dio.httpClientAdapter;
    originalInterceptors = dio.interceptors.toList();
    dio.interceptors.clear(keepImplyContentTypeInterceptor: false);
    adapter = ActivityHttpAdapter();
    dio.httpClientAdapter = adapter;
    repository = ApiTrackingActivityRepository();
  });

  tearDown(() {
    final Dio dio = ApiClient.instance.raw;
    dio.httpClientAdapter = originalAdapter;
    dio.interceptors.clear(keepImplyContentTypeInterceptor: false);
    dio.interceptors.addAll(originalInterceptors);
  });

  test('activity API list, detail, save and delete share the backend contract',
      () async {
    final List<TrackedActivity> recent = await repository.listRecent(limit: 10);
    expect(recent.single.type, TrackedActivityType.run);
    expect(recent.single.thumbnailUrl, contains('/uploads/routes/'));

    expect((await repository.get('activity-1')).distanceM, 250);
    final TrackedActivity saved = await repository.saveProcessed(
      route: processedRoute(),
      clientId: 'session-safe-retry',
    );
    expect(saved.id, 'saved-activity');
    await repository.delete('activity-1');

    expect(
      adapter.requests.map((RequestOptions value) => value.method),
      <String>['GET', 'GET', 'POST', 'DELETE'],
    );
    expect(adapter.requests.first.queryParameters['limit'], 10);
    final Map<String, dynamic> body =
        adapter.requests[2].data as Map<String, dynamic>;
    expect(body['clientId'], 'session-safe-retry');
    expect(body['source'], 'app');
    expect(body['distanceM'], 250);
    expect(body['movingSec'], 55);
    expect((body['splits'] as List), hasLength(1));
  });

  test('too-short processed routes stay local and never call the API',
      () async {
    final ProcessedRoute empty = ProcessedRoute.empty(
      const RouteFilterReport(
        total: 0,
        accepted: 0,
        rejected: <RoutePointRejection, int>{},
      ),
    );
    await expectLater(
      repository.saveProcessed(route: empty, clientId: 'short'),
      throwsA(isA<Exception>()),
    );
    expect(adapter.requests, isEmpty);
  });
}
