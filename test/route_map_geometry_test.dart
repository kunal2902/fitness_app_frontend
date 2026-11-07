import 'package:fitness_app/models/route_map_geometry.dart';
import 'package:fitness_app/models/route_models.dart';
import 'package:fitness_app/utils/polyline_codec.dart';
import 'package:fitness_app/widgets/activity_route_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('route map geometry', () {
    test('decodes the route and computes bounds, start and end', () {
      final RouteMapGeometry geometry = RouteMapGeometry.decode(
        r'_p~iF~ps|U_ulLnnqC_mqNvxq`@',
      );

      expect(geometry.coordinates, hasLength(3));
      expect(geometry.start, const RouteCoordinate(38.5, -120.2));
      expect(geometry.end, const RouteCoordinate(43.252, -126.453));
      expect(geometry.bounds!.minLatitude, 38.5);
      expect(geometry.bounds!.maxLatitude, 43.252);
      expect(geometry.bounds!.minLongitude, -126.453);
      expect(geometry.bounds!.maxLongitude, -120.2);
    });

    test('places complete split boundaries along the route', () {
      const List<RouteCoordinate> route = <RouteCoordinate>[
        RouteCoordinate(0, 0),
        RouteCoordinate(0, 0.02),
      ];
      const List<RouteSplit> splits = <RouteSplit>[
        RouteSplit(
          index: 1,
          distanceM: 1000,
          duration: Duration(minutes: 5),
          moving: Duration(minutes: 5),
          isPartial: false,
        ),
        RouteSplit(
          index: 2,
          distanceM: 1000,
          duration: Duration(minutes: 5),
          moving: Duration(minutes: 5),
          isPartial: false,
        ),
        RouteSplit(
          index: 3,
          distanceM: 223.9,
          duration: Duration(minutes: 1),
          moving: Duration(minutes: 1),
          isPartial: true,
        ),
      ];
      final RouteMapGeometry geometry = RouteMapGeometry.decode(
        PolylineCodec.encode(route),
        splits: splits,
      );

      expect(geometry.splitCoordinates, hasLength(2));
      expect(geometry.splitCoordinates[0].latitude, 0);
      expect(
        geometry.splitCoordinates[0].longitude,
        closeTo(0.008993, 0.00001),
      );
      expect(
        geometry.splitCoordinates[1].longitude,
        closeTo(0.017986, 0.00001),
      );
    });

    test('fits the short arc when a route crosses the antimeridian', () {
      const List<RouteCoordinate> route = <RouteCoordinate>[
        RouteCoordinate(10, 179.8),
        RouteCoordinate(10.1, -179.7),
      ];
      final RouteMapGeometry geometry = RouteMapGeometry.decode(
        PolylineCodec.encode(route),
      );

      expect(geometry.bounds!.minLongitude, closeTo(179.8, 0.00001));
      expect(geometry.bounds!.maxLongitude, closeTo(-179.7, 0.00001));
      expect(geometry.bounds!.centre.longitude, closeTo(-179.95, 0.00001));
    });

    test('keeps empty routes empty and rejects corrupt routes', () {
      expect(RouteMapGeometry.decode('').isEmpty, isTrue);
      expect(
        () => RouteMapGeometry.decode('_p~iF'),
        throwsFormatException,
      );
    });
  });

  group('route map widgets', () {
    testWidgets('fallback renderer draws a route without a platform map',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ActivityRouteMap(
              encodedPolyline: r'_p~iF~ps|U_ulLnnqC_mqNvxq`@',
              forceFallback: true,
            ),
          ),
        ),
      );

      expect(find.byType(RouteShapePreview), findsOneWidget);
      expect(find.text('Route preview unavailable'), findsNothing);
    });

    testWidgets('empty and invalid routes have honest placeholders',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                ActivityRouteMap(encodedPolyline: '', height: 100),
                ActivityRouteMap(encodedPolyline: '_p~iF', height: 100),
              ],
            ),
          ),
        ),
      );

      expect(find.text('No outdoor route for this activity'), findsOneWidget);
      expect(find.text('Route preview unavailable'), findsOneWidget);
    });
  });
}
