import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/nutrition/meal_log_bloc.dart';
import '../../blocs/nutrition/nutrition_status.dart';
import '../../models/api_exception.dart';
import '../../models/food_log.dart';
import '../../models/nutrition_models.dart';
import '../../services/nutrition_repository.dart';
import '../../services/nutrition_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/nutrition_math.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/macro_meter.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/quantity_stepper.dart';
import '../../widgets/section_card.dart';
import '../../widgets/segmented_toggle.dart';

/// Choose a portion and log it — and the same screen, prefilled, to edit
/// an entry already in the diary.
///
/// One widget for both because they are the same decision: which serving,
/// how many, which meal. Two screens would drift, and the add flow is the
/// one where a portion-validation mismatch would show up first.
class PortionPickerScreen extends StatefulWidget {
  const PortionPickerScreen({
    required this.date,
    required this.mealType,
    this.food,
    this.foodId,
    this.editing,
    super.key,
  }) : assert(
          food != null || foodId != null || editing != null,
          'Need a food, a food id, or an entry to edit',
        );

  /// Diary day the entry belongs to.
  final String date;

  /// Meal to preselect.
  final MealType? mealType;

  /// The food, when the caller already has it — search results carry the
  /// full record, so tapping a result needs no round trip.
  final Food? food;

  /// Fetched on open when [food] is absent.
  final String? foodId;

  /// Set to edit an existing entry rather than add a new one. Carries the
  /// item's **index** so a meal containing two identical foods edits the
  /// one that was tapped.
  final ({FoodLog log, int itemIndex})? editing;

  @override
  State<PortionPickerScreen> createState() => _PortionPickerScreenState();
}

class _PortionPickerScreenState extends State<PortionPickerScreen> {
  Food? _food;
  ApiException? _loadError;
  bool _isLoading = false;

  FoodServing? _serving;
  double _quantity = 1;
  late MealType _mealType;

  /// Generated once, not per attempt. The whole point of the idempotency
  /// key is that a retry after a dropped response carries the *same* id —
  /// regenerate it and the server writes the meal twice.
  String? _clientId;

  /// The entry being edited, resolved once from the index.
  FoodLogItem? _editedItem;

  /// Whether the user actually chose the meal. Needed because `_mealType`
  /// is non-null and defaults from the clock: an entry in the "Other"
  /// bucket (unrecognised meal type) would otherwise be silently filed
  /// under whichever meal it happened to be opened at.
  bool _mealTypeChosen = false;

  /// Set when the stored serving label no longer resolves against the
  /// food, so the screen can say the portion was reset rather than let a
  /// blind Save convert "2 katori" into "1 × 100 g".
  bool _portionReset = false;
  bool _saving = false;
  bool _saveFailed = false;
  MealLogMutation? _submittedOperation;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _mealType = widget.editing?.log.mealType ??
        widget.mealType ??
        MealType.suggestedFor(DateTime.now());
    _editedItem = widget.editing == null
        ? null
        : widget.editing!.log.items[widget.editing!.itemIndex];

    final Food? supplied = widget.food;
    if (supplied != null) {
      _food = supplied;
      _applyInitialPortion(supplied);
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final String? id = widget.foodId ?? _editedItem?.foodId;
    if (id == null) {
      // Nothing to fetch and nothing supplied — render a reason rather
      // than an empty screen with no bottom bar and no retry.
      setState(
        () => _loadError = const ApiException(
          message: 'That food could not be opened.',
          code: 'NO_FOOD',
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final Food food = await context.read<NutritionRepository>().getFood(id);
      if (!mounted) return;
      setState(() {
        _food = food;
        _isLoading = false;
      });
      _applyInitialPortion(food);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = nutritionFailure(error);
      });
    }
  }

