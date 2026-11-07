import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/training_models.dart';
import '../../routes/app_routes.dart';
import '../../services/training_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/exercise_muscle_map.dart';
import '../../widgets/section_card.dart';
import 'exercise_demo.dart';
import 'training_ui.dart';

class ExerciseDetailScreen extends StatefulWidget {
  const ExerciseDetailScreen({
    required this.repository,
    required this.exerciseId,
    super.key,
  });

  final TrainingRepository repository;
  final String exerciseId;

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  CancelToken? _request;
  TrainingExercise? _exercise;
  TrainingTaxonomy? _taxonomy;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _request?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _request?.cancel();
    final token = CancelToken();
    _request = token;
    setState(() => _error = null);
    try {
      var exercise = await widget.repository.loadExercise(
        widget.exerciseId,
        cancelToken: token,
      );
      if (!mounted || token.isCancelled) return;
      TrainingTaxonomy? taxonomy;
      try {
        taxonomy = await widget.repository.loadTaxonomy(cancelToken: token);
      } on ApiException {
        // The reviewed exercise is independently usable if labels fail to load.
      }
      if (!mounted || token.isCancelled) return;
      if (taxonomy != null && taxonomy.releaseId != exercise.releaseId) {
        exercise = await widget.repository.loadExercise(
          widget.exerciseId,
          cancelToken: token,
        );
        if (taxonomy.releaseId != exercise.releaseId) taxonomy = null;
      }
      if (!mounted || token.isCancelled) return;
      setState(() {
        _exercise = exercise;
        _taxonomy = taxonomy;
      });
    } on Object catch (error) {
      if (!mounted || token.isCancelled) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _exercise;
    final error = _error;
    final Widget body;
    if (exercise != null) {
      body = _ExerciseContent(exercise: exercise, taxonomy: _taxonomy);
    } else if (error != null) {
      body = Center(
        child: Padding(
          padding: AppSpacing.page,
          child: TrainingNotice(
            message: trainingErrorText(error),
            action: _load,
          ),
        ),
      );
    } else {
      body = const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading exercise'),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise details')),
      body: SafeArea(top: false, child: body),
    );
  }
}

class _ExerciseContent extends StatelessWidget {
  const _ExerciseContent({required this.exercise, required this.taxonomy});

  final TrainingExercise exercise;
  final TrainingTaxonomy? taxonomy;

  @override
  Widget build(BuildContext context) {
    final muscleLabels = <String, String>{
      for (final muscle in taxonomy?.muscles ?? const <TrainingMuscle>[])
        muscle.id: muscle.name,
    };
    final equipmentLabels = <String, String>{
      for (final item in taxonomy?.equipment ?? const <TrainingEquipment>[])
        item.id: item.name,
    };
    final requirements = requiredEquipmentLabels(exercise, equipmentLabels);
    final optionalEquipment = exercise.optionalEquipmentIds
        .map((id) => equipmentLabels[id] ?? trainingLabel(id))
        .toList();
    final measurement = switch (exercise.measurementType) {
      'duration' => 'Time in seconds',
      'distance' => 'Distance in metres',
      'reps_load' => exercise.loadingMode == 'assisted'
          ? 'Reps and assistance in kg'
          : 'Reps and added load in kg',
      _ => 'Repetitions',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: <Widget>[
        Text(exercise.name, style: context.text.headlineMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          <String>[
            trainingLabel(exercise.difficulty),
            trainingLabel(exercise.trainingType),
            trainingLabel(exercise.loadingMode),
          ].join(' · '),
          style: context.text.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(exercise.unilateral ? '$measurement per side' : measurement),
        const SizedBox(height: AppSpacing.lg),
        ExerciseDemo(
          key: ValueKey<String>(
            '${exercise.releaseId}:${exercise.id}:${exercise.version}',
          ),
          exercise: exercise,
        ),
        const SizedBox(height: AppSpacing.md),
        ExerciseMuscleMap(
          onMuscleTap: (id) => Navigator.of(context).pushNamed(
            AppRoutes.exerciseLibrary,
            arguments: ExerciseLibraryArguments(initialMuscleId: id),
          ),
          primary: <String, String>{
            for (final id in exercise.primaryMuscleIds)
              id: muscleLabels[id] ?? trainingLabel(id),
          },
          secondary: <String, String>{
            for (final id in exercise.secondaryMuscleIds)
              id: muscleLabels[id] ?? trainingLabel(id),
          },
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Equipment',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (exercise.equipmentStatus == 'unknown')
                const Text('Equipment requirements are unconfirmed.')
              else if (requirements.isEmpty)
                const Text('No required equipment')
              else ...<Widget>[
                if (requirements.length > 1)
                  const Text('Choose an option from each row.'),
                for (final requirement in requirements)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      requirements.length > 1 ? '•  $requirement' : requirement,
                    ),
                  ),
              ],
              if (optionalEquipment.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Optional equipment\n${optionalEquipment.join(', ')}',
                  style: context.text.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _TechniqueCard(
          title: 'Instructions',
          items: exercise.instructions,
          numbered: true,
        ),
        const SizedBox(height: AppSpacing.md),
        _TechniqueCard(title: 'Form cues', items: exercise.formCues),
        const SizedBox(height: AppSpacing.md),
        _TechniqueCard(
          title: 'Common mistakes',
          items: exercise.commonMistakes,
        ),
        if (exercise.regressionIds.isNotEmpty ||
            exercise.progressionIds.isNotEmpty ||
            exercise.substitutionIds.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Related exercises',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _related(context, 'Easier', exercise.regressionIds),
                _related(context, 'Harder', exercise.progressionIds),
                _related(context, 'Substitutions', exercise.substitutionIds),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _related(BuildContext context, String label, List<String> ids) {
    if (ids.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: context.text.titleSmall),
          for (final id in ids)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(trainingLabel(id)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).pushNamed(AppRoutes.exerciseDetail, arguments: id),
            ),
        ],
      ),
    );
  }
}

class _TechniqueCard extends StatelessWidget {
  const _TechniqueCard({
    required this.title,
    required this.items,
    this.numbered = false,
  });

  final String title;
  final List<String> items;
  final bool numbered;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final (index, text) in items.indexed)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == items.length - 1 ? 0 : AppSpacing.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(numbered ? '${index + 1}.' : '•'),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
          ],
        ),
      );
}
