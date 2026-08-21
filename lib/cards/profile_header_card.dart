import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../theme/app_theme.dart';
import '../widgets/section_card.dart';
import '../widgets/user_avatar.dart';

/// Top card of the profile tab: who the user is, plus the two entry points
/// for changing it — the camera badge on the avatar and the Edit button.
class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({
    required this.user,
    required this.onEditProfile,
    required this.onEditPhoto,
    this.isUploadingAvatar = false,
    super.key,
  });

  final UserModel? user;
  final VoidCallback onEditProfile;
  final VoidCallback onEditPhoto;
  final bool isUploadingAvatar;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return SectionCard(
      gradient: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // Avatar with the camera badge overlapping its corner.
              SizedBox(
                height: 84,
                width: 84,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    UserAvatar(
                      user: user,
                      size: 84,
                      showBusy: isUploadingAvatar,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Material(
                        color: palette.accent,
                        shape: CircleBorder(
                          side: BorderSide(color: palette.surface, width: 3),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: isUploadingAvatar ? null : onEditPhoto,
                          child: SizedBox(
                            height: 32,
                            width: 32,
                            child: Icon(
                              Icons.photo_camera_rounded,
                              size: 16,
                              color: palette.onAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      user?.fullName.isNotEmpty ?? false
                          ? user!.fullName
                          : 'Your name',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user?.username.isNotEmpty ?? false
                          ? '@${user!.username}'
                          : '@username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium
                          ?.copyWith(color: palette.accent),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),
          Divider(color: palette.border, height: 1),
          const SizedBox(height: AppSpacing.md),

          _InfoRow(
            icon: Icons.mail_outline_rounded,
            label: 'Email',
            value: user?.email ?? '—',
            trailing: (user?.isEmailVerified ?? false)
                ? null
                : const _UnverifiedChip(),
          ),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Member since',
            value: _formatJoined(user?.createdAt),
          ),

          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEditProfile,
              icon: const Icon(Icons.edit_rounded, size: AppSize.iconSm),
              label: const Text('Edit profile'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(AppSize.buttonHeightSm),
                side: BorderSide(color: palette.borderStrong),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatJoined(DateTime? date) {
    if (date == null) return '—';
    const List<String> months = <String>[
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Row(
      children: <Widget>[
        Icon(icon, size: AppSize.iconSm, color: palette.textTertiary),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: context.text.bodySmall?.copyWith(color: palette.textTertiary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodyMedium
                ?.copyWith(color: palette.textPrimary),
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: AppSpacing.xs),
          trailing!,
        ],
      ],
    );
  }
}

class _UnverifiedChip extends StatelessWidget {
  const _UnverifiedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.16),
        borderRadius: AppRadius.rXs,
      ),
      child: Text(
        'UNVERIFIED',
        style: context.text.labelSmall?.copyWith(
          color: AppColors.warning,
          fontSize: 9,
        ),
      ),
    );
  }
}
