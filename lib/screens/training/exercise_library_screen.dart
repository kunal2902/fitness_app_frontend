import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/training_models.dart';
import '../../routes/app_routes.dart';
import '../home/discovery_artwork.dart';
import '../../services/training_repository.dart';
import '../../theme/app_theme.dart';
import 'training_ui.dart';

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({
    required this.repository,
    this.initialMuscleId,
    this.initialMuscleGroup,
    this.initialEquipmentId,
    this.initialAvailableEquipment = false,
    super.key,
  });

  final TrainingRepository repository;
  final String? initialMuscleId;
  final String? initialMuscleGroup;
  final String? initialEquipmentId;
  final bool initialAvailableEquipment;

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

enum _EquipmentFilter { any, none, profile, uses }

class _LibraryFilters {
  const _LibraryFilters({
    this.muscleGroup,
    this.muscleId,
    this.primaryOnly = false,
    this.equipment = _EquipmentFilter.any,
    this.equipmentId,
    this.difficulty,
    this.movement,
    this.trainingType,
    this.loadingMode,
    this.sort = 'relevance',
  });

  final String? muscleGroup;
  final String? muscleId;
  final bool primaryOnly;
  final _EquipmentFilter equipment;
  final String? equipmentId;
  final String? difficulty;
  final String? movement;
  final String? trainingType;
  final String? loadingMode;
  final String sort;

  int get count => <bool>[
        muscleGroup != null,
        muscleId != null,
        equipment != _EquipmentFilter.any,
        difficulty != null,
        movement != null,
        trainingType != null,
        loadingMode != null,
        sort != 'relevance',
      ].where((selected) => selected).length;
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _search = TextEditingController();
  late _LibraryFilters _filters;
  TrainingTaxonomy? _taxonomy;
  Object? _taxonomyError;
  CancelToken? _taxonomyRequest;
  CancelToken? _resultRequest;
  Timer? _debounce;
  List<TrainingExercise> _results = const <TrainingExercise>[];
  Object? _error;
  bool _pageError = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _needsProfile = false;
  String? _profileName;
  String? _releaseId;
  String? _nextCursor;

  @override
  void initState() {
    super.initState();
    final equipment = widget.initialAvailableEquipment
        ? _EquipmentFilter.profile
        : widget.initialEquipmentId == null
            ? _EquipmentFilter.any
            : _EquipmentFilter.uses;
    _filters = _LibraryFilters(
      muscleId: widget.initialMuscleId,
      muscleGroup: widget.initialMuscleGroup,
      equipment: equipment,
      equipmentId: widget.initialEquipmentId,
    );
    unawaited(_loadTaxonomy());
    unawaited(_reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _taxonomyRequest?.cancel();
    _resultRequest?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadTaxonomy() async {
    _taxonomyRequest?.cancel();
    final token = CancelToken();
    _taxonomyRequest = token;
    try {
      final taxonomy = await widget.repository.loadTaxonomy(cancelToken: token);
      if (!mounted || token.isCancelled) return;
      setState(() {
        _taxonomy = taxonomy;
        _taxonomyError = null;
      });
    } on Object catch (error) {
      if (!mounted || token.isCancelled) return;
      setState(() => _taxonomyError = error);
    }
  }

  void _queryChanged() {
    _debounce?.cancel();
    _resultRequest?.cancel();
    setState(() {
      _loading = true;
      _loadingMore = false;
      _needsProfile = false;
      _results = const <TrainingExercise>[];
      _nextCursor = null;
      _error = null;
    });
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_reload()),
    );
  }

