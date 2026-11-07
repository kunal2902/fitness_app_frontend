import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:fitness_app/models/training_models.dart';
import 'package:fitness_app/routes/app_routes.dart';
import 'package:fitness_app/screens/training/exercise_detail_screen.dart';
import 'package:fitness_app/screens/training/exercise_library_screen.dart';
import 'package:fitness_app/services/training_repository.dart';
import 'package:fitness_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _pushUp = TrainingExercise(
  id: 'push_up',
  version: 1,
  name: 'Push-up',
  primaryMuscleIds: ['pectorals'],
  secondaryMuscleIds: ['triceps'],
  movementPatternIds: ['horizontal_push'],
  equipmentStatus: 'known',
  equipmentRequirementGroups: [],
  optionalEquipmentIds: [],
  difficulty: 'beginner',
  trainingType: 'strength',
  loadingMode: 'bodyweight',
  measurementType: 'reps',
  unilateral: false,
  releaseId: 'test_release',
  instructions: ['Set your hands on the floor.'],
);

class _Repository extends Fake implements TrainingRepository {
  final delayedSearch = Completer<TrainingExercisePage>();
  CancelToken? delayedToken;

  @override
  Future<TrainingTaxonomy> loadTaxonomy({CancelToken? cancelToken}) async =>
      const TrainingTaxonomy(
        catalogueVersion: 1,
        releaseId: 'test_release',
        muscleGroups: [TrainingMuscleGroup(id: 'chest', name: 'Chest')],
        muscles: [
          TrainingMuscle(
            id: 'pectorals',
            name: 'Chest muscles',
            group: 'chest',
          ),
          TrainingMuscle(id: 'triceps', name: 'Triceps', group: 'arms'),
        ],
        equipment: [],
      );

  @override
  Future<TrainingExercisePage> searchExercises({
    String query = '',
    Set<String> muscleIds = const {},
    String? muscleGroup,
    String muscleRole = 'any',
    String? equipmentMode,
    Set<String>? equipmentIds,
    String? equipmentProfileId,
    String? difficulty,
    String? movementPattern,
    String? loadingMode,
    String? trainingType,
    String? sort,
    String? cursor,
    int limit = 20,
    CancelToken? cancelToken,
  }) async {
    if (query == 'push') {
      delayedToken = cancelToken;
      return delayedSearch.future;
    }
    return const TrainingExercisePage(
      catalogueVersion: 1,
      releaseId: 'test_release',
      items: [],
    );
  }

  @override
  Future<TrainingExercise> loadExercise(
    String id, {
    CancelToken? cancelToken,
  }) async =>
      _pushUp;
}

void main() {
  testWidgets('a slow search cannot replace the newer result', (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ExerciseLibraryScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    final search = find.byType(TextField);
    await tester.enterText(search, 'push');
    await tester.pump(const Duration(milliseconds: 310));
    expect(repository.delayedToken, isNotNull);
    await tester.enterText(search, 'squat');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();

    expect(repository.delayedToken!.isCancelled, isTrue);
    repository.delayedSearch.complete(
      const TrainingExercisePage(
        catalogueVersion: 1,
        releaseId: 'test_release',
        items: [_pushUp],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Push-up'), findsNothing);
  });

  testWidgets('detail links a named muscle to the filtered library',
      (tester) async {
    RouteSettings? target;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ExerciseDetailScreen(
          repository: _Repository(),
          exerciseId: 'push_up',
        ),
        onGenerateRoute: (settings) {
          target = settings;
          return MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('Filtered exercise results')),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('demonstration is not available'),
      findsOneWidget,
    );
    final muscle = find.text('Chest muscles');
    await tester.scrollUntilVisible(muscle, 180);
    await tester.ensureVisible(muscle);
    await tester.pumpAndSettle();
    await tester.tap(muscle.hitTestable());
    await tester.pumpAndSettle();
    expect(target?.name, AppRoutes.exerciseLibrary);
    expect(
      (target?.arguments as ExerciseLibraryArguments?)?.initialMuscleId,
      'pectorals',
    );
  });
}
