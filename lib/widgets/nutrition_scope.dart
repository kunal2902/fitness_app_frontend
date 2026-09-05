import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/nutrition/food_search_bloc.dart';
import '../blocs/nutrition/meal_log_bloc.dart';
import '../blocs/nutrition/nutrition_summary_bloc.dart';
import '../services/api_nutrition_repository.dart';
import '../services/nutrition_repository.dart';

/// Lives below authentication and above the tab stack. Account changes replace
/// the entire scope; ordinary tab changes preserve its state. No automatic I/O.
class NutritionScope extends StatelessWidget {
  const NutritionScope({
    required this.sessionId,
    required this.child,
    this.repositoryFactory,
    super.key,
  });
  final String? sessionId;
  final Widget child;
  final NutritionRepository Function()? repositoryFactory;

  @override
  Widget build(BuildContext context) => sessionId == null
      ? const SizedBox.shrink()
      : _NutritionSession(
          key: ValueKey<String>(sessionId!),
          repositoryFactory: repositoryFactory ?? ApiNutritionRepository.new,
          child: child,
        );
}

class _NutritionSession extends StatefulWidget {
  const _NutritionSession({
    required this.repositoryFactory,
    required this.child,
    super.key,
  });
  final NutritionRepository Function() repositoryFactory;
  final Widget child;
  @override
  State<_NutritionSession> createState() => _NutritionSessionState();
}

class _NutritionSessionState extends State<_NutritionSession> {
  late final NutritionRepository _repository;
  late final FoodSearchBloc _search;
  late final MealLogBloc _logs;
  late final NutritionSummaryBloc _summary;

  @override
  void initState() {
    super.initState();
    _repository = widget.repositoryFactory();
    _search = FoodSearchBloc(repository: _repository);
    _logs = MealLogBloc(repository: _repository);
    _summary = NutritionSummaryBloc(repository: _repository);
  }

  @override
  Widget build(BuildContext context) =>
      RepositoryProvider<NutritionRepository>.value(
        value: _repository,
        child: MultiBlocProvider(
          // Not `<BlocProvider<dynamic>>`: BlocProvider is declared
          // `BlocProvider<T extends StateStreamableSource<Object?>>`, and
          // `dynamic` does not satisfy that bound — the analyzer rejects
          // the explicit type argument outright. Left to inference, the
          // literal takes MultiBlocProvider's own `List<SingleChildWidget>`
          // context, which is the correct type anyway.
          providers: [
            BlocProvider<FoodSearchBloc>.value(value: _search),
            BlocProvider<MealLogBloc>.value(value: _logs),
            BlocProvider<NutritionSummaryBloc>.value(value: _summary),
          ],
          child: widget.child,
        ),
      );

  @override
  void dispose() {
    // Mark handlers as closing before cancellation resolves their HTTP futures.
    unawaited(_search.close());
    unawaited(_logs.close());
    unawaited(_summary.close());
    _repository.dispose();
    super.dispose();
  }
}