  Future<void> _reload({
    bool keepResults = false,
    bool loadMore = false,
  }) async {
    _debounce?.cancel();
    final cursor = loadMore ? _nextCursor : null;
    if (loadMore && (cursor == null || _loadingMore || _loading)) return;
    _resultRequest?.cancel();
    final token = CancelToken();
    _resultRequest = token;
    final filters = _filters;
    final query = _search.text.trim();
    setState(() {
      _loading = !loadMore;
      _loadingMore = loadMore;
      _error = null;
      _needsProfile = false;
      if (!loadMore && !keepResults) {
        _results = const <TrainingExercise>[];
        _nextCursor = null;
        _profileName = null;
      }
    });

    try {
      TrainingEquipmentProfile? profile;
      if (filters.equipment == _EquipmentFilter.profile) {
        final preferences = await widget.repository.loadPreferences(
          cancelToken: token,
        );
        if (!mounted || token.isCancelled) return;
        profile = preferences.activeEquipmentProfile;
        if (profile == null) {
          setState(() {
            _needsProfile = true;
            _results = const <TrainingExercise>[];
            _nextCursor = null;
            _profileName = null;
          });
          return;
        }
      }
      final equipmentMode = switch (filters.equipment) {
        _EquipmentFilter.any => null,
        _EquipmentFilter.uses => 'uses',
        _ => 'available',
      };
      final page = await widget.repository.searchExercises(
        query: query,
        muscleGroup: filters.muscleId == null ? filters.muscleGroup : null,
        muscleIds: <String>{if (filters.muscleId != null) filters.muscleId!},
        muscleRole: filters.primaryOnly ? 'primary' : 'any',
        equipmentMode: equipmentMode,
        equipmentIds: switch (filters.equipment) {
          _EquipmentFilter.none => const <String>{},
          _EquipmentFilter.uses => <String>{filters.equipmentId!},
          _ => null,
        },
        equipmentProfileId: profile?.id,
        difficulty: filters.difficulty,
        movementPattern: filters.movement,
        loadingMode: filters.loadingMode,
        trainingType: filters.trainingType,
        sort: filters.sort,
        cursor: cursor,
        cancelToken: token,
      );
      if (!mounted || token.isCancelled) return;
      if (loadMore && _releaseId != page.releaseId) {
        await _reload(keepResults: true);
        return;
      }
      setState(() {
        _releaseId = page.releaseId;
        _profileName = profile?.name;
        _results = loadMore
            ? <TrainingExercise>[..._results, ...page.items]
            : page.items;
        _nextCursor = page.nextCursor;
      });
      if ((_taxonomy != null || _taxonomyError != null) &&
          _taxonomy?.releaseId != page.releaseId) {
        unawaited(_loadTaxonomy());
      }
    } on Object catch (error) {
      if (!mounted || token.isCancelled) return;
      if (loadMore &&
          error is ApiException &&
          (error.code == 'TRAINING_CATALOGUE_CHANGED' ||
              error.fieldErrors.containsKey('cursor'))) {
        await _reload(keepResults: true);
        return;
      }
      setState(() {
        _error = error;
        _pageError = loadMore;
      });
    } finally {
      if (mounted && !token.isCancelled) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _openFilters() async {
    final taxonomy = _taxonomy;
    if (taxonomy == null) return;
    FocusScope.of(context).unfocus();
    final filters = await showModalBottomSheet<_LibraryFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _FilterSheet(filters: _filters, taxonomy: taxonomy),
    );
    if (!mounted || filters == null) return;
    setState(() => _filters = filters);
    await _reload();
  }

  Future<void> _openEquipment() async {
    final saved = await Navigator.of(
      context,
    ).pushNamed<dynamic>(AppRoutes.trainingEquipment);
    if (!mounted || saved != true) return;
    await _reload();
  }

  void _clearFilters() {
    _search.clear();
    setState(() => _filters = const _LibraryFilters());
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final taxonomy = _releaseId == null || _releaseId == _taxonomy?.releaseId
        ? _taxonomy
        : null;
    final muscles = <String, String>{
      for (final muscle in taxonomy?.muscles ?? const <TrainingMuscle>[])
        muscle.id: muscle.name,
    };
    final muscleGroups = <String, String>{
      for (final muscle in taxonomy?.muscles ?? const <TrainingMuscle>[])
        muscle.id: muscle.group,
    };
    final equipment = <String, String>{
      for (final item in taxonomy?.equipment ?? const <TrainingEquipment>[])
        item.id: item.name,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercises'),
        actions: <Widget>[
          IconButton(
            tooltip: 'My equipment',
            onPressed: _openEquipment,
            icon: const Icon(Icons.fitness_center_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: _search,
                    maxLength: 100,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => _queryChanged(),
                    onSubmitted: (_) => unawaited(_reload()),
                    decoration: InputDecoration(
                      labelText: 'Search exercises',
                      hintText: 'Try pull-up or goblet squat',
                      counterText: '',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _search.clear();
                                _queryChanged();
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: _taxonomy == null ? null : _openFilters,
                        icon: const Icon(Icons.tune),
                        label: Text(
                          _filters.count == 0
                              ? 'Filters'
                              : 'Filters (${_filters.count})',
                        ),
                      ),
                      if (_filters.count > 0)
                        TextButton(
                          onPressed: _clearFilters,
                          child: const Text('Reset'),
                        ),
                      if (_profileName != null)
                        Text(
                          'My equipment: $_profileName',
                          style: context.text.labelMedium?.copyWith(
                            color: context.palette.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  if (_taxonomyError != null &&
                      _taxonomy == null &&
                      _error == null &&
                      !_loading)
                    TrainingNotice(
                      message: 'Filters could not load.',
                      action: _loadTaxonomy,
                    ),
                ],
              ),
            ),
            const Divider(),
            if (_loading && _results.isNotEmpty)
              const LinearProgressIndicator(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await Future.wait(<Future<void>>[
                    _loadTaxonomy(),
                    _reload(keepResults: true),
                  ]);
                },
                child: ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _results.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _results.length) return _footer();
                    final exercise = _results[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _ExerciseTile(
                        exercise: exercise,
                        muscles: muscles,
                        muscleGroups: muscleGroups,
                        equipment: equipment,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    if (_loading && _results.isEmpty || _loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading exercises'),
        ),
      );
    }
    if (_needsProfile) {
      return TrainingNotice(
        message:
            'Choose an active equipment profile to see exercises that fit your setup.',
        action: _openEquipment,
        label: 'Set up my equipment',
      );
    }
    final error = _error;
    if (error != null) {
      return TrainingNotice(
        message: trainingErrorText(error),
        action: () =>
            unawaited(_reload(keepResults: true, loadMore: _pageError)),
      );
    }
    if (_results.isEmpty) {
      return TrainingNotice(
        message: 'No exercises match your search and filters.',
        action: _search.text.isNotEmpty || _filters.count > 0
            ? _clearFilters
            : null,
        label: 'Clear search and filters',
      );
    }
    if (_nextCursor != null) {
      return Center(
        child: TextButton(
          onPressed: _loading ? null : () => unawaited(_reload(loadMore: true)),
          child: const Text('Load more exercises'),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({
    required this.exercise,
    required this.muscles,
    required this.muscleGroups,
    required this.equipment,
  });

  final TrainingExercise exercise;
  final Map<String, String> muscles;

  /// Muscle id to muscle group, so a bodyweight movement with no equipment to
  /// show can fall back to the artwork for the region it trains.
  final Map<String, String> muscleGroups;
  final Map<String, String> equipment;

  /// The image behind the card.
  ///
  /// An approved poster from the catalogue wins: it is the only image that
  /// actually shows this movement. Everything after it is category artwork
  /// chosen for recognition, not instruction.
  ImageProvider<Object>? _artwork() {
    final TrainingMedia? poster = exercise.poster;
    if (poster != null) return NetworkImage(poster.url);
    return DiscoveryArtwork.exercise(
      exerciseId: exercise.id,
      equipmentIds: <String>[
        for (final TrainingEquipmentRequirement group
            in exercise.equipmentRequirementGroups)
          ...group.anyOf,
        ...exercise.optionalEquipmentIds,
      ],
      muscleGroup: exercise.primaryMuscleIds
          .map((String id) => muscleGroups[id])
          .firstWhere((String? group) => group != null, orElse: () => null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targets = exercise.primaryMuscleIds
        .map((id) => muscles[id] ?? trainingLabel(id))
        .join(', ');
    final requirements = requiredEquipmentLabels(exercise, equipment);
    final equipmentText = exercise.equipmentStatus == 'unknown'
        ? 'Equipment unconfirmed'
        : requirements.isEmpty
            ? 'No required equipment'
            : requirements.map((group) {
                return requirements.length > 1 && group.contains(' or ')
                    ? '($group)'
                    : group;
              }).join(' + ');
    final ImageProvider<Object>? artwork = _artwork();
    final AppPalette palette = context.palette;
    final String meta =
        '${trainingLabel(exercise.difficulty)} · $targets';

    return Semantics(
      button: true,
      label: '${exercise.name}. $meta. $equipmentText',
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.rMd,
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(
            context,
          ).pushNamed(AppRoutes.exerciseDetail, arguments: exercise.id),
          child: SizedBox(
            // Tall enough for three lines of text at the app's 1.3 scaling
            // cap without the scrim crowding the name.
            height: 118 * MediaQuery.textScalerOf(context).scale(16) / 16,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (artwork != null)
                  Image(
                    image: artwork,
                    fit: BoxFit.cover,
                    // Category artwork is decorative; the Semantics label
                    // above already names the exercise.
                    excludeFromSemantics: true,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                // Left-weighted so the text stays readable over any
                // photograph while the image still shows on the right.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: artwork == null
                          ? <Color>[palette.surface, palette.surface]
                          : <Color>[
                              Colors.black.withValues(alpha: 0.88),
                              Colors.black.withValues(alpha: 0.35),
                            ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              exercise.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.titleMedium?.copyWith(
                                color: artwork == null ? null : Colors.white,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(
                                color: artwork == null
                                    ? palette.textSecondary
                                    : Colors.white70,
                              ),
                            ),
                            Text(
                              equipmentText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(
                                color: artwork == null
                                    ? palette.textSecondary
                                    : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: artwork == null
                            ? palette.textSecondary
                            : Colors.white,
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
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.filters, required this.taxonomy});

  final _LibraryFilters filters;
  final TrainingTaxonomy taxonomy;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _group = widget.filters.muscleGroup;
  late String? _muscle = widget.filters.muscleId;
  late bool _primaryOnly = widget.filters.primaryOnly;
  late _EquipmentFilter _equipment = widget.filters.equipment;
  late String? _equipmentId = widget.filters.equipmentId;
  late String? _difficulty = widget.filters.difficulty;
  late String? _movement = widget.filters.movement;
  late String? _trainingType = widget.filters.trainingType;
  late String? _loadingMode = widget.filters.loadingMode;
  late String _sort = widget.filters.sort;

  @override
  Widget build(BuildContext context) {
    final taxonomy = widget.taxonomy;
    final fields = <Widget>[
      _choice(
        'Muscle group',
        _group,
        <String, String>{
          for (final group in taxonomy.muscleGroups) group.id: group.name,
        },
        (value) => setState(() {
          _group = value;
          _muscle = null;
        }),
      ),
      _choice(
        'Muscle',
        _muscle,
        <String, String>{
          for (final muscle in taxonomy.muscles)
            if (_group == null || muscle.group == _group)
              muscle.id: muscle.name,
        },
        (value) => setState(() => _muscle = value),
      ),
      if (_group != null || _muscle != null)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Primary target only'),
          value: _primaryOnly,
          onChanged: (value) => setState(() => _primaryOnly = value),
        ),
      _choice(
        'Equipment',
        _equipment.name,
        const <String, String>{
          'none': 'No required equipment',
          'profile': 'Fits my active equipment profile',
          'uses': 'Uses selected equipment',
        },
        (value) => setState(
          () => _equipment = _EquipmentFilter.values.byName(value ?? 'any'),
        ),
      ),
      if (_equipment == _EquipmentFilter.uses)
        _choice(
          'Equipment used',
          _equipmentId,
          <String, String>{
            for (final item in taxonomy.equipment) item.id: item.name,
          },
          (value) => setState(() => _equipmentId = value),
          emptyLabel: 'Choose equipment',
        ),
      _choice(
        'Difficulty',
        _difficulty,
        _labels(taxonomy.difficulties),
        (value) => setState(() => _difficulty = value),
      ),
      _choice(
        'Training type',
        _trainingType,
        _labels(taxonomy.trainingTypes),
        (value) => setState(() => _trainingType = value),
      ),
      _choice(
        'Movement',
        _movement,
        _labels(taxonomy.movementPatternIds),
        (value) => setState(() => _movement = value),
      ),
      _choice(
        'Loading',
        _loadingMode,
        _labels(const <String>['bodyweight', 'added_load', 'assisted']),
        (value) => setState(() => _loadingMode = value),
      ),
      _choice(
        'Sort by',
        _sort,
        const <String, String>{'name': 'Name', 'difficulty': 'Difficulty'},
        (value) => setState(() => _sort = value ?? 'relevance'),
        emptyLabel: 'Relevance',
      ),
    ];

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                'Exercise filters',
                style: context.text.headlineSmall,
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: fields,
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FilledButton(
                onPressed: _equipment == _EquipmentFilter.uses &&
                        !taxonomy.equipment
                            .any((item) => item.id == _equipmentId)
                    ? null
                    : () => Navigator.of(context).pop(
                          _LibraryFilters(
                            muscleGroup: _group,
                            muscleId: _muscle,
                            primaryOnly: _primaryOnly &&
                                (_group != null || _muscle != null),
                            equipment: _equipment,
                            equipmentId: _equipmentId,
                            difficulty: _difficulty,
                            movement: _movement,
                            trainingType: _trainingType,
                            loadingMode: _loadingMode,
                            sort: _sort,
                          ),
                        ),
                child: const Text('Apply filters'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, String> _labels(List<String> ids) => <String, String>{
        for (final id in ids) id: trainingLabel(id),
      };

  Widget _choice(
    String title,
    String? value,
    Map<String, String> choices,
    ValueChanged<String?> onChanged, {
    String emptyLabel = 'Any',
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: InputDecorator(
          decoration: InputDecoration(labelText: title),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: choices.containsKey(value) ? value : '',
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: '', child: Text(emptyLabel)),
                for (final entry in choices.entries)
                  DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => onChanged(value == '' ? null : value),
            ),
          ),
        ),
      );
}
