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
      selected: isSelected,
      label: goal.label,
      child: Opacity(
        opacity: isDisabled ? 0.42 : 1,
        child: AnimatedContainer(
          duration: AppDuration.fast,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isSelected
                ? palette.accent.withValues(alpha: 0.12)
                : palette.surface,
            borderRadius: AppRadius.rMd,
            border: Border.all(
              color: isSelected ? palette.accent : palette.border,
              width: isSelected ? 1.8 : 1,
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
                          color: isSelected
                              ? palette.accent
                              : palette.textSecondary,
                        ),
                        const Spacer(),
                        AnimatedScale(
                          duration: AppDuration.fast,
                          scale: isSelected ? 1 : 0.6,
                          child: AnimatedOpacity(
                            duration: AppDuration.fast,
                            opacity: isSelected ? 1 : 0,
                            child: Container(
                              height: 22,
                              width: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: palette.accent,
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: palette.onAccent,
                              ),
                            ),
                          ),
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
