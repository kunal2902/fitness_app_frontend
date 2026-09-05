import 'dart:async';

import 'package:fitness_app/blocs/nutrition/food_search_bloc.dart';
import 'package:fitness_app/blocs/nutrition/meal_log_bloc.dart';
import 'package:fitness_app/blocs/nutrition/nutrition_status.dart';
import 'package:fitness_app/blocs/nutrition/nutrition_summary_bloc.dart';
import 'package:fitness_app/models/api_exception.dart';
import 'package:fitness_app/models/food_log.dart';
import 'package:fitness_app/models/nutrition_models.dart';
import 'package:fitness_app/services/nutrition_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/nutrition_fakes.dart';

Future<void> flushEvents() async {
  for (int i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeNutritionRepository repository;
  setUp(() {
    repository = FakeNutritionRepository();
  });
  tearDown(() {
    repository.dispose();
  });

  group('FoodSearchBloc', () {
    testWidgets('debounces 250 ms; only the latest input is requested',
        (WidgetTester tester) async {
      final FoodSearchBloc bloc = FoodSearchBloc(repository: repository);
      addTearDown(bloc.close);
      bloc.add(const FoodSearchChanged('r'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      bloc.add(const FoodSearchChanged(' rice '));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repository.searches, isEmpty);
      expect(bloc.state.isLoading, isTrue);
      await tester.pump(const Duration(milliseconds: 149));
      expect(repository.searches, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.searches, <String>['rice']);
      expect(bloc.state.foods, <Food>[sampleFood]);
      expect(bloc.state.status, FoodSearchStatus.success);
    });

    testWidgets(
        'immediately cancels HTTP and ignores late success during debounce',
        (WidgetTester tester) async {
      final Completer<FoodSearchResult> old = Completer<FoodSearchResult>();
      repository.onSearch = (String query) => query == 'rice'
          ? old.future
          : Future<FoodSearchResult>.value(
              (
                foods: <Food>[],
                query: query,
                catalogueEmpty: false,
                globalLookupUnavailable: false,
              ),
            );
      final FoodSearchBloc bloc = FoodSearchBloc(repository: repository);
      addTearDown(bloc.close);
      bloc.add(const FoodSearchChanged('rice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(repository.searches, <String>['rice']);
      bloc.add(const FoodSearchChanged('apple'));
      await tester.pump();
      expect(repository.searchTokens.first!.isCancelled, isTrue);
      old.complete(
        (
          foods: <Food>[sampleFood],
          query: 'rice',
          catalogueEmpty: false,
          globalLookupUnavailable: false,
        ),
      );
      await tester.pump();
      expect(bloc.state.query, 'apple');
      expect(bloc.state.foods, isEmpty);
      expect(bloc.state.status, FoodSearchStatus.debouncing);
      await tester.pump(const Duration(milliseconds: 250));
      expect(bloc.state.isEmpty, isTrue);
    });

    test('clearing input cancels request and ignores its late error', () async {
      final Completer<FoodSearchResult> pending = Completer<FoodSearchResult>();
      repository.onSearch = (_) => pending.future;
      final FoodSearchBloc bloc = FoodSearchBloc(
        repository: repository,
        debounceDuration: Duration.zero,
      );
      addTearDown(bloc.close);
      bloc.add(const FoodSearchChanged('rice'));
      await flushEvents();
      bloc.add(const FoodSearchChanged('   '));
      await flushEvents();
      pending.completeError(const ApiException.network());
      await flushEvents();
      expect(repository.searchTokens.single!.isCancelled, isTrue);
      expect(bloc.state, const FoodSearchState());
      expect(repository.searches, hasLength(1));
    });

    test('normalizes long queries and supports explicit retry after failure',
        () async {
      final FoodSearchBloc bloc = FoodSearchBloc(
        repository: repository,
        debounceDuration: Duration.zero,
      );
      addTearDown(bloc.close);
      repository.onSearch = (_) async => throw const ApiException.network();
      bloc.add(FoodSearchChanged(' ${'a' * 100} '));
      await flushEvents();
      expect(bloc.state.query.length, 80);
      expect(bloc.state.error!.code, 'NETWORK');
      repository.onSearch = null;
      bloc.add(FoodSearchChanged(bloc.state.query));
      await flushEvents();
      expect(bloc.state.status, FoodSearchStatus.success);
      expect(bloc.state.error, isNull);
    });

    test('wrong query echo is a failure, not a valid empty result', () async {
      repository.onSearch = (_) async => (
            foods: <Food>[],
            query: 'wrong',
            catalogueEmpty: false,
            globalLookupUnavailable: false,
          );
      final FoodSearchBloc bloc = FoodSearchBloc(
        repository: repository,
        debounceDuration: Duration.zero,
      );
      addTearDown(bloc.close);
      bloc.add(const FoodSearchChanged('rice'));
      await flushEvents();
      expect(bloc.state.error!.code, 'BAD_ENVELOPE');
      expect(bloc.state.isEmpty, isFalse);
    });

    test('close cancels debounce without starting a request', () async {
      final FoodSearchBloc bloc = FoodSearchBloc(repository: repository);
      bloc.add(const FoodSearchChanged('rice'));
      await flushEvents();
      await bloc.close();
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(repository.searches, isEmpty);
    });
  });

  group('MealLogBloc', () {
    test('preserves last good diary on same-day refresh failure', () async {
      final MealLogBloc bloc = MealLogBloc(repository: repository);
      addTearDown(bloc.close);
      repository.onList = (_) async => <FoodLog>[sampleLog()];
      bloc.add(const MealLogsRequested(diaryDay));
      await flushEvents();
      repository.onList = (_) async => throw const ApiException.network();
      bloc.add(const MealLogsRequested(diaryDay));
      await flushEvents();
      expect(bloc.state.status, NutritionLoadStatus.failure);
      expect(bloc.state.hasLoaded, isTrue);
      expect(bloc.state.logs, <FoodLog>[sampleLog()]);
      expect(() => bloc.state.logs.clear(), throwsUnsupportedError);
    });

    test('changing day ignores an out-of-order response', () async {
      final Completer<List<FoodLog>> old = Completer<List<FoodLog>>();
      repository.onList = (String date) => date == previousDiaryDay
          ? old.future
          : Future<List<FoodLog>>.value(<FoodLog>[sampleLog()]);
      final MealLogBloc bloc = MealLogBloc(repository: repository);
      addTearDown(bloc.close);
      bloc.add(const MealLogsRequested(previousDiaryDay));
      await flushEvents();
      bloc.add(const MealLogsRequested(diaryDay));
      await flushEvents();
      old.complete(<FoodLog>[sampleLog(date: previousDiaryDay)]);
      await flushEvents();
      expect(bloc.state.date, diaryDay);
      expect(bloc.state.logs.single.date, diaryDay);
    });

    test('failed create retains its draft and retries with the same clientId',
        () async {
      final MealLogBloc bloc = MealLogBloc(repository: repository);
      addTearDown(bloc.close);
      final MealLogDraft draft = sampleDraft();
      repository.onCreate = (_) async => throw const ApiException.timeout();
      bloc.add(MealLogCreateRequested(draft));
      await flushEvents();
      expect(bloc.state.mutation.canRetry, isTrue);
      expect(bloc.state.mutation.savedLog, isNull);
      repository.onCreate = (_) async => (log: sampleLog(), duplicate: true);
      bloc.add(const MealLogRetryRequested());
      await flushEvents();
      expect(repository.creates, <MealLogDraft>[draft, draft]);
      expect(bloc.state.mutation.status, NutritionWriteStatus.success);
      expect(bloc.state.mutation.duplicate, isTrue);
      expect(bloc.state.mutation.canRetry, isFalse);
    });

    test('double tap creates once; create/edit/delete share one queue',
        () async {
      final Completer<MealLogResult> first = Completer<MealLogResult>();
      repository.onCreate = (_) => first.future;
      final MealLogBloc bloc = MealLogBloc(repository: repository);
      addTearDown(bloc.close);
      final MealLogDraft draft = sampleDraft();
      bloc.add(MealLogCreateRequested(draft));
      bloc.add(MealLogCreateRequested(draft));
      bloc.add(
        MealLogUpdateRequested(
          MealLogEdit(logId: logId, originalDate: diaryDay, notes: 'Changed'),
        ),
      );
      bloc.add(const MealLogDeleteRequested(logId: logId, date: diaryDay));
      await flushEvents();
      expect(repository.creates, hasLength(1));
      expect(repository.updates, isEmpty);
      expect(repository.deletes, isEmpty);
      first.complete((log: sampleLog(), duplicate: false));
      await flushEvents();
      expect(repository.creates, hasLength(1));
      expect(repository.updates, hasLength(1));
      expect(repository.deletes, <String>[logId]);
      expect(bloc.state.mutation.deletedId, logId);
    });

    test('queue does not start another write after close', () async {
      final Completer<MealLogResult> pending = Completer<MealLogResult>();
      repository.onCreate = (_) => pending.future;
      final MealLogBloc bloc = MealLogBloc(repository: repository);
      bloc.add(MealLogCreateRequested(sampleDraft()));
      bloc.add(MealLogCreateRequested(sampleDraft(clientId: 'meal-2')));
      await flushEvents();
      final Future<void> closing = bloc.close();
      pending.complete((log: sampleLog(), duplicate: false));
      await flushEvents();
      await closing;
      expect(repository.creates, hasLength(1));
    });

    test('later queued success does not erase a failed meal or its retry ID',
        () async {
      final MealLogBloc bloc = MealLogBloc(repository: repository);
      addTearDown(bloc.close);
      final MealLogDraft first = sampleDraft();
      repository.onCreate = (MealLogDraft draft) async {
        if (draft.clientId == first.clientId) {
          throw const ApiException.network();
        }
        return (log: sampleLog(clientId: draft.clientId), duplicate: false);
      };
      bloc.add(MealLogCreateRequested(first));
      bloc.add(MealLogCreateRequested(sampleDraft(clientId: 'meal-2')));
      await flushEvents();
      expect(bloc.state.mutation.status, NutritionWriteStatus.success);
      expect(bloc.state.canRetry, isTrue);
      expect(
        bloc.state.failedMutations.single.operation,
        MealLogCreateRequested(first),
      );
      repository.onCreate = null;
      // A rebuilt form may reconstruct the draft with the same logical ID.
      bloc.add(
        MealLogRetryRequested(
          operation: MealLogCreateRequested(sampleDraft()),
        ),
      );
      await flushEvents();
      expect(
        repository.creates.map((MealLogDraft draft) => draft.clientId),
        <String>['meal-1', 'meal-2', 'meal-1'],
      );
      expect(bloc.state.failedMutations, isEmpty);
    });

    test('invalid dates and server validation keep actionable errors',
        () async {
      final MealLogBloc bloc = MealLogBloc(repository: repository);
      addTearDown(bloc.close);
      bloc.add(const MealLogsRequested('2026-02-30'));
      await flushEvents();
      expect(bloc.state.error!.fieldErrors, contains('date'));
      expect(repository.diaryReads, isEmpty);
      const ApiException validation = ApiException(
        message: 'Food unavailable',
        statusCode: 422,
        fieldErrors: <String, String>{
          'items.0.foodId': 'Choose another food',
        },
      );
      repository.onCreate = (_) async => throw validation;
      bloc.add(MealLogCreateRequested(sampleDraft()));
      await flushEvents();
      expect(bloc.state.mutation.error, same(validation));
    });
  });

  group('NutritionSummaryBloc and shared invalidation', () {
    test('create, edit and delete refresh both diary and summary', () async {
      final MealLogBloc logs = MealLogBloc(repository: repository);
      final NutritionSummaryBloc summary =
          NutritionSummaryBloc(repository: repository);
      addTearDown(logs.close);
      addTearDown(summary.close);
      logs.add(const MealLogsRequested(diaryDay));
      summary.add(const NutritionSummaryRequested(diaryDay));
      await flushEvents();
      logs.add(MealLogCreateRequested(sampleDraft()));
      await flushEvents();
      logs.add(
        MealLogUpdateRequested(
          MealLogEdit(
            logId: logId,
            originalDate: diaryDay,
            date: previousDiaryDay,
          ),
        ),
      );
      await flushEvents();
      logs.add(const MealLogDeleteRequested(logId: logId, date: diaryDay));
      await flushEvents();
      expect(repository.diaryReads, hasLength(4));
      expect(repository.summaryReads, hasLength(4));
      repository.notify(NutritionChange(dates: <String>{previousDiaryDay}));
      await flushEvents();
      expect(repository.diaryReads, hasLength(4));
      expect(repository.summaryReads, hasLength(4));
    });

    test('late summary errors cannot replace the new day', () async {
      final Completer<NutritionSummary> old = Completer<NutritionSummary>();
      repository.onSummary = (String date) => date == previousDiaryDay
          ? old.future
          : Future<NutritionSummary>.value(NutritionSummary.empty(date));
      final NutritionSummaryBloc bloc =
          NutritionSummaryBloc(repository: repository);
      addTearDown(bloc.close);
      bloc.add(const NutritionSummaryRequested(previousDiaryDay));
      await flushEvents();
      bloc.add(const NutritionSummaryRequested(diaryDay));
      await flushEvents();
      old.completeError(const ApiException.network());
      await flushEvents();
      expect(bloc.state.summary!.date, diaryDay);
      expect(bloc.state.error, isNull);
    });

    test('target saves refresh summary; failures preserve last good data',
        () async {
      final NutritionSummaryBloc bloc =
          NutritionSummaryBloc(repository: repository);
      addTearDown(bloc.close);
      bloc.add(const NutritionSummaryRequested(diaryDay));
      await flushEvents();
      expect(bloc.state.summary!.target, isNull);
      repository.onSummary = (String date) async =>
          NutritionSummary.empty(date, target: sampleTarget);
      bloc.add(
        const NutritionTargetsSubmitted(
          NutritionTargetEdit(
            kcal: 2000,
            proteinG: 100,
            carbsG: 250,
            fatG: 65,
          ),
        ),
      );
      await flushEvents();
      expect(repository.summaryReads, hasLength(2));
      expect(bloc.state.summary!.target, sampleTarget);
      expect(bloc.state.targetSave.status, NutritionWriteStatus.success);
      repository.onTargets =
          (_) async => throw ArgumentError.value(-1, 'kcal', 'Out of range');
      bloc.add(const NutritionTargetsSubmitted(NutritionTargetEdit(kcal: -1)));
      await flushEvents();
      expect(bloc.state.targetSave.error!.fieldErrors, contains('kcal'));
      expect(bloc.state.summary!.target, sampleTarget);
      repository.onSummary = (_) async => throw const ApiException.network();
      bloc.add(const NutritionSummaryRequested(diaryDay));
      await flushEvents();
      expect(bloc.state.status, NutritionLoadStatus.failure);
      expect(bloc.state.summary!.target, sampleTarget);
    });
  });
}
