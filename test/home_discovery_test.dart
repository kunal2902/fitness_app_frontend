import 'package:dio/dio.dart';
import 'package:fitness_app/models/training_models.dart';
import 'package:fitness_app/routes/app_routes.dart';
import 'package:fitness_app/screens/home/home_screen.dart';
import 'package:fitness_app/services/training_repository.dart';
import 'package:fitness_app/store/app_store.dart';
import 'package:fitness_app/theme/app_theme.dart';
import 'package:fitness_app/widgets/discovery_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Home's two carousels: the muscle groups it holds locally, and the
/// equipment list it reads from the active release.
class _FakeTrainingRepository implements TrainingRepository {
  _FakeTrainingRepository({this.taxonomy, this.error});

  final TrainingTaxonomy? taxonomy;
  final Object? error;
  int taxonomyCalls = 0;

  @override
  Future<TrainingTaxonomy> loadTaxonomy({CancelToken? cancelToken}) async {
    taxonomyCalls += 1;
    if (error != null) throw error!;
    return taxonomy!;
  }

  @override
  Future<TrainingExercisePage> searchExercises({
    String query = '',
    Set<String> muscleIds = const <String>{},
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
  }) =>
      throw UnimplementedError();

  @override
  Future<TrainingExercise> loadExercise(
    String id, {
    CancelToken? cancelToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<TrainingPreferences> loadPreferences({
    CancelToken? cancelToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<TrainingPreferences> saveEquipmentPreferences({
    required int revision,
    required List<TrainingEquipmentProfile> equipmentProfiles,
    required String? activeEquipmentProfileId,
    CancelToken? cancelToken,
  }) =>
      throw UnimplementedError();
}

TrainingTaxonomy _taxonomy(List<Map<String, dynamic>> equipment) {
  return TrainingTaxonomy.fromJson(<String, dynamic>{
    'catalogueVersion': 2,
    'releaseId': 'test_release',
    'muscleGroups': <Map<String, dynamic>>[
      <String, dynamic>{'id': 'chest', 'name': 'Chest'},
    ],
    'muscles': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'pectorals',
        'name': 'Pectorals',
        'group': 'chest',
        'svgRegionIds': <String>[],
      },
    ],
    'equipment': equipment,
    'movementPatternIds': <String>['horizontal_push'],
    'difficulties': <String>['beginner'],
    'trainingTypes': <String>['strength'],
  });
}

Map<String, dynamic> _item(String id, String name, String category) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'category': category,
      'aliases': <String>[],
    };

void main() {
  late List<Route<dynamic>> pushed;

  Widget host(TrainingRepository repository) {
    pushed = <Route<dynamic>>[];
    return ChangeNotifierProvider<AppStore>.value(
      value: AppStore.instance,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: HomeScreen(repository: repository),
        navigatorObservers: <NavigatorObserver>[_Recorder(pushed)],
        onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<dynamic>(
          settings: settings,
          builder: (_) => const Scaffold(body: Text('PUSHED')),
        ),
      ),
    );
  }

