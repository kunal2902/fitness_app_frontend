import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/nutrition/meal_log_bloc.dart';
import '../../blocs/nutrition/nutrition_status.dart';
import '../../blocs/nutrition/nutrition_summary_bloc.dart';
import '../../cards/meal_section_card.dart';
import '../../cards/nutrition_totals_card.dart';
import '../../models/food_log.dart';
import '../../models/nutrition_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/diary_date.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/diary_date_bar.dart';
import '../../widgets/glow_background.dart';
import 'food_search_screen.dart';
import 'nutrition_navigation.dart';
import 'nutrition_target_sheet.dart';
import 'portion_picker_screen.dart';

/// The Nutrition tab: one day's totals, then the day's meals.
///
/// Two blocs feed it and the screen owns the date that keeps them in step —
/// the summary supplies the server's totals and target, the log bloc
/// supplies the individual entries. Neither is derived from the other on
/// purpose: recomputing the header from the visible rows would let a
/// half-refreshed screen show a total that disagrees with the server's.
class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen>
    with WidgetsBindingObserver {
  late String _date = DiaryDate.today();

  /// True while the user has not deliberately paged away from today.
  ///
  /// The shell builds every tab at sign-in, so `_date` is frozen at
  /// whatever today was when the app launched. Leave it resident
  /// overnight — normal on a phone — and breakfast is logged to yesterday.
  bool _followingToday = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // NutritionScope does no I/O of its own, so the first fetch starts
    // here. The shell builds all five tabs up front, which means the diary
    // is already loaded by the time the tab is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(_date));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || !_followingToday) return;
    final String today = DiaryDate.today();
    if (today != _date) _changeDate(today, following: true);
  }

  void _load(String date) {
    if (!mounted) return;
    context.read<NutritionSummaryBloc>().add(NutritionSummaryRequested(date));
    context.read<MealLogBloc>().add(MealLogsRequested(date));
  }

  void _changeDate(String date, {bool? following}) {
    if (date == _date) return;
    setState(() {
      _date = date;
      _followingToday = following ?? DiaryDate.isToday(date);
    });
    _load(date);
  }

  /// Holds the pull gesture until both blocs settle, rather than for a
  /// fixed delay — a spinner that retracts while the old numbers are still
  /// on screen reads as "refreshed" when nothing has changed.
  Future<void> _refresh() async {
    _load(_date);

    final NutritionSummaryBloc summary = context.read<NutritionSummaryBloc>();
    final MealLogBloc logs = context.read<MealLogBloc>();

    bool settled() =>
        summary.state.status != NutritionLoadStatus.loading &&
        logs.state.status != NutritionLoadStatus.loading;

    final DateTime deadline = DateTime.now().add(const Duration(seconds: 15));
    while (mounted && !settled() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  void _addFood(MealType? mealType) {
    unawaited(
      pushNutritionRoute<void>(
        context,
        FoodSearchScreen(date: _date, mealType: mealType),
      ),
    );
  }

  /// Edits by **index**, not by item value. `FoodLogItem` is an Equatable,
  /// so two identical foods logged in one meal compare equal — matching by
  /// value would rewrite both.
  void _editItem(FoodLog log, int itemIndex) {
    unawaited(
      pushNutritionRoute<void>(
        context,
        PortionPickerScreen(
          date: log.date,
          mealType: log.mealType,
          foodId: log.items[itemIndex].foodId,
          editing: (log: log, itemIndex: itemIndex),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(FoodLog log) async {
    final int count = log.items.length;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          count == 1
              ? 'This removes ${log.items.first.name} from your diary.'
              : 'This removes all $count foods logged together.',
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

    if (confirmed != true || !mounted) return;
    context
        .read<MealLogBloc>()
        .add(MealLogDeleteRequested(logId: log.id, date: log.date));
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Scaffold(
      backgroundColor: palette.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addFood(null),
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log food'),
      ),
      body: GlowBackground(
        alignment: const Alignment(0, -0.95),
        child: SafeArea(
          child: BlocListener<MealLogBloc, MealLogState>(
            // Status as well as revision. The bloc computes `revision`
            // once per operation and emits it TWICE — saving, then success
            // or failure — so watching revision alone means the terminal
            // state never fires and every outcome is swallowed.
            listenWhen: (MealLogState a, MealLogState b) =>
                a.mutation.revision != b.mutation.revision ||
                a.mutation.status != b.mutation.status,
            listener: _onMutation,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs,
                    AppSpacing.xs,
                    AppSpacing.xs,
                    0,
                  ),
                  child: _DateBar(
                    date: _date,
                    onChanged: _changeDate,
                  ),
                ),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onMutation(BuildContext context, MealLogState state) {
    final MealLogMutationState mutation = state.mutation;

    // Only the operations that *end* on this screen. A create is started
    // from the search screen, which stays mounted underneath the picker
    // and reports it there — without this split both listeners fire and
    // the user gets the same snackbar twice.
    final bool isOurs = mutation.operation is MealLogDeleteRequested ||
        mutation.operation is MealLogUpdateRequested;
    if (!isOurs) return;

    if (mutation.status == NutritionWriteStatus.failure) {
      // Resolved now, not inside the callback: a snackbar outlives the
      // route that raised it, so by the time Retry is tapped this context
      // may be defunct and the bloc may be closed.
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
    } else if (mutation.status == NutritionWriteStatus.success) {
      AppSnackbar.success(
        context,
        mutation.deletedId != null ? 'Entry deleted' : 'Entry updated',
      );
    }
  }

  Widget _body() {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: context.palette.accent,
      backgroundColor: context.palette.surfaceHigh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          // Clear of the extended FAB.
          AppSpacing.huge + AppSpacing.xl,
        ),
        children: <Widget>[
          const _FailedSavesBanner(),
          _SummarySection(date: _date),
          const SizedBox(height: AppSpacing.md),
          _MealsSection(
            date: _date,
            onAdd: _addFood,
            onEditItem: _editItem,
            onDeleteLog: _confirmDelete,
          ),
        ],
      ),
    );
  }
}

/// Wraps the date bar so a rebuild of the busy indicator does not rebuild
/// the whole diary.
class _DateBar extends StatelessWidget {
  const _DateBar({required this.date, required this.onChanged});

  final String date;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NutritionSummaryBloc, NutritionSummaryState>(
      buildWhen: (NutritionSummaryState a, NutritionSummaryState b) =>
          a.status != b.status,
      builder: (BuildContext context, NutritionSummaryState summary) {
        return BlocBuilder<MealLogBloc, MealLogState>(
          buildWhen: (MealLogState a, MealLogState b) => a.status != b.status,
          builder: (BuildContext context, MealLogState logs) {
            return DiaryDateBar(
              date: date,
              onChanged: onChanged,
              // Either fetch counts — once a day has loaded the sections
              // stop showing skeletons and this is the only progress cue.
              isBusy: summary.status == NutritionLoadStatus.loading ||
                  logs.status == NutritionLoadStatus.loading,
            );
          },
        );
      },
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NutritionSummaryBloc, NutritionSummaryState>(
      builder: (BuildContext context, NutritionSummaryState state) {
        // The bloc holds its own date. Rendering a summary for a day the
        // user has already paged away from is the exact bug the echoed
        // date exists to prevent, so treat a mismatch as "not loaded yet".
        final bool isCurrent = state.date == date;
        final NutritionSummary? summary = isCurrent ? state.summary : null;

        if (summary == null) {
          if (isCurrent && state.status == NutritionLoadStatus.failure) {
            return _FailureCard(
              message: state.error?.message ??
                  'Could not load your day. Check your connection.',
              onRetry: () => context
                  .read<NutritionSummaryBloc>()
                  .add(NutritionSummaryRequested(date)),
            );
          }
          return const _TotalsSkeleton();
        }

        return Column(
          children: <Widget>[
            // A refresh can fail after a day has loaded, and the bloc keeps
            // the previous summary. Saying so is the difference between
            // stale numbers and stale numbers presented as current.
            if (state.status == NutritionLoadStatus.failure)
              _StaleStrip(
                onRetry: () => context
                    .read<NutritionSummaryBloc>()
                    .add(NutritionSummaryRequested(date)),
              ),
            NutritionTotalsCard(
              summary: summary,
              onEditTargets: () => NutritionTargetSheet.show(
                context,
                current: summary.target,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MealsSection extends StatelessWidget {
  const _MealsSection({
    required this.date,
    required this.onAdd,
    required this.onEditItem,
    required this.onDeleteLog,
  });

  final String date;
  final void Function(MealType? mealType) onAdd;
  final void Function(FoodLog log, int itemIndex) onEditItem;
  final void Function(FoodLog log) onDeleteLog;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MealLogBloc, MealLogState>(
      builder: (BuildContext context, MealLogState state) {
        final bool isCurrent = state.date == date;

        if (!isCurrent || !state.hasLoaded) {
          if (isCurrent && state.status == NutritionLoadStatus.failure) {
            return _FailureCard(
              message: state.error?.message ??
                  'Could not load your meals. Check your connection.',
              onRetry: () =>
                  context.read<MealLogBloc>().add(MealLogsRequested(date)),
            );
          }
          return const _MealsSkeleton();
        }

        // Group once. An "Other" bucket collects entries whose meal type
        // this build does not recognise — the server could add a fifth,
        // and silently hiding the user's food would be worse than an
        // extra heading.
        final Map<MealType?, List<FoodLog>> grouped =
            <MealType?, List<FoodLog>>{};
        for (final FoodLog log in state.logs) {
          grouped.putIfAbsent(log.mealType, () => <FoodLog>[]).add(log);
        }

        final List<MealType?> sections = <MealType?>[
          ...MealType.values,
          if (grouped.containsKey(null)) null,
        ];

        return Column(
          children: <Widget>[
            if (state.status == NutritionLoadStatus.failure)
              _StaleStrip(
                onRetry: () =>
                    context.read<MealLogBloc>().add(MealLogsRequested(date)),
              ),
            for (final MealType? meal in sections) ...<Widget>[
              if (meal != sections.first) const SizedBox(height: AppSpacing.md),
              MealSectionCard(
                mealType: meal,
                logs: grouped[meal] ?? const <FoodLog>[],
                onAdd: () => onAdd(meal),
                onEditItem: onEditItem,
                onDeleteLog: onDeleteLog,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Surfaces saves that failed and were never retried.
///
/// This is the only screen guaranteed to be mounted when a write resolves.
/// A meal added from the search flow can fail *after* the user has backed
/// out of both the picker and the search screen, and without this the
/// failure lands in `failedMutations` where nothing reads it — the food is
/// simply missing from the diary with no reason given.
class _FailedSavesBanner extends StatelessWidget {
  const _FailedSavesBanner();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MealLogBloc, MealLogState>(
      buildWhen: (MealLogState a, MealLogState b) =>
          a.failedMutations.length != b.failedMutations.length,
      builder: (BuildContext context, MealLogState state) {
        if (state.failedMutations.isEmpty) return const SizedBox.shrink();

        final AppPalette palette = context.palette;
        final int count = state.failedMutations.length;

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: AppRadius.rMd,
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.cloud_upload_outlined,
                size: AppSize.iconMd,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  count == 1
                      ? 'One entry did not save.'
                      : '$count entries did not save.',
                  style: context.text.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () {
                  final MealLogBloc bloc = context.read<MealLogBloc>();
                  // Each retained failure is replayed with its own stored
                  // operation *instance* — MealLogDraft and MealLogEdit use
                  // identity equality, so a rebuilt-but-equal event would
                  // be rejected by the bloc's retry guard.
                  for (final MealLogMutationState failure
                      in state.failedMutations) {
                    final MealLogMutation? operation = failure.operation;
                    if (operation == null) continue;
                    bloc.add(MealLogRetryRequested(operation: operation));
                  }
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "This is your last saved copy" — shown over data still on screen
/// because a *refresh* failed, not the first load.
class _StaleStrip extends StatelessWidget {
  const _StaleStrip({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: AppRadius.rSm,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.sync_problem_rounded,
            size: AppSize.iconSm,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Could not refresh — showing your last saved copy.',
              style: context.text.bodySmall
                  ?.copyWith(color: palette.textTertiary),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.cloud_off_rounded,
            size: 32,
            color: AppColors.warning,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style:
                context.text.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _TotalsSkeleton extends StatelessWidget {
  const _TotalsSkeleton();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: palette.border),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _MealsSkeleton extends StatelessWidget {
  const _MealsSkeleton();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      children: List<Widget>.generate(
        4,
        (int i) => Container(
          height: 96,
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: AppRadius.rLg,
            border: Border.all(color: palette.border),
          ),
        ),
      ),
    );
  }
}
