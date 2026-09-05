import 'dart:async';

import 'package:fitness_app/blocs/nutrition/food_search_bloc.dart';
import 'package:fitness_app/blocs/nutrition/meal_log_bloc.dart';
import 'package:fitness_app/blocs/nutrition/nutrition_summary_bloc.dart';
import 'package:fitness_app/models/api_exception.dart';
import 'package:fitness_app/models/nutrition_models.dart';
import 'package:fitness_app/screens/nutrition/food_search_screen.dart';
import 'package:fitness_app/screens/nutrition/portion_picker_screen.dart';
import 'package:fitness_app/services/nutrition_repository.dart';
import 'package:fitness_app/theme/app_theme.dart';
import 'package:fitness_app/widgets/quantity_stepper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/nutrition_fakes.dart';

void main() {
  Future<FakeNutritionRepository> openSearch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final FakeNutritionRepository repository = FakeNutritionRepository();
    final FoodSearchBloc search = FoodSearchBloc(repository: repository);
    final MealLogBloc logs = MealLogBloc(repository: repository);
    final NutritionSummaryBloc summary =
        NutritionSummaryBloc(repository: repository);
    addTearDown(() async {
      await search.close();
      await logs.close();
      await summary.close();
      repository.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RepositoryProvider<NutritionRepository>.value(
          value: repository,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<FoodSearchBloc>.value(value: search),
              BlocProvider<MealLogBloc>.value(value: logs),
              BlocProvider<NutritionSummaryBloc>.value(value: summary),
            ],
            child: const FoodSearchScreen(
              date: diaryDay,
              mealType: MealType.breakfast,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return repository;
  }

  Future<void> searchRice(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'rice');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  }

  Future<void> openPortion(WidgetTester tester) async {
    await searchRice(tester);
    await tester.tap(find.text('Test rice'));
    await tester.pumpAndSettle();
  }

  testWidgets('search navigation retains providers and portion macros double',
      (WidgetTester tester) async {
    final FakeNutritionRepository repository = await openSearch(tester);
    await openPortion(tester);
    expect(find.byType(PortionPickerScreen), findsOneWidget);
    expect(find.text('1 × 100 g = 100 g'), findsOneWidget);
    expect(find.text('130'), findsOneWidget);
    final Finder increase = find.descendant(
      of: find.byType(QuantityStepper),
      matching: find.byIcon(Icons.add_rounded),
    );
    await tester.tap(increase);
    await tester.pump();
    await tester.tap(increase);
    await tester.pump();
    expect(find.text('2 × 100 g = 200 g'), findsOneWidget);
    expect(find.text('260'), findsOneWidget);
    expect(repository.creates, isEmpty);
  });

  testWidgets('search failure retries and empty results never fabricate food',
      (WidgetTester tester) async {
    final FakeNutritionRepository repository = await openSearch(tester);
    repository.onSearch = (_) async => throw const ApiException.network();
    await searchRice(tester);
    expect(find.text('Search failed'), findsOneWidget);
    repository.onSearch = (String query) async => (
          foods: <Food>[],
          query: query,
          catalogueEmpty: false,
          globalLookupUnavailable: false,
        );
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('No matches for "rice"'), findsOneWidget);
    expect(repository.creates, isEmpty);
  });

  testWidgets('global catalogue outage is not presented as a spelling miss',
      (WidgetTester tester) async {
    final FakeNutritionRepository repository = await openSearch(tester);
    repository.onSearch = (String query) async => (
          foods: <Food>[],
          query: query,
          catalogueEmpty: false,
          globalLookupUnavailable: true,
        );
    await searchRice(tester);
    expect(find.text('Global food search is unavailable'), findsOneWidget);
    expect(find.text('No matches for "rice"'), findsNothing);
  });

  testWidgets(
      'failed meal save keeps the portion form open for correction and retry',
      (WidgetTester tester) async {
    final FakeNutritionRepository repository = await openSearch(tester);
    final Completer<MealLogResult> pending = Completer<MealLogResult>();
    repository.onCreate = (_) => pending.future;
    await openPortion(tester);
    await tester.tap(find.text('Add to breakfast'));
    await tester.pump();
    final bool stayedOpenWhileSaving =
        find.byType(PortionPickerScreen).evaluate().isNotEmpty;
    pending.completeError(const ApiException.network());
    await tester.pumpAndSettle();
    expect(repository.creates, hasLength(1));
    expect(
      stayedOpenWhileSaving,
      isTrue,
      reason:
          'A submitted draft is not a confirmed save; the editor must not close yet.',
    );
    expect(find.byType(PortionPickerScreen), findsOneWidget);
    expect(find.text('1 × 100 g = 100 g'), findsOneWidget);
    final String firstClientId = repository.creates.single.clientId;
    repository.onCreate = (_) async => (
          log: sampleLog(clientId: firstClientId),
          duplicate: false,
        );
    await tester.tap(find.text('Add to breakfast'));
    await tester.pumpAndSettle();
    expect(repository.creates, hasLength(2));
    expect(repository.creates.last.clientId, firstClientId);
    expect(find.byType(PortionPickerScreen), findsNothing);
  });

  testWidgets('editing a failed create starts a new idempotent meal',
      (WidgetTester tester) async {
    final FakeNutritionRepository repository = await openSearch(tester);
    repository.onCreate = (_) async => throw const ApiException.network();
    await openPortion(tester);
    await tester.tap(find.text('Add to breakfast'));
    await tester.pumpAndSettle();
    final String failedClientId = repository.creates.single.clientId;
    final Finder increase = find.descendant(
      of: find.byType(QuantityStepper),
      matching: find.byIcon(Icons.add_rounded),
    );
    await tester.tap(increase);
    await tester.pump();
    repository.onCreate = (MealLogDraft draft) async => (
          log: sampleLog(clientId: draft.clientId),
          duplicate: false,
        );
    await tester.tap(find.text('Add to breakfast'));
    await tester.pumpAndSettle();
    expect(repository.creates, hasLength(2));
    expect(repository.creates.last.clientId, isNot(failedClientId));
    expect(repository.creates.last.items.single.grams, 150);
    expect(find.byType(PortionPickerScreen), findsNothing);
  });
}
