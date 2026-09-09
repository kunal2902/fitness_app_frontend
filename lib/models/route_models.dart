import 'package:equatable/equatable.dart';

/// A single position on a processed route.
///
/// Deliberately smaller than a raw `TrackingPoint`: once the processor has run,
/// accuracy, speed and provider flags have already done their job and only the
/// geometry needs to survive into storage, transport and rendering.
class RouteCoordinate extends Equatable {
  const RouteCoordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  List<Object?> get props => <Object?>[latitude, longitude];

  @override
  String toString() => 'RouteCoordinate($latitude, $longitude)';
}

/// The rectangle a map has to show to fit the whole route.
class RouteBounds extends Equatable {
  const RouteBounds({
    required this.minLatitude,
    required this.minLongitude,
    required this.maxLatitude,
    required this.maxLongitude,
  });

  /// Null for an empty route — there is no meaningful rectangle around nothing,
  /// and returning a zero-size one at (0, 0) would point the map at the ocean
  /// off Ghana.
  static RouteBounds? around(Iterable<RouteCoordinate> coordinates) {
    double? minLat, minLng, maxLat, maxLng;
    for (final RouteCoordinate c in coordinates) {
      minLat = minLat == null || c.latitude < minLat ? c.latitude : minLat;
      maxLat = maxLat == null || c.latitude > maxLat ? c.latitude : maxLat;
      minLng = minLng == null || c.longitude < minLng ? c.longitude : minLng;
      maxLng = maxLng == null || c.longitude > maxLng ? c.longitude : maxLng;
    }
    if (minLat == null) return null;
    return RouteBounds(
      minLatitude: minLat,
      minLongitude: minLng!,
      maxLatitude: maxLat!,
      maxLongitude: maxLng!,
    );
  }

  final double minLatitude;
  final double minLongitude;
  final double maxLatitude;
  final double maxLongitude;

  RouteCoordinate get centre => RouteCoordinate(
        (minLatitude + maxLatitude) / 2,
        (minLongitude + maxLongitude) / 2,
      );

  @override
  List<Object?> get props =>
      <Object?>[minLatitude, minLongitude, maxLatitude, maxLongitude];
}

/// One completed (or trailing partial) distance split.
class RouteSplit extends Equatable {
  const RouteSplit({
    required this.index,
    required this.distanceM,
    required this.duration,
    required this.moving,
    required this.isPartial,
  });

  /// 1-based, so split 1 is the first kilometre.
  final int index;
  final double distanceM;

  /// Recorded time inside this split. Excludes paused and unrecorded time,
  /// exactly like [ProcessedRoute.recorded].
  final Duration duration;

  /// [duration] minus any stationary hold inside this split.
  final Duration moving;

  /// True for the trailing fragment of an activity that did not land on a
  /// whole split boundary. Its pace is real but it is not comparable with the
  /// full splits, so surfaces should mark it.
  final bool isPartial;

  /// Seconds per kilometre from moving time. Null when the split covered no
  /// meaningful distance.
  double? get paceSecPerKm {
    if (distanceM < 1) return null;
    return moving.inMilliseconds / 1000 / (distanceM / 1000);
  }

  @override
  List<Object?> get props =>
      <Object?>[index, distanceM, duration, moving, isPartial];
}

/// Why the processor threw a raw fix away.
enum RoutePointRejection {
  /// `isMock` was set. A mock provider means the route is not a record of
  /// anything that happened.
  mock,

  /// Latitude, longitude or timestamp was non-finite or out of range.
  coordinate,

  /// Accuracy was unknown, zero, or worse than the configured limit.
  accuracy,

  /// The fix was not newer than the one before it in the same segment.
  timestamp,

  /// The implied speed from the previous accepted fix was impossible.
  speed,
}

/// What the filter kept and what it discarded, so a suspicious result can be
/// explained without re-running the pipeline.
class RouteFilterReport extends Equatable {
  const RouteFilterReport({
    required this.total,
    required this.accepted,
    required this.rejected,
  });

