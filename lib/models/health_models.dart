import 'package:equatable/equatable.dart';

enum HealthProviderAvailability {
  checking,
  available,
  installRequired,
  unsupported,
}

enum HealthAccessStatus { unknown, notRequested, authorized, denied }

enum DeviceHealthMetric {
  steps,
  activeKcal,
  restingHr,
  spo2,
  weightKg,
}

extension DeviceHealthMetricName on DeviceHealthMetric {
  String get storageName => name;
}

class DeviceHealthSample extends Equatable {
  const DeviceHealthSample({
    required this.id,
    required this.metric,
    required this.value,
    required this.from,
    required this.to,
  });

  final String id;
  final DeviceHealthMetric metric;
  final double value;
  final DateTime from;
  final DateTime to;

  @override
  List<Object?> get props => <Object?>[id, metric, value, from, to];
}

class HealthChangePage extends Equatable {
  const HealthChangePage({
    required this.nextToken,
    required this.hasMore,
    required this.tokenExpired,
    required this.hasChanges,
  });

  final String nextToken;
  final bool hasMore;
  final bool tokenExpired;
  final bool hasChanges;

  @override
  List<Object?> get props => <Object?>[
        nextToken,
        hasMore,
        tokenExpired,
        hasChanges,
      ];
}

enum HealthSource { healthconnect, healthkit }

class HealthDailySummary extends Equatable {
  const HealthDailySummary({
    required this.date,
    required this.steps,
    required this.activeKcal,
    required this.source,
    this.restingHr,
    this.spo2,
    this.vo2Max,
    this.weightKg,
  });

  final String date;
  final int steps;
  final double activeKcal;
  final double? restingHr;
  final double? spo2;
  final double? vo2Max;
  final double? weightKg;
  final HealthSource source;

  bool get hasPhoneData => steps > 0 || activeKcal > 0;
  bool get hasWearableData =>
      restingHr != null || spo2 != null || vo2Max != null;
  bool get hasAnyData => hasPhoneData || hasWearableData || weightKg != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'date': date,
        'steps': steps,
        'activeKcal': _finiteNonNegative(activeKcal),
        // Explicit nulls clear records removed at the source.
        'restingHr': restingHr,
        'spo2': spo2,
        'vo2Max': vo2Max,
        'weightKg': weightKg,
        'source': source.name,
      };

  Map<String, dynamic> toCacheJson() => toJson();

  factory HealthDailySummary.fromJson(Map<String, dynamic> json) {
    return HealthDailySummary(
      date: (json['date'] ?? '').toString(),
      steps: (json['steps'] as num?)?.toInt() ?? 0,
      activeKcal: (json['activeKcal'] as num?)?.toDouble() ?? 0,
      restingHr: (json['restingHr'] as num?)?.toDouble(),
      spo2: (json['spo2'] as num?)?.toDouble(),
      vo2Max: (json['vo2Max'] as num?)?.toDouble(),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      source: json['source'] == HealthSource.healthkit.name
          ? HealthSource.healthkit
          : HealthSource.healthconnect,
    );
  }

  static double _finiteNonNegative(double value) =>
      value.isFinite && value > 0 ? value : 0;

  @override
  List<Object?> get props => <Object?>[
        date,
        steps,
        activeKcal,
        restingHr,
        spo2,
        vo2Max,
        weightKg,
        source,
      ];
}

class HealthSyncResult extends Equatable {
  const HealthSyncResult({
    required this.today,
    required this.checkedAt,
    required this.uploadedDays,
    required this.backgroundEnabled,
  });

  final HealthDailySummary? today;
  final DateTime checkedAt;
  final int uploadedDays;
  final bool backgroundEnabled;

  @override
  List<Object?> get props => <Object?>[
        today,
        checkedAt,
        uploadedDays,
        backgroundEnabled,
      ];
}

