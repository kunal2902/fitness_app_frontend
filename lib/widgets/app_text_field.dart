import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Standard text input for the account details form.
///
/// Adds on top of [TextFormField]: a label above the field (rather than a
/// floating placeholder, which reads better on dark backgrounds), an
/// optional trailing status widget for async availability checks, and a
/// built-in obscure toggle for passwords.
class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.obscure = false,
    this.prefixIcon,
    this.statusWidget,
    this.inputFormatters,
    this.autofillHints,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final bool obscure;
  final IconData? prefixIcon;

  /// Rendered at the right edge — e.g. a spinner or a green check while
  /// checking whether a username is taken.
  final Widget? statusWidget;

  final List<TextInputFormatter>? inputFormatters;
  final List<String>? autofillHints;

  /// Server-side error for this field, shown under the input.
  final String? errorText;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool autofocus;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.label,
          style: context.text.labelMedium?.copyWith(
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: widget.controller,
          validator: widget.validator,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          textCapitalization: widget.textCapitalization,
          obscureText: _obscured,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          autofillHints: widget.autofillHints,
          inputFormatters: widget.inputFormatters,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          style: context.text.bodyLarge?.copyWith(color: palette.textPrimary),
          cursorColor: palette.accent,
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.errorText,
            prefixIcon:
                widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
            suffixIcon: _buildSuffix(palette),
          ),
        ),
      ],
    );
  }

  Widget? _buildSuffix(AppPalette palette) {
    if (widget.obscure) {
      return IconButton(
        onPressed: () => setState(() => _obscured = !_obscured),
        icon: Icon(
          _obscured
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: AppSize.iconMd,
        ),
        color: palette.textTertiary,
        tooltip: _obscured ? 'Show password' : 'Hide password',
      );
    }
    if (widget.statusWidget != null) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: Center(
          widthFactor: 1,
          child: widget.statusWidget,
        ),
      );
    }
    return null;
  }
}

/// Five-segment strength meter shown under the password field.
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({
    required this.strength,
    required this.label,
    super.key,
  });

  /// 0.0 – 1.0
  final double strength;
  final String label;

  Color _color(BuildContext context) {
    if (strength < 0.4) return AppColors.danger;
    if (strength < 0.7) return AppColors.warning;
    if (strength < 0.9) return AppColors.success;
    return context.palette.accent;
  }

  @override
  Widget build(BuildContext context) {
    if (strength <= 0) return const SizedBox.shrink();
    final Color color = _color(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: strength,
                minHeight: 4,
                backgroundColor: context.palette.border,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: color,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
