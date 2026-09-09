import 'dart:math' as math;

import '../models/route_models.dart';
import '../models/tracking_models.dart';
import 'polyline_codec.dart';

/// Tuning for [RouteProcessor]. Every value is a judgement call, so each one is
/// named, defaulted conservatively, and overridable per activity type.
class RouteProcessorOptions {
  const RouteProcessorOptions({
    this.maxAccuracyM = 25,
    this.maxSpeedMps = 12,
    this.maxLegGap = const Duration(seconds: 20),
    this.movingSpeedMps = 0.7,
    this.stationaryHold = const Duration(seconds: 10),
    this.splitDistanceM = 1000,
    this.elevationWindow = 5,
    this.elevationThresholdM = 3,
    this.maxConsecutiveSpeedRejections = 5,
  });

  /// Fixes worse than this are dropped. Unfiltered GPS inflates distance by
  /// 5–15%, and users notice immediately when their 5K reads 5.4K.
  final double maxAccuracyM;

  /// Roughly 43 km/h. Above a sprinter's top speed but below anything a phone
  /// in a car would produce, so it catches the jump without clipping real
  /// downhill cycling. Raise it for vehicle-assisted activities.
  final double maxSpeedMps;

  /// Two fixes further apart than this are not joined: the path between them
  /// is unknown, so counting the straight line would invent distance the user
  /// did not cover.
  final Duration maxLegGap;

  /// Below this, the athlete is treated as stationary. Slow walking is around
  /// 1 m/s, so this sits under the slowest real movement while staying above
  /// the drift of a phone sitting still.
  final double movingSpeedMps;

  /// How long stationary has to last before it stops counting as moving time.
  /// Shorter dips are GPS noise or a dodged pedestrian, not a traffic light.
  final Duration stationaryHold;

  final double splitDistanceM;

  /// Points in the centred moving average applied to altitude before any gain
  /// is accumulated.
  final int elevationWindow;

  /// Smoothed altitude has to move this far before it counts as climb or
  /// descent. Without it, GPS altitude noise alone manufactures hundreds of
  /// metres of gain over an hour on flat ground.
  final double elevationThresholdM;

  /// After this many consecutive impossible-speed rejections the processor
  /// stops assuming the outlier is the new fix and accepts that the athlete
  /// really did move — a tunnel exit, say. The leg is broken rather than
  /// bridged, so the jump adds no distance, but the rest of the run survives.
  final int maxConsecutiveSpeedRejections;
}

/// Turns the recorder's raw fixes into distance, time, pace, splits, elevation
/// and a polyline.
///
/// Pure functions over plain data: no I/O, no platform channels, no clock. That
/// is what lets the whole of this file be tested against fixture routes without
/// a device, which matters because route maths is where the subtle bugs live
/// and "go for a run to check" is not a test loop.
///
/// The recorder's own live distance is provisional. This is the authority.
class RouteProcessor {
  const RouteProcessor._();

  /// IUGG mean Earth radius. Android's `Location.distanceBetween` solves the
  /// WGS84 ellipsoid instead, so the recorder's live figure and this one differ
  /// by a few tenths of a percent. That is expected: the notification shows a
  /// provisional number, and this replaces it.
  static const double earthRadiusM = 6371008.8;

