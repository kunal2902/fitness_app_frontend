import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fitness_app/models/tracking_models.dart';
import 'package:fitness_app/utils/route_processor.dart';

/// Degrees of latitude that are exactly [metres] apart on a meridian.
///
/// Fixtures run due north for a reason: along a constant longitude the
/// haversine reduces to `R × Δlat`, so a route of _n_ legs is exactly
/// `n × spacing` metres. That turns "did the distance come out right?" into an
/// exact assertion instead of a tolerance nobody can justify.
double latitudeStepFor(double metres) =>
    metres / RouteProcessor.earthRadiusM * 180 / math.pi;

/// A clean recording: [legs] + 1 fixes, evenly spaced in time and distance.
List<TrackingPoint> straightRoute({
  required int legs,
  double spacingM = 2.5,
  Duration interval = const Duration(seconds: 1),
  double startLatitude = 28.5931,
  double startLongitude = 77.2197,
  DateTime? startedAt,
  double accuracyM = 6,
  int segmentIndex = 0,
  double? altitudeStartM,
  double altitudeStepM = 0,
  int startIndex = 0,
}) {
  final DateTime origin = startedAt ?? DateTime.utc(2026, 9, 7, 6);
  final double step = latitudeStepFor(spacingM);

  return List<TrackingPoint>.generate(legs + 1, (int i) {
    final int k = startIndex + i;
    return TrackingPoint(
      capturedAt: origin.add(interval * i),
      latitude: startLatitude + k * step,
      longitude: startLongitude,
      altitudeM:
          altitudeStartM == null ? null : altitudeStartM + k * altitudeStepM,
      accuracyM: accuracyM,
      speedMps: spacingM / (interval.inMilliseconds / 1000),
      bearingDegrees: 0,
      acceptedForLiveDistance: true,
      isMock: false,
      segmentIndex: segmentIndex,
    );
  });
}

/// Fixes at one position, one second apart — a traffic light.
List<TrackingPoint> stationaryRun({
  required int seconds,
  required TrackingPoint at,
}) {
  return List<TrackingPoint>.generate(
    seconds,
    (int i) => TrackingPoint(
      capturedAt: at.capturedAt.add(Duration(seconds: i + 1)),
      latitude: at.latitude,
      longitude: at.longitude,
      altitudeM: at.altitudeM,
      accuracyM: at.accuracyM,
      speedMps: 0,
      bearingDegrees: 0,
      acceptedForLiveDistance: true,
      isMock: false,
      segmentIndex: at.segmentIndex,
    ),
  );
}

/// The on-disk fixture in the recorder's own channel format, so the test
/// exercises `TrackingPoint.fromMap` and not just hand-built objects.
///
/// Built to have exact ground truth: 60 raw fixes, 5 of them deliberately bad,
/// split across a 90-second pause. TRACKING_STEP2.md documents which index
/// carries which defect and what the route sums to.
List<TrackingPoint> loadRecordedRoute() {
  final File file = File('test/support/fixtures/lodhi_loop.json');
  final List<dynamic> raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  return raw
      .cast<Map<String, dynamic>>()
      .map(TrackingPoint.fromMap)
      .toList(growable: false);
}
