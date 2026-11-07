import 'package:fitness_app/models/health_models.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceHealthSample sample(
  String id,
  DeviceHealthMetric metric,
  double value,
  DateTime at,
) {
  return DeviceHealthSample(
    id: id,
    metric: metric,
    value: value,
    from: at,
    to: at.add(const Duration(minutes: 1)),
  );
}

void main() {
  test('BMI is profile-only, metric and guarded against invalid values', () {
    expect(
      calculateProfileBmi(heightCm: 175, weightKg: 70),
      closeTo(22.8571, 0.0001),
    );
    expect(calculateProfileBmi(heightCm: null, weightKg: 70), isNull);
    expect(calculateProfileBmi(heightCm: 0, weightKg: 70), isNull);
    expect(calculateProfileBmi(heightCm: 175, weightKg: -1), isNull);
  });

  test('daily aggregation de-duplicates, normalizes and clears empty data', () {
    final DateTime first = DateTime(2026, 9, 11);
    final DateTime second = DateTime(2026, 9, 12);
    final List<HealthDailySummary> days = aggregateHealthDays(
      from: first,
      to: second.add(const Duration(hours: 22)),
      source: HealthSource.healthconnect,
      samples: <DeviceHealthSample>[
        sample('steps-1', DeviceHealthMetric.steps, 1200, first),
        sample('steps-1', DeviceHealthMetric.steps, 1200, first),
        sample('steps-2', DeviceHealthMetric.steps, 300.4, first),
        sample('energy-1', DeviceHealthMetric.activeKcal, 123.45, first),
        sample('hr-1', DeviceHealthMetric.restingHr, 60, first),
        sample('hr-2', DeviceHealthMetric.restingHr, 64, first),
        sample('bad-hr', DeviceHealthMetric.restingHr, 500, first),
        sample('spo2-1', DeviceHealthMetric.spo2, 0.98, first),
        sample('weight-old', DeviceHealthMetric.weightKg, 71, first),
        sample(
          'weight-new',
          DeviceHealthMetric.weightKg,
          70.5,
          first.add(const Duration(hours: 8)),
        ),
      ],
    );

    expect(days, hasLength(2));
    expect(days.first.date, '2026-09-11');
    expect(days.first.steps, 1500);
    expect(days.first.activeKcal, 123.45);
    expect(days.first.restingHr, 62);
    expect(days.first.spo2, 98);
    expect(days.first.weightKg, 70.5);
    expect(days.first.vo2Max, isNull);

    expect(days.last.date, '2026-09-12');
    expect(days.last.hasAnyData, isFalse);
    expect(days.last.toJson(), containsPair('restingHr', null));
    expect(days.last.toJson(), containsPair('spo2', null));
    expect(days.last.toJson(), containsPair('vo2Max', null));
    expect(days.last.toJson(), containsPair('weightKg', null));
  });
}
