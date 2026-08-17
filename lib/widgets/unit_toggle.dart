import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// A two-or-more-way segmented control with a sliding pill behind the
/// active segment. Used for cm/inches and kg/lbs.
///
/// Generic so it works with any value type:
/// ```dart
/// UnitToggle<HeightUnit>(
///   values: HeightUnit.values,
///   selected: unit,
///   labelOf: (u) => u.label,
///   onChanged: (u) => bloc.add(OnboardingHeightUnitChanged(u)),
/// )
/// ```
class UnitToggle<T> extends StatelessWidget {
  const UnitToggle({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.width,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;
  final double? width;

  static const double _height = 44;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final int index = values.indexOf(selected);
    final int safeIndex = index < 0 ? 0 : index;

    return Container(
      width: width,
      height: _height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: AppRadius.rPill,
        border: Border.all(color: palette.border),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double segmentWidth = constraints.maxWidth / values.length;
          return Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: AppDuration.normal,
                curve: Curves.easeOutCubic,
                left: safeIndex * segmentWidth,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.accent,
                    borderRadius: AppRadius.rPill,
                  ),
                ),
              ),
              Row(
                children: values.map((T value) {
                  final bool isActive = value == selected;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (isActive) return;
                        HapticFeedback.selectionClick();
                        onChanged(value);
                      },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: AppDuration.fast,
                          style: context.text.labelMedium!.copyWith(
                            color: isActive
                                ? palette.onAccent
                                : palette.textSecondary,
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w600,
                          ),
                          child: Text(labelOf(value)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}
