import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fitness_app/config/api_endpoints.dart';
import 'package:fitness_app/models/api_exception.dart';
import 'package:fitness_app/models/training_models.dart';
import 'package:fitness_app/services/api_client.dart';
import 'package:fitness_app/services/training_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_harness.dart';

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.respond);

  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

void main() {
  setUpAll(initAuthTestStorage);
  setUp(resetSignedIn);

  test('no equipment is encoded explicitly and selected muscle narrows group',
      () async {
    final adapter = _RecordingAdapter(
      (_) => _json(200, {
        'success': true,
        'data': {
          'catalogueVersion': 1,
          'releaseId': 'wire_test',
          'items': [],
          'nextCursor': null,
        },
      }),
    );
    ApiClient.instance.raw.httpClientAdapter = adapter;
    final repo = ApiTrainingRepository(isSessionCurrent: () => true);
    addTearDown(repo.dispose);
    final page = await repo.searchExercises(
      equipmentMode: 'available',
      equipmentIds: const {},
      muscleGroup: 'back',
      muscleIds: const {'lats'},
    );
    expect(page.items, isEmpty);
    final parameters = adapter.requests.single.uri.queryParameters;
    expect(parameters['equipmentIds'], '');
    expect(parameters['muscles'], 'lats');
    expect(parameters, isNot(contains('muscleGroups')));
  });

  test('a pending preference mutation cannot replay after session invalidation',
      () async {
    final refreshStarted = Completer<void>();
    final refreshed = Completer<ResponseBody>();
    final adapter = _RecordingAdapter((options) {
      if (options.path == ApiEndpoints.refresh) {
        refreshStarted.complete();
        return refreshed.future;
      }
      return _json(401, {'message': 'Expired'});
    });
    ApiClient.instance.raw.httpClientAdapter = adapter;
    bool sessionCurrent = true;
    final repo = ApiTrainingRepository(isSessionCurrent: () => sessionCurrent);
    addTearDown(repo.dispose);
    final save = repo.saveEquipmentPreferences(
      revision: 0,
      equipmentProfiles: const [
        TrainingEquipmentProfile(id: 'home', name: 'Home', equipmentIds: []),
      ],
      activeEquipmentProfileId: 'home',
    );
    final assertion = expectLater(
      save,
      throwsA(
        isA<ApiException>().having(
          (error) => error.isCancelled,
          'cancelled',
          isTrue,
        ),
      ),
    );
    await refreshStarted.future;
    sessionCurrent = false;
    ApiClient.instance.invalidateSession();
    refreshed.complete(_json(200, sessionBody(accessToken: 'rotated')));
    await assertion;
    expect(adapter.requests.map((request) => request.path), [
      ApiEndpoints.trainingPreferences,
      ApiEndpoints.refresh,
    ]);
    final body = adapter.requests.first.data as Map<String, dynamic>;
    expect(body['revision'], 0);
    expect(body['activeEquipmentProfileId'], 'home');
  });
}
