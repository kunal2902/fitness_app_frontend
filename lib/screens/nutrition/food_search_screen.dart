import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/nutrition/food_search_bloc.dart';
import '../../blocs/nutrition/meal_log_bloc.dart';
import '../../blocs/nutrition/nutrition_status.dart';
import '../../cards/food_result_tile.dart';
import '../../models/nutrition_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';
import 'nutrition_navigation.dart';
import 'portion_picker_screen.dart';
import 'saved_meals_screen.dart';

/// Find a food and open its portion picker.
///
/// Search is a `restartable` bloc with the debounce inside the handler, so
/// every keystroke cancels the previous request rather than queueing
/// behind it. This screen therefore does nothing clever — it types into
/// the bloc and renders what comes back.
class FoodSearchScreen extends StatefulWidget {
  const FoodSearchScreen({
    required this.date,
    required this.mealType,
    super.key,
  });

  final String date;
  final MealType? mealType;

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  final TextEditingController _controller = TextEditingController();

  /// The last results that actually arrived.
  ///
  /// The bloc emits a *fresh* state on both the debouncing and loading
  /// transitions, so `state.foods` is empty for the whole debounce +
  /// request window. Rendering that directly blanks the list on every
  /// keystroke — the screen flickers empty as you type. Holding the last
  /// success here keeps the rows on screen while the next one runs.
  List<Food> _lastResults = const <Food>[];
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    // The bloc is session-scoped and outlives this screen, so it still
    // holds the previous search. Without this reset the screen opens with
    // an empty field listing the results of whatever was searched last.
    context.read<FoodSearchBloc>().add(const FoodSearchChanged(''));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(Food food) {
    // A food with no servings has nothing to pick, and DraftLogItem would
    // refuse it anyway. Stop here with a reason rather than opening a
    // picker that cannot submit.
    if (!food.hasServings) {
      AppSnackbar.error(
        context,
        '${food.name} has no portion sizes yet, so it cannot be logged.',
      );
      return;
    }

    unawaited(
      pushNutritionRoute<void>(
        context,
        PortionPickerScreen(
          date: widget.date,
          mealType: widget.mealType,
          food: food,
        ),
      ),
    );
  }

