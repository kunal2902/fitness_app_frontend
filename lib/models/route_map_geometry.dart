import 'package:equatable/equatable.dart';

import '../utils/polyline_codec.dart';
import '../utils/route_processor.dart';
import 'route_models.dart';

/// Decoded, display-ready route information shared by interactive and static
/// map surfaces. Keeping this pure makes fitting and split placement testable
/// without a platform map view.
class RouteMapGeometry extends Equatable {
  RouteMapGeometry._({
    required List<RouteCoordinate> coordinates,
    required List<RouteCoordinate> splitCoordinates,
  })  : coordinates = List<RouteCoordinate>.unmodifiable(coordinates),
        splitCoordinates = List<RouteCoordinate>.unmodifiable(splitCoordinates),
        bounds = RouteBounds.around(coordinates);

  factory RouteMapGeometry.decode(
    String encodedPolyline, {
    Iterable<RouteSplit> splits = const <RouteSplit>[],
  }) {
    final List<RouteCoordinate> coordinates =
        PolylineCodec.decode(encodedPolyline);
    return RouteMapGeometry._(
      coordinates: coordinates,
      splitCoordinates: _locateSplits(coordinates, splits.toList()),
    );
  }

  final List<RouteCoordinate> coordinates;
  final List<RouteCoordinate> splitCoordinates;
  final RouteBounds? bounds;

  bool get isEmpty => coordinates.isEmpty;
  RouteCoordinate? get start => coordinates.firstOrNull;
  RouteCoordinate? get end => coordinates.lastOrNull;

  @override
  List<Object?> get props => <Object?>[coordinates, splitCoordinates, bounds];

  static List<RouteCoordinate> _locateSplits(
    List<RouteCoordinate> route,
    List<RouteSplit> splits,
  ) {
    if (route.length < 2 || splits.length < 2) {
      return const <RouteCoordinate>[];
    }

    final List<double> targets = <double>[];
    double cumulative = 0;
    for (int i = 0; i < splits.length - 1; i++) {
      final RouteSplit split = splits[i];
      if (split.distanceM <= 0) continue;
      cumulative += split.distanceM;
      if (!split.isPartial) targets.add(cumulative);
    }

    final List<RouteCoordinate> found = <RouteCoordinate>[];
    double travelled = 0;
    int targetIndex = 0;
    for (int i = 1; i < route.length && targetIndex < targets.length; i++) {
      final RouteCoordinate from = route[i - 1];
      final RouteCoordinate to = route[i];
      final double leg = RouteProcessor.haversineM(
        from.latitude,
        from.longitude,
        to.latitude,
        to.longitude,
      );
      if (leg <= 0) continue;

      while (targetIndex < targets.length &&
          targets[targetIndex] <= travelled + leg) {
        final double fraction = ((targets[targetIndex] - travelled) / leg)
            .clamp(0.0, 1.0)
            .toDouble();
        double longitudeDelta = to.longitude - from.longitude;
        while (longitudeDelta > 180) {
          longitudeDelta -= 360;
        }
        while (longitudeDelta < -180) {
          longitudeDelta += 360;
        }
        double longitude = from.longitude + longitudeDelta * fraction;
        while (longitude > 180) {
          longitude -= 360;
        }
        while (longitude < -180) {
          longitude += 360;
        }
        found.add(
          RouteCoordinate(
            from.latitude + (to.latitude - from.latitude) * fraction,
            longitude,
          ),
        );
        targetIndex += 1;
      }
      travelled += leg;
    }
    return found;
  }

  /// Approximate route length. Used only to label an accessibility surface.
  double get distanceM {
    double total = 0;
    for (int i = 1; i < coordinates.length; i++) {
      total += RouteProcessor.haversineM(
        coordinates[i - 1].latitude,
        coordinates[i - 1].longitude,
        coordinates[i].latitude,
        coordinates[i].longitude,
      );
    }
    return total < 0 ? 0 : total;
  }
}
