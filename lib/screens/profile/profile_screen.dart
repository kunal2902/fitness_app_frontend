import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/profile/profile_bloc.dart';
import '../../cards/enrolled_activities_card.dart';
import '../../cards/profile_header_card.dart';
import '../../cards/workout_calendar_card.dart';
import '../../config/app_config.dart';
import '../../models/user_model.dart';
import '../../models/workout_day.dart';
import '../../routes/app_routes.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/glow_background.dart';
import 'edit_profile_screen.dart';

/// Profile tab: who you are, how consistent you have been, and what you
/// are enrolled in.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ProfileBloc>(
      create: (_) => ProfileBloc()..add(const ProfileStarted()),
      child: const _ProfileView(),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    final ProfileBloc bloc = context.read<ProfileBloc>();
    final ImagePicker picker = ImagePicker();

    try {
      // Downscale at pick time. A modern phone camera produces 4–8 MB
      // files that the 5 MB server limit would reject, and an avatar never
      // renders above a couple of hundred pixels.
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: AppConfig.avatarMaxDimension.toDouble(),
        maxHeight: AppConfig.avatarMaxDimension.toDouble(),
        imageQuality: AppConfig.avatarJpegQuality,
      );
      if (file == null) return;
      bloc.add(ProfileAvatarSelected(file.path));
    } on Exception {
      if (!context.mounted) return;
      AppSnackbar.error(
        context,
        'Could not open your photos. Check the app permissions and try again.',
      );
    }
  }

  Future<void> _showPhotoOptions(BuildContext context, bool hasAvatar) async {
    final AppPalette palette = context.palette;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: palette.borderStrong,
                    borderRadius: AppRadius.rPill,
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.photo_library_rounded,
                    color: palette.accent,
                  ),
                  title: const Text('Choose from gallery'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickImage(context, ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.photo_camera_rounded,
                    color: palette.accent,
                  ),
                  title: const Text('Take a photo'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickImage(context, ImageSource.camera);
                  },
                ),
                if (hasAvatar)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.danger,
                    ),
                    title: const Text(
                      'Remove current photo',
                      style: TextStyle(color: AppColors.danger),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context
                          .read<ProfileBloc>()
                          .add(const ProfileAvatarRemoved());
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEditProfile(BuildContext context) async {
    final ProfileBloc bloc = context.read<ProfileBloc>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider<ProfileBloc>.value(
          value: bloc,
          child: const EditProfileScreen(),
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: context.palette.surfaceHigh,
        title: const Text('Sign out?'),
        content: const Text(
          'Your saved answers stay on this device, but you will need to sign '
          'in again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<AuthBloc>().add(const AuthLogoutRequested());
              Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.welcome,
                (Route<dynamic> route) => false,
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The user comes from the store rather than AuthBloc so an avatar or
    // name change repaints here the moment it is persisted.
    final UserModel? user = context.watch<AppStore>().user;

    return BlocConsumer<ProfileBloc, ProfileState>(
      listenWhen: (ProfileState a, ProfileState b) =>
          a.errorMessage != b.errorMessage ||
          a.successMessage != b.successMessage,
      listener: (BuildContext context, ProfileState state) {
        if (state.errorMessage != null) {
          AppSnackbar.error(context, state.errorMessage!);
          context.read<ProfileBloc>().add(const ProfileMessageCleared());
        } else if (state.successMessage != null) {
          AppSnackbar.success(context, state.successMessage!);
          // Keep AuthBloc's copy of the user in step with the store.
          final UserModel? updated = AppStore.instance.user;
          if (updated != null) {
            context.read<AuthBloc>().add(AuthUserUpdated(updated));
          }
          context.read<ProfileBloc>().add(const ProfileMessageCleared());
        }
      },
      builder: (BuildContext context, ProfileState state) {
        final ProfileBloc bloc = context.read<ProfileBloc>();

        return Scaffold(
          body: GlowBackground(
            alignment: const Alignment(0, -0.95),
            child: SafeArea(
              child: RefreshIndicator(
                // Wait for the reload to finish, otherwise the spinner
                // snaps away before any data has actually arrived.
                onRefresh: () async {
                  bloc.add(const ProfileStarted());
                  await bloc.stream.firstWhere(
                    (ProfileState s) =>
                        !s.isLoadingCalendar && !s.isLoadingActivities,
                  );
                },
                color: context.palette.accent,
                backgroundColor: context.palette.surfaceHigh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text('Profile', style: context.text.displaySmall),
                        ),
                        IconButton(
                          tooltip: 'Sign out',
                          onPressed: () => _confirmSignOut(context),
                          icon: const Icon(Icons.logout_rounded),
                          color: context.palette.textSecondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    ProfileHeaderCard(
                      user: user,
                      isUploadingAvatar: state.isUploadingAvatar,
                      onEditProfile: () => _openEditProfile(context),
                      onEditPhoto: () => _showPhotoOptions(
                        context,
                        (user?.avatarUrl ?? '').isNotEmpty,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    WorkoutCalendarCard(
                      mode: state.calendarMode,
                      visibleMonth: state.visibleMonth,
                      dayLookup: state.dayLookup,
                      streak: state.streak,
                      isLoading: state.isLoadingCalendar,
                      onModeChanged: (CalendarMode mode) =>
                          bloc.add(ProfileCalendarModeChanged(mode)),
                      onMonthChanged: (DateTime month) =>
                          bloc.add(ProfileMonthChanged(month)),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    EnrolledActivitiesCard(
                      activities: state.activities,
                      isLoading: state.isLoadingActivities,
                      onExplore: () => AppSnackbar.show(
                        context,
                        'Activities are coming in the next phase.',
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