  Future<void> _openSavedMeals() async {
    final String? message = await pushNutritionRoute<String>(
      context,
      SavedMealsScreen(date: widget.date, mealType: widget.mealType),
    );
    if (message != null && mounted) AppSnackbar.success(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: Text(
          widget.mealType == null
              ? 'Add food'
              : 'Add to ${widget.mealType!.label.toLowerCase()}',
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _openSavedMeals,
            icon: const Icon(Icons.bookmarks_outlined),
            label: const Text('Saved meals'),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      // Confirmation lives here, not on the summary screen: the user is
      // sent straight back after adding, and a snackbar fired from a screen
      // that is being popped never appears.
      body: BlocListener<MealLogBloc, MealLogState>(
        // Status as well as revision: the bloc reuses one revision for
        // the saving emission and the terminal one, so revision alone
        // never sees success or failure.
        listenWhen: (MealLogState a, MealLogState b) =>
            a.mutation.revision != b.mutation.revision ||
            a.mutation.status != b.mutation.status,
        listener: _onMutation,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: _SearchField(
                controller: _controller,
                onChanged: (String value) => context
                    .read<FoodSearchBloc>()
                    .add(FoodSearchChanged(value)),
                onClear: () {
                  _controller.clear();
                  context.read<FoodSearchBloc>().add(
                        const FoodSearchChanged(''),
                      );
                },
              ),
            ),
            Expanded(
              child: BlocBuilder<FoodSearchBloc, FoodSearchState>(
                builder: (BuildContext context, FoodSearchState state) =>
                    _results(state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onMutation(BuildContext context, MealLogState state) {
    final MealLogMutationState mutation = state.mutation;

    // Creates only. The diary screen is still mounted below this one and
    // reports edits and deletes; without the split, one save would raise
    // the same snackbar from both listeners.
    if (mutation.operation is! MealLogCreateRequested) return;

    switch (mutation.status) {
      case NutritionWriteStatus.success:
        AppSnackbar.success(
          context,
          // `duplicate` is not an error: the idempotency key did its job
          // and the server returned the entry it already had.
          mutation.duplicate ? 'Already logged' : 'Added to your diary',
        );
      case NutritionWriteStatus.failure:
        // Resolved before the snackbar is shown: it outlives this route,
        // so the context may be defunct by the time Retry is tapped.
        final MealLogBloc bloc = context.read<MealLogBloc>();
        final MealLogMutation? operation = mutation.operation;
        AppSnackbar.show(
          context,
          mutation.error?.message ?? 'Could not save that.',
          kind: SnackKind.error,
          actionLabel: 'Retry',
          onAction: () {
            if (bloc.isClosed || operation == null) return;
            bloc.add(MealLogRetryRequested(operation: operation));
          },
        );
      case NutritionWriteStatus.initial:
      case NutritionWriteStatus.saving:
        break;
    }
  }

  Widget _results(FoodSearchState state) {
    final AppPalette palette = context.palette;

    if (state.status == FoodSearchStatus.success) {
      _lastResults = state.foods;
      _lastQuery = state.query;
    } else if (state.status == FoodSearchStatus.initial) {
      _lastResults = const <Food>[];
      _lastQuery = '';
    }

    if (state.status == FoodSearchStatus.initial && _lastResults.isEmpty) {
      return const _SearchHint();
    }

    if (state.status == FoodSearchStatus.failure) {
      return _SearchMessage(
        icon: Icons.wifi_off_rounded,
        title: 'Search failed',
        message: state.error?.message ?? 'Please try again.',
        action: OutlinedButton(
          onPressed: () => context
              .read<FoodSearchBloc>()
              .add(FoodSearchChanged(state.query)),
          child: const Text('Try again'),
        ),
      );
    }

    if (state.isEmpty) {
      if (state.globalLookupUnavailable) {
        return _SearchMessage(
          icon: Icons.cloud_off_rounded,
          title: 'Global food search is unavailable',
          message: 'The local database had no match and the server could not '
              'reach the global food catalogue. Check the backend connection '
              'and try again.',
          action: OutlinedButton(
            onPressed: () => context
                .read<FoodSearchBloc>()
                .add(FoodSearchChanged(state.query)),
            child: const Text('Try again'),
          ),
        );
      }
      // Two very different failures that look identical from here. Telling
      // someone to "try a shorter word" when the food database was never
      // imported sends them hunting for a spelling that does not exist.
      if (state.catalogueEmpty) {
        return const _SearchMessage(
          icon: Icons.inventory_2_outlined,
          title: 'No food data loaded',
          message: 'The food database has not been imported on the server '
              'yet, so nothing can be found. Run the catalogue import and '
              'try again.',
        );
      }
      return _SearchMessage(
        icon: Icons.search_off_rounded,
        title: 'No matches for "${state.query}"',
        message: 'Try the English name, or a shorter word.',
      );
    }

    // Still typing, and nothing has come back yet for any query.
    if (_lastResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Keep the previous results visible while the next request runs.
    // Blanking the list on every keystroke makes typing feel like the app
    // is fighting you.
    return Stack(
      children: <Widget>[
        ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          itemCount: _lastResults.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            thickness: 1,
            indent: AppSpacing.lg,
            endIndent: AppSpacing.lg,
            color: palette.border,
          ),
          itemBuilder: (BuildContext context, int index) {
            final Food food = _lastResults[index];
            return FoodResultTile(
              food: food,
              // The query these results are FOR, not the one being typed —
              // otherwise the alias hint highlights against a string the
              // rows were never matched on.
              query: _lastQuery,
              onTap: () => _open(food),
            );
          },
        ),
        if (state.isLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
            ),
          ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      autofocus: true,
      textInputAction: TextInputAction.search,
      style: context.text.bodyLarge,
      decoration: InputDecoration(
        hintText: 'Search foods — try oats, paneer, Greek yogurt',
        prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (BuildContext context, TextEditingValue value, Widget? _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              onPressed: onClear,
              tooltip: 'Clear',
              icon: Icon(Icons.close_rounded, color: palette.textTertiary),
            );
          },
        ),
        filled: true,
        fillColor: palette.surface,
        border: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: palette.accent),
        ),
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.restaurant_menu_rounded,
              size: 40,
              color: palette.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('What did you eat?', style: context.text.titleMedium),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Search in English or by the name you use — poha, bhindi, '
              'jeera and dahi all work.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall
                  ?.copyWith(color: palette.textTertiary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: palette.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.text.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.text.bodySmall
                  ?.copyWith(color: palette.textTertiary, height: 1.5),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
