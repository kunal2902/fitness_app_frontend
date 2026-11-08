import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/enums.dart';
import '../theme/app_theme.dart';

/// Large tap target for Q1. Two of these sit side by side.
class GenderCard extends StatelessWidget {
  const GenderCard({
    required this.gender,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final Gender gender;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Semantics(
      button: true,
      selected: isSelected,
      label: gender.label,
      child: AnimatedContainer(
        duration: AppDuration.normal,
        curve: Curves.easeOut,
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
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.xl,
                horizontal: AppSpacing.md,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedContainer(
                    duration: AppDuration.normal,
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.rSm,
                      color: isSelected ? palette.accent : palette.surfaceHigh,
                    ),
                    child: Icon(
                      gender.icon,
                      size: 30,
                      color:
                          isSelected ? palette.onAccent : palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    gender.label,
                    textAlign: TextAlign.center,
                    style: context.text.titleLarge?.copyWith(
                      color: isSelected
                          ? palette.textPrimary
                          : palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
