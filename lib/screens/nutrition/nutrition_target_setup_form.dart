import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../models/nutrition_target_setup.dart';
import '../../models/onboarding_data.dart';
import '../../services/nutrition_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';

/// Optional setup inside Nutrition. It only previews/copies values; the
/// containing sheet owns the separate, explicit save action.
class NutritionTargetSetupForm extends StatefulWidget {
  const NutritionTargetSetupForm({
    required this.repository,
    required this.onUseEstimate,
    this.profile,
    this.savedSetup,
    super.key,
  });
  final NutritionRepository repository;
  final OnboardingData? profile;
  final NutritionTargetSetup? savedSetup;
  final ValueChanged<NutritionTargetRecommendation> onUseEstimate;

  @override
  State<NutritionTargetSetupForm> createState() =>
      _NutritionTargetSetupFormState();
}

class _NutritionTargetSetupFormState extends State<NutritionTargetSetupForm> {
  late final TextEditingController _age;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  Gender? _gender;
  NutritionActivityLevel? _activity;
  NutritionWeightGoal? _goal;
  bool _confirmed = false;
  bool _busy = false;
  bool _used = false;
  String? _error;
  NutritionTargetRecommendation? _preview;
  CancelToken? _request;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    final OnboardingData? profile = widget.profile;
    final NutritionTargetSetup? saved = widget.savedSetup;
    _age = TextEditingController(text: saved?.age.toString() ?? '');
    _height = TextEditingController(
      text: (profile?.heightCm ?? saved?.heightCm)?.toString() ?? '',
    );
    _weight = TextEditingController(
      text: (profile?.weightKg ?? saved?.weightKg)?.toString() ?? '',
    );
    _gender = profile?.gender ?? saved?.gender;
    _activity = saved?.activityLevel;
    _goal = saved?.goal ??
        NutritionWeightGoal.fromFitnessGoals(
          profile?.goals ?? const <FitnessGoal>[],
        );
  }

  void _changed(VoidCallback edit) {
    _request?.cancel('Setup changed');
    _generation++;
    setState(() {
      edit();
      _busy = false;
      _preview = null;
      _used = false;
      _error = null;
    });
  }

  Future<void> _calculate() async {
    if (_busy) return;
    final int? age = int.tryParse(_age.text.trim());
    final double? height = double.tryParse(_height.text.trim());
    final double? weight = double.tryParse(_weight.text.trim());
    if (age == null ||
        height == null ||
        weight == null ||
        _gender == null ||
        _activity == null ||
        _goal == null) {
      setState(
        () => _error =
            'Enter your current age, height and weight, and choose an equation setting, activity level and weight goal.',
      );
      return;
    }
    final NutritionTargetSetup setup = NutritionTargetSetup(
      age: age,
      gender: _gender!,
      heightCm: height,
      weightKg: weight,
      activityLevel: _activity!,
      goal: _goal!,
    );
    if (setup.errors.isNotEmpty || !_confirmed) {
      setState(
        () => _error = setup.errors.isNotEmpty
            ? setup.errors.values.first
            : 'Please confirm the suitability statement before requesting an estimate.',
      );
      return;
    }
    final int generation = ++_generation;
    final CancelToken token = CancelToken();
    _request?.cancel('New estimate');
    _request = token;
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _used = false;
    });
    try {
      final NutritionTargetRecommendation result =
          await widget.repository.recommendTargets(
        setup,
        eligibilityConfirmed: _confirmed,
        cancelToken: token,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _preview = result;
        _busy = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      final failure = nutritionFailure(error);
      setState(() {
        _busy = false;
        _error = failure.isCancelled
            ? null
            : failure.fieldErrors.isNotEmpty
                ? failure.fieldErrors.values.join('\n')
                : failure.message;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _request?.cancel('Target setup closed');
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  Widget _number(
    String name,
    String label,
    TextEditingController controller, {
    bool integer = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: TextField(
          key: ValueKey<String>('setup-$name'),
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: !integer),
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => _changed(() {}),
        ),
      );

  Widget _choice<T>(
    String name,
    String label,
    T? value,
    List<T> values,
    String Function(T) text,
    ValueChanged<T?> change,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              key: ValueKey<String>('setup-$name'),
              value: value,
              isExpanded: true,
              hint: const Text('Choose'),
              items: values
                  .map(
                    (T item) => DropdownMenuItem<T>(
                      value: item,
                      child: Text(text(item), maxLines: 2),
                    ),
                  )
                  .toList(),
              onChanged: (T? selected) => _changed(() => change(selected)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final NutritionTargetRecommendation? preview = _preview;
    return ExpansionTile(
      key: const ValueKey<String>('nutrition-estimate-setup'),
      tilePadding: EdgeInsets.zero,
      title: const Text('Estimate from my profile'),
      subtitle: const Text('Optional — review before saving'),
      children: <Widget>[
        Text(
          'Confirm your current measurements and age. Activity means your usual daily activity, not your exercise skill level. The equation uses a sex-specific setting; confirm it below. You can enter targets manually instead.',
          style: context.text.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        _number('age', 'Current age (18–78 years)', _age, integer: true),
        _number('height', 'Height (cm)', _height),
        _number('weight', 'Weight (kg)', _weight),
        _choice<Gender>(
          'gender',
          'Equation sex setting (confirm)',
          _gender,
          Gender.values,
          (Gender value) => value.label,
          (Gender? value) => _gender = value,
        ),
        _choice<NutritionActivityLevel>(
          'activity',
          'Usual activity',
          _activity,
          NutritionActivityLevel.values,
          (NutritionActivityLevel value) => value.label,
          (NutritionActivityLevel? value) => _activity = value,
        ),
        _choice<NutritionWeightGoal>(
          'goal',
          'Weight goal (confirm)',
          _goal,
          NutritionWeightGoal.values,
          (NutritionWeightGoal value) => value.label,
          (NutritionWeightGoal? value) => _goal = value,
        ),
        CheckboxListTile(
          key: const ValueKey<String>('setup-confirm'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'I confirm these inputs are current. I am an adult, not pregnant or breastfeeding, and do not need a medically prescribed diet.',
          ),
          value: _confirmed,
          onChanged: (bool? value) =>
              _changed(() => _confirmed = value ?? false),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              _error!,
              style:
                  context.text.bodySmall?.copyWith(color: context.scheme.error),
            ),
          ),
        PrimaryButton(
          key: const ValueKey<String>('calculate-targets'),
          label: 'Preview estimate',
          isLoading: _busy,
          onPressed: _calculate,
        ),
        if (preview != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            preview.reviewed
                ? 'Estimated daily targets'
                : 'Development preview — awaiting review',
            style: context.text.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${preview.target.kcal.round()} kcal · ${preview.target.proteinG} g protein · ${preview.target.carbsG} g carbs · ${preview.target.fatG} g fat',
          ),
          Text(
            'Resting estimate: ${preview.bmrKcal.round()} kcal. Activity-adjusted estimate: ${preview.tdeeKcal.round()} kcal.',
            style: context.text.bodySmall,
          ),
          for (final String warning in preview.warnings)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(warning, style: context.text.bodySmall),
            ),
          TextButton(
            key: const ValueKey<String>('use-target-estimate'),
            onPressed: _used
                ? null
                : () {
                    widget.onUseEstimate(preview);
                    setState(() => _used = true);
                  },
            child: Text(
              _used ? 'Copied below — review, then save' : 'Use estimate below',
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