  /// Preselects the serving and quantity.
  ///
  /// When editing, matches the stored `unitLabel` against the food's
  /// servings the way the server does. If the label no longer resolves —
  /// the food's servings were re-curated since the meal was logged — it
  /// falls back to the default rather than sending a label the server will
  /// reject.
  void _applyInitialPortion(Food food) {
    final FoodLogItem? item = _editedItem;
    FoodServing? serving;
    double quantity = 1;
    bool reset = false;

    if (item != null) {
      serving = food.servingByLabel(item.unitLabel);
      if (serving != null) {
        quantity = item.quantity;
      } else if (NutritionMath.isGramUnitLabel(item.unitLabel)) {
        // Logged by weight. No food carries a serving whose label
        // normalises to "g", so the lookup always misses here. Map it onto
        // the 100 g row, which every food has, preserving the exact mass:
        // quantity x 100 g == the grams originally logged.
        for (final FoodServing candidate in food.servings) {
          if (candidate.isHundredGrams) {
            serving = candidate;
            quantity = NutritionMath.round(item.grams / candidate.grams);
            break;
          }
        }
      }
      // Genuinely unresolvable — the food's servings were re-curated since
      // this meal was logged. Fall back, but say so.
      if (serving == null) reset = true;
    }

    setState(() {
      _serving = serving ?? food.defaultServing;
      _quantity = quantity;
      _portionReset = reset;
    });
  }

  double get _grams {
    final FoodServing? serving = _serving;
    if (serving == null) return 0;
    try {
      return serving.gramsFor(_quantity);
    } on ArgumentError {
      return 0;
    }
  }

  /// Per-100 g values the preview scales from.
  ///
  /// When editing, this is the **frozen snapshot** taken at log time, not
  /// the food's current composition. The diary row shows the snapshot, so
  /// previewing from live data would make tapping a 250 kcal entry open an
  /// editor reading 310 — for any food whose macros were repaired since.
  Macros get _basis =>
      _editedItem?.snapshot.per100g ?? _food?.per100g ?? Macros.zero;

  Macros get _macros => _basis.forGrams(_grams);

  void _changeDraft(VoidCallback change) {
    setState(() {
      change();
      if (_saveFailed) {
        // A changed retry is a new logical create. Reusing the old id would
        // make an ambiguous earlier commit return the pre-edit meal.
        _clientId = null;
        _submittedOperation = null;
        _saveFailed = false;
      }
    });
  }

  void _onMutation(BuildContext context, MealLogState state) {
    final MealLogMutation? submitted = _submittedOperation;
    final MealLogMutationState mutation = state.mutation;
    if (submitted == null || !identical(mutation.operation, submitted)) return;

    switch (mutation.status) {
      case NutritionWriteStatus.saving:
        if (!_saving) setState(() => _saving = true);
      case NutritionWriteStatus.failure:
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      case NutritionWriteStatus.success:
        _saving = false;
        if (mounted) Navigator.of(context).pop();
      case NutritionWriteStatus.initial:
        break;
    }
  }

  void _submit() {
    final Food? food = _food;
    final FoodServing? serving = _serving;
    if (food == null || serving == null) return;

    final MealLogBloc bloc = context.read<MealLogBloc>();
    final NutritionRepository repository = context.read<NutritionRepository>();
    if (bloc.isClosed) return;

    // Catches Object, not just ArgumentError: `newClientId()` throws an
    // ApiException once the session closes, which would otherwise escape
    // the tap handler uncaught.
    try {
      final DraftLogItem draftItem = DraftLogItem.of(
        food: food,
        serving: serving,
        quantity: _quantity,
      );

      final ({FoodLog log, int itemIndex})? editing = widget.editing;
      if (editing == null) {
        _clientId ??= repository.newClientId();
        final MealLogCreateRequested operation = MealLogCreateRequested(
          MealLogDraft(
            clientId: _clientId!,
            date: widget.date,
            mealType: _mealType,
            items: <DraftLogItem>[draftItem],
          ),
        );
        setState(() {
          _submittedOperation = operation;
          _saving = true;
          _saveFailed = false;
        });
        bloc.add(operation);
      } else {
        // Re-read the log from the bloc rather than trusting the copy
        // captured when this screen was pushed. The edit path always does
        // a getFood round trip first, so that snapshot is seconds old, and
        // the change stream may have refreshed the log underneath —
        // resending stale siblings would silently revert them.
        final FoodLog? current = _currentLog(bloc, editing.log.id);
        if (current == null) {
          AppSnackbar.error(
            context,
            'That entry is no longer in your diary.',
          );
          Navigator.of(context).pop();
          return;
        }
        if (editing.itemIndex >= current.items.length) {
          AppSnackbar.error(
            context,
            'That entry changed while you were editing it. '
            'Open it again to make your change.',
          );
          Navigator.of(context).pop();
          return;
        }

        final MealLogUpdateRequested operation = MealLogUpdateRequested(
          MealLogEdit(
            logId: current.id,
            originalDate: current.date,
            date: widget.date == current.date ? null : widget.date,
            mealType: !_mealTypeChosen || _mealType == current.mealType
                ? null
                : _mealType,
            // Replace only the item being edited. A PATCH sends the
            // whole array, so the untouched foods in a multi-food meal
            // have to be resent or they are deleted.
            items: <DraftLogItem>[
              for (final (int index, FoodLogItem existing)
                  in current.items.indexed)
                if (index == editing.itemIndex)
                  draftItem
                else
                  DraftLogItem.fromLogItem(existing),
            ],
          ),
        );
        setState(() {
          _submittedOperation = operation;
          _saving = true;
          _saveFailed = false;
        });
        bloc.add(operation);
      }
    } catch (error) {
      // DraftLogItem refuses a food with no server id or an out-of-range
      // portion. Better here, naming the problem, than as a 422.
      AppSnackbar.error(context, nutritionFailure(error).message);
    }
  }

