import 'package:fitness_app/blocs/tracking/health_sync_cubit.dart';
import 'package:fitness_app/models/health_models.dart';
import 'package:fitness_app/theme/app_theme.dart';
import 'package:fitness_app/widgets/health_connect_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(HealthSyncState state) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: SingleChildScrollView(
        child: HealthConnectCard(
          state: state,
          onConnect: () {},
          onInstall: () {},
          onOpenSettings: () {},
          onRefresh: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders install, rationale and denied states', (tester) async {
    await tester.pumpWidget(
      app(
        const HealthSyncState(
          availability: HealthProviderAvailability.installRequired,
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('health-install')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      app(
        const HealthSyncState(
          availability: HealthProviderAvailability.available,
          access: HealthAccessStatus.notRequested,
          bmi: 22.8,
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('health-connect')),
      findsOneWidget,
    );
    expect(find.textContaining('BMI 22.8'), findsOneWidget);
    expect(
      find.textContaining('VO₂ max sync is not available yet'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      app(
        const HealthSyncState(
          availability: HealthProviderAvailability.available,
          access: HealthAccessStatus.denied,
        ),
      ),
    );
    expect(find.byKey(const ValueKey<String>('health-retry')), findsOneWidget);
    expect(find.text('Open health settings'), findsOneWidget);
  });

  testWidgets('connected state explains both phone and wearable empty data',
      (tester) async {
    await tester.pumpWidget(
      app(
        HealthSyncState(
          availability: HealthProviderAvailability.available,
          access: HealthAccessStatus.authorized,
          result: HealthSyncResult(
            today: const HealthDailySummary(
              date: '2026-09-12',
              steps: 0,
              activeKcal: 0,
              source: HealthSource.healthconnect,
            ),
            checkedAt: DateTime(2026, 9, 12, 12),
            uploadedDays: 30,
            backgroundEnabled: false,
          ),
          bmi: 22.9,
        ),
      ),
    );

    expect(find.text('No health readings yet'), findsOneWidget);
    expect(find.text('No wearable readings'), findsOneWidget);
    expect(find.text('VO₂ max'), findsOneWidget);
    expect(find.text('coming later'), findsOneWidget);
    expect(find.textContaining('Background access is off'), findsOneWidget);
  });

  testWidgets('connected phone data leads with steps and active-energy rings',
      (tester) async {
    await tester.pumpWidget(
      app(
        HealthSyncState(
          availability: HealthProviderAvailability.available,
          access: HealthAccessStatus.authorized,
          result: HealthSyncResult(
            today: const HealthDailySummary(
              date: '2026-09-17',
              steps: 8420,
              activeKcal: 430,
              source: HealthSource.healthconnect,
            ),
            checkedAt: DateTime(2026, 9, 17, 12),
            uploadedDays: 1,
            backgroundEnabled: true,
          ),
        ),
      ),
    );

    expect(find.text('8420'), findsNWidgets(2));
    expect(find.text('430 kcal'), findsOneWidget);
    expect(find.textContaining('daily guides of 10,000 steps'), findsOneWidget);
  });
}
