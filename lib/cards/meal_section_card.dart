import 'package:flutter/material.dart';

import '../models/food_log.dart';
import '../models/nutrition_models.dart';
import '../theme/app_theme.dart';
import '../utils/nutrition_math.dart';
import '../widgets/section_card.dart';

/// One meal's entries, with the meal's running total in the header.
///
/// Renders even when empty, so all four meals are always visible in the
/// same order — a diary that reflows as you fill it in is harder to scan
/// than one with four fixed slots, and the empty row doubles as the "add
/// something here" affordance.
class MealSectionCard extends StatelessWidget {
  const MealSectionCard({
    required this.mealType,
    required this.logs,
    required this.onAdd,
    required this.onEditItem,
    required this.onDeleteLog,
    super.key,
  });

  /// Null renders the "Other" bucket — entries whose meal type this build
  /// does not recognise. They are shown rather than hidden, because they
  /// are the user's data and they still count towards the day.
  final MealType? mealType;

  final List<FoodLog> logs;
  final VoidCallback onAdd;
  final void Function(FoodLog log, int itemIndex) onEditItem;
  final void Function(FoodLog log) onDeleteLog;

  String get _title => mealType?.label ?? 'Other';

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Macros totals = NutritionMath.sumMacros(
      logs.expand((FoodLog log) => log.items).map((FoodLogItem i) => i.macros),
    );
    final bool isEmpty = logs.isEmpty;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleMedium,
                ),
              ),
              if (!isEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: Text(
                    '${totals.kcal.round()} kcal',
                    style: context.text.bodyMedium
                        ?.copyWith(color: palette.textSecondary),
                  ),
                ),
              IconButton(
                onPressed: onAdd,
                tooltip: 'Add to $_title',
                icon: const Icon(Icons.add_rounded),
                color: palette.accent,
                constraints:
                    const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ),
          if (isEmpty)
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xxs,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                'Nothing logged yet',
                style: context.text.bodySmall
                    ?.copyWith(color: palette.textTertiary),
              ),
            )
          else
            for (final FoodLog log in logs)
              for (final (int index, FoodLogItem item) in log.items.indexed)
                _EntryRow(
                  log: log,
                  item: item,
                  // A log can hold several foods. Deleting removes the
                  // whole entry, so say so rather than implying one row
                  // will go.
                  isOnlyItem: log.items.length == 1,
                  onEdit: () => onEditItem(log, index),
                  onDelete: () => onDeleteLog(log),
                ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.log,
    required this.item,
    required this.isOnlyItem,
    required this.onEdit,
    required this.onDelete,
  });

  final FoodLog log;
  final FoodLogItem item;
  final bool isOnlyItem;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return InkWell(
      onTap: onEdit,
      borderRadius: AppRadius.rSm,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.portionLabel} · ${item.grams.round()} g',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall
                        ?.copyWith(color: palette.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '${item.macros.kcal.round()}',
              style: context.text.bodyMedium
                  ?.copyWith(color: palette.textSecondary),
            ),
            PopupMenuButton<_EntryAction>(
              tooltip: 'Entry options',
              icon: Icon(
                Icons.more_vert_rounded,
                size: AppSize.iconMd,
                color: palette.textTertiary,
              ),
              onSelected: (_EntryAction action) => switch (action) {
                _EntryAction.edit => onEdit(),
                _EntryAction.delete => onDelete(),
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<_EntryAction>>[
                const PopupMenuItem<_EntryAction>(
                  value: _EntryAction.edit,
                  child: Text('Edit portion'),
                ),
                PopupMenuItem<_EntryAction>(
                  value: _EntryAction.delete,
                  child: Text(
                    isOnlyItem
                        ? 'Delete'
                        : 'Delete all ${log.items.length} foods',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _EntryAction { edit, delete }