  /// The live copy of the log being edited, or null if it has since been
  /// deleted or moved off this diary day.
  static FoodLog? _currentLog(MealLogBloc bloc, String logId) {
    for (final FoodLog log in bloc.state.logs) {
      if (log.id == logId) return log;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Food? food = _food;

    return BlocListener<MealLogBloc, MealLogState>(
      listenWhen: (MealLogState before, MealLogState after) =>
          before.mutation.revision != after.mutation.revision ||
          before.mutation.status != after.mutation.status,
      listener: _onMutation,
      child: Scaffold(
        backgroundColor: palette.bg,
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit portion' : 'Add food'),
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: GlowBackground(
            alignment: const Alignment(0, -0.9),
            child: SafeArea(
              top: false,
              child: _content(food),
            ),
          ),
        ),
        bottomNavigationBar: food == null || _serving == null
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: PrimaryButton(
                  label: _isEditing
                      ? 'Save changes'
                      : 'Add to ${_mealType.label.toLowerCase()}',
                  icon: _isEditing ? Icons.check_rounded : Icons.add_rounded,
                  isLoading: _saving,
                  onPressed: _grams > 0 && !_saving ? _submit : null,
                ),
              ),
      ),
    );
  }

  Widget _content(Food? food) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final ApiException? error = _loadError;
    if (error != null) {
      return _ErrorBody(message: error.message, onRetry: _load);
    }

    if (food == null) return const SizedBox.shrink();
    return _body(food);
  }

  Widget _body(Food food) {
    final AppPalette palette = context.palette;
    final FoodServing? serving = _serving;

    if (serving == null) {
      return _ErrorBody(
        message:
            '${food.name} has no portion sizes yet, so it cannot be logged. '
            'Try another food.',
        onRetry: null,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: <Widget>[
        Text(food.name, style: context.text.headlineSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          food.displayAliases.isEmpty
              ? food.group
              : food.displayAliases.take(4).join(' · '),
          style: context.text.bodySmall?.copyWith(color: palette.textTertiary),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Portion',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ServingChips(
                servings: food.servings,
                selected: serving,
                onSelected: (FoodServing next) =>
                    _changeDraft(() => _serving = next),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'How many?',
                      style: context.text.bodyMedium
                          ?.copyWith(color: palette.textSecondary),
                    ),
                  ),
                  QuantityStepper(
                    quantity: _quantity,
                    onChanged: (double next) =>
                        _changeDraft(() => _quantity = next),
                    onTapValue: _promptForQuantity,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                // The gram figure is the thing the server validates, so
                // show it — it is also what makes "1.5 katori" concrete.
                '${QuantityStepper.formatQuantity(_quantity)} × '
                '${serving.label} = ${_formatGrams(_grams)} g',
                style: context.text.bodySmall
                    ?.copyWith(color: palette.textTertiary),
              ),
              if (_portionReset) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'The portion you logged is no longer available for this '
                  'food, so it has been reset. Check it before saving.',
                  style: context.text.bodySmall
                      ?.copyWith(color: AppColors.warning, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'This portion',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    '${_macros.kcal.round()}',
                    style: context.text.displaySmall
                        ?.copyWith(color: palette.accent),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'kcal',
                    style: context.text.bodyMedium
                        ?.copyWith(color: palette.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              MacroMeterGroup(consumed: _macros),
              const SizedBox(height: AppSpacing.md),
              MacroSplitBar(macros: _macros),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Meal',
          child: SegmentedToggle<MealType>(
            values: MealType.values,
            selected: _mealType,
            labelOf: (MealType meal) => meal.label,
            onChanged: (MealType meal) => _changeDraft(() {
              _mealType = meal;
              _mealTypeChosen = true;
            }),
            dense: true,
          ),
        ),
        if (food.energySource?.isDerived ?? false) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          const _ProvenanceNote(
            text: 'Energy for this food was recalculated from its protein, '
                'carbohydrate and fat content — the published figure was '
                'missing or inconsistent.',
          ),
        ],
      ],
    );
  }

  Future<void> _promptForQuantity() async {
    final double? result = await showDialog<double>(
      context: context,
      builder: (BuildContext context) => _ExactAmountDialog(
        initial: _quantity,
        unitLabel: _serving?.label ?? '',
      ),
    );

    if (!mounted || result == null) return;
    if (!result.isFinite || result <= 0) return;
    _changeDraft(() => _quantity = NutritionMath.round(result));
  }

  static String _formatGrams(double grams) => grams == grams.roundToDouble()
      ? grams.toStringAsFixed(0)
      : grams.toStringAsFixed(1);
}

