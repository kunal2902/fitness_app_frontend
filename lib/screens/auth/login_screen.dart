import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/primary_button.dart';

/// Sign-in for returning users. Accepts either the username or the email.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identifier = TextEditingController();
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    context.read<AuthBloc>().add(
          AuthLoginSubmitted(
            identifier: _identifier.text.trim(),
            password: _password.text,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return BlocConsumer<AuthBloc, AuthState>(
      listener: (BuildContext context, AuthState state) {
        if (state.status == AuthFlowStatus.failure) {
          AppSnackbar.error(
            context,
            state.errorMessage ?? 'Could not sign you in.',
          );
        }
        if (state.isAuthenticated) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            AppRoutes.home,
            (Route<dynamic> route) => false,
          );
        }
      },
      builder: (BuildContext context, AuthState state) {
        final bool busy = state.isSubmitting;

        return Scaffold(
          appBar: AppBar(
            leading: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: CircleIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: busy ? null : () => Navigator.of(context).pop(),
              ),
            ),
            leadingWidth: 60,
          ),
          body: GlowBackground(
            alignment: const Alignment(0, -0.9),
            child: SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  children: <Widget>[
                    Text(
                      'WELCOME BACK',
                      style: context.text.labelSmall
                          ?.copyWith(color: palette.accent),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Sign in', style: context.text.displaySmall),
                    const SizedBox(height: AppSpacing.xxl),

                    AppTextField(
                      label: 'Username or email',
                      controller: _identifier,
                      hint: 'you@example.com',
                      prefixIcon: Icons.person_outline_rounded,
                      enabled: !busy,
                      autofillHints: const <String>[AutofillHints.username],
                      validator: (String? v) =>
                          (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    AppTextField(
                      label: 'Password',
                      controller: _password,
                      prefixIcon: Icons.lock_outline_rounded,
                      obscure: true,
                      enabled: !busy,
                      textInputAction: TextInputAction.done,
                      autofillHints: const <String>[AutofillHints.password],
                      validator: (String? v) =>
                          (v ?? '').isEmpty ? 'Required' : null,
                      onSubmitted: (_) => _submit(),
                    ),

                    const SizedBox(height: AppSpacing.xxl),
                    PrimaryButton(
                      label: 'Sign in',
                      isLoading: busy,
                      onPressed: busy ? null : _submit,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: GhostButton(
                        label: 'New here? Create an account',
                        onPressed: busy
                            ? null
                            : () => Navigator.of(context)
                                .pushNamed(AppRoutes.onboarding),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
