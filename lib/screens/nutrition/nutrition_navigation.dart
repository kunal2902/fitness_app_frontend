import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/nutrition/food_search_bloc.dart';
import '../../blocs/nutrition/meal_log_bloc.dart';
import '../../blocs/nutrition/nutrition_summary_bloc.dart';
import '../../services/nutrition_repository.dart';

/// Pushes a nutrition screen with the scope's blocs carried across.
///
/// This is not optional plumbing. `NutritionScope` provides the three blocs
/// and the repository *inside* the tab shell, but `Navigator.push` builds
/// the new route against the **Navigator's** context — which sits above the
/// shell. A pushed screen therefore cannot see any of them, and
/// `context.read<MealLogBloc>()` throws `ProviderNotFoundException` the
/// moment the search or picker screen builds.
///
/// So the providers are captured from the pushing context, where they are
/// in scope, and re-provided by value inside the route. `.value` and not
/// `create:` — these blocs belong to the scope and outlive the route; a
/// `create:` provider would close them when the screen pops and leave the
/// diary tab with three dead blocs.
Future<T?> pushNutritionRoute<T>(BuildContext context, Widget page) {
  final NutritionRepository repository = context.read<NutritionRepository>();
  final MealLogBloc logs = context.read<MealLogBloc>();
  final FoodSearchBloc search = context.read<FoodSearchBloc>();
  final NutritionSummaryBloc summary = context.read<NutritionSummaryBloc>();

  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      builder: (BuildContext _) =>
          RepositoryProvider<NutritionRepository>.value(
        value: repository,
        child: MultiBlocProvider(
          // No explicit type argument: BlocProvider's bound is
          // `T extends StateStreamableSource<Object?>`, so a written-out
          // `<BlocProvider<dynamic>>` does not satisfy it and fails to
          // compile. Inference lands on SingleChildWidget, which is what
          // MultiBlocProvider actually wants.
          providers: [
            BlocProvider<MealLogBloc>.value(value: logs),
            BlocProvider<FoodSearchBloc>.value(value: search),
            BlocProvider<NutritionSummaryBloc>.value(value: summary),
          ],
          child: page,
        ),
      ),
    ),
  );
}