  Future<void> pump(WidgetTester tester, TrainingRepository repository) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(repository));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  ExerciseLibraryArguments argsOf(Route<dynamic> route) =>
      route.settings.arguments! as ExerciseLibraryArguments;

  group('browse by muscle', () {
    testWidgets('is a carousel, not a grid of tiles', (tester) async {
      await pump(
        tester,
        _FakeTrainingRepository(taxonomy: _taxonomy(const [])),
      );

      expect(find.text('Browse by muscle'), findsOneWidget);
      // The muscle carousel plus whatever the equipment section rendered.
      expect(find.byType(DiscoveryCarousel), findsWidgets);
      expect(find.byType(PageView), findsWidgets);
      // A grid would have laid every group out at once; a carousel shows the
      // focused card and the one peeking beside it.
      expect(find.text('Chest'), findsOneWidget);
    });

    testWidgets('swiping reaches the later groups', (tester) async {
      await pump(
        tester,
        _FakeTrainingRepository(taxonomy: _taxonomy(const [])),
      );

      expect(find.text('Lower legs'), findsNothing);

      final Finder carousel = find.byType(PageView).first;
      for (int i = 0; i < 7; i++) {
        await tester.drag(carousel, const Offset(-400, 0));
        await tester.pumpAndSettle();
      }

      expect(find.text('Lower legs'), findsOneWidget);
    });

    testWidgets('a card opens the library filtered to that group',
        (tester) async {
      await pump(
        tester,
        _FakeTrainingRepository(taxonomy: _taxonomy(const [])),
      );

      await tester.tap(find.text('Chest'));
      await tester.pumpAndSettle();

      expect(pushed, hasLength(1));
      expect(pushed.single.settings.name, AppRoutes.exerciseLibrary);
      expect(argsOf(pushed.single).initialMuscleGroup, 'chest');
    });

    testWidgets('all muscle cards use bundled photography', (tester) async {
      await pump(
        tester,
        _FakeTrainingRepository(taxonomy: _taxonomy(const [])),
      );

      final carousel = tester
          .widget<DiscoveryCarousel>(find.byType(DiscoveryCarousel).first);
      final images = carousel.items
          .map((item) => (item.image! as AssetImage).assetName)
          .toList();
      final manifest = await tester.runAsync(
        () => AssetManifest.loadFromAssetBundle(rootBundle),
      );
      expect(images.toSet(), hasLength(8));
      expect(manifest!.listAssets(), containsAll(images));
      expect(find.byType(Image), findsWidgets);
      expect(tester.takeException(), isNull);
      expect(find.text('Chest'), findsOneWidget);
    });
  });

  group('browse by equipment', () {
    testWidgets('renders one slide per item in the active release',
        (tester) async {
      final repository = _FakeTrainingRepository(
        taxonomy: _taxonomy(<Map<String, dynamic>>[
          _item('pull_up_bar', 'Secure pull-up bar', 'support'),
          _item('resistance_band', 'Resistance band', 'resistance'),
          _item('dumbbell_pair', 'Pair of dumbbells', 'free_weight'),
        ]),
      );
      await pump(tester, repository);

      expect(repository.taxonomyCalls, 1);
      expect(find.text('Browse by equipment'), findsOneWidget);
      expect(find.text('Secure pull-up bar'), findsOneWidget);
      // Category is surfaced as the subtitle, humanised.
      expect(find.text('Support'), findsOneWidget);
      final carousel =
          tester.widget<DiscoveryCarousel>(find.byType(DiscoveryCarousel).last);
      expect(
        carousel.items.map((item) => (item.image! as AssetImage).assetName),
        <String>[
          'assets/equipment/pull_up_bar.jpg',
          'assets/equipment/resistance_band.jpg',
          'assets/equipment/dumbbell_pair.jpg',
        ],
      );
    });

    testWidgets('a slide opens the library filtered to that item',
        (tester) async {
      await pump(
        tester,
        _FakeTrainingRepository(
          taxonomy: _taxonomy(<Map<String, dynamic>>[
            _item('resistance_band', 'Resistance band', 'resistance'),
          ]),
        ),
      );

      await tester.tap(find.text('Resistance band'));
      await tester.pumpAndSettle();

      expect(argsOf(pushed.single).initialEquipmentId, 'resistance_band');
      expect(argsOf(pushed.single).initialMuscleGroup, isNull);
    });

    testWidgets(
        'the list comes from the release, so new kit appears without '
        'a client change', (tester) async {
      // Nothing in Home hardcodes equipment ids: an item added by a later
      // catalogue release has to show up on its own, or every content change
      // needs an app release to match.
      await pump(
        tester,
        _FakeTrainingRepository(
          taxonomy: _taxonomy(<Map<String, dynamic>>[
            _item('future_kit', 'Future equipment', 'support'),
            _item('weighted_vest', 'Weighted vest', 'accessory'),
          ]),
        ),
      );

      expect(find.text('Future equipment'), findsOneWidget);
      final carousel =
          tester.widget<DiscoveryCarousel>(find.byType(DiscoveryCarousel).last);
      expect(carousel.items.first.image, isNull);
      expect(carousel.items.last.image, isA<AssetImage>());
      await tester.drag(find.byType(PageView).last, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('Weighted vest'), findsOneWidget);
    });

    testWidgets('a failed taxonomy degrades to a retry, leaving Home usable',
        (tester) async {
      final repository = _FakeTrainingRepository(error: StateError('offline'));
      await pump(tester, repository);

      expect(
        find.textContaining('Could not load the equipment'),
        findsOneWidget,
      );
      // The rest of Home still works — that is the point of not blocking on it.
      expect(find.text('Browse by muscle'), findsOneWidget);
      expect(find.text('Exercise library'), findsOneWidget);
      expect(find.text('My equipment'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(repository.taxonomyCalls, 2);
    });

    testWidgets(
        'an empty equipment list renders nothing rather than an '
        'empty frame', (tester) async {
      await pump(
        tester,
        _FakeTrainingRepository(taxonomy: _taxonomy(const [])),
      );

      expect(find.text('Browse by equipment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('photo credits are available from Home', (tester) async {
    await pump(
      tester,
      _FakeTrainingRepository(taxonomy: _taxonomy(const [])),
    );
    await tester.runAsync(() async {
      await rootBundle.loadString('assets/discovery_photo_credits.txt');
      await tester.tap(find.text('Photo credits'));
    });
    await tester.pumpAndSettle();

    expect(find.text('Discovery photo credits'), findsOneWidget);
    final text =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(text, contains('https://www.pexels.com/license/'));
    expect(text, contains('https://creativecommons.org/licenses/by-sa/4.0/'));
  });
}

class _Recorder extends NavigatorObserver {
  _Recorder(this.pushed);

  final List<Route<dynamic>> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The app's own first route has nothing beneath it; only navigation the
    // test caused does.
    if (previousRoute != null) pushed.add(route);
    super.didPush(route, previousRoute);
  }
}
