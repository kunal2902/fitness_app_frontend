import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fitness_app/config/api_endpoints.dart';
import 'package:fitness_app/models/api_exception.dart';
import 'package:fitness_app/models/enums.dart';
import 'package:fitness_app/models/nutrition_models.dart';
import 'package:fitness_app/models/nutrition_target_setup.dart';
import 'package:fitness_app/services/api_client.dart';
import 'package:fitness_app/services/api_nutrition_repository.dart';
import 'package:fitness_app/services/nutrition_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/nutrition_fakes.dart';

Map<String, dynamic> logJson({
  String date = diaryDay,
  String clientId = 'meal-1',
}) =>
    <String, dynamic>{
      'id': logId,
      'date': date,
      'clientId': clientId,
      'mealType': 'lunch',
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'foodId': foodId,
          'grams': 100,
          'quantity': 100,
          'unitLabel': 'g',
          'snapshot': <String, dynamic>{
            'externalId': 'test:rice',
            'name': 'Test rice',
            'per100g': sampleMacros.toJson(),
            'sourceVersion': '1',
          },
          'macros': sampleMacros.toJson(),
        },
      ],
    };

Map<String, dynamic> savedMealJson({
  String id = 'cccccccccccccccccccccccc',
  String name = 'Regular lunch',
}) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'defaultMealType': 'lunch',
      'items': logJson()['items'],
      'totals': sampleMacros.toJson(),
      'useCount': 0,
    };

ResponseBody envelope(Map<String, dynamic> data) => ResponseBody.fromString(
      jsonEncode(<String, dynamic>{'success': true, 'data': data}),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );

ResponseBody errorResponse(int status, String code) => ResponseBody.fromString(
      jsonEncode(<String, dynamic>{'message': 'Test error', 'code': code}),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );

class NutritionHttpAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  Future<ResponseBody> Function(RequestOptions)? respond;
  int? expectedCount;
  final Completer<void> allStarted = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requests.length == expectedCount) allStarted.complete();
    if (respond != null) return respond!(options);
    switch ((options.method, options.path)) {
      case ('GET', ApiEndpoints.foodSearch):
        return envelope(<String, dynamic>{
          'foods': <Object>[],
          'query': options.queryParameters['q'],
        });
      case ('GET', ApiEndpoints.nutritionLogs):
        return envelope(<String, dynamic>{
          'logs': <Object>[],
          'date': options.queryParameters['date'],
        });
      case ('POST', ApiEndpoints.nutritionLogs):
        final Map<String, dynamic> body = options.data as Map<String, dynamic>;
        return envelope(<String, dynamic>{
          'log': logJson(
            date: body['date'] as String,
            clientId: body['clientId'] as String,
          ),
          'duplicate': false,
        });
      case ('GET', ApiEndpoints.savedMeals):
        return envelope(<String, dynamic>{
          'meals': <Map<String, dynamic>>[savedMealJson()],
        });
      case ('POST', ApiEndpoints.savedMeals):
        final Map<String, dynamic> body = options.data as Map<String, dynamic>;
        return envelope(<String, dynamic>{
          'meal': savedMealJson(name: body['name'] as String),
        });
      case ('POST', '/nutrition/saved-meals/cccccccccccccccccccccccc/log'):
        final Map<String, dynamic> body = options.data as Map<String, dynamic>;
        return envelope(<String, dynamic>{
          'log': <String, dynamic>{
            ...logJson(
              date: body['date'] as String,
              clientId: body['clientId'] as String,
            ),
            'mealType': body['mealType'],
          },
          'duplicate': false,
        });
      case ('GET', ApiEndpoints.nutritionSummary):
        return envelope(<String, dynamic>{
          'summary': <String, dynamic>{
            'date': options.queryParameters['date'],
            'totals': sampleMacros.toJson(),
            'meals': <Object>[],
            'target': null,
          },
        });
      case ('GET', ApiEndpoints.nutritionTargets):
        return envelope(<String, dynamic>{'target': null});
      case ('PATCH', ApiEndpoints.nutritionTargets):
        return envelope(
          <String, dynamic>{'target': sampleTarget.asMacros.toJson()},
        );
      case ('PATCH', _):
        final Map<String, dynamic> body = options.data as Map<String, dynamic>;
        return envelope(<String, dynamic>{
          'log': logJson(date: body['date'] as String? ?? diaryDay),
        });
      case ('DELETE', _):
        return envelope(<String, dynamic>{'deleted': true});
      default:
        return envelope(<String, dynamic>{
          'food': <String, dynamic>{
            'id': foodId,
            'externalId': 'test:rice',
            'name': 'Test rice',
            'per100g': sampleMacros.toJson(),
            'servings': <Object>[],
          },
        });
    }
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const NutritionTargetSetup setup = NutritionTargetSetup(
    age: 30,
    gender: Gender.male,
    heightCm: 175,
    weightKg: 70,
    activityLevel: NutritionActivityLevel.sedentary,
    goal: NutritionWeightGoal.maintain,
  );
  late NutritionHttpAdapter adapter;
  late HttpClientAdapter originalAdapter;
  late List<Interceptor> originalInterceptors;
  late ApiNutritionRepository repository;
  late List<NutritionChange> changes;
  late StreamSubscription<NutritionChange> subscription;

  setUp(() {
    final Dio dio = ApiClient.instance.raw;
    originalAdapter = dio.httpClientAdapter;
    originalInterceptors = dio.interceptors.toList();
    // Auth storage is independent of this contract test. Keep the real
    // ApiClient verb, error mapping, service serialization and model parsing.
    dio.interceptors.clear(keepImplyContentTypeInterceptor: false);
    adapter = NutritionHttpAdapter();
    dio.httpClientAdapter = adapter;
    repository = ApiNutritionRepository();
    changes = <NutritionChange>[];
    subscription = repository.changes.listen(changes.add);
  });
  tearDown(() async {
    await subscription.cancel();
    repository.dispose();
    final Dio dio = ApiClient.instance.raw;
    dio.httpClientAdapter = originalAdapter;
    dio.interceptors.clear(keepImplyContentTypeInterceptor: false);
    dio.interceptors.addAll(originalInterceptors);
  });

  test(
      'all nine operations use the existing service, correct verbs and cancellation tokens',
      () async {
    await repository.searchFoods(' rice ');
    expect((await repository.getFood('test:rice')).id, foodId);
    expect(await repository.listLogs(diaryDay), isEmpty);
    final MealLogResult saved = await repository.createLog(sampleDraft());
    expect(saved.log.clientId, 'meal-1');
    expect(saved.log.totals, sampleMacros);
    await repository.updateLog(
      MealLogEdit(
        logId: logId,
        originalDate: diaryDay,
        date: previousDiaryDay,
        clearNotes: true,
      ),
    );
    await repository.deleteLog(logId, date: previousDiaryDay);
    expect((await repository.summary(diaryDay)).totals, sampleMacros);
    expect(await repository.getTargets(), isNull);
    expect(
      await repository.updateTargets(const NutritionTargetEdit(kcal: 2000)),
      sampleTarget,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
        adapter.requests.map((RequestOptions r) => '${r.method} ${r.path}'),
        <String>[
          'GET /foods/search',
          'GET /foods/test:rice',
          'GET /nutrition/logs',
          'POST /nutrition/logs',
          'PATCH /nutrition/logs/$logId',
          'DELETE /nutrition/logs/$logId',
          'GET /nutrition/summary',
          'GET /nutrition/targets',
          'PATCH /nutrition/targets',
        ]);
    expect(
      adapter.requests.every((RequestOptions r) => r.cancelToken != null),
      isTrue,
    );
    final Map<String, dynamic> createBody =
        adapter.requests[3].data as Map<String, dynamic>;
    expect(createBody['clientId'], 'meal-1');
    expect((createBody['items'] as List).single, <String, dynamic>{
      'foodId': foodId,
      'grams': 100.0,
      'quantity': 100.0,
      'unitLabel': 'g',
    });
    expect(
      adapter.requests[4].data,
      <String, dynamic>{'date': previousDiaryDay, 'notes': null},
    );
    expect(adapter.requests.last.data, <String, dynamic>{'kcal': 2000.0});
    expect(changes, hasLength(4));
    expect(changes[0].dates, <String>{diaryDay});
    expect(changes[1].dates, <String>{diaryDay, previousDiaryDay});
    expect(changes[2].dates, <String>{previousDiaryDay});
    expect(changes[3].targetsChanged, isTrue);
  });

  test(
      'target preview uses the typed request, preserves cancellation and never invalidates saved data',
      () async {
    adapter.respond = (_) async => envelope(<String, dynamic>{
          'recommendation': <String, dynamic>{
            'setup': setup.toJson(),
            'target': sampleTarget.asMacros.toJson(),
            'bmrKcal': 1648.8,
            'tdeeKcal': 1978.5,
            'policyVersion': 'mifflin-v1-candidate-1',
            'reviewed': false,
            'warnings': <String>['Development preview'],
          },
        });
    final CancelToken token = CancelToken();
    final NutritionTargetRecommendation result =
        await repository.recommendTargets(
      setup,
      eligibilityConfirmed: true,
      cancelToken: token,
    );
    expect(result.setup, setup);
    expect(adapter.requests.single.path, ApiEndpoints.nutritionRecommendation);
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.cancelToken, same(token));
    expect(adapter.requests.single.data, <String, dynamic>{
      'setup': setup.toJson(),
      'eligibilityConfirmed': true,
    });
    expect(changes, isEmpty);
    adapter.respond = (_) async => envelope(<String, dynamic>{
          'target': <String, dynamic>{
            ...sampleTarget.asMacros.toJson(),
            'setup': setup.toJson(),
          },
        });
    final saved = await repository
        .updateTargets(const NutritionTargetEdit(kcal: 2000, setup: setup));
    expect(saved.setup, setup);
    expect((adapter.requests.last.data as Map)['setup'], setup.toJson());
  });

  test('saved meal endpoints preserve payloads and invalidate only reused day',
      () async {
    final saved = await repository.listSavedMeals();
    expect(saved.single.name, 'Regular lunch');

    final created = await repository.saveMealFromDiary(
      name: '  Workday lunch  ',
      sourceDate: diaryDay,
      sourceMealType: MealType.lunch,
    );
    expect(created.name, 'Workday lunch');
    await repository.deleteSavedMeal(saved.single.id);
    final result = await repository.logSavedMeal(
      mealId: saved.single.id,
      date: previousDiaryDay,
      mealType: MealType.dinner,
      clientId: 'reuse-1',
    );
    await Future<void>.delayed(Duration.zero);

    expect(result.log.date, previousDiaryDay);
    expect(result.log.mealType, MealType.dinner);
    expect(
      adapter.requests
          .map((RequestOptions request) => '${request.method} ${request.path}'),
      <String>[
        'GET /nutrition/saved-meals',
        'POST /nutrition/saved-meals',
        'DELETE /nutrition/saved-meals/${saved.single.id}',
        'POST /nutrition/saved-meals/${saved.single.id}/log',
      ],
    );
    expect(adapter.requests[1].data, <String, dynamic>{
      'name': 'Workday lunch',
      'sourceDate': diaryDay,
      'sourceMealType': 'lunch',
    });
    expect(adapter.requests[3].data, <String, dynamic>{
      'date': previousDiaryDay,
      'mealType': 'dinner',
      'clientId': 'reuse-1',
    });
    expect(changes, hasLength(1));
    expect(changes.single.dates, <String>{previousDiaryDay});
  });

  test(
      'target preview rejects missing consent, malformed responses and production review errors',
      () async {
    await expectLater(
      repository.recommendTargets(setup, eligibilityConfirmed: false),
      throwsA(isA<ApiException>()),
    );
    expect(adapter.requests, isEmpty);
    adapter.respond = (_) async =>
        envelope(<String, dynamic>{'recommendation': <String, dynamic>{}});
    await expectLater(
      repository.recommendTargets(setup, eligibilityConfirmed: true),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 'BAD_ENVELOPE'),
      ),
    );
    adapter.respond =
        (_) async => errorResponse(403, 'TARGET_POLICY_REVIEW_REQUIRED');
    await expectLater(
      repository.recommendTargets(setup, eligibilityConfirmed: true),
      throwsA(
        isA<ApiException>().having(
          (ApiException e) => e.code,
          'code',
          'TARGET_POLICY_REVIEW_REQUIRED',
        ),
      ),
    );
    expect(changes, isEmpty);
  });

  test('normalizes query, clamps limit, preserves caller cancellation token',
      () async {
    final CancelToken token = CancelToken();
    final FoodSearchResult result = await repository
        .searchFoods(' ${'a' * 100} ', limit: 100, cancelToken: token);
    expect(result.query.length, 80);
    expect(
      adapter.requests.single.queryParameters,
      <String, dynamic>{'q': 'a' * 80, 'limit': 50},
    );
    expect(adapter.requests.single.cancelToken, same(token));
    expect(() => result.foods.clear(), throwsUnsupportedError);
    await repository.searchFoods('  ');
    expect(adapter.requests, hasLength(1));
  });

  test('rejects mismatched search, diary and summary echoes', () async {
    adapter.respond = (_) async =>
        envelope(<String, dynamic>{'foods': <Object>[], 'query': 'wrong'});
    await expectLater(
      repository.searchFoods('rice'),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 'BAD_ENVELOPE'),
      ),
    );
    adapter.respond = (_) async => envelope(
          <String, dynamic>{'logs': <Object>[], 'date': previousDiaryDay},
        );
    await expectLater(
      repository.listLogs(diaryDay),
      throwsA(isA<ApiException>()),
    );
    adapter.respond = (_) async => envelope(<String, dynamic>{
          'logs': <Object>[logJson(date: previousDiaryDay)],
          'date': diaryDay,
        });
    await expectLater(
      repository.listLogs(diaryDay),
      throwsA(isA<ApiException>()),
    );
    adapter.respond = (_) async => envelope(<String, dynamic>{
          'summary': <String, dynamic>{'date': previousDiaryDay},
        });
    await expectLater(
      repository.summary(diaryDay),
      throwsA(isA<ApiException>()),
    );
  });

  test(
      'lost create response invalidates reads and retry sends identical clientId',
      () async {
    final MealLogDraft draft = sampleDraft();
    adapter.respond = (RequestOptions options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
    await expectLater(
      repository.createLog(draft),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 'TIMEOUT'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(changes.single.dates, <String>{diaryDay});
    adapter.respond = (_) async =>
        envelope(<String, dynamic>{'log': logJson(), 'duplicate': true});
    expect((await repository.createLog(draft)).duplicate, isTrue);
    expect(
      adapter.requests.map((RequestOptions r) => (r.data as Map)['clientId']),
      <String>['meal-1', 'meal-1'],
    );
  });

  test('only an already-deleted log 404 is treated as successful deletion',
      () async {
    adapter.respond = (_) async => errorResponse(404, 'NO_FOOD_LOG');
    await repository.deleteLog(logId, date: diaryDay);
    await Future<void>.delayed(Duration.zero);
    expect(changes, hasLength(1));
    adapter.respond = (_) async => errorResponse(404, 'ROUTE_NOT_FOUND');
    await expectLater(
      repository.deleteLog(logId, date: diaryDay),
      throwsA(isA<ApiException>()),
    );
    expect(changes, hasLength(1));
  });

  test('a mismatched saved meal is a failure and still reconciles the diary',
      () async {
    adapter.respond = (_) async => envelope(<String, dynamic>{
          'log': logJson(clientId: 'someone-else'),
          'duplicate': false,
        });
    await expectLater(
      repository.createLog(sampleDraft()),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 'BAD_ENVELOPE'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(changes.single.dates, <String>{diaryDay});
  });

  test('bad drafts, dates and targets never issue HTTP requests', () async {
    expect(() => sampleDraft(clientId: ' '), throwsArgumentError);
    await expectLater(repository.listLogs('2026-02-30'), throwsArgumentError);
    await expectLater(
      repository.updateTargets(const NutritionTargetEdit(kcal: -1)),
      throwsArgumentError,
    );
    await expectLater(
      repository.updateLog(MealLogEdit(logId: logId, originalDate: diaryDay)),
      throwsArgumentError,
    );
    expect(adapter.requests, isEmpty);
    expect(changes, isEmpty);
  });

  test('disposal cancels read/write requests and prevents any new network work',
      () async {
    final Completer<ResponseBody> pending = Completer<ResponseBody>();
    adapter.respond = (_) => pending.future;
    adapter.expectedCount = 9;
    final List<Future<Object?>> requests = <Future<Object?>>[
      repository.searchFoods('rice'),
      repository.getFood(foodId),
      repository.listLogs(diaryDay),
      repository.createLog(sampleDraft()),
      repository.updateLog(
        MealLogEdit(logId: logId, originalDate: diaryDay, notes: 'edit'),
      ),
      repository.deleteLog(logId, date: diaryDay),
      repository.summary(diaryDay),
      repository.getTargets(),
      repository.updateTargets(const NutritionTargetEdit(kcal: 2000)),
    ];
    final Future<void> errors = Future.wait(
      requests.map(
        (Future<Object?> request) => expectLater(
          request,
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.isCancelled,
              'cancelled',
              isTrue,
            ),
          ),
        ),
      ),
    );
    await adapter.allStarted.future.timeout(const Duration(seconds: 3));
    expect(adapter.requests, hasLength(9));
    repository.dispose();
    await errors;
    expect(
      adapter.requests.every((RequestOptions r) => r.cancelToken!.isCancelled),
      isTrue,
    );
    pending.complete(envelope(<String, dynamic>{}));
    await expectLater(
      repository.summary(diaryDay),
      throwsA(isA<ApiException>()),
    );
    expect(adapter.requests, hasLength(9));
    expect(changes, isEmpty);
  });

  test('account guard rejects a late response before the next widget frame',
      () async {
    bool current = true;
    final ApiNutritionRepository guarded =
        ApiNutritionRepository(isSessionCurrent: () => current);
    addTearDown(guarded.dispose);
    final Completer<ResponseBody> pending = Completer<ResponseBody>();
    adapter.respond = (_) => pending.future;
    final Future<FoodSearchResult> request = guarded.searchFoods('rice');
    final Future<void> check = expectLater(
      request,
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.isCancelled, 'cancelled', isTrue),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    current = false;
    pending.complete(
      envelope(<String, dynamic>{'foods': <Object>[], 'query': 'rice'}),
    );
    await check;
    final int count = adapter.requests.length;
    await expectLater(
      guarded.createLog(sampleDraft()),
      throwsA(isA<ApiException>()),
    );
    expect(adapter.requests, hasLength(count));
    expect(() => guarded.newClientId(), throwsA(isA<ApiException>()));
  });
}
