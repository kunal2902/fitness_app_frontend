import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/training_models.dart';
import '../../routes/app_routes.dart';
import '../../services/training_repository.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/discovery_carousel.dart';
import '../../widgets/montage_background.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_card.dart';
import 'discovery_artwork.dart';

/// Training discovery entry point in the signed-in tab shell.
class HomeScreen extends StatefulWidget {
  const HomeScreen({this.repository, super.key});

  /// Injectable for tests. The tab builds its own against the live session.
  final TrainingRepository? repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// The eight groups of the locked taxonomy. Held here rather than fetched
  /// because they are stable across releases and Home is the first screen the
  /// user sees — a spinner where the main navigation should be is worse than a
  /// list that cannot go stale. Equipment is fetched, because that list does
  /// grow with a release.
  static const List<_MuscleGroup> _muscleGroups = <_MuscleGroup>[
    _MuscleGroup('chest', 'Chest', Icons.fitness_center_rounded),
    _MuscleGroup('back', 'Back', Icons.rowing_rounded),
    _MuscleGroup('shoulders', 'Shoulders', Icons.sports_gymnastics_rounded),
    _MuscleGroup('arms', 'Arms', Icons.sports_mma_rounded),
    _MuscleGroup('core', 'Core', Icons.self_improvement_rounded),
    _MuscleGroup('hips', 'Hips', Icons.directions_walk_rounded),
    _MuscleGroup('thighs', 'Thighs', Icons.directions_run_rounded),
    _MuscleGroup('lower_legs', 'Lower legs', Icons.stairs_rounded),
  ];

  TrainingRepository? _owned;
  List<TrainingEquipment>? _equipment;
  bool _equipmentFailed = false;

  TrainingRepository get _repository => widget.repository ?? _owned!;

  @override
  void initState() {
    super.initState();
    if (widget.repository == null) {
      final AppStore store = context.read<AppStore>();
      final String? accountId = store.isAuthenticated ? store.user?.id : null;
      _owned = ApiTrainingRepository(
        isSessionCurrent: () =>
            accountId != null &&
            store.isAuthenticated &&
            store.user?.id == accountId,
      );
    }
    unawaited(_loadEquipment());
  }

