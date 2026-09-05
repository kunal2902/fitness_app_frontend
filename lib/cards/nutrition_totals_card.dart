import 'package:flutter/material.dart';

import '../models/food_log.dart';
import '../utils/diary_date.dart';
import '../theme/app_theme.dart';
import '../widgets/kcal_ring.dart';
import '../widgets/macro_meter.dart';
import '../widgets/section_card.dart';

/// The day at a glance: energy against target, then the three macros.
///
/// Reads the totals straight off the server's summary rather than
/// recomputing them from the visible entries. The two can legitimately
/// differ for a moment — a save is in flight, a refresh has not landed —
/// and showing a locally-summed number that disagrees with the server's is
/// worse than showing a slightly stale one, because the user cannot tell
/// which is real.
class NutritionTotalsCard extends StatelessWidget {
  const NutritionTotalsCard({
    required this.summary,
    required this.onEditTargets,
    super.key,
  });

  final NutritionSummary summary;
  final VoidCallback onEditTargets;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final NutritionTarget? target = summary.target;

    return SectionCard(
      gradient: true,
      // From the data, not a constant. Page back three days and a card
      // headed TODAY over Friday's ring is the one place the header
      // outright contradicts the day being shown. `summary.date` is the
      // server's echo, which the bloc has already verified.
      title: DiaryDate.label(summary.date),
      trailing: TextButton(
        onPressed: onEditTargets,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(target == null ? 'Set goals' : 'Edit goals'),
      ),
      child: Column(
        children: <Widget>[
          Center(
            child: KcalRing(
              consumed: summary.totals.kcal,
              target: target?.kcal,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          MacroMeterGroup(
            consumed: summary.totals,
            target: target?.asMacros,
          ),
          if (target == null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Icon(
                  Icons.flag_outlined,
                  size: AppSize.iconSm,
                  color: palette.textTertiary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Set a daily goal to see how the day is tracking.',
                    style: context.text.bodySmall
                        ?.copyWith(color: palette.textTertiary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
