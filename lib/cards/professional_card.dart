import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/professional.dart';
import '../theme/app_theme.dart';
import '../widgets/presence_dot.dart';

/// A coach in the Assistance list.
///
/// Leads with the things that decide whether someone taps: who they are,
/// whether they are available *right now*, and what they are good at.
class ProfessionalCard extends StatelessWidget {
  const ProfessionalCard({
    required this.professional,
    required this.onTap,
    super.key,
  });

  final Professional professional;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final String? avatar = AppConfig.resolveMediaUrl(professional.avatarUrl);

    // "New" rather than "0.0 (0)" — an unrated coach should not look badly
    // rated.
    final String rating = professional.ratingAverage.toStringAsFixed(1);
    final String ratingLabel = professional.ratingCount == 0
        ? 'New'
        : '$rating (${professional.ratingCount})';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        gradient: palette.cardGradient,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: palette.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.rLg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _Avatar(
                      professional: professional,
                      avatarUrl: avatar,
                      size: 64,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            professional.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            professional.headline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          PresenceLabel(
                            isOnline: professional.isOnline,
                            label: professional.presenceLabel,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.md),

                // Credibility row: rating, experience, clients — then the
                // rate, pushed right.
                //
                // Both halves are Flexible + scale-down rather than a
                // Spacer between rigid children: six intrinsically-sized
                // widgets on a 320dp phone at 1.3x text scale overflow the
                // row, and an overflow here paints the yellow stripes
                // straight across the card.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _MetaChip(
                              icon: Icons.star_rounded,
                              label: ratingLabel,
                              tint: AppColors.warning,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            _MetaChip(
                              icon: Icons.workspace_premium_rounded,
                              label: '${professional.yearsExperience}y',
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            _MetaChip(
                              icon: Icons.groups_rounded,
                              label: '${professional.clientsCoached}',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          textBaseline: TextBaseline.alphabetic,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          children: <Widget>[
                            Text(
                              professional.formattedRate,
                              style: context.text.titleMedium
                                  ?.copyWith(color: palette.accent),
                            ),
                            Text(
                              ' /session',
                              style: context.text.bodySmall
                                  ?.copyWith(color: palette.textTertiary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                if (professional.specialities.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: professional.specialities
                        .take(4)
                        .map(
                          (Speciality s) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: palette.accent.withValues(alpha: 0.12),
                              borderRadius: AppRadius.rXs,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(s.icon, size: 12, color: palette.accent),
                                const SizedBox(width: 4),
                                Text(
                                  s.label,
                                  style: context.text.labelSmall?.copyWith(
                                    color: palette.accent,
                                    fontSize: 10,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.professional,
    required this.avatarUrl,
    required this.size,
  });

  final Professional professional;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          ClipOval(
            child: SizedBox(
              height: size,
              width: size,
              child: avatarUrl == null
                  ? _Monogram(initials: professional.initials, size: size)
                  : Image.network(
                      avatarUrl!,
                      fit: BoxFit.cover,
                      cacheWidth: (size * 3).round(),
                      errorBuilder: (_, __, ___) =>
                          _Monogram(initials: professional.initials, size: size),
                    ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 2,
            child: PresenceDot(
              isOnline: professional.isOnline,
              ringColor: palette.surfaceHigh,
            ),
          ),
        ],
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.initials, required this.size});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.voltGradient),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
          color: AppColors.onVolt,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.tint});

  final IconData icon;
  final String label;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: tint ?? palette.textTertiary),
        const SizedBox(width: 3),
        Text(
          label,
          style: context.text.bodySmall?.copyWith(
            color: palette.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