  @override
  void dispose() {
    if (_owned case final ApiTrainingRepository repository) {
      repository.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEquipment() async {
    try {
      final TrainingTaxonomy taxonomy = await _repository.loadTaxonomy();
      if (!mounted) return;
      setState(() {
        _equipment = taxonomy.equipment;
        _equipmentFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Home still works without it: "My equipment" and the library are both
      // reachable below, so a failed taxonomy costs the carousel and nothing
      // else.
      setState(() => _equipmentFailed = true);
    }
  }

  void _openLibrary(ExerciseLibraryArguments arguments) {
    Navigator.of(context).pushNamed(
      AppRoutes.exerciseLibrary,
      arguments: arguments,
    );
  }

  List<DiscoveryCarouselItem> get _muscleSlides {
    return <DiscoveryCarouselItem>[
      for (final _MuscleGroup group in _muscleGroups)
        DiscoveryCarouselItem(
          id: group.id,
          label: group.label,
          icon: group.icon,
          image: DiscoveryArtwork.muscle(group.id),
          onTap: () => _openLibrary(
            ExerciseLibraryArguments(initialMuscleGroup: group.id),
          ),
        ),
    ];
  }

  List<DiscoveryCarouselItem> get _equipmentSlides {
    final List<TrainingEquipment> items = _equipment ?? const [];
    return <DiscoveryCarouselItem>[
      for (final TrainingEquipment item in items)
        DiscoveryCarouselItem(
          id: item.id,
          label: item.name,
          subtitle: _equipmentCategoryLabel(item.category),
          icon: _equipmentIcon(item.id, item.category),
          image: DiscoveryArtwork.equipment(item.id),
          imageAlignment: item.id == 'band_anchor'
              ? const Alignment(0, -0.93)
              : Alignment.center,
          onTap: () => _openLibrary(
            ExerciseLibraryArguments(initialEquipmentId: item.id),
          ),
        ),
    ];
  }

  Future<void> _showPhotoCredits() async {
    final String credits = await DefaultAssetBundle.of(context)
        .loadString(DiscoveryArtwork.creditsAsset)
        .onError((_, __) => 'Photo credits could not load.');
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.76,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: AppSpacing.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Discovery photo credits',
                  style: sheetContext.text.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      credits,
                      style: sheetContext.text.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? firstName = context.select<AppStore, String?>(
      (AppStore store) => store.user?.firstName,
    );
    final AppPalette palette = context.palette;

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              0,
              AppSpacing.xxl,
            ),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'TRAINING',
                      style: context.text.labelSmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      firstName == null || firstName.isEmpty
                          ? 'Home'
                          : 'Hi, $firstName',
                      style: context.text.displayMedium,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _ExerciseLibraryCard(),
                    const SizedBox(height: AppSpacing.xxxl),
                    Text(
                      'Browse by muscle',
                      style: context.text.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
              DiscoveryCarousel(items: _muscleSlides),
              const SizedBox(height: AppSpacing.xxxl),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Browse by equipment',
                      style: context.text.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
              if (_equipment == null && !_equipmentFailed)
                const _CarouselSkeleton()
              else if (_equipmentFailed)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.lg),
                  child: _EquipmentUnavailable(onRetry: _loadEquipment),
                )
              else
                DiscoveryCarousel(items: _equipmentSlides),
              const SizedBox(height: AppSpacing.xxxl),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.lg),
                child: SectionCard(
                  padding: EdgeInsets.zero,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: AppRadius.rMd,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: <Widget>[
                        ListTile(
                          leading: const Icon(Icons.tune_rounded),
                          title: const Text('My equipment'),
                          subtitle:
                              const Text('Manage your equipment profiles'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context)
                              .pushNamed(AppRoutes.trainingEquipment),
                        ),
                        const Divider(
                          height: 1,
                          indent: AppSpacing.md,
                          endIndent: AppSpacing.md,
                        ),
                        ListTile(
                          leading: const Icon(Icons.fitness_center_rounded),
                          title: const Text('Train with my equipment'),
                          subtitle:
                              const Text('Find exercises for your saved kit'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _openLibrary(
                            const ExerciseLibraryArguments(
                              initialAvailableEquipment: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.lg),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: _showPhotoCredits,
                    child: const Text('Photo credits'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MuscleGroup {
  const _MuscleGroup(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

String _equipmentCategoryLabel(String category) {
  return switch (category) {
    'free_weight' => 'Free weight',
    'resistance' => 'Resistance',
    'support' => 'Support',
    'accessory' => 'Accessory',
    _ => category.replaceAll('_', ' '),
  };
}

/// Per-item icons where one reads clearly, falling back to the category so a
/// newly added item is never iconless.
IconData _equipmentIcon(String id, String category) {
  return switch (id) {
    'pull_up_bar' || 'low_row_bar' => Icons.horizontal_rule_rounded,
    'resistance_band' || 'band_anchor' => Icons.waves_rounded,
    'dumbbell' || 'dumbbell_pair' => Icons.fitness_center_rounded,
    'kettlebell' => Icons.sports_handball_rounded,
    'barbell' => Icons.fitness_center_rounded,
    'flat_bench' || 'adjustable_bench' => Icons.weekend_rounded,
    'exercise_mat' => Icons.crop_landscape_rounded,
    'wall' => Icons.square_foot_rounded,
    'elevated_support' || 'plyo_box' => Icons.inbox_rounded,
    'parallettes' || 'dip_bar' => Icons.table_rows_rounded,
    'gymnastic_rings' => Icons.circle_outlined,
    'jump_rope' => Icons.timeline_rounded,
    'weighted_vest' => Icons.shield_moon_rounded,
    _ => switch (category) {
        'free_weight' => Icons.fitness_center_rounded,
        'resistance' => Icons.waves_rounded,
        'accessory' => Icons.category_rounded,
        _ => Icons.handyman_rounded,
      },
  };
}

class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return SizedBox(
      height: 184,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        children: <Widget>[
          for (int i = 0; i < 3; i++)
            Container(
              width: 240,
              margin: const EdgeInsets.only(right: AppSpacing.sm),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: AppRadius.rMd,
                border: Border.all(color: palette.border),
              ),
            ),
        ],
      ),
    );
  }
}

class _EquipmentUnavailable extends StatelessWidget {
  const _EquipmentUnavailable({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: <Widget>[
          Icon(Icons.cloud_off_rounded, color: context.palette.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Could not load the equipment list.',
              style: context.text.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () => onRetry(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// The first thing a signed-in user sees, so it carries the montage.
///
/// Text and button colours are fixed light rather than taken from the
/// palette: they sit over footage and a scrim in both themes, where the
/// palette's dark-on-light would disappear.
class _ExerciseLibraryCard extends StatelessWidget {
  const _ExerciseLibraryCard();

  /// Bundle the clip at this path and add it to
  /// `MontageBackground.bundledAssets` to switch the motion on. Until then the
  /// card shows the poster still, which is why it looks finished either way.
  static const String _montage = 'assets/video/library_montage.mp4';

  /// The compilation shown until a clip is bundled.
  ///
  /// Ordered to move around the body rather than through similar frames, so
  /// consecutive slides do not look like the same photograph twice. All are
  /// already licensed and credited in `assets/discovery_photo_credits.txt`.
  static const List<String> _sequence = <String>[
    'chest',
    'back',
    'thighs',
    'shoulders',
    'core',
    'arms',
  ];

  @override
  Widget build(BuildContext context) {
    return MontageBackground(
      asset: _montage,
      stills: <ImageProvider<Object>>[
        for (final String group in _sequence)
          if (DiscoveryArtwork.muscle(group) case final AssetImage art) art,
      ],
      // The floor under both moving tiers, so the card is never a grey box.
      poster: DiscoveryArtwork.muscle('chest'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                border: Border.all(color: Colors.white24),
                borderRadius: AppRadius.rSm,
              ),
              child: const Icon(
                Icons.fitness_center_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Exercise library',
              style: context.text.displaySmall?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Find movements for your next session and see which muscles they target.',
              style: context.text.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Find exercises',
              icon: Icons.arrow_forward_rounded,
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.exerciseLibrary),
            ),
          ],
        ),
      ),
    );
  }
}
