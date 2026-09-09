import 'package:fitness_app/models/route_models.dart';
import 'package:fitness_app/models/tracking_models.dart';
import 'package:fitness_app/utils/polyline_codec.dart';
import 'package:fitness_app/utils/route_processor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/route_fixtures.dart';

void main() {
  group('haversine', () {
    test('one degree of latitude is the mean-radius arc', () {
      // R × π/180 for the IUGG mean radius the processor uses.
      expect(
        RouteProcessor.haversineM(0, 77.2197, 1, 77.2197),
        closeTo(111195.0802, 0.001),
      );
    });

    test('one degree of longitude shrinks with the cosine of latitude', () {
      final double atEquator = RouteProcessor.haversineM(0, 0, 0, 1);
      final double atDelhi =
          RouteProcessor.haversineM(28.5931, 0, 28.5931, 1);
      expect(atEquator, closeTo(111195.0802, 0.001));
      expect(atDelhi, closeTo(atEquator * 0.878, 20));
    });

    test('a point is zero metres from itself', () {
      expect(RouteProcessor.haversineM(28.5931, 77.2197, 28.5931, 77.2197), 0);
    });

    test('distance is symmetric', () {
      final double there =
          RouteProcessor.haversineM(28.5931, 77.2197, 28.6139, 77.2090);
      final double back =
          RouteProcessor.haversineM(28.6139, 77.2090, 28.5931, 77.2197);
      expect(there, closeTo(back, 1e-9));
    });
  });

  group('polyline codec', () {
    test('matches the reference vector from the published algorithm', () {
      const List<RouteCoordinate> route = <RouteCoordinate>[
        RouteCoordinate(38.5, -120.2),
        RouteCoordinate(40.7, -120.95),
        RouteCoordinate(43.252, -126.453),
      ];
      expect(PolylineCodec.encode(route), r'_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(PolylineCodec.decode(r'_p~iF~ps|U_ulLnnqC_mqNvxq`@'), route);
    });

    test('round-trips a recorded route exactly at five decimal places', () {
      final ProcessedRoute route =
          RouteProcessor.process(loadRecordedRoute());
      final List<RouteCoordinate> decoded =
          PolylineCodec.decode(route.encodedPolyline);

      expect(decoded, hasLength(route.coordinates.length));
      for (int i = 0; i < decoded.length; i++) {
        expect(
          decoded[i].latitude,
          closeTo(route.coordinates[i].latitude, 0.000005),
        );
        expect(
          decoded[i].longitude,
          closeTo(route.coordinates[i].longitude, 0.000005),
        );
      }
      // Encoding the decoded route must be a fixed point: no drift on re-save.
      expect(PolylineCodec.encode(decoded), route.encodedPolyline);
    });

    test('handles negative, antimeridian and empty input', () {
      const List<RouteCoordinate> edges = <RouteCoordinate>[
        RouteCoordinate(-33.86785, 151.20732),
        RouteCoordinate(-89.99999, -179.99999),
        RouteCoordinate(0, 0),
        RouteCoordinate(89.99999, 179.99999),
      ];
      expect(PolylineCodec.decode(PolylineCodec.encode(edges)), edges);
      expect(PolylineCodec.encode(const <RouteCoordinate>[]), '');
      expect(PolylineCodec.decode(''), isEmpty);
    });

    test('rejects corrupt input instead of returning a truncated route', () {
      // A latitude with no longitude after it.
      expect(
        () => PolylineCodec.decode('_p~iF'),
        throwsFormatException,
      );
      // A continuation bit with nothing following it.
      expect(
        () => PolylineCodec.decode(r'_p~iF~ps|U_'),
        throwsFormatException,
      );
    });
  });

  group('clean route', () {
    // 400 legs of 3 m at 1 Hz: 1200 m in 400 s, a flat 5:33/km.
    final List<TrackingPoint> raw = straightRoute(legs: 400, spacingM: 3);
    final ProcessedRoute route = RouteProcessor.process(raw);

    test('keeps every fix', () {
      expect(route.filter.total, 401);
      expect(route.filter.accepted, 401);
      expect(route.filter.rejectedCount, 0);
      expect(route.filter.acceptedRatio, 1);
    });

    test('distance is the sum of the legs', () {
      expect(route.distanceM, closeTo(1200, 0.0001));
    });

    test('recorded, moving and wall-clock time all agree when nothing stops',
        () {
      expect(route.recorded, const Duration(seconds: 400));
      expect(route.moving, const Duration(seconds: 400));
      expect(route.wallClock, const Duration(seconds: 400));
    });

    test('pace and speed come out of moving time', () {
      expect(route.avgPaceSecPerKm, closeTo(333.3333, 0.001));
      expect(route.avgSpeedMps, closeTo(3, 0.0001));
    });

    test('splits close on the kilometre and the tail is marked partial', () {
      expect(route.splits, hasLength(2));

      final RouteSplit first = route.splits.first;
      expect(first.index, 1);
      expect(first.distanceM, 1000);
      expect(first.isPartial, isFalse);
      // 333 whole seconds plus a third of the leg that crosses 1000 m.
      expect(first.duration.inMilliseconds, closeTo(333333, 10));
      expect(first.paceSecPerKm, closeTo(333.333, 0.1));

      final RouteSplit last = route.splits.last;
      expect(last.index, 2);
      expect(last.distanceM, closeTo(200, 0.0001));
      expect(last.isPartial, isTrue);
      expect(last.duration.inMilliseconds, closeTo(66667, 10));
    });

    test('split durations add back up to the recorded time', () {
      final int total = route.splits.fold(
        0,
        (int sum, RouteSplit split) => sum + split.duration.inMilliseconds,
      );
      expect(total, closeTo(route.recorded.inMilliseconds, 2));
    });

    test('bounds enclose the route', () {
      final RouteBounds bounds = route.bounds!;
      expect(bounds.minLatitude, closeTo(raw.first.latitude, 1e-12));
      expect(bounds.maxLatitude, closeTo(raw.last.latitude, 1e-12));
      expect(bounds.minLongitude, bounds.maxLongitude);
    });
  });

  group('filter rejection cases', () {
    final ProcessedRoute route = RouteProcessor.process(loadRecordedRoute());

    test('each bad fix is rejected for the right reason', () {
      expect(route.filter.total, 60);
      expect(route.filter.accepted, 55);
      expect(route.filter.countOf(RoutePointRejection.accuracy), 2);
      expect(route.filter.countOf(RoutePointRejection.mock), 1);
      expect(route.filter.countOf(RoutePointRejection.timestamp), 1);
      expect(route.filter.countOf(RoutePointRejection.speed), 1);
      expect(route.filter.countOf(RoutePointRejection.coordinate), 0);
    });

    test('a rejected fix does not break the leg around it', () {
      // 27 seconds of segment 0 plus 29 of segment 1, all at 2.5 m/s, with the
      // five bad fixes bridged rather than cutting the route into pieces.
      expect(route.distanceM, closeTo(140, 0.0001));
      expect(route.recorded, const Duration(seconds: 56));
    });

    test('the pause is excluded from recorded time but not from wall clock',
        () {
      expect(route.wallClock, const Duration(seconds: 147));
      expect(
        route.wallClock - route.recorded,
        const Duration(seconds: 91),
      );
    });

    test('a route shorter than one split is a single partial split', () {
      expect(route.splits, hasLength(1));
      expect(route.splits.single.isPartial, isTrue);
      expect(route.splits.single.distanceM, closeTo(140, 0.0001));
    });

    test('fixes without altitude are skipped, not read as sea level', () {
      // 55 accepted fixes, three of which carried no altitude.
      expect(route.elevation!.sampleCount, 52);
      expect(route.elevation!.minM, greaterThan(200));
      expect(route.elevation!.lossM, 0);
    });

    test('an accuracy limit rejects everything a stricter one would', () {
      final ProcessedRoute strict = RouteProcessor.process(
        loadRecordedRoute(),
        options: const RouteProcessorOptions(maxAccuracyM: 5),
      );
      expect(strict.filter.accepted, 0);
      expect(strict.isEmpty, isTrue);
      expect(strict.avgPaceSecPerKm, isNull);
      expect(strict.encodedPolyline, '');
      expect(strict.bounds, isNull);
    });
  });

  group('leg breaks', () {
    test('a pause is never bridged by a straight line', () {
      final List<TrackingPoint> first = straightRoute(legs: 10);
      // Resumed a kilometre away, five minutes later, as a new segment.
      final List<TrackingPoint> second = straightRoute(
        legs: 10,
        startedAt: first.last.capturedAt.add(const Duration(minutes: 5)),
        startLatitude: first.last.latitude + latitudeStepFor(1000),
        segmentIndex: 1,
      );

      final ProcessedRoute route =
          RouteProcessor.process(<TrackingPoint>[...first, ...second]);

      expect(route.filter.accepted, 22);
      // 2 × 10 legs of 2.5 m. The kilometre between segments is not distance
      // the runner covered on foot.
      expect(route.distanceM, closeTo(50, 0.0001));
      expect(route.recorded, const Duration(seconds: 20));
    });

    test('a long signal gap inside one segment is not bridged either', () {
      final List<TrackingPoint> before = straightRoute(legs: 5);
      final List<TrackingPoint> after = straightRoute(
        legs: 5,
        startedAt: before.last.capturedAt.add(const Duration(seconds: 60)),
        startLatitude: before.last.latitude + latitudeStepFor(150),
        startIndex: 0,
      );

      final ProcessedRoute route =
          RouteProcessor.process(<TrackingPoint>[...before, ...after]);

      expect(route.filter.rejectedCount, 0);
      expect(route.distanceM, closeTo(25, 0.0001));
      expect(route.recorded, const Duration(seconds: 10));
      expect(route.wallClock, const Duration(seconds: 70));
    });

    test('a persistent relocation is accepted once the outlier budget runs out',
        () {
      final List<TrackingPoint> start = straightRoute(legs: 5);
      // Ten fixes 2 km away: the first few look like noise, then it becomes
      // clear the athlete really is somewhere else.
      final List<TrackingPoint> elsewhere = straightRoute(
        legs: 9,
        startedAt: start.last.capturedAt.add(const Duration(seconds: 1)),
        startLatitude: start.last.latitude + latitudeStepFor(2000),
      );

      final ProcessedRoute route =
          RouteProcessor.process(<TrackingPoint>[...start, ...elsewhere]);

      // Five rejected, then the rest accepted with the jump not counted.
      expect(route.filter.countOf(RoutePointRejection.speed), 5);
      expect(route.filter.accepted, 11);
      expect(route.distanceM, closeTo(12.5 + 10, 0.0001));
    });
  });

  group('moving time', () {
    test('a traffic light is excluded from moving time', () {
      final List<TrackingPoint> before = straightRoute(legs: 20);
      final List<TrackingPoint> stopped =
          stationaryRun(seconds: 15, at: before.last);
      final List<TrackingPoint> after = straightRoute(
        legs: 20,
        startedAt: stopped.last.capturedAt.add(const Duration(seconds: 1)),
        startLatitude: stopped.last.latitude,
      );

      final ProcessedRoute route = RouteProcessor.process(
        <TrackingPoint>[...before, ...stopped, ...after],
      );

      expect(route.recorded, const Duration(seconds: 56));
      // The 15 held fixes bracket 16 legs that cover no ground — the one into
      // the stop and the one out of it included — and 16 s clears the hold.
      expect(route.moving, const Duration(seconds: 40));
      expect(route.moving.inSeconds, lessThan(route.recorded.inSeconds));
    });

    test('a brief dip below walking pace still counts as moving', () {
      final List<TrackingPoint> before = straightRoute(legs: 20);
      final List<TrackingPoint> stopped =
          stationaryRun(seconds: 5, at: before.last);
      final List<TrackingPoint> after = straightRoute(
        legs: 20,
        startedAt: stopped.last.capturedAt.add(const Duration(seconds: 1)),
        startLatitude: stopped.last.latitude,
      );

      final ProcessedRoute route = RouteProcessor.process(
        <TrackingPoint>[...before, ...stopped, ...after],
      );

      expect(route.recorded, const Duration(seconds: 46));
      expect(route.moving, route.recorded);
    });
  });

  group('elevation', () {
    test('a steady climb accumulates above the noise threshold', () {
      final ProcessedRoute route = RouteProcessor.process(
        straightRoute(legs: 39, altitudeStartM: 216, altitudeStepM: 1),
      );

      final RouteElevation elevation = route.elevation!;
      expect(elevation.sampleCount, 40);
      expect(elevation.minM, closeTo(217, 1e-9));
      expect(elevation.maxM, closeTo(254, 1e-9));
      expect(elevation.gainM, closeTo(36, 1e-9));
      expect(elevation.lossM, 0);
    });

    test('flat ground with noisy altitude reports no gain', () {
      final List<TrackingPoint> base = straightRoute(legs: 39);
      final List<TrackingPoint> flat = List<TrackingPoint>.generate(
        base.length,
        (int i) => TrackingPoint(
          capturedAt: base[i].capturedAt,
          latitude: base[i].latitude,
          longitude: base[i].longitude,
          // ±1 m of jitter, which is optimistic for GPS altitude.
          altitudeM: 216 + (i.isEven ? 1.0 : -1.0),
          accuracyM: base[i].accuracyM,
          speedMps: base[i].speedMps,
          bearingDegrees: base[i].bearingDegrees,
          acceptedForLiveDistance: true,
          isMock: false,
        ),
      );

      final RouteElevation elevation =
          RouteProcessor.process(flat).elevation!;
      expect(elevation.gainM, 0);
      expect(elevation.lossM, 0);
    });

    test('too few altitude samples reports nothing rather than guessing', () {
      expect(RouteProcessor.process(straightRoute(legs: 40)).elevation, isNull);
    });
  });

  group('degenerate input', () {
    test('an empty recording processes to an empty route', () {
      final ProcessedRoute route =
          RouteProcessor.process(const <TrackingPoint>[]);
      expect(route.isEmpty, isTrue);
      expect(route.distanceM, 0);
      expect(route.splits, isEmpty);
      expect(route.avgPaceSecPerKm, isNull);
      expect(route.avgSpeedMps, isNull);
      expect(route.filter.acceptedRatio, 0);
    });

    test('a single fix has a position but no distance or pace', () {
      final ProcessedRoute route =
          RouteProcessor.process(straightRoute(legs: 0));
      expect(route.coordinates, hasLength(1));
      expect(route.distanceM, 0);
      expect(route.recorded, Duration.zero);
      expect(route.splits, isEmpty);
      expect(route.avgPaceSecPerKm, isNull);
      expect(route.bounds, isNotNull);
    });

    test('non-finite coordinates are rejected, not propagated', () {
      final List<TrackingPoint> raw = <TrackingPoint>[
        TrackingPoint(
          capturedAt: DateTime.utc(2026, 9, 7, 6),
          latitude: double.nan,
          longitude: 77.2197,
          altitudeM: null,
          accuracyM: 5,
          speedMps: 0,
          bearingDegrees: 0,
          acceptedForLiveDistance: false,
          isMock: false,
        ),
        TrackingPoint(
          capturedAt: DateTime.utc(2026, 9, 7, 6, 0, 1),
          latitude: 91,
          longitude: 77.2197,
          altitudeM: null,
          accuracyM: 5,
          speedMps: 0,
          bearingDegrees: 0,
          acceptedForLiveDistance: false,
          isMock: false,
        ),
      ];
      final ProcessedRoute route = RouteProcessor.process(raw);
      expect(route.filter.countOf(RoutePointRejection.coordinate), 2);
      expect(route.isEmpty, isTrue);
    });
  });
}