  final int total;
  final int accepted;
  final Map<RoutePointRejection, int> rejected;

  int get rejectedCount =>
      rejected.values.fold(0, (int sum, int count) => sum + count);

  int countOf(RoutePointRejection reason) => rejected[reason] ?? 0;

  /// Share of raw fixes that survived, 0..1. A run well under ~0.8 usually
  /// means poor sky view rather than a processing bug.
  double get acceptedRatio => total == 0 ? 0 : accepted / total;

  @override
  List<Object?> get props => <Object?>[total, accepted, rejected];
}

/// Smoothed elevation for the route.
///
/// Only produced when enough fixes actually carried an altitude. GPS altitude
/// is poor — errors of tens of metres are normal — so these numbers are
/// smoothed and threshold-accumulated, and should be presented as approximate.
class RouteElevation extends Equatable {
  const RouteElevation({
    required this.gainM,
    required this.lossM,
    required this.minM,
    required this.maxM,
    required this.sampleCount,
  });

  final double gainM;
  final double lossM;
  final double minM;
  final double maxM;

  /// How many raw fixes carried an altitude. Fewer samples than accepted
  /// points means the profile is interpolated over gaps.
  final int sampleCount;

  @override
  List<Object?> get props =>
      <Object?>[gainM, lossM, minM, maxM, sampleCount];
}

/// The finished result of reprocessing one recorded workout.
class ProcessedRoute extends Equatable {
  const ProcessedRoute({
    required this.coordinates,
    required this.encodedPolyline,
    required this.distanceM,
    required this.recorded,
    required this.moving,
    required this.wallClock,
    required this.splits,
    required this.filter,
    this.startedAt,
    this.endedAt,
    this.elevation,
    this.bounds,
  });

  /// An activity whose every fix was rejected. Not an error — a workout
  /// started indoors and stopped a few seconds later legitimately has no route.
  factory ProcessedRoute.empty(RouteFilterReport filter) => ProcessedRoute(
        coordinates: const <RouteCoordinate>[],
        encodedPolyline: '',
        distanceM: 0,
        recorded: Duration.zero,
        moving: Duration.zero,
        wallClock: Duration.zero,
        splits: const <RouteSplit>[],
        filter: filter,
      );

  final List<RouteCoordinate> coordinates;

  /// Google encoded polyline, precision 5. Storage and transport form — a
  /// one-hour run at 1 Hz is a few KB here versus hundreds as raw JSON.
  final String encodedPolyline;

  final double distanceM;

  /// Time the recorder was actually collecting fixes: the sum of the gaps
  /// between consecutive connected points. Pauses and signal blackouts are
  /// excluded because no leg spans them.
  final Duration recorded;

  /// [recorded] minus stationary holds — traffic lights, in other words.
  /// This is the denominator runners expect their pace to use.
  final Duration moving;

  /// First to last accepted fix, pauses included. The "elapsed time" a
  /// stopwatch would have shown.
  final Duration wallClock;

  final List<RouteSplit> splits;
  final RouteFilterReport filter;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Null when too few fixes carried an altitude to say anything honest.
  final RouteElevation? elevation;

  /// Null for an empty route.
  final RouteBounds? bounds;

  bool get isEmpty => coordinates.isEmpty;

  /// Seconds per kilometre from moving time. Null below one metre, where the
  /// figure would be noise divided by noise.
  double? get avgPaceSecPerKm {
    if (distanceM < 1) return null;
    return moving.inMilliseconds / 1000 / (distanceM / 1000);
  }

  double? get avgSpeedMps {
    final int ms = moving.inMilliseconds;
    if (ms <= 0 || distanceM < 1) return null;
    return distanceM / (ms / 1000);
  }

  @override
  List<Object?> get props => <Object?>[
        coordinates,
        encodedPolyline,
        distanceM,
        recorded,
        moving,
        wallClock,
        splits,
        filter,
        startedAt,
        endedAt,
        elevation,
        bounds,
      ];
}
