import 'package:flutter/material.dart';

import '../models/workout_day.dart';
import '../theme/app_theme.dart';
import '../widgets/section_card.dart';
import '../widgets/segmented_toggle.dart';
import 'streak_card.dart';

/// Month grid of training days, with a Previous/Goal toggle and the streak
/// counters underneath.
///
/// One card rather than two because the calendar is the evidence and the
/// streak is the summary — separating them would make the user compare
/// across a card boundary.
class WorkoutCalendarCard extends StatelessWidget {
  const WorkoutCalendarCard({
    required this.mode,
    required this.visibleMonth,
    required this.dayLookup,
    required this.streak,
    required this.isLoading,
    required this.onModeChanged,
    required this.onMonthChanged,
    super.key,
  });

  final CalendarMode mode;
  final DateTime visibleMonth;
  final Map<DateTime, WorkoutDay> dayLookup;
  final StreakStats streak;
  final bool isLoading;
  final ValueChanged<CalendarMode> onModeChanged;
  final ValueChanged<DateTime> onMonthChanged;

  static const List<String> _weekdayLabels = <String>[
    'M', 'T', 'W', 'T', 'F', 'S', 'S',
  ];

  static const List<String> _monthNames = <String>[
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  bool get _canGoForward {
    final DateTime now = DateTime.now();
    final DateTime thisMonth = DateTime(now.year, now.month);
    // History cannot run into the future; a plan can.
    if (mode == CalendarMode.goal) {
      final DateTime limit = DateTime(now.year, now.month + 3);
      return visibleMonth.isBefore(limit);
    }
    return visibleMonth.isBefore(thisMonth);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return SectionCard(
      title: 'Consistency',
      trailing: SizedBox(
        width: 150,
        child: SegmentedToggle<CalendarMode>(
          dense: true,
          values: CalendarMode.values,
          selected: mode,
          labelOf: (CalendarMode m) =>
              m == CalendarMode.previous ? 'Previous' : 'Goal',
          onChanged: onModeChanged,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ---- Month navigation ------------------------------------------
          Row(
            children: <Widget>[
              _MonthArrow(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous month',
                onPressed: () => onMonthChanged(
                  DateTime(visibleMonth.year, visibleMonth.month - 1),
                ),
              ),
              Expanded(
                child: Text(
                  '${_monthNames[visibleMonth.month - 1]} ${visibleMonth.year}',
                  textAlign: TextAlign.center,
                  style: context.text.titleMedium,
                ),
              ),
              _MonthArrow(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next month',
                onPressed: _canGoForward
                    ? () => onMonthChanged(
                          DateTime(visibleMonth.year, visibleMonth.month + 1),
                        )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ---- Weekday header --------------------------------------------
          Row(
            children: _weekdayLabels
                .map(
                  (String label) => Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: context.text.labelSmall?.copyWith(
                          color: palette.textTertiary,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.xs),

          // ---- Grid --------------------------------------------------------
          AnimatedOpacity(
            duration: AppDuration.fast,
            opacity: isLoading ? 0.45 : 1,
            child: _MonthGrid(
              month: visibleMonth,
              dayLookup: dayLookup,
            ),
          ),

          const SizedBox(height: AppSpacing.md),
          _Legend(mode: mode),

          const SizedBox(height: AppSpacing.lg),
          StreakCard(streak: streak),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.dayLookup});

  final DateTime month;
  final Map<DateTime, WorkoutDay> dayLookup;

  @override
  Widget build(BuildContext context) {
    final DateTime first = DateTime(month.year, month.month);
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    // Weeks start on Monday: DateTime.weekday is Mon=1 … Sun=7.
    final int leadingBlanks = first.weekday - 1;
    final int cellCount = leadingBlanks + daysInMonth;
    final int rows = (cellCount / 7).ceil();

    final DateTime today = WorkoutDay.dayKey(DateTime.now());

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: rows * 7,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemBuilder: (BuildContext context, int index) {
        final int dayNumber = index - leadingBlanks + 1;
        if (dayNumber < 1 || dayNumber > daysInMonth) {
          return const SizedBox.shrink();
        }

        final DateTime date = DateTime(month.year, month.month, dayNumber);
        return _DayCell(
          dayNumber: dayNumber,
          day: dayLookup[date],
          isToday: date == today,
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.dayNumber,
    required this.day,
    required this.isToday,
  });

  final int dayNumber;
  final WorkoutDay? day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    Color background = Colors.transparent;
    Color border = Colors.transparent;
    Color text = palette.textTertiary;
    FontWeight weight = FontWeight.w500;

    switch (day?.status) {
      case WorkoutDayStatus.completed:
        background = palette.accent;
        text = palette.onAccent;
        weight = FontWeight.w800;
      case WorkoutDayStatus.missed:
        border = AppColors.danger.withValues(alpha: 0.55);
        text = AppColors.danger;
        weight = FontWeight.w600;
      case WorkoutDayStatus.planned:
        border = palette.accent.withValues(alpha: 0.6);
        text = palette.accent;
        weight = FontWeight.w600;
      case WorkoutDayStatus.rest:
      case null:
        background = palette.surfaceAlt;
        text = palette.textTertiary;
    }

    return Semantics(
      label: _semanticLabel(),
      child: Tooltip(
        message: day?.title ?? '',
        triggerMode:
            day?.title == null ? TooltipTriggerMode.manual : TooltipTriggerMode.tap,
        child: Container(
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(
              color: isToday && day?.status != WorkoutDayStatus.completed
                  ? palette.textSecondary
                  : border,
              width: isToday ? 1.6 : 1.4,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '$dayNumber',
            style: context.text.bodySmall?.copyWith(
              color: text,
              fontWeight: weight,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  String _semanticLabel() {
    final String suffix = switch (day?.status) {
      WorkoutDayStatus.completed => 'workout completed',
      WorkoutDayStatus.missed => 'workout missed',
      WorkoutDayStatus.planned => 'workout planned',
      _ => 'rest day',
    };
    return 'Day $dayNumber, $suffix';
  }
}

class _MonthArrow extends StatelessWidget {
  const _MonthArrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final bool enabled = onPressed != null;

    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        size: AppSize.iconLg,
        color: enabled ? palette.textPrimary : palette.textTertiary,
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.mode});

  final CalendarMode mode;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        _LegendDot(fill: palette.accent, label: 'Completed'),
        _LegendDot(
          fill: Colors.transparent,
          border: palette.accent.withValues(alpha: 0.6),
          label: 'Planned',
        ),
        _LegendDot(
          fill: Colors.transparent,
          border: AppColors.danger.withValues(alpha: 0.55),
          label: 'Missed',
        ),
        // In Previous mode the grey cells are rest days AND days that
        // simply have not happened yet, so "Rest" would be a lie for half
        // of them.
        _LegendDot(
          fill: palette.surfaceAlt,
          label: mode == CalendarMode.previous ? 'No session' : 'Rest',
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.fill, required this.label, this.border});

  final Color fill;
  final Color? border;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          height: 10,
          width: 10,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: border == null ? null : Border.all(color: border!, width: 1.4),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: context.text.bodySmall?.copyWith(
            color: context.palette.textTertiary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
