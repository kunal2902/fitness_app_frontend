import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/nutrition_models.dart';
import '../../models/saved_meal.dart';
import '../../services/nutrition_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';

/// Lists the member's reusable meal templates and logs one to [date].
class SavedMealsScreen extends StatefulWidget {
  const SavedMealsScreen({
    required this.date,
    required this.mealType,
    super.key,
  });

  final String date;
  final MealType? mealType;

  @override
  State<SavedMealsScreen> createState() => _SavedMealsScreenState();
}

class _SavedMealsScreenState extends State<SavedMealsScreen> {
  late final NutritionRepository _repository;
  late Future<List<SavedMeal>> _request;
  final Set<String> _busyMeals = <String>{};
  final Map<String, String> _clientIds = <String, String>{};

  @override
  void initState() {
    super.initState();
    _repository = context.read<NutritionRepository>();
    _request = _repository.listSavedMeals();
  }

  void _reload() {
    setState(() => _request = _repository.listSavedMeals());
  }

  Future<MealType?> _chooseMealType(SavedMeal meal) async {
    if (widget.mealType != null) return widget.mealType;
    return showModalBottomSheet<MealType>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'Add ${meal.name} to…',
                style: context.text.titleMedium,
              ),
            ),
            for (final MealType type in MealType.values)
              ListTile(
                leading: Icon(
                  type == meal.defaultMealType
                      ? Icons.star_rounded
                      : Icons.restaurant_rounded,
                ),
                title: Text(type.label),
                subtitle: type == meal.defaultMealType
                    ? const Text('Usual meal')
                    : null,
                onTap: () => Navigator.of(context).pop(type),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _use(SavedMeal meal) async {
    final MealType? mealType = await _chooseMealType(meal);
    if (mealType == null || !mounted) return;
    final String operationKey =
        '${meal.id}:${widget.date}:${mealType.apiValue}';
    if (_busyMeals.contains(operationKey)) return;
    final String clientId = _clientIds.putIfAbsent(
      operationKey,
      _repository.newClientId,
    );
    setState(() => _busyMeals.add(operationKey));
    try {
      final MealLogResult result = await _repository.logSavedMeal(
        mealId: meal.id,
        date: widget.date,
        mealType: mealType,
        clientId: clientId,
      );
      _clientIds.remove(operationKey);
      if (!mounted) return;
      Navigator.of(context).pop(
        result.duplicate
            ? '${meal.name} was already added'
            : '${meal.name} added to ${mealType.label.toLowerCase()}',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyMeals.remove(operationKey));
      AppSnackbar.show(
        context,
        nutritionFailure(error).message,
        kind: SnackKind.error,
        actionLabel: 'Retry',
        onAction: () => _use(meal),
      );
    }
  }

  Future<void> _delete(SavedMeal meal) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete saved meal?'),
        content: Text(
          '${meal.name} will be removed from saved meals. '
          'Food already logged in your diary will not change.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busyMeals.contains(meal.id)) return;
    setState(() => _busyMeals.add(meal.id));
    try {
      await _repository.deleteSavedMeal(meal.id);
      if (!mounted) return;
      setState(() {
        _busyMeals.remove(meal.id);
        _request = _repository.listSavedMeals();
      });
      AppSnackbar.success(context, '${meal.name} deleted');
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyMeals.remove(meal.id));
      AppSnackbar.error(context, nutritionFailure(error).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.bg,
      appBar: AppBar(title: const Text('Saved meals')),
      body: FutureBuilder<List<SavedMeal>>(
        future: _request,
        builder:
            (BuildContext context, AsyncSnapshot<List<SavedMeal>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _SavedMealsMessage(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load saved meals',
              message: nutritionFailure(snapshot.error!).message,
              action: OutlinedButton(
                onPressed: _reload,
                child: const Text('Try again'),
              ),
            );
          }
          final List<SavedMeal> meals = snapshot.data ?? const <SavedMeal>[];
          if (meals.isEmpty) {
            return const _SavedMealsMessage(
              icon: Icons.bookmark_border_rounded,
              title: 'No saved meals yet',
              message: 'Open a meal in your diary and tap the bookmark icon '
                  'to save all of its foods for another day.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              final Future<List<SavedMeal>> next = _repository.listSavedMeals();
              setState(() => _request = next);
              await next;
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: meals.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (BuildContext context, int index) {
                final SavedMeal meal = meals[index];
                final bool busy = _busyMeals.any(
                  (String key) =>
                      key == meal.id || key.startsWith('${meal.id}:'),
                );
                return _SavedMealCard(
                  meal: meal,
                  busy: busy,
                  destination: widget.mealType,
                  onUse: () => _use(meal),
                  onDelete: () => _delete(meal),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SavedMealCard extends StatelessWidget {
  const _SavedMealCard({
    required this.meal,
    required this.busy,
    required this.destination,
    required this.onUse,
    required this.onDelete,
  });

  final SavedMeal meal;
  final bool busy;
  final MealType? destination;
  final VoidCallback onUse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Card(
      color: palette.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.rMd,
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    meal.name,
                    style: context.text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : onDelete,
                  tooltip: 'Delete ${meal.name}',
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            Text(
              meal.itemSummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: palette.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${meal.totals.kcal.round()} kcal  ·  '
              'P ${meal.totals.proteinG.round()}g  ·  '
              'C ${meal.totals.carbsG.round()}g  ·  '
              'F ${meal.totals.fatG.round()}g',
              style: context.text.labelMedium?.copyWith(
                color: palette.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: busy ? null : onUse,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
                label: Text(
                  destination == null
                      ? 'Add to diary'
                      : 'Add to ${destination!.label.toLowerCase()}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedMealsMessage extends StatelessWidget {
  const _SavedMealsMessage({
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 42, color: context.palette.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: context.text.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: context.palette.textTertiary,
                height: 1.5,
              ),
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