/// Computes BMI only from the profile measurements already held by AppStore.
/// Device health weight/height records intentionally do not feed this value.
double? calculateProfileBmi({double? heightCm, double? weightKg}) {
  if (heightCm == null || weightKg == null) return null;
  if (!heightCm.isFinite || !weightKg.isFinite) return null;
  if (heightCm <= 0 || weightKg <= 0) return null;
  final double heightM = heightCm / 100;
  final double value = weightKg / (heightM * heightM);
  return value.isFinite ? value : null;
}

String healthLocalDate(DateTime value) {
  final DateTime local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

DateTime healthStartOfDay(DateTime value) {
  final DateTime local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Builds one complete row per local calendar day. Complete rows are
/// important: zeroes and explicit nulls let a source deletion clear stale
/// server data during the 30-day reconciliation window.
List<HealthDailySummary> aggregateHealthDays({
  required Iterable<DeviceHealthSample> samples,
  required DateTime from,
  required DateTime to,
  required HealthSource source,
}) {
  final DateTime first = healthStartOfDay(from);
  final DateTime last = healthStartOfDay(to);
  if (last.isBefore(first)) return const <HealthDailySummary>[];

  final Map<String, _DailyAccumulator> accumulators =
      <String, _DailyAccumulator>{};
  for (DateTime day = first;
      !day.isAfter(last);
      day = day.add(const Duration(days: 1))) {
    accumulators[healthLocalDate(day)] = _DailyAccumulator();
  }

  // Native stores occasionally surface the same UUID twice (for example
  // after a provider refresh). Count it once before reducing into days.
  final Set<String> seen = <String>{};
  for (final DeviceHealthSample sample in samples) {
    if (!sample.value.isFinite || sample.value < 0) continue;
    final String identity = sample.id.isEmpty
        ? '${sample.metric.name}:${sample.from.microsecondsSinceEpoch}:'
            '${sample.to.microsecondsSinceEpoch}:${sample.value}'
        : '${sample.metric.name}:${sample.id}';
    if (!seen.add(identity)) continue;

    final String date = healthLocalDate(sample.from);
    final _DailyAccumulator? day = accumulators[date];
    if (day == null) continue;
    day.add(sample);
  }

  return accumulators.entries
      .map(
        (MapEntry<String, _DailyAccumulator> entry) =>
            entry.value.finish(entry.key, source),
      )
      .toList(growable: false);
}

class _DailyAccumulator {
  double steps = 0;
  double activeKcal = 0;
  final List<double> restingHr = <double>[];
  final List<double> spo2 = <double>[];
  double? weightKg;
  DateTime? weightAt;

  void add(DeviceHealthSample sample) {
    switch (sample.metric) {
      case DeviceHealthMetric.steps:
        steps += sample.value;
      case DeviceHealthMetric.activeKcal:
        activeKcal += sample.value;
      case DeviceHealthMetric.restingHr:
        if (sample.value >= 20 && sample.value <= 260) {
          restingHr.add(sample.value);
        }
      case DeviceHealthMetric.spo2:
        final double percent =
            sample.value <= 1 ? sample.value * 100 : sample.value;
        if (percent >= 0 && percent <= 100) spo2.add(percent);
      case DeviceHealthMetric.weightKg:
        if (sample.value >= 1 &&
            sample.value <= 500 &&
            (weightAt == null || !sample.from.isBefore(weightAt!))) {
          weightKg = sample.value;
          weightAt = sample.from;
        }
    }
  }

  HealthDailySummary finish(String date, HealthSource source) {
    return HealthDailySummary(
      date: date,
      steps: steps.round().clamp(0, 1000000).toInt(),
      activeKcal: activeKcal.clamp(0, 100000).toDouble(),
      restingHr: _average(restingHr),
      spo2: _average(spo2),
      // health 13.3.2 does not expose Vo2MaxRecord. Keep the wire value
      // explicit so a formerly synced value is not shown as current.
      vo2Max: null,
      weightKg: weightKg,
      source: source,
    );
  }

  double? _average(List<double> values) {
    if (values.isEmpty) return null;
    final double value =
        values.reduce((double a, double b) => a + b) / values.length;
    return double.parse(value.toStringAsFixed(2));
  }
}
