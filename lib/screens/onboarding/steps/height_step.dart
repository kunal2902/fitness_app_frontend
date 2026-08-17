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
import '../../../widgets/unit_toggle.dart';

/// Q2 — Height, with a cm ⇄ ft/in toggle.
///
/// The canonical value is always centimetres. In imperial mode the ruler
/// runs in whole inches and converts on the way in and out, so flipping
/// units never drifts the underlying measurement.
class HeightStep extends StatefulWidget {
  const HeightStep({super.key});

  @override
  State<HeightStep> createState() => _HeightStepState();
}

class _HeightStepState extends State<HeightStep> {
  /// Live value while the ruler is moving (not yet committed to the BLoC).
  double? _liveCm;

  @override
  void initState() {
    super.initState();
    // The ruler always shows *something*, so seed the answer with that same
    // default — otherwise "Continue" would sit disabled under a value the
    // user can plainly see.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final OnboardingBloc bloc = context.read<OnboardingBloc>();
      if (bloc.state.data.heightCm == null) {
        bloc.add(const OnboardingHeightChanged(AppConfig.defaultHeightCm));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingBloc, OnboardingState>(
      buildWhen: (OnboardingState a, OnboardingState b) =>
          a.data.heightCm != b.data.heightCm ||
          a.data.heightUnit != b.data.heightUnit,
      builder: (BuildContext context, OnboardingState state) {
        final HeightUnit unit = state.data.heightUnit;
        final double committedCm =
            state.data.heightCm ?? AppConfig.defaultHeightCm;
        final double cm = _liveCm ?? committedCm;

        final bool isMetric = unit == HeightUnit.cm;

        return OnboardingStepLayout(
          stepNumber: 2,
          totalSteps: OnboardingData.totalSteps,
          title: 'How tall are you?',
          subtitle: 'Drag the ruler to your height.',
          child: Column(
            children: <Widget>[
              Center(
                child: UnitToggle<HeightUnit>(
                  width: 200,
                  values: HeightUnit.values,
                  selected: unit,
                  labelOf: (HeightUnit u) => u.label,
                  onChanged: (HeightUnit u) {
                    setState(() => _liveCm = cm);
                    context
                        .read<OnboardingBloc>()
                        .add(OnboardingHeightUnitChanged(u));
                  },
                ),
              ),
              const Spacer(),
              MeasurementDisplayCard(
                value: UnitConverter.heightValue(cm, unit),
                unitLabel: isMetric ? 'cm' : 'ft in',
                caption: isMetric
                    ? UnitConverter.formatHeight(cm, HeightUnit.inches)
                    : UnitConverter.formatHeight(cm, HeightUnit.cm),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (isMetric)
                RulerPicker(
                  key: const ValueKey<String>('height-cm'),
                  min: AppConfig.minHeightCm,
                  max: AppConfig.maxHeightCm,
                  value: cm,
                  step: 1,
                  majorEvery: 5,
                  onChanged: (double v) => setState(() => _liveCm = v),
                  onChangeEnd: (double v) {
                    setState(() => _liveCm = null);
                    context
                        .read<OnboardingBloc>()
                        .add(OnboardingHeightChanged(v));
                  },
                )
              else
                RulerPicker(
                  key: const ValueKey<String>('height-in'),
                  min: UnitConverter.cmToInches(AppConfig.minHeightCm)
                      .roundToDouble(),
                  max: UnitConverter.cmToInches(AppConfig.maxHeightCm)
                      .roundToDouble(),
                  value: UnitConverter.cmToInches(cm),
                  step: 1,
                  majorEvery: 6,
                  labelBuilder: (double inches) {
                    final int total = inches.round();
                    return "${total ~/ 12}'${total % 12}";
                  },
                  onChanged: (double inches) => setState(
                    () => _liveCm = UnitConverter.inchesToCm(inches),
                  ),
                  onChangeEnd: (double inches) {
                    setState(() => _liveCm = null);
                    context.read<OnboardingBloc>().add(
                          OnboardingHeightChanged(
                            UnitConverter.inchesToCm(inches),
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
