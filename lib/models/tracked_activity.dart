import 'package:equatable/equatable.dart';

import 'route_models.dart';

enum TrackedActivityType { run, walk, hike, cycle, other }

extension TrackedActivityTypeLabel on TrackedActivityType {
  String get label => switch (this) {
        TrackedActivityType.run => 'Run',
        TrackedActivityType.walk => 'Walk',
        TrackedActivityType.hike => 'Hike',
        TrackedActivityType.cycle => 'Ride',
        TrackedActivityType.other => 'Workout',
      };

  String get wireName => name;
}

enum TrackedActivitySource { app, healthconnect, manual }

class TrackedActivitySplit extends Equatable {
  const TrackedActivitySplit({
    required this.index,
    required this.distanceM,
    required this.durationSec,
    required this.movingSec,
    required this.isPartial,
    this.paceSecPerKm,
  });

  final int index;
  final double distanceM;
  final int durationSec;
  final int movingSec;
  final double? paceSecPerKm;
  final bool isPartial;

  factory TrackedActivitySplit.fromJson(Map<String, dynamic> json) {
    return TrackedActivitySplit(
      index: (json['index'] as num?)?.toInt() ?? 0,
      distanceM: (json['distanceM'] as num?)?.toDouble() ?? 0,
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      movingSec: (json['movingSec'] as num?)?.toInt() ?? 0,
      paceSecPerKm: (json['paceSecPerKm'] as num?)?.toDouble(),
      isPartial: json['isPartial'] as bool? ?? false,
    );
  }

  RouteSplit get routeSplit => RouteSplit(
        index: index,
        distanceM: distanceM,
        duration: Duration(seconds: durationSec),
        moving: Duration(seconds: movingSec),
        isPartial: isPartial,
      );

  @override
  List<Object?> get props => <Object?>[
        index,
        distanceM,
        durationSec,
        movingSec,
        paceSecPerKm,
        isPartial,
      ];
}

/// Optional chart point accepted by the detail UI.
///
/// The Step 3 API currently exposes elevation gain and aggregate heart-rate
/// values. Keeping sampled series optional lets the UI render them when a
/// future recorder/backend supplies them, while remaining honest today.
class ActivityChartPoint extends Equatable {
  const ActivityChartPoint({required this.progress, required this.value});

  /// Normalized route progress from 0 to 1.
  final double progress;
  final double value;

  @override
  List<Object?> get props => <Object?>[progress, value];
}

class TrackedActivity extends Equatable {
  const TrackedActivity({
    required this.id,
    required this.type,
    required this.startedAt,
    required this.endedAt,
    required this.durationSec,
    required this.movingSec,
    required this.distanceM,
    required this.encodedPolyline,
    required this.splits,
    required this.calories,
    required this.source,
    this.elevationGainM,
    this.avgPaceSecPerKm,
    this.thumbnailUrl,
    this.avgHr,
    this.maxHr,
    this.clientId,
    this.elevationProfile = const <ActivityChartPoint>[],
    this.heartRateSeries = const <ActivityChartPoint>[],
  });

  final String id;
  final TrackedActivityType type;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSec;
  final int movingSec;
  final double distanceM;
  final double? elevationGainM;
  final double? avgPaceSecPerKm;
  final String encodedPolyline;
  final String? thumbnailUrl;
  final List<TrackedActivitySplit> splits;
  final double calories;
  final double? avgHr;
  final double? maxHr;
  final TrackedActivitySource source;
  final String? clientId;
  final List<ActivityChartPoint> elevationProfile;
  final List<ActivityChartPoint> heartRateSeries;

  List<RouteSplit> get routeSplits => splits
      .map((TrackedActivitySplit split) => split.routeSplit)
      .toList(growable: false);

  factory TrackedActivity.fromJson(
    Map<String, dynamic> json, {
    String? Function(String? value)? resolveMediaUrl,
  }) {
    final List<TrackedActivitySplit> splits =
        (json['splits'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (Map value) => TrackedActivitySplit.fromJson(
                Map<String, dynamic>.from(value),
              ),
            )
            .toList(growable: false);
    final String? rawThumbnail = json['thumbnailUrl']?.toString();
    return TrackedActivity(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      type: _activityType(json['type']),
      startedAt: DateTime.tryParse((json['startedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      endedAt: DateTime.tryParse((json['endedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      movingSec: (json['movingSec'] as num?)?.toInt() ?? 0,
      distanceM: (json['distanceM'] as num?)?.toDouble() ?? 0,
      elevationGainM: (json['elevationGainM'] as num?)?.toDouble(),
      avgPaceSecPerKm: (json['avgPaceSecPerKm'] as num?)?.toDouble(),
      encodedPolyline: (json['encodedPolyline'] ?? '').toString(),
      thumbnailUrl: resolveMediaUrl?.call(rawThumbnail) ?? rawThumbnail,
      splits: splits,
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      avgHr: (json['avgHr'] as num?)?.toDouble(),
      maxHr: (json['maxHr'] as num?)?.toDouble(),
      source: _activitySource(json['source']),
      clientId: json['clientId']?.toString(),
      elevationProfile: _chartPoints(json['elevationProfile']),
      heartRateSeries: _chartPoints(json['heartRateSeries']),
    );
  }

  static TrackedActivityType _activityType(Object? value) =>
      TrackedActivityType.values.firstWhere(
        (TrackedActivityType type) => type.name == value,
        orElse: () => TrackedActivityType.other,
      );

  static TrackedActivitySource _activitySource(Object? value) =>
      TrackedActivitySource.values.firstWhere(
        (TrackedActivitySource source) => source.name == value,
        orElse: () => TrackedActivitySource.manual,
      );

  static List<ActivityChartPoint> _chartPoints(Object? raw) {
    if (raw is! List || raw.isEmpty) return const <ActivityChartPoint>[];
    final List<ActivityChartPoint> points = <ActivityChartPoint>[];
    for (int index = 0; index < raw.length; index += 1) {
      final Object? item = raw[index];
      double? value;
      double? progress;
      if (item is num) {
        value = item.toDouble();
      } else if (item is Map) {
        value = (item['value'] as num?)?.toDouble();
        progress = (item['progress'] as num?)?.toDouble();
      }
      if (value == null || !value.isFinite) continue;
      final double fallback = raw.length == 1 ? 0 : index / (raw.length - 1);
      points.add(
        ActivityChartPoint(
          progress: (progress ?? fallback).clamp(0, 1).toDouble(),
          value: value,
        ),
      );
    }
    return List<ActivityChartPoint>.unmodifiable(points);
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        type,
        startedAt,
        endedAt,
        durationSec,
        movingSec,
        distanceM,
        elevationGainM,
        avgPaceSecPerKm,
        encodedPolyline,
        thumbnailUrl,
        splits,
        calories,
        avgHr,
        maxHr,
        source,
        clientId,
        elevationProfile,
        heartRateSeries,
      ];
}
