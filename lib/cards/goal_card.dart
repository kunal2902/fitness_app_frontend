import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/enums.dart';
import '../theme/app_theme.dart';

/// Grid tile for Q4. Multi-select, so the affordance is a checkbox-style
/// badge in the corner rather than a radio dot.
class GoalCard extends StatelessWidget {
  const GoalCard({
    required this.goal,
    required this.isSelected,
    required this.onTap,
    this.isDisabled = false,
    super.key,
  });

  final FitnessGoal goal;
  final bool isSelected;
  final VoidCallback onTap;

  /// True once the selection cap is reached and this one isn't picked.
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Semantics(
      button: true,
      enabled: !isDisabled,
      selected: isSelected,
      label: goal.label,
      child: Opacity(
        opacity: isDisabled ? 0.42 : 1,
        child: AnimatedContainer(
          duration: AppDuration.fast,
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 122),
          decoration: BoxDecoration(
            color: isSelected ? palette.surfaceAlt : palette.surface,
            borderRadius: AppRadius.rMd,
            border: Border.all(
              color: isSelected ? palette.accent : palette.border,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.rMd,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: isDisabled
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onTap();
                    },
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          goal.icon,
                          size: AppSize.iconLg,
                          color: palette.textPrimary,
                        ),
                        const Spacer(),
                        Container(
                          height: 22,
                          width: 22,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: isSelected ? palette.accent : null,
                            border: Border.all(
                              color: isSelected
                                  ? palette.accent
                                  : palette.borderStrong,
                            ),
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 15,
                                  color: palette.onAccent,
                                )
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      goal.label,
                      style: context.text.titleSmall?.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    if (goal.subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        goal.subtitle!,
                        style: context.text.bodySmall?.copyWith(
                          color: palette.textTertiary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
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
