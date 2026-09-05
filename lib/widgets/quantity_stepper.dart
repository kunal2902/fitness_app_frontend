import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// How many of a serving the user is logging.
///
/// Steps in halves rather than whole numbers, because half a katori and
/// one and a half rotis are ordinary portions and forcing them through a
/// keyboard for every meal is what makes a food diary tedious enough to
/// abandon. Long-press the field to type an exact amount.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    required this.quantity,
    required this.onChanged,
    this.step = 0.5,
    this.min = 0.5,
    this.max = 99,
    this.onTapValue,
    super.key,
  });

  final double quantity;
  final ValueChanged<double> onChanged;
  final double step;
  final double min;
  final double max;

  /// Opens an exact-entry field. Null hides the affordance.
  final VoidCallback? onTapValue;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final bool canDecrease = quantity - step >= min - 0.0001;
    final bool canIncrease = quantity + step <= max + 0.0001;

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: AppRadius.rPill,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StepButton(
            icon: Icons.remove_rounded,
            onPressed: canDecrease
                ? () => onChanged(_snap(quantity - step))
                : null,
          ),
          GestureDetector(
            onTap: onTapValue,
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 64),
              child: Text(
                formatQuantity(quantity),
                textAlign: TextAlign.center,
                style: context.text.titleMedium
                    ?.copyWith(color: palette.textPrimary),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            onPressed:
                canIncrease ? () => onChanged(_snap(quantity + step)) : null,
          ),
        ],
      ),
    );
  }

  /// Keeps the value on the step grid. Floating-point addition drifts —
  /// 0.5 + 0.5 + 0.5 is 1.5000000000000002 — and that drift ends up in the
  /// `quantity` field of a request, where the server echoes it back into
  /// the diary as "1.5000000000000002 × 1 katori".
  double _snap(double value) {
    final double snapped = (value / step).round() * step;
    return (snapped * 100).round() / 100;
  }

  /// Two decimals at most, no trailing zeroes: "1", "1.5", "0.25".
  static String formatQuantity(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final bool enabled = onPressed != null;

    return InkWell(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onPressed!();
            }
          : null,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Icon(
          icon,
          size: AppSize.iconMd,
          color: enabled ? palette.accent : palette.textTertiary,
        ),
      ),
    );
  }
}
