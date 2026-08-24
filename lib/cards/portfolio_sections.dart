import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/professional.dart';
import '../theme/app_theme.dart';

/// Section heading used throughout the portfolio.
class PortfolioSectionHeader extends StatelessWidget {
  const PortfolioSectionHeader({
    required this.title,
    required this.icon,
    this.count,
    super.key,
  });

  final String title;
  final IconData icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: <Widget>[
          Icon(icon, size: AppSize.iconSm, color: palette.accent),
          const SizedBox(width: AppSpacing.xs),
          Text(
            title.toUpperCase(),
            style: context.text.labelSmall?.copyWith(color: palette.accent),
          ),
          if (count != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                borderRadius: AppRadius.rXs,
              ),
              child: Text(
                '$count',
                style: context.text.labelSmall?.copyWith(
                  color: palette.textTertiary,
                  fontSize: 10,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Divider(color: palette.border, height: 1)),
        ],
      ),
    );
  }
}

/// One credential.
class CertificationTile extends StatelessWidget {
  const CertificationTile({required this.certification, super.key});

  final Certification certification;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              borderRadius: AppRadius.rSm,
            ),
            child: Icon(
              Icons.verified_rounded,
              size: AppSize.iconMd,
              color: palette.accent,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  certification.title,
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${certification.issuer} · ${certification.year}',
                  style: context.text.bodySmall
                      ?.copyWith(color: palette.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A client result, with before/after images when they exist.
class TransformationCard extends StatelessWidget {
  const TransformationCard({required this.transformation, super.key});

  final ClientTransformation transformation;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final String? before =
        AppConfig.resolveMediaUrl(transformation.beforeImageUrl);
    final String? after =
        AppConfig.resolveMediaUrl(transformation.afterImageUrl);
    final bool hasImages = before != null || after != null;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        gradient: palette.cardGradient,
        borderRadius: AppRadius.rLg,
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (hasImages)
            SizedBox(
              height: 170,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _BeforeAfterImage(url: before, label: 'BEFORE'),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _BeforeAfterImage(url: after, label: 'AFTER'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        transformation.clientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleMedium,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.14),
                        borderRadius: AppRadius.rXs,
                      ),
                      child: Text(
                        transformation.durationLabel,
                        style: context.text.labelSmall?.copyWith(
                          color: palette.accent,
                          fontSize: 10,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  transformation.summary,
                  style: context.text.bodySmall
                      ?.copyWith(color: palette.textSecondary, height: 1.5),
                ),
                if (transformation.highlights.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  ...transformation.highlights.map(
                    (String highlight) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Container(
                              height: 5,
                              width: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: palette.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              highlight,
                              style: context.text.bodySmall?.copyWith(
                                color: palette.textPrimary,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BeforeAfterImage extends StatelessWidget {
  const _BeforeAfterImage({required this.url, required this.label});

  final String? url;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (url == null)
          Container(
            color: palette.surfaceAlt,
            child: Icon(
              Icons.image_outlined,
              color: palette.textTertiary,
              size: AppSize.iconLg,
            ),
          )
        else
          Image.network(
            url!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: palette.surfaceAlt,
              child: Icon(
                Icons.broken_image_outlined,
                color: palette.textTertiary,
                size: AppSize.iconLg,
              ),
            ),
          ),
        Positioned(
          left: AppSpacing.xs,
          bottom: AppSpacing.xs,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: AppRadius.rXs,
            ),
            child: Text(
              label,
              style: context.text.labelSmall?.copyWith(
                color: Colors.white,
                fontSize: 9,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A competition placing, a milestone, a feature.
class AchievementTile extends StatelessWidget {
  const AchievementTile({required this.achievement, super.key});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.rMd,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.emoji_events_rounded,
            size: AppSize.iconMd,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        achievement.title,
                        style: context.text.titleSmall,
                      ),
                    ),
                    if (achievement.year != null) ...<Widget>[
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '${achievement.year}',
                        style: context.text.bodySmall
                            ?.copyWith(color: palette.textTertiary),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.description,
                  style: context.text.bodySmall
                      ?.copyWith(color: palette.textSecondary, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
