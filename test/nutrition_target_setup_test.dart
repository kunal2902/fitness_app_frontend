import 'dart:async';

import 'package:fitness_app/blocs/nutrition/nutrition_summary_bloc.dart';
import 'package:fitness_app/blocs/nutrition/nutrition_status.dart';
import 'package:fitness_app/models/api_exception.dart';
import 'package:fitness_app/models/enums.dart';
import 'package:fitness_app/models/food_log.dart';
import 'package:fitness_app/models/nutrition_target_setup.dart';
import 'package:fitness_app/models/onboarding_data.dart';
import 'package:fitness_app/screens/nutrition/nutrition_target_sheet.dart';
import 'package:fitness_app/services/nutrition_repository.dart';
import 'package:fitness_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/nutrition_fakes.dart';

const NutritionTargetSetup targetSetup = NutritionTargetSetup(
  age: 30,
  gender: Gender.male,
  heightCm: 175,
  weightKg: 70,
  activityLevel: NutritionActivityLevel.sedentary,
  goal: NutritionWeightGoal.maintain,
);
const OnboardingData onboardingProfile = OnboardingData(
  gender: Gender.male,
  heightCm: 175,
  weightKg: 70,
  goals: <FitnessGoal>[FitnessGoal.buildStrength],
  fitnessLevel: FitnessLevel.advanced,
);
NutritionTargetRecommendation previewFor(NutritionTargetSetup setup) =>
    NutritionTargetRecommendation(
      setup: setup,
      target: sampleTarget,
      bmrKcal: 1648.8,
      tdeeKcal: 1978.5,
      policyVersion: 'mifflin-v1-candidate-1',
      reviewed: false,
      warnings: const <String>['An estimate, not medical advice.'],
    );

Finder field(String name) => find.byKey(ValueKey<String>(name));
String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(field(key)).controller!.text;

