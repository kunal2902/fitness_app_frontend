import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/profile/profile_bloc.dart';
import '../../config/app_config.dart';
import '../../models/user_model.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/glow_background.dart';
import '../../widgets/primary_button.dart';

/// Edit name, username and email.
///
/// Only changed fields are sent — a PATCH with every field would let a
/// stale value here overwrite an edit made somewhere else.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final UserModel? _original = AppStore.instance.user;
  late final TextEditingController _fullName =
      TextEditingController(text: _original?.fullName ?? '');
  late final TextEditingController _username =
      TextEditingController(text: _original?.username ?? '');
  late final TextEditingController _email =
      TextEditingController(text: _original?.email ?? '');

  @override
  void initState() {
    super.initState();
    for (final TextEditingController c in <TextEditingController>[
      _fullName,
      _username,
      _email,
    ]) {
      c.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _email.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _hasChanges =>
      _changedFullName != null ||
      _changedUsername != null ||
      _changedEmail != null;

  String? get _changedFullName {
    final String value = _fullName.text.trim();
    return value == (_original?.fullName ?? '') ? null : value;
  }

  String? get _changedUsername {
    final String value = _username.text.trim().toLowerCase();
    return value == (_original?.username ?? '') ? null : value;
  }

  String? get _changedEmail {
    final String value = _email.text.trim().toLowerCase();
    return value == (_original?.email ?? '') ? null : value;
  }

  /// Set when this screen submits, so an avatar upload finishing
  /// elsewhere cannot close the form out from under the user.
  bool _submitted = false;

  void _save() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }

    _submitted = true;
    context.read<ProfileBloc>().add(
          ProfileUpdateSubmitted(
            fullName: _changedFullName,
            username: _changedUsername,
            email: _changedEmail,
          ),
        );
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;

    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: context.palette.surfaceHigh,
        title: const Text('Discard changes?'),
        content: const Text('Your edits have not been saved.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return BlocConsumer<ProfileBloc, ProfileState>(
      listenWhen: (ProfileState a, ProfileState b) =>
          a.isSaving != b.isSaving ||
          a.successMessage != b.successMessage ||
          a.errorMessage != b.errorMessage,
      listener: (BuildContext context, ProfileState state) {
        // The parent screen owns the snackbar; this one just closes once
        // the save lands.
        if (_submitted && !state.isSaving && state.successMessage != null) {
          Navigator.of(context).pop();
        }
        if (_submitted && !state.isSaving && state.errorMessage != null) {
          // Let them correct the highlighted field and try again.
          _submitted = false;
        }
      },
      builder: (BuildContext context, ProfileState state) {
        final bool busy = state.isSaving;

        return PopScope(
          canPop: !_hasChanges && !busy,
          onPopInvokedWithResult: (bool didPop, Object? result) async {
            if (didPop || busy) return;
            if (await _confirmDiscard() && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Edit profile'),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: busy
                    ? null
                    : () async {
                        if (await _confirmDiscard() && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
              ),
            ),
            body: GlowBackground(
              alignment: const Alignment(0, -0.9),
              child: SafeArea(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.xxl,
                    ),
                    children: <Widget>[
                      AppTextField(
                        label: 'Full name',
                        controller: _fullName,
                        prefixIcon: Icons.person_outline_rounded,
                        enabled: !busy,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: <TextInputFormatter>[
                          LengthLimitingTextInputFormatter(
                            AppConfig.fullNameMaxLength,
                          ),
                        ],
                        validator: Validators.fullName,
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      AppTextField(
                        label: 'Username',
                        controller: _username,
                        prefixIcon: Icons.alternate_email_rounded,
                        enabled: !busy,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.deny(RegExp(r'\s')),
                          LengthLimitingTextInputFormatter(
                            AppConfig.usernameMaxLength,
                          ),
                        ],
                        validator: Validators.username,
                        errorText: state.fieldErrors['username'],
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      AppTextField(
                        label: 'Email',
                        controller: _email,
                        prefixIcon: Icons.mail_outline_rounded,
                        enabled: !busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        ],
                        validator: Validators.email,
                        errorText: state.fieldErrors['email'],
                        onSubmitted: (_) => _save(),
                      ),

                      if (_changedEmail != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(
                              Icons.info_outline_rounded,
                              size: AppSize.iconSm,
                              color: AppColors.warning,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                'Changing your email marks it unverified until '
                                'you confirm the new address.',
                                style: context.text.bodySmall
                                    ?.copyWith(color: palette.textTertiary),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: AppSpacing.xxl),
                      PrimaryButton(
                        label: 'Save changes',
                        isLoading: busy,
                        onPressed: (busy || !_hasChanges) ? null : _save,
                      ),
                      if (!_hasChanges) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Center(
                          child: Text(
                            'Nothing changed yet',
                            style: context.text.bodySmall
                                ?.copyWith(color: palette.textTertiary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