/// The food's own servings, as a wrap of selectable chips.
///
/// Chips rather than a dropdown: most foods carry two or three portions,
/// and a dropdown hides them behind a tap for no gain.
class _ServingChips extends StatelessWidget {
  const _ServingChips({
    required this.servings,
    required this.selected,
    required this.onSelected,
  });

  final List<FoodServing> servings;
  final FoodServing selected;
  final ValueChanged<FoodServing> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        for (final FoodServing serving in servings)
          _ServingChip(
            label: serving.label,
            grams: serving.grams,
            isSelected: serving.key == selected.key,
            palette: palette,
            onTap: () => onSelected(serving),
          ),
      ],
    );
  }
}

class _ServingChip extends StatelessWidget {
  const _ServingChip({
    required this.label,
    required this.grams,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final double grams;
  final bool isSelected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? palette.accent.withValues(alpha: 0.16)
          : palette.surfaceHigh,
      borderRadius: AppRadius.rSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.rSm,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rSm,
            border: Border.all(
              color: isSelected ? palette.accent : palette.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: context.text.bodyMedium?.copyWith(
                  color: isSelected ? palette.accent : palette.textPrimary,
                ),
              ),
              Text(
                '${grams.round()} g',
                style: context.text.bodySmall
                    ?.copyWith(color: palette.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProvenanceNote extends StatelessWidget {
  const _ProvenanceNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.rSm,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            size: AppSize.iconSm,
            color: palette.textTertiary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: context.text.bodySmall
                  ?.copyWith(color: palette.textTertiary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

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
              Icons.no_meals_rounded,
              size: 40,
              color: palette.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium
                  ?.copyWith(color: palette.textSecondary),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Types an exact quantity.
///
/// A `StatefulWidget` purely so the controller is disposed by the dialog's
/// own lifecycle. Creating it beside `showDialog` and disposing after the
/// await looks equivalent and is not: the future completes when the route
/// pops, while the field stays mounted through the exit transition and
/// still writes to the controller on focus loss — "A TextEditingController
/// was used after being disposed", intermittently.
class _ExactAmountDialog extends StatefulWidget {
  const _ExactAmountDialog({required this.initial, required this.unitLabel});

  final double initial;
  final String unitLabel;

  @override
  State<_ExactAmountDialog> createState() => _ExactAmountDialogState();
}

class _ExactAmountDialogState extends State<_ExactAmountDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: QuantityStepper.formatQuantity(widget.initial),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop(double.tryParse(_controller.text.trim()));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Exact amount'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(suffixText: widget.unitLabel),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Set')),
      ],
    );
  }
}