void main() {
  test('setup roundtrips without changing the signup contract', () {
    expect(NutritionTargetSetup.fromJson(targetSetup.toJson()), targetSetup);
    expect(onboardingProfile.toJson(), isNot(contains('age')));
    expect(onboardingProfile.toJson(), isNot(contains('activityLevel')));
    final NutritionTarget target = NutritionTarget.fromJson(<String, dynamic>{
      ...sampleTarget.asMacros.toJson(),
      'setup': targetSetup.toJson(),
    });
    expect(target.setup, targetSetup);
    expect(
      NutritionTarget.fromJson(sampleTarget.asMacros.toJson()).setup,
      isNull,
    );
  });

  test(
      'conflicting goals require a choice; skill level does not imply activity',
      () {
    expect(NutritionWeightGoal.fromFitnessGoals(<FitnessGoal>[]), isNull);
    expect(
      NutritionWeightGoal.fromFitnessGoals(
        <FitnessGoal>[FitnessGoal.loseFat, FitnessGoal.buildMuscle],
      ),
      isNull,
    );
    expect(
      NutritionWeightGoal.fromFitnessGoals(
        <FitnessGoal>[FitnessGoal.weightGain],
      ),
      NutritionWeightGoal.gainWeight,
    );
    expect(
      NutritionWeightGoal.fromFitnessGoals(
        <FitnessGoal>[FitnessGoal.loseFat],
      ),
      NutritionWeightGoal.loseFat,
    );
  });

  test('invalid setup and malformed recommendations are rejected', () {
    expect(
      () => NutritionTargetSetup.fromJson(
        <String, dynamic>{...targetSetup.toJson(), 'age': 17},
      ),
      throwsFormatException,
    );
    expect(
      () => NutritionTargetSetup.fromJson(
        <String, dynamic>{...targetSetup.toJson(), 'age': 30.5},
      ),
      throwsFormatException,
    );
    expect(
      () => NutritionTargetRecommendation.fromJson(<String, dynamic>{}),
      throwsFormatException,
    );
  });

  group('Target setup UI', () {
    late FakeNutritionRepository repository;
    late NutritionSummaryBloc bloc;
    setUp(() {
      repository = FakeNutritionRepository();
      repository.onRecommend =
          (NutritionTargetSetup setup) async => previewFor(setup);
      bloc = NutritionSummaryBloc(repository: repository);
    });
    tearDown(() async {
      await bloc.close();
      repository.dispose();
    });

    Future<void> show(
      WidgetTester tester, {
      NutritionTarget? current,
      OnboardingData? profile = onboardingProfile,
    }) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RepositoryProvider<NutritionRepository>.value(
            value: repository,
            child: BlocProvider<NutritionSummaryBloc>.value(
              value: bloc,
              child: Scaffold(
                body: NutritionTargetSheet(current: current, profile: profile),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> fillSetup(WidgetTester tester) async {
      await tester.tap(find.text('Estimate from my profile'));
      await tester.pumpAndSettle();
      await tester.enterText(field('setup-age'), '30');
      await tester.tap(field('setup-activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(NutritionActivityLevel.sedentary.label).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('setup-confirm'));
      await tester.tap(field('setup-confirm'));
      await tester.pump();
    }

    testWidgets(
        'profile prefill has no automatic age, activity or network write',
        (WidgetTester tester) async {
      await show(tester);
      await tester.tap(find.text('Estimate from my profile'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'setup-age'), isEmpty);
      expect(fieldText(tester, 'setup-height'), '175.0');
      expect(fieldText(tester, 'setup-weight'), '70.0');
      expect(
        tester
            .widget<DropdownButton<NutritionActivityLevel>>(
              field('setup-activity'),
            )
            .value,
        isNull,
      );
      await tester.ensureVisible(field('calculate-targets'));
      await tester.tap(field('calculate-targets'));
      await tester.pump();
      expect(repository.recommendations, isEmpty);
      expect(repository.targetUpdates, isEmpty);
    });

    testWidgets(
        'preview is read-only; copying it fills editable fields without saving',
        (WidgetTester tester) async {
      await show(tester);
      await fillSetup(tester);
      await tester.ensureVisible(field('calculate-targets'));
      await tester.tap(field('calculate-targets'));
      await tester.pumpAndSettle();
      expect(repository.recommendations.single, targetSetup);
      expect(repository.targetUpdates, isEmpty);
      expect(
        find.text('Development preview — awaiting review'),
        findsOneWidget,
      );
      await tester.ensureVisible(field('use-target-estimate'));
      await tester.tap(field('use-target-estimate'));
      await tester.pump();
      expect(fieldText(tester, 'target-energy'), '2000');
      expect(fieldText(tester, 'target-protein'), '100');
      expect(repository.targetUpdates, isEmpty);
      // A failed save retains the form and metadata, ready for an explicit retry.
      repository.onTargets = (_) async => throw const ApiException.timeout();
      await tester.ensureVisible(find.text('Save goals'));
      await tester.tap(find.text('Save goals'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        if (bloc.state.targetSave.status != NutritionWriteStatus.failure) {
          await bloc.stream
              .firstWhere(
                (NutritionSummaryState state) =>
                    state.targetSave.status == NutritionWriteStatus.failure,
              )
              .timeout(const Duration(seconds: 2));
        }
      });
      await tester.pumpAndSettle();
      expect(repository.targetUpdates.single.setup, targetSetup);
      expect(fieldText(tester, 'target-energy'), '2000');
      expect(
        find.text('The server took too long to respond. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'editing existing targets preserves decimal precision and sends only changed fields',
        (WidgetTester tester) async {
      const NutritionTarget existing = NutritionTarget(
        kcal: 2100,
        proteinG: 110.25,
        carbsG: 251.5,
        fatG: 63.75,
      );
      await show(tester, current: existing);
      expect(fieldText(tester, 'target-protein'), '110.25');
      expect(fieldText(tester, 'target-fat'), '63.75');
      await tester.enterText(field('target-protein'), '120.5');
      repository.onTargets = (_) async => throw const ApiException.network();
      await tester.tap(find.text('Save goals'));
      await tester.pumpAndSettle();
      final NutritionTargetEdit edit = repository.targetUpdates.single;
      expect(edit.proteinG, 120.5);
      expect(edit.kcal, isNull);
      expect(edit.carbsG, isNull);
      expect(edit.fatG, isNull);
      expect(fieldText(tester, 'target-protein'), '120.5');
      expect(repository.recommendations, isEmpty);
    });

    testWidgets('changed setup cancels old request and ignores a late preview',
        (WidgetTester tester) async {
      final Completer<NutritionTargetRecommendation> pending =
          Completer<NutritionTargetRecommendation>();
      repository.onRecommend = (_) => pending.future;
      await show(tester);
      await fillSetup(tester);
      await tester.ensureVisible(field('calculate-targets'));
      await tester.tap(field('calculate-targets'));
      await tester.pump();
      await tester.enterText(field('setup-age'), '31');
      await tester.pump();
      expect(repository.recommendationTokens.single!.isCancelled, isTrue);
      pending.complete(previewFor(targetSetup));
      await tester.pumpAndSettle();
      expect(field('use-target-estimate'), findsNothing);
      expect(repository.targetUpdates, isEmpty);
    });

    testWidgets('unsupported estimates explain the field error and allow retry',
        (WidgetTester tester) async {
      repository.onRecommend = (_) async => throw const ApiException(
            message: 'Please fix the highlighted fields.',
            statusCode: 422,
            fieldErrors: <String, String>{
              'weightKg': 'These measurements need individual guidance.',
            },
          );
      await show(tester);
      await fillSetup(tester);
      await tester.ensureVisible(field('calculate-targets'));
      await tester.tap(field('calculate-targets'));
      await tester.pumpAndSettle();
      expect(
        find.text('These measurements need individual guidance.'),
        findsOneWidget,
      );
      expect(fieldText(tester, 'setup-weight'), '70.0');
      expect(field('use-target-estimate'), findsNothing);
      repository.onRecommend =
          (NutritionTargetSetup setup) async => previewFor(setup);
      await tester.ensureVisible(field('calculate-targets'));
      await tester.tap(field('calculate-targets'));
      await tester.pumpAndSettle();
      expect(field('use-target-estimate'), findsOneWidget);
      expect(repository.targetUpdates, isEmpty);
    });

    testWidgets('save prevents double taps and closes only after confirmation',
        (WidgetTester tester) async {
      final Completer<NutritionTarget> pending = Completer<NutritionTarget>();
      repository.onTargets = (_) => pending.future;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RepositoryProvider<NutritionRepository>.value(
            value: repository,
            child: BlocProvider<NutritionSummaryBloc>.value(
              value: bloc,
              child: Builder(
                builder: (BuildContext context) => Scaffold(
                  body: TextButton(
                    onPressed: () => NutritionTargetSheet.show(
                      context,
                      current: sampleTarget,
                    ),
                    child: const Text('Open goals'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open goals'));
      await tester.pumpAndSettle();
      await tester.enterText(field('target-energy'), '2100');
      await tester.ensureVisible(find.text('Save goals'));
      await tester.tap(find.text('Save goals'));
      await tester.tap(find.text('Save goals'));
      await tester.pump();
      expect(repository.targetUpdates, hasLength(1));
      expect(find.byType(NutritionTargetSheet), findsOneWidget);
      await tester.runAsync(() async {
        pending.complete(sampleTarget);
        await bloc.stream
            .firstWhere(
              (NutritionSummaryState state) =>
                  state.targetSave.status == NutritionWriteStatus.success,
            )
            .timeout(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();
      expect(find.byType(NutritionTargetSheet), findsNothing);
      expect(repository.targetUpdates, hasLength(1));
    });

    testWidgets(
        'saved inputs reopen for confirmation and closing cancels pending preview',
        (WidgetTester tester) async {
      final Completer<NutritionTargetRecommendation> pending =
          Completer<NutritionTargetRecommendation>();
      repository.onRecommend = (_) => pending.future;
      await show(
        tester,
        current: const NutritionTarget(
          kcal: 2000,
          proteinG: 100,
          carbsG: 250,
          fatG: 65,
          setup: targetSetup,
        ),
      );
      await tester.tap(find.text('Estimate from my profile'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'setup-age'), '30');
      expect(
        tester.widget<CheckboxListTile>(field('setup-confirm')).value,
        isFalse,
      );
      await tester.tap(field('setup-confirm'));
      await tester.tap(field('calculate-targets'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(repository.recommendationTokens.single!.isCancelled, isTrue);
      pending.complete(previewFor(targetSetup));
      await tester.pump();
      expect(repository.targetUpdates, isEmpty);
    });
  });
}
