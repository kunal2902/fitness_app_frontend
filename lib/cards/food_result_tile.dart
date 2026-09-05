import 'package:flutter/material.dart';

import '../models/nutrition_models.dart';
import '../theme/app_theme.dart';

/// A food in the search results.
///
/// Leads with the name, then the two things that decide whether this is
/// the right row: what one portion of it costs in energy, and — for an
/// Indian corpus where the English name is often not the one the user
/// thinks in — the local names that matched. "Rice flakes" means nothing
/// to someone who typed `poha`; showing the alias is what closes that gap.
class FoodResultTile extends StatelessWidget {
  const FoodResultTile({
    required this.food,
    required this.onTap,
    this.query = '',
    super.key,
  });

  final Food food;
  final VoidCallback onTap;

  /// Used to surface the alias that actually matched, rather than the
  /// first of the eleven a food typically carries.
  final String query;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final double? kcal = food.kcalPerDefaultServing;
    final FoodServing? serving = food.defaultServing;
    final String? alias = _matchingAlias();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    food.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyLarge,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      if (food.isRecipe) ...<Widget>[
                        _Chip(
                          label: 'Dish',
                          tint: palette.accent,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                      ],
                      Flexible(
                        child: Text(
                          alias ?? food.group,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall
                              ?.copyWith(color: palette.textTertiary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // A food with no servings cannot be logged at all — say so
            // here rather than letting the user tap through to a picker
            // that has nothing to pick.
            if (kcal == null || serving == null)
              Text(
                'No portions',
                style: context.text.bodySmall
                    ?.copyWith(color: palette.textTertiary),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '${kcal.round()} kcal',
                    style: context.text.bodyMedium
                        ?.copyWith(color: palette.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    serving.label,
                    style: context.text.bodySmall
                        ?.copyWith(color: palette.textTertiary),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// The alias containing the query, if any. Falls back to null so the
  /// caller shows the food group instead of an arbitrary Kannada name.
  String? _matchingAlias() {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) return null;
    // Already obvious from the title.
    if (food.name.toLowerCase().contains(needle)) return null;

    for (final FoodAlias alias in food.aliases) {
      if (alias.name.toLowerCase().contains(needle)) return alias.name;
    }
    return null;
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: AppRadius.rXs,
      ),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: tint,
          fontSize: 10,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
