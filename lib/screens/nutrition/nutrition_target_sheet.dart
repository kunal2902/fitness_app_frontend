import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/nutrition/nutrition_status.dart';
import '../../blocs/nutrition/nutrition_summary_bloc.dart';
import '../../models/api_exception.dart';
import '../../models/food_log.dart';
import '../../models/nutrition_target_setup.dart';
import '../../models/onboarding_data.dart';
import '../../services/nutrition_repository.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/macro_palette.dart';
import '../../widgets/primary_button.dart';
import 'nutrition_target_setup_form.dart';

/// Editable daily goals with optional profile-based estimation. Previewing
/// never saves; the member must explicitly review and save all changes.
class NutritionTargetSheet extends StatefulWidget {
  const NutritionTargetSheet({this.current, this.profile, super.key});

  final NutritionTarget? current;
  final OnboardingData? profile;

  static Future<void> show(
    BuildContext context, {
    NutritionTarget? current,
  }) {
    final NutritionSummaryBloc bloc = context.read<NutritionSummaryBloc>();
    final NutritionRepository repository = context.read<NutritionRepository>();
    final OnboardingData? profile = AppStore.instance.user?.fitnessProfile;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) =>
          BlocProvider<NutritionSummaryBloc>.value(
        value: bloc,
        child: RepositoryProvider<NutritionRepository>.value(
          value: repository,
          child: NutritionTargetSheet(current: current, profile: profile),
        ),
      ),
    );
  }

  @override
  State<NutritionTargetSheet> createState() => _NutritionTargetSheetState();
}

class _NutritionTargetSheetState extends State<NutritionTargetSheet> {
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;

