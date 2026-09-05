import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/diary_date.dart';

/// Moves the diary one calendar day at a time.
///
/// Stepping goes through [DiaryDate.shift], which round-trips a `DateTime`
/// so month and year boundaries roll over properly — adding a 24-hour
/// `Duration` would land on the same calendar day across a DST change and
/// the diary would appear to skip a date.
class DiaryDateBar extends StatelessWidget {
  const DiaryDateBar({
    required this.date,
    required this.onChanged,
    this.isBusy = false,
    super.key,
  });

  final String date;
  final ValueChanged<String> onChanged;

  /// Shows a hairline progress line rather than disabling the arrows —
  /// paging ahead while a fetch is in flight is a reasonable thing to do,
  /// and the blocs use a restartable transformer so the stale one is
  /// dropped.
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final bool isToday = DiaryDate.isToday(date);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            _StepButton(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Previous day',
              onPressed: () => onChanged(DiaryDate.previous(date)),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Tapping the label jumps back to today — the single most
                // common navigation after paging back a few days.
                onTap: isToday ? null : () => onChanged(DiaryDate.today()),
                child: Column(
                  children: <Widget>[
                    Text(
                      DiaryDate.label(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleMedium,
                    ),
                    if (!isToday)
                      Text(
                        'Tap to return to today',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall
                            ?.copyWith(color: palette.textTertiary),
                      ),
                  ],
                ),
              ),
            ),
            _StepButton(
              icon: Icons.chevron_right_rounded,
              tooltip: 'Next day',
              // Forward past today is allowed — planning tomorrow's meals
              // is a real use, and the server accepts any valid date.
              onPressed: () => onChanged(DiaryDate.next(date)),
            ),
          ],
        ),
        SizedBox(
          height: 2,
          child: isBusy
              ? LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
                )
              : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: AppSize.iconLg),
      color: context.palette.textSecondary,
      // Bigger than the glyph — a 24px arrow is an awkward tap target.
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}
