import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/onboarding/onboarding_bloc.dart';
import '../../config/app_config.dart';
import '../../models/api_exception.dart';
import '../../models/auth_models.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/primary_button.dart';

/// Final step of signup — the account itself.
///
/// The nine answers are already buffered in [OnboardingBloc]; this screen
/// adds the credentials and fires the single `POST /auth/signup` that
/// creates the user and their fitness profile together.
class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _username = TextEditingController();
  final TextEditingController _fullName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  final AuthService _authService = AuthService();

  Timer? _debounce;
  bool _checkingAvailability = false;
  String? _usernameServerError;
  String? _emailServerError;
  double _passwordStrength = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _username.dispose();
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Availability check (debounced)
  // -------------------------------------------------------------------------

  void _scheduleAvailabilityCheck() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 550), _checkAvailability);
  }

  Future<void> _checkAvailability() async {
    final String username = _username.text.trim();
    final String email = _email.text.trim();

    // Only ask the server about values that are already locally valid.
    final bool usernameOk = Validators.username(username) == null;
    final bool emailOk = Validators.email(email) == null;
    if (!usernameOk && !emailOk) return;

    setState(() => _checkingAvailability = true);
    try {
      final AvailabilityResult result = await _authService.checkAvailability(
        username: usernameOk ? username : null,
        email: emailOk ? email : null,
      );
      if (!mounted) return;
      setState(() {
        _usernameServerError = (usernameOk && !result.usernameAvailable)
            ? 'That username is taken'
            : null;
        _emailServerError = (emailOk && !result.emailAvailable)
            ? 'An account with this email already exists'
            : null;
      });
    } on ApiException {
      // Availability is a convenience — signup still validates server-side.
    } finally {
      if (mounted) setState(() => _checkingAvailability = false);
    }
  }

  // -------------------------------------------------------------------------
  // Submit
  // -------------------------------------------------------------------------

  void _submit() {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_usernameServerError != null || _emailServerError != null) return;

    final OnboardingState onboarding = context.read<OnboardingBloc>().state;

    if (!onboarding.data.isComplete) {
      AppSnackbar.error(
        context,
        'Some questions are still unanswered. Go back and finish them first.',
      );
      return;
    }

    context.read<AuthBloc>().add(
          AuthSignupSubmitted(
            username: _username.text.trim(),
            fullName: _fullName.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            fitnessProfile: onboarding.data,
          ),
        );
  }

  void _applyServerFieldErrors(Map<String, String> errors) {
    setState(() {
      _usernameServerError = errors['username'];
      _emailServerError = errors['email'];
    });
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return BlocConsumer<AuthBloc, AuthState>(
      listener: (BuildContext context, AuthState state) {
        if (state.status == AuthFlowStatus.failure) {
          if (state.fieldErrors.isNotEmpty) {
            _applyServerFieldErrors(state.fieldErrors);
          }
          AppSnackbar.error(
            context,
            state.errorMessage ?? 'Signup failed. Please try again.',
          );
        }

        if (state.isAuthenticated && state.justSignedUp) {
          context.read<OnboardingBloc>().add(const OnboardingReset());
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
                      'ALMOST THERE',
                      style: context.text.labelSmall
                          ?.copyWith(color: palette.accent),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Create your account', style: context.text.displaySmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Your answers are saved — this is the last step.',
                      style: context.text.bodyMedium
                          ?.copyWith(color: palette.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    AppTextField(
                      label: 'Username',
                      controller: _username,
                      hint: 'e.g. iron_kunal',
                      prefixIcon: Icons.alternate_email_rounded,
                      enabled: !busy,
                      autofillHints: const <String>[AutofillHints.newUsername],
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        LengthLimitingTextInputFormatter(
                          AppConfig.usernameMaxLength,
                        ),
                      ],
                      validator: Validators.username,
                      errorText: _usernameServerError,
                      statusWidget: _checkingAvailability
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      onChanged: (_) {
                        if (_usernameServerError != null) {
                          setState(() => _usernameServerError = null);
                        }
                        _scheduleAvailabilityCheck();
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    AppTextField(
                      label: 'Full name',
                      controller: _fullName,
                      hint: 'Your name as you want it shown',
                      prefixIcon: Icons.person_outline_rounded,
                      enabled: !busy,
                      keyboardType: TextInputType.name,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const <String>[AutofillHints.name],
                      inputFormatters: <TextInputFormatter>[
                        LengthLimitingTextInputFormatter(
                          AppConfig.fullNameMaxLength,
                        ),
                      ],
                      validator: Validators.fullName,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    AppTextField(
                      label: 'Email',
                      controller: _email,
                      hint: 'you@example.com',
                      prefixIcon: Icons.mail_outline_rounded,
                      enabled: !busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const <String>[AutofillHints.email],
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      validator: Validators.email,
                      errorText: _emailServerError,
                      onChanged: (_) {
                        if (_emailServerError != null) {
                          setState(() => _emailServerError = null);
                        }
                        _scheduleAvailabilityCheck();
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    AppTextField(
                      label: 'Password',
                      controller: _password,
                      hint: 'At least ${AppConfig.passwordMinLength} characters',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscure: true,
                      enabled: !busy,
                      textInputAction: TextInputAction.done,
                      autofillHints: const <String>[AutofillHints.newPassword],
                      inputFormatters: <TextInputFormatter>[
                        LengthLimitingTextInputFormatter(
                          AppConfig.passwordMaxLength,
                        ),
                      ],
                      validator: Validators.password,
                      onChanged: (String value) => setState(
                        () => _passwordStrength =
                            Validators.passwordStrength(value),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    PasswordStrengthBar(
                      strength: _passwordStrength,
                      label: Validators.strengthLabel(_passwordStrength),
                    ),

                    const SizedBox(height: AppSpacing.xxl),
                    PrimaryButton(
                      label: 'Create account',
                      isLoading: busy,
                      onPressed: busy ? null : _submit,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(
                            'Already have an account? ',
                            style: context.text.bodyMedium
                                ?.copyWith(color: palette.textSecondary),
                          ),
                          GestureDetector(
                            onTap: busy
                                ? null
                                : () => Navigator.of(context)
                                    .pushNamed(AppRoutes.login),
                            child: Text(
                              'Sign in',
                              style: context.text.bodyMedium?.copyWith(
                                color: palette.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
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