  String? _error;
  NutritionTargetSetup? _setup;
  NutritionTargetEdit? _submittedEdit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final NutritionTarget? current = widget.current;
    _setup = current?.setup;
    _kcal = TextEditingController(text: _initial(current?.kcal));
    _protein = TextEditingController(text: _initial(current?.proteinG));
    _carbs = TextEditingController(text: _initial(current?.carbsG));
    _fat = TextEditingController(text: _initial(current?.fatG));
  }

  static String _initial(double? value) => value == null
      ? ''
      : value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString();

  void _useEstimate(NutritionTargetRecommendation recommendation) {
    setState(() {
      _setup = recommendation.setup;
      _kcal.text = _initial(recommendation.target.kcal);
      _protein.text = _initial(recommendation.target.proteinG);
      _carbs.text = _initial(recommendation.target.carbsG);
      _fat.text = _initial(recommendation.target.fatG);
      _error = null;
    });
  }

  @override
  void dispose() {
    _kcal.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  /// Parses one field, distinguishing "left blank" from "typed nonsense".
  ///
  /// The distinction matters: an empty field means "leave this goal
  /// alone", but `1..5` also fails `tryParse` — and treating that as
  /// "leave alone" would silently discard an edit the user believes they
  /// made, then close on a successful PATCH that changed nothing.
  static ({double? value, bool malformed}) _read(
    TextEditingController controller,
  ) {
    final String text = controller.text.trim();
    if (text.isEmpty) return (value: null, malformed: false);
    final double? parsed = double.tryParse(text);
    return (value: parsed, malformed: parsed == null);
  }

  void _submit() {
    if (_saving ||
        context.read<NutritionSummaryBloc>().state.targetSave.isSaving) {
      return;
    }
    final ({double? value, bool malformed}) kcalIn = _read(_kcal);
    final ({double? value, bool malformed}) proteinIn = _read(_protein);
    final ({double? value, bool malformed}) carbsIn = _read(_carbs);
    final ({double? value, bool malformed}) fatIn = _read(_fat);

    if (kcalIn.malformed ||
        proteinIn.malformed ||
        carbsIn.malformed ||
        fatIn.malformed) {
      setState(() => _error = 'Enter each goal as a plain number.');
      return;
    }

    final double? kcal = kcalIn.value;
    final double? protein = proteinIn.value;
    final double? carbs = carbsIn.value;
    final double? fat = fatIn.value;

    // The first save must set all four — the server has nothing to merge a
    // partial update into and answers with a field-level error.
    if (widget.current == null &&
        (kcal == null || protein == null || carbs == null || fat == null)) {
      setState(() => _error = 'Fill in all four to set your first goal.');
      return;
    }

    // All blank. Caught here so the user never sees the service layer's
    // internal "needs at least one field to change".
    if (kcal == null && protein == null && carbs == null && fat == null) {
      setState(() => _error = 'Change at least one goal, or close.');
      return;
    }

    if (kcal != null && !NutritionTarget.isSafeKcal(kcal)) {
      setState(
        () => _error = 'Daily energy must be between '
            '${NutritionTarget.minKcal.round()} and '
            '${NutritionTarget.maxKcal.round()} kcal.',
      );
      return;
    }

    // The macro ceilings the server enforces, named per field rather than
    // arriving as a bare "Must be between 0 and 1000".
    final String? outOfRange = _checkRange(
          MacroKind.protein.label,
          protein,
          NutritionTarget.maxProteinG,
        ) ??
        _checkRange(
          MacroKind.carbs.label,
          carbs,
          NutritionTarget.maxCarbsG,
        ) ??
        _checkRange(MacroKind.fat.label, fat, NutritionTarget.maxFatG);
    if (outOfRange != null) {
      setState(() => _error = outOfRange);
      return;
    }

    final NutritionTarget? current = widget.current;
    final NutritionTargetEdit edit = NutritionTargetEdit(
      kcal: kcal == current?.kcal ? null : kcal,
      proteinG: protein == current?.proteinG ? null : protein,
      carbsG: carbs == current?.carbsG ? null : carbs,
      fatG: fat == current?.fatG ? null : fat,
      setup: _setup == current?.setup ? null : _setup,
    );
    if (edit.kcal == null &&
        edit.proteinG == null &&
        edit.carbsG == null &&
        edit.fatG == null &&
        edit.setup == null) {
      setState(
        () => _error = 'Your goals are unchanged. Edit a value or close.',
      );
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    _submittedEdit = edit;
    context.read<NutritionSummaryBloc>().add(
          NutritionTargetsSubmitted(edit),
        );
  }

  static String? _checkRange(String label, double? value, double max) {
    if (value == null) return null;
    if (value.isFinite && value >= 0 && value <= max) return null;
    return '$label must be between 0 and ${max.round()} g.';
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return BlocListener<NutritionSummaryBloc, NutritionSummaryState>(
      listenWhen: (NutritionSummaryState a, NutritionSummaryState b) =>
          a.targetSave.revision != b.targetSave.revision ||
          a.targetSave.status != b.targetSave.status,
      listener: (BuildContext context, NutritionSummaryState state) {
        if (_submittedEdit == null ||
            !identical(state.targetSave.edit, _submittedEdit)) {
          return;
        }
        if (state.targetSave.status == NutritionWriteStatus.success) {
          Navigator.of(context).pop();
        } else if (state.targetSave.status == NutritionWriteStatus.failure) {
          setState(
            () {
              _saving = false;
              final ApiException? failure = state.targetSave.error;
              _error = failure != null && failure.fieldErrors.isNotEmpty
                  ? failure.fieldErrors.values.join('\n')
                  : failure?.message ?? 'Could not save that.';
            },
          );
        }
      },
      child: AbsorbPointer(
        absorbing: _saving,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.xl),
              ),
              border: Border.all(color: palette.border),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        height: 4,
                        width: 40,
                        decoration: BoxDecoration(
                          color: palette.borderStrong,
                          borderRadius: AppRadius.rPill,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Daily goals', style: context.text.titleLarge),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Set what you are aiming for each day. You can change '
                      'these at any time.',
                      style: context.text.bodySmall
                          ?.copyWith(color: palette.textTertiary, height: 1.5),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    NutritionTargetSetupForm(
                      repository: context.read<NutritionRepository>(),
                      profile: widget.profile,
                      savedSetup: widget.current?.setup,
                      onUseEstimate: _useEstimate,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _TargetField(
                      controller: _kcal,
                      label: 'Energy',
                      suffix: 'kcal',
                      tint: palette.accent,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _TargetField(
                      controller: _protein,
                      label: MacroKind.protein.label,
                      suffix: 'g',
                      tint: MacroPalette.protein,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _TargetField(
                      controller: _carbs,
                      label: MacroKind.carbs.label,
                      suffix: 'g',
                      tint: MacroPalette.carbs,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _TargetField(
                      controller: _fat,
                      label: MacroKind.fat.label,
                      suffix: 'g',
                      tint: MacroPalette.fat,
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(
                            Icons.error_outline_rounded,
                            size: AppSize.iconSm,
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              _error!,
                              style: context.text.bodySmall
                                  ?.copyWith(color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    BlocBuilder<NutritionSummaryBloc, NutritionSummaryState>(
                      buildWhen: (
                        NutritionSummaryState a,
                        NutritionSummaryState b,
                      ) =>
                          a.targetSave.isSaving != b.targetSave.isSaving,
                      builder: (
                        BuildContext context,
                        NutritionSummaryState state,
                      ) {
                        return PrimaryButton(
                          label: 'Save goals',
                          isLoading: state.targetSave.isSaving,
                          onPressed: _submit,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TargetField extends StatelessWidget {
  const _TargetField({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.tint,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Row(
      children: <Widget>[
        Container(
          height: 10,
          width: 10,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: AppRadius.rXs,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style:
                context.text.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
        ),
        SizedBox(
          width: 120,
          child: TextField(
            key: ValueKey<String>('target-${label.toLowerCase()}'),
            controller: controller,
            textAlign: TextAlign.end,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: context.text.bodyLarge,
            decoration: InputDecoration(
              isDense: true,
              suffixText: suffix,
              filled: true,
              fillColor: palette.surfaceHigh,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.rSm,
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.rSm,
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.rSm,
                borderSide: BorderSide(color: palette.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
