import 'package:fitness_app/blocs/tracking/activity_feed_cubit.dart';
import 'package:fitness_app/models/route_models.dart';
import 'package:fitness_app/models/tracked_activity.dart';
import 'package:fitness_app/screens/tracking/activity_detail_screen.dart';
import 'package:fitness_app/services/tracking_activity_repository.dart';
import 'package:fitness_app/theme/app_theme.dart';
import 'package:fitness_app/widgets/recent_activities.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TrackedActivity sampleActivity({
  List<ActivityChartPoint> elevation = const <ActivityChartPoint>[],
  List<ActivityChartPoint> heartRate = const <ActivityChartPoint>[],
}) {
  return TrackedActivity(
    id: 'activity-1',
    type: TrackedActivityType.run,
    startedAt: DateTime(2026, 9, 17, 6),
    endedAt: DateTime(2026, 9, 17, 6, 30),
    durationSec: 1800,
    movingSec: 1700,
    distanceM: 5000,
    elevationGainM: 42,
    avgPaceSecPerKm: 340,
    encodedPolyline: '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
    splits: const <TrackedActivitySplit>[
      TrackedActivitySplit(
        index: 1,
        distanceM: 1000,
        durationSec: 350,
        movingSec: 340,
        paceSecPerKm: 340,
        isPartial: false,
      ),
      TrackedActivitySplit(
        index: 2,
        distanceM: 800,
        durationSec: 280,
        movingSec: 270,
        paceSecPerKm: 337.5,
        isPartial: true,
      ),
    ],
    calories: 410,
    avgHr: 155,
    maxHr: 181,
    source: TrackedActivitySource.app,
    elevationProfile: elevation,
    heartRateSeries: heartRate,
  );
}

class Step6FakeRepository implements TrackingActivityRepository {
  Step6FakeRepository(this.activity);

  TrackedActivity activity;
  int deletes = 0;

  @override
  Future<void> delete(String id) async => deletes += 1;

  @override
  Future<TrackedActivity> get(String id) async => activity;

  @override
  Future<List<TrackedActivity>> listRecent({int limit = 10}) async =>
      <TrackedActivity>[activity];

  @override
  Future<TrackedActivity> saveProcessed({
    required ProcessedRoute route,
    required String clientId,
    TrackedActivityType type = TrackedActivityType.run,
    double calories = 0,
  }) async =>
      activity;
}

void main() {
  test('wire model preserves optional samples and split conversion', () {
    final TrackedActivity activity = TrackedActivity.fromJson(
      const <String, dynamic>{
        'id': 'wire-1',
        'type': 'cycle',
        'startedAt': '2026-09-17T06:00:00.000Z',
        'endedAt': '2026-09-17T06:30:00.000Z',
        'durationSec': 1800,
        'movingSec': 1700,
        'distanceM': 8000,
        'encodedPolyline': '',
        'splits': <Map<String, dynamic>>[
          <String, dynamic>{
            'index': 1,
            'distanceM': 1000,
            'durationSec': 240,
            'movingSec': 230,
            'paceSecPerKm': 230,
            'isPartial': false,
          },
        ],
        'calories': 300,
        'source': 'app',
        'elevationProfile': <num>[10, 14, 12],
        'heartRateSeries': <Map<String, num>>[
          <String, num>{'progress': 0, 'value': 120},
          <String, num>{'progress': 1, 'value': 160},
        ],
      },
    );

    expect(activity.type, TrackedActivityType.cycle);
    expect(activity.routeSplits.single.moving, const Duration(seconds: 230));
    expect(activity.elevationProfile, hasLength(3));
    expect(activity.heartRateSeries.last.progress, 1);
  });

  testWidgets('recent activities render a static route and open on tap',
      (WidgetTester tester) async {
    TrackedActivity? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: RecentActivities(
              state: ActivityFeedState(
                activities: <TrackedActivity>[sampleActivity()],
              ),
              onRetry: () {},
              onOpen: (TrackedActivity value) => opened = value,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Recent activities'), findsOneWidget);
    expect(find.text('5.00 km'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('activity-activity-1')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('activity-activity-1')),
    );
    expect(opened?.id, 'activity-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent activities distinguish empty and retryable error states',
      (WidgetTester tester) async {
    int retries = 0;
    Widget subject(ActivityFeedState state) => MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: RecentActivities(
              state: state,
              onRetry: () => retries += 1,
              onOpen: (_) {},
            ),
          ),
        );

    await tester.pumpWidget(subject(const ActivityFeedState()));
    expect(find.text('No activities yet'), findsOneWidget);

    await tester.pumpWidget(
      subject(const ActivityFeedState(error: 'No connection.')),
    );
    expect(find.text('Activities are unavailable'), findsOneWidget);
    expect(find.text('No connection.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  testWidgets(
      'activity detail shows map, splits and honest aggregate fallbacks',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final TrackedActivity activity = sampleActivity();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ActivityDetailScreen(
          initialActivity: activity,
          repository: Step6FakeRepository(activity),
          forceMapFallback: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('5.00 km'), findsOneWidget);
    expect(find.text('5:40 /km'), findsNWidgets(2));
    expect(find.text('SPLITS'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    expect(find.text('42 m'), findsOneWidget);
    expect(find.text('155'), findsOneWidget);
    expect(find.text('181'), findsOneWidget);
    expect(find.textContaining('summary heart-rate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail draws elevation and heart-rate charts when samples exist',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const List<ActivityChartPoint> elevation = <ActivityChartPoint>[
      ActivityChartPoint(progress: 0, value: 210),
      ActivityChartPoint(progress: .5, value: 224),
      ActivityChartPoint(progress: 1, value: 218),
    ];
    const List<ActivityChartPoint> heartRate = <ActivityChartPoint>[
      ActivityChartPoint(progress: 0, value: 120),
      ActivityChartPoint(progress: .5, value: 160),
      ActivityChartPoint(progress: 1, value: 150),
    ];
    final TrackedActivity activity = sampleActivity(
      elevation: elevation,
      heartRate: heartRate,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ActivityDetailScreen(
          initialActivity: activity,
          repository: Step6FakeRepository(activity),
          forceMapFallback: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey<String>('activity-chart-Elevation profile'),
      ),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey<String>('activity-chart-Heart-rate chart'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
