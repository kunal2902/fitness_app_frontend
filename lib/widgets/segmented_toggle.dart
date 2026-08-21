import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// A segmented control with a sliding pill behind the active segment.
///
/// Generic over the value type, so the same widget drives the cm/inches and
/// kg/lbs toggles in onboarding and the previous/goal toggle on the
/// calendar card:
///
/// ```dart
/// SegmentedToggle<HeightUnit>(
///   values: HeightUnit.values,
///   selected: unit,
///   labelOf: (u) => u.label,
///   onChanged: (u) => bloc.add(OnboardingHeightUnitChanged(u)),
/// )
/// ```
class SegmentedToggle<T> extends StatelessWidget {
  const SegmentedToggle({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.width,
    this.dense = false,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;
  final double? width;

  /// Shorter and tighter, for use inside a card header.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final int index = values.indexOf(selected);
    final int safeIndex = index < 0 ? 0 : index;
    final double height = dense ? 34 : 44;

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(dense ? 3 : 4),
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                          ),
                          child: AnimatedDefaultTextStyle(
                            duration: AppDuration.fast,
                            style: (dense
                                    ? context.text.labelSmall!
                                    : context.text.labelMedium!)
                                .copyWith(
                              letterSpacing: dense ? 0.2 : null,
                              color: isActive
                                  ? palette.onAccent
                                  : palette.textSecondary,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w600,
                            ),
                            child: Text(
                              labelOf(value),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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
