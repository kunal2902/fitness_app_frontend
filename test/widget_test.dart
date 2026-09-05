import 'package:fitness_app/blocs/nutrition/food_search_bloc.dart';
import 'package:fitness_app/blocs/nutrition/meal_log_bloc.dart';
import 'package:fitness_app/blocs/nutrition/nutrition_summary_bloc.dart';
import 'package:fitness_app/services/nutrition_repository.dart';
import 'package:fitness_app/widgets/nutrition_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/nutrition_fakes.dart';

void main() {
  testWidgets(
      'nutrition providers persist per account, reset on switch and close on logout',
      (WidgetTester tester) async {
    final List<FakeNutritionRepository> repositories =
        <FakeNutritionRepository>[];
    late FoodSearchBloc search;
    late MealLogBloc logs;
    late NutritionSummaryBloc summary;
    Widget app(String? account) => MaterialApp(
          home: NutritionScope(
            sessionId: account,
            repositoryFactory: () {
              final FakeNutritionRepository repository =
                  FakeNutritionRepository();
              repositories.add(repository);
              return repository;
            },
            child: Builder(
              builder: (BuildContext context) {
                search = context.read<FoodSearchBloc>();
                logs = context.read<MealLogBloc>();
                summary = context.read<NutritionSummaryBloc>();
                expect(
                  context.read<NutritionRepository>(),
                  same(repositories.last),
                );
                return const Text('Nutrition child');
              },
            ),
          ),
        );

    await tester.pumpWidget(app('account-A'));
    final FoodSearchBloc firstSearch = search;
    final MealLogBloc firstLogs = logs;
    final NutritionSummaryBloc firstSummary = summary;
    expect(repositories.single.searches, isEmpty);
    expect(repositories.single.diaryReads, isEmpty);
    expect(repositories.single.summaryReads, isEmpty);
    await tester.pumpWidget(app('account-A'));
    expect(repositories, hasLength(1));
    expect(search, same(firstSearch));
    search.add(const FoodSearchChanged('rice'));
    await tester.pump();
    await tester.pumpWidget(app('account-B'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(repositories, hasLength(2));
    expect(repositories.first.disposed, isTrue);
    expect(firstSearch.isClosed, isTrue);
    expect(firstLogs.isClosed, isTrue);
    expect(firstSummary.isClosed, isTrue);
    expect(search, isNot(same(firstSearch)));
    expect(search.state, const FoodSearchState());
    await tester.pump(const Duration(seconds: 1));
    expect(repositories.first.searches, isEmpty);

    await tester.pumpWidget(app(null));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(repositories.last.disposed, isTrue);
    expect(search.isClosed, isTrue);
    expect(find.text('Nutrition child'), findsNothing);
  });
}