  /// Great-circle distance in metres.
  static double haversineM(
    double latitude1,
    double longitude1,
    double latitude2,
    double longitude2,
  ) {
    final double dLat = _radians(latitude2 - latitude1);
    final double dLon = _radians(longitude2 - longitude1);
    final double a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_radians(latitude1)) *
            math.cos(_radians(latitude2)) *
            math.pow(math.sin(dLon / 2), 2);
    // asin is better conditioned than atan2 for the short legs that dominate a
    // 1 Hz recording; the clamp guards against a hair over 1 from rounding.
    return 2 * earthRadiusM * math.asin(math.sqrt(a).clamp(0.0, 1.0));
  }

  static double distanceBetween(RouteCoordinate a, RouteCoordinate b) =>
      haversineM(a.latitude, a.longitude, b.latitude, b.longitude);

  static ProcessedRoute process(
    List<TrackingPoint> raw, {
    RouteProcessorOptions options = const RouteProcessorOptions(),
  }) {
    final _FilterResult filtered = _filter(raw, options);
    final List<_Fix> fixes = filtered.fixes;
    if (fixes.isEmpty) return ProcessedRoute.empty(filtered.report);

    final List<_Leg> legs = _legs(fixes);
    _classifyMoving(legs, options);

    double distanceM = 0;
    int recordedMs = 0;
    int movingMs = 0;
    for (final _Leg leg in legs) {
      distanceM += leg.distanceM;
      recordedMs += leg.durationMs;
      if (leg.moving) movingMs += leg.durationMs;
    }

    final List<RouteCoordinate> coordinates = fixes
        .map(
          (_Fix f) => RouteCoordinate(f.point.latitude, f.point.longitude),
        )
        .toList(growable: false);

    final DateTime startedAt = fixes.first.point.capturedAt;
    final DateTime endedAt = fixes.last.point.capturedAt;

    return ProcessedRoute(
      coordinates: coordinates,
      encodedPolyline: PolylineCodec.encode(coordinates),
      distanceM: distanceM,
      recorded: Duration(milliseconds: recordedMs),
      moving: Duration(milliseconds: movingMs),
      wallClock: endedAt.difference(startedAt),
      splits: _splits(legs, options),
      filter: filtered.report,
      startedAt: startedAt,
      endedAt: endedAt,
      elevation: _elevation(fixes, options),
      bounds: RouteBounds.around(coordinates),
    );
  }

  // ---------------------------------------------------------------- filtering

  static _FilterResult _filter(
    List<TrackingPoint> raw,
    RouteProcessorOptions options,
  ) {
    final Map<RoutePointRejection, int> rejected =
        <RoutePointRejection, int>{};
    final List<_Fix> fixes = <_Fix>[];
    TrackingPoint? anchor;
    int consecutiveSpeedRejections = 0;

    void reject(RoutePointRejection reason) {
      rejected[reason] = (rejected[reason] ?? 0) + 1;
    }

    for (final TrackingPoint point in raw) {
      if (point.isMock) {
        reject(RoutePointRejection.mock);
        continue;
      }
      if (!_hasUsableCoordinate(point)) {
        reject(RoutePointRejection.coordinate);
        continue;
      }
      // Accuracy of exactly zero means "not reported", not "perfect".
      if (!point.accuracyM.isFinite ||
          point.accuracyM <= 0 ||
          point.accuracyM > options.maxAccuracyM) {
        reject(RoutePointRejection.accuracy);
        continue;
      }

      bool startsNewLeg = true;
      if (anchor != null && point.segmentIndex == anchor.segmentIndex) {
        final int gapMs =
            point.capturedAt.difference(anchor.capturedAt).inMilliseconds;
        if (gapMs <= 0) {
          // Out of order or a duplicate timestamp. Either way it cannot be
          // measured against the anchor, and keeping it would let a zero
          // divisor into the speed test.
          reject(RoutePointRejection.timestamp);
          continue;
        }
        if (gapMs <= options.maxLegGap.inMilliseconds) {
          final double metres = haversineM(
            anchor.latitude,
            anchor.longitude,
            point.latitude,
            point.longitude,
          );
          if (metres / (gapMs / 1000) > options.maxSpeedMps) {
            consecutiveSpeedRejections += 1;
            if (consecutiveSpeedRejections <=
                options.maxConsecutiveSpeedRejections) {
              reject(RoutePointRejection.speed);
              continue;
            }
            // Persistently far away: the athlete moved, we just cannot see how.
            // Accept and break the leg, which keeps the run without inventing
            // the straight line across the gap.
          } else {
            startsNewLeg = false;
          }
        }
        // A gap longer than maxLegGap accepts the point but starts a new leg.
      }

      consecutiveSpeedRejections = 0;
      fixes.add(_Fix(point, startsNewLeg: startsNewLeg));
      anchor = point;
    }

    return _FilterResult(
      fixes,
      RouteFilterReport(
        total: raw.length,
        accepted: fixes.length,
        rejected: Map<RoutePointRejection, int>.unmodifiable(rejected),
      ),
    );
  }

  static bool _hasUsableCoordinate(TrackingPoint point) {
    final double lat = point.latitude;
    final double lng = point.longitude;
    return lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
  }

  // --------------------------------------------------------------------- legs

  static List<_Leg> _legs(List<_Fix> fixes) {
    final List<_Leg> legs = <_Leg>[];
    for (int i = 1; i < fixes.length; i++) {
      if (fixes[i].startsNewLeg) continue;
      final TrackingPoint from = fixes[i - 1].point;
      final TrackingPoint to = fixes[i].point;
      legs.add(
        _Leg(
          fromIndex: i - 1,
          toIndex: i,
          distanceM: haversineM(
            from.latitude,
            from.longitude,
            to.latitude,
            to.longitude,
          ),
          durationMs: to.capturedAt.difference(from.capturedAt).inMilliseconds,
        ),
      );
    }
    return legs;
  }

  /// Marks each leg moving or stationary, then gives back any stationary run
  /// shorter than [RouteProcessorOptions.stationaryHold].
  ///
  /// Without the hold, a single slow fix in the middle of a steady run would
  /// carve a second out of moving time and nudge the pace. With it, only a
  /// genuine stop counts.
  static void _classifyMoving(List<_Leg> legs, RouteProcessorOptions options) {
    for (final _Leg leg in legs) {
      leg.moving = leg.durationMs > 0 &&
          leg.distanceM / (leg.durationMs / 1000) >= options.movingSpeedMps;
    }

    final int holdMs = options.stationaryHold.inMilliseconds;
    int i = 0;
    while (i < legs.length) {
      if (legs[i].moving) {
        i += 1;
        continue;
      }
      // Only extend the run while the legs are genuinely adjacent in time — a
      // leg break means there is unrecorded time between them, and the two
      // sides of it are not one stop.
      int end = i + 1;
      int runMs = legs[i].durationMs;
      while (end < legs.length &&
          !legs[end].moving &&
          legs[end].fromIndex == legs[end - 1].toIndex) {
        runMs += legs[end].durationMs;
        end += 1;
      }
      if (runMs < holdMs) {
        for (int k = i; k < end; k++) {
          legs[k].moving = true;
        }
      }
      i = end;
    }
  }

  // ------------------------------------------------------------------- splits

  static List<RouteSplit> _splits(
    List<_Leg> legs,
    RouteProcessorOptions options,
  ) {
    final double target = options.splitDistanceM;
    if (target <= 0) return const <RouteSplit>[];

    final List<RouteSplit> splits = <RouteSplit>[];
    double carriedDistance = 0;
    int carriedMs = 0;
    int carriedMovingMs = 0;
    int index = 1;

    for (final _Leg leg in legs) {
      double remaining = leg.distanceM;
      int remainingMs = leg.durationMs;

      // One leg can span more than one boundary when a long gap was bridged,
      // so this closes as many splits as the leg covers.
      while (remaining > 0 && carriedDistance + remaining >= target) {
        final double needed = target - carriedDistance;
        final int takenMs = (remainingMs * (needed / remaining)).round();

        carriedMs += takenMs;
        if (leg.moving) carriedMovingMs += takenMs;
        splits.add(
          RouteSplit(
            index: index,
            distanceM: target,
            duration: Duration(milliseconds: carriedMs),
            moving: Duration(milliseconds: carriedMovingMs),
            isPartial: false,
          ),
        );

        index += 1;
        remaining -= needed;
        remainingMs -= takenMs;
        carriedDistance = 0;
        carriedMs = 0;
        carriedMovingMs = 0;
      }

      carriedDistance += remaining;
      carriedMs += remainingMs;
      if (leg.moving) carriedMovingMs += remainingMs;
    }

    // Sub-metre tails are rounding, not a split worth showing a pace for.
    if (carriedDistance >= 1) {
      splits.add(
        RouteSplit(
          index: index,
          distanceM: carriedDistance,
          duration: Duration(milliseconds: carriedMs),
          moving: Duration(milliseconds: carriedMovingMs),
          isPartial: true,
        ),
      );
    }
    return List<RouteSplit>.unmodifiable(splits);
  }

  // ---------------------------------------------------------------- elevation

  static RouteElevation? _elevation(
    List<_Fix> fixes,
    RouteProcessorOptions options,
  ) {
    final List<double> altitudes = <double>[
      for (final _Fix fix in fixes)
        if (fix.point.altitudeM != null && fix.point.altitudeM!.isFinite)
          fix.point.altitudeM!,
    ];
    // Two samples cannot be smoothed and cannot be told apart from noise.
    if (altitudes.length < 3) return null;

    final List<double> smoothed = _smooth(altitudes, options.elevationWindow);

    double gain = 0;
    double loss = 0;
    double reference = smoothed.first;
    double min = smoothed.first;
    double max = smoothed.first;
    for (final double value in smoothed) {
      if (value < min) min = value;
      if (value > max) max = value;
      final double delta = value - reference;
      if (delta >= options.elevationThresholdM) {
        gain += delta;
        reference = value;
      } else if (delta <= -options.elevationThresholdM) {
        loss += -delta;
        reference = value;
      }
    }

    return RouteElevation(
      gainM: gain,
      lossM: loss,
      minM: min,
      maxM: max,
      sampleCount: altitudes.length,
    );
  }

  /// Centred moving average, shrinking the window at the ends rather than
  /// padding, so the first and last samples are not dragged toward a value
  /// that was never measured.
  static List<double> _smooth(List<double> values, int window) {
    final int half = window <= 1 ? 0 : window ~/ 2;
    if (half == 0) return List<double>.of(values);

    return List<double>.generate(values.length, (int i) {
      final int start = math.max(0, i - half);
      final int end = math.min(values.length - 1, i + half);
      double sum = 0;
      for (int k = start; k <= end; k++) {
        sum += values[k];
      }
      return sum / (end - start + 1);
    });
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}

class _Fix {
  const _Fix(this.point, {required this.startsNewLeg});

  final TrackingPoint point;

  /// True when this fix cannot be joined to the one before it: a new recording
  /// segment after a pause, a gap too long to interpolate, or a relocation the
  /// speed filter gave up rejecting.
  final bool startsNewLeg;
}

class _Leg {
  _Leg({
    required this.fromIndex,
    required this.toIndex,
    required this.distanceM,
    required this.durationMs,
  });

  final int fromIndex;
  final int toIndex;
  final double distanceM;
  final int durationMs;
  bool moving = false;
}

class _FilterResult {
  const _FilterResult(this.fixes, this.report);

  final List<_Fix> fixes;
  final RouteFilterReport report;
}
