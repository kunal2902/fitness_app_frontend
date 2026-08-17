import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/enums.dart';
import '../theme/app_theme.dart';

/// Full-width selectable row — the workhorse for the rep-range questions
/// (pull-ups, push-ups, squats, dips) and fitness level.
///
/// Works with anything implementing [SelectableOption], so all five
/// questions share one widget.
class OptionCard extends StatelessWidget {
  const OptionCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
    this.trailing,
    super.key,
  });

  final SelectableOption option;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Semantics(
      button: true,
      selected: isSelected,
      label: option.label,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isSelected
              ? palette.accent.withValues(alpha: 0.10)
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
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  if (option.icon != null) ...<Widget>[
                    Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? palette.accent.withValues(alpha: 0.16)
                            : palette.surfaceAlt,
                        borderRadius: AppRadius.rSm,
                      ),
                      child: Icon(
                        option.icon,
                        size: AppSize.iconMd,
                        color:
                            isSelected ? palette.accent : palette.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          option.label,
                          style: context.text.titleMedium?.copyWith(
                            color: isSelected
                                ? palette.textPrimary
                                : palette.textPrimary,
                          ),
                        ),
                        if (option.subtitle != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            option.subtitle!,
                            style: context.text.bodySmall?.copyWith(
                              color: palette.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  trailing ?? _SelectionDot(isSelected: isSelected),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return AnimatedContainer(
      duration: AppDuration.fast,
      height: 24,
      width: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? palette.accent : Colors.transparent,
        border: Border.all(
          color: isSelected ? palette.accent : palette.borderStrong,
          width: 1.6,
        ),
      ),
      child: isSelected
          ? Icon(Icons.check_rounded, size: 16, color: palette.onAccent)
          : null,
    );
  }
}
