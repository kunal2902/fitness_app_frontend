import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The same reading width and hierarchy for sign-in and account creation.
class AuthFormLayout extends StatelessWidget {
  const AuthFormLayout({
    required this.formKey,
    required this.eyebrow,
    required this.title,
    required this.children,
    this.description,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final String eyebrow;
  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: formKey,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              children: [
                Text(
                  eyebrow,
                  style: context.text.labelSmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  header: true,
                  child: Text(title, style: context.text.displayMedium),
                ),
                if (description != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(description!, style: context.text.bodyMedium),
                ],
                const SizedBox(height: AppSpacing.lg),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.lg),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
