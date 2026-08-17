import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../blocs/onboarding/onboarding_bloc.dart';
import '../../../cards/measurement_display_card.dart';
import '../../../config/app_config.dart';
import '../../../models/enums.dart';
import '../../../models/onboarding_data.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/unit_converter.dart';
import '../../../widgets/onboarding_step_layout.dart';
import '../../../widgets/ruler_picker.dart';
import '../../../widgets/segmented_toggle.dart';

/// Q3 — Weight, with a kg ⇄ lbs toggle.
///
/// Same contract as [HeightStep]: kilograms are canonical, the ruler runs
/// in whatever unit is on screen.
class WeightStep extends StatefulWidget {
  const WeightStep({super.key});

  @override
  State<WeightStep> createState() => _WeightStepState();
}

class _WeightStepState extends State<WeightStep> {
  double? _liveKg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final OnboardingBloc bloc = context.read<OnboardingBloc>();
      if (bloc.state.data.weightKg == null) {
        bloc.add(const OnboardingWeightChanged(AppConfig.defaultWeightKg));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingBloc, OnboardingState>(
      buildWhen: (OnboardingState a, OnboardingState b) =>
          a.data.weightKg != b.data.weightKg ||
          a.data.weightUnit != b.data.weightUnit,
      builder: (BuildContext context, OnboardingState state) {
        final WeightUnit unit = state.data.weightUnit;
        final double committedKg =
            state.data.weightKg ?? AppConfig.defaultWeightKg;
        final double kg = _liveKg ?? committedKg;
        final bool isMetric = unit == WeightUnit.kg;

        return OnboardingStepLayout(
          stepNumber: 3,
          totalSteps: OnboardingData.totalSteps,
          title: 'What do you weigh?',
          subtitle: 'An estimate is fine — you can refine it any time.',
          child: Column(
            children: <Widget>[
              Center(
                child: SegmentedToggle<WeightUnit>(
                  width: 200,
                  values: WeightUnit.values,
                  selected: unit,
                  labelOf: (WeightUnit u) => u.label,
                  onChanged: (WeightUnit u) {
                    setState(() => _liveKg = kg);
                    context
                        .read<OnboardingBloc>()
                        .add(OnboardingWeightUnitChanged(u));
                  },
                ),
              ),
              const Spacer(),
              MeasurementDisplayCard(
                value: UnitConverter.weightValue(kg, unit),
                unitLabel: unit.label,
                caption: isMetric
                    ? UnitConverter.formatWeight(kg, WeightUnit.lbs)
                    : UnitConverter.formatWeight(kg, WeightUnit.kg),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (isMetric)
                RulerPicker(
                  key: const ValueKey<String>('weight-kg'),
                  min: AppConfig.minWeightKg,
                  max: AppConfig.maxWeightKg,
                  value: kg,
                  step: 0.5,
                  majorEvery: 10,
                  labelBuilder: (double v) => v.round().toString(),
                  onChanged: (double v) => setState(() => _liveKg = v),
                  onChangeEnd: (double v) {
                    setState(() => _liveKg = null);
                    context
                        .read<OnboardingBloc>()
                        .add(OnboardingWeightChanged(v));
                  },
                )
              else
                RulerPicker(
                  key: const ValueKey<String>('weight-lbs'),
                  min: UnitConverter.kgToLbs(AppConfig.minWeightKg)
                      .roundToDouble(),
                  max: UnitConverter.kgToLbs(AppConfig.maxWeightKg)
                      .roundToDouble(),
                  value: UnitConverter.kgToLbs(kg),
                  step: 1,
                  majorEvery: 10,
                  onChanged: (double lbs) => setState(
                    () => _liveKg = UnitConverter.lbsToKg(lbs),
                  ),
                  onChangeEnd: (double lbs) {
                    setState(() => _liveKg = null);
                    context.read<OnboardingBloc>().add(
                          OnboardingWeightChanged(
                            UnitConverter.lbsToKg(lbs),
                          ),
                        );
                  },
                ),
              const Spacer(),
            ],
          ),
        );
      },
    );
  }
}
