import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../config/app_config.dart';
import '../models/route_map_geometry.dart';
import '../models/route_models.dart';
import '../theme/app_colors.dart';

/// Interactive route map for an activity detail or post-workout surface.
///
/// It draws route annotations only after the style is ready, fits the full
/// route, and falls back to an offline vector preview if the style cannot load.
class ActivityRouteMap extends StatefulWidget {
  const ActivityRouteMap({
    required this.encodedPolyline,
    this.splits = const <RouteSplit>[],
    this.height = 260,
    this.interactive = true,
    this.showSplitMarkers = true,
    this.styleUrl,
    this.forceFallback = false,
    super.key,
  });

  final String encodedPolyline;
  final List<RouteSplit> splits;
  final double height;
  final bool interactive;
  final bool showSplitMarkers;
  final String? styleUrl;

  /// Lets unsupported platforms and widget tests use the no-plugin renderer.
  final bool forceFallback;

  @override
  State<ActivityRouteMap> createState() => _ActivityRouteMapState();
}

class _ActivityRouteMapState extends State<ActivityRouteMap> {
  RouteMapGeometry? _geometry;
  Object? _decodeError;
  MapLibreMapController? _controller;
  Timer? _styleTimeout;
  bool _styleReady = false;
  bool _mapFailed = false;
  int _mapRevision = 0;

  bool get _supportsMapLibre =>
      !widget.forceFallback &&
      (kIsWeb ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant ActivityRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.encodedPolyline != widget.encodedPolyline ||
        !listEquals(oldWidget.splits, widget.splits) ||
        oldWidget.styleUrl != widget.styleUrl) {
      _styleTimeout?.cancel();
      _controller = null;
      _styleReady = false;
      _mapFailed = false;
      _mapRevision += 1;
      _decode();
    }
  }

  @override
  void dispose() {
    _styleTimeout?.cancel();
    super.dispose();
  }

  void _decode() {
    try {
      _geometry = RouteMapGeometry.decode(
        widget.encodedPolyline,
        splits: widget.splits,
      );
      _decodeError = null;
    } on FormatException catch (error) {
      _geometry = null;
      _decodeError = error;
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    _styleTimeout?.cancel();
    _styleTimeout = Timer(const Duration(seconds: 12), () {
      if (!mounted || _styleReady || _controller != controller) return;
      setState(() => _mapFailed = true);
    });
  }

  Future<void> _onStyleLoaded() async {
    final MapLibreMapController? controller = _controller;
    final RouteMapGeometry? geometry = _geometry;
    if (controller == null || geometry == null || geometry.isEmpty) return;

    try {
      final List<LatLng> route = geometry.coordinates
          .map((RouteCoordinate c) => LatLng(c.latitude, c.longitude))
          .toList(growable: false);

      if (route.length > 1) {
        await controller.addLines(<LineOptions>[
          LineOptions(
            geometry: route,
            lineColor: '#050707',
            lineWidth: 9,
            lineOpacity: 0.72,
            lineJoin: 'round',
          ),
          LineOptions(
            geometry: route,
            lineColor: '#C6FF3D',
            lineWidth: 5,
            lineOpacity: 1,
            lineJoin: 'round',
          ),
        ]);
      }

      final List<CircleOptions> markers = <CircleOptions>[
        if (widget.showSplitMarkers)
          for (final RouteCoordinate split in geometry.splitCoordinates)
            CircleOptions(
              geometry: LatLng(split.latitude, split.longitude),
              circleRadius: 5,
              circleColor: '#0B0F0E',
              circleStrokeWidth: 2,
              circleStrokeColor: '#C6FF3D',
            ),
        CircleOptions(
          geometry: route.first,
          circleRadius: 7,
          circleColor: '#C6FF3D',
          circleStrokeWidth: 3,
          circleStrokeColor: '#050707',
        ),
        CircleOptions(
          geometry: route.last,
          circleRadius: 7,
          circleColor: '#F7F9F8',
          circleStrokeWidth: 3,
          circleStrokeColor: '#050707',
        ),
      ];
      await controller.addCircles(markers);
      await _fit(controller, geometry);

      if (!mounted || _controller != controller) return;
      _styleTimeout?.cancel();
      setState(() {
        _styleReady = true;
        _mapFailed = false;
      });
    } catch (_) {
      if (!mounted || _controller != controller) return;
      _styleTimeout?.cancel();
      setState(() => _mapFailed = true);
    }
  }

  Future<void> _fit(
    MapLibreMapController controller,
    RouteMapGeometry geometry,
  ) async {
    final RouteBounds bounds = geometry.bounds!;
    final double latitudeSpan = bounds.maxLatitude - bounds.minLatitude;
    double longitudeSpan = bounds.maxLongitude - bounds.minLongitude;
    if (longitudeSpan < 0) longitudeSpan += 360;
    if (latitudeSpan.abs() < 0.000001 && longitudeSpan.abs() < 0.000001) {
      final RouteCoordinate centre = bounds.centre;
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(centre.latitude, centre.longitude),
          15,
        ),
      );
      return;
    }
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(bounds.minLatitude, bounds.minLongitude),
          northeast: LatLng(bounds.maxLatitude, bounds.maxLongitude),
        ),
        left: 42,
        top: 42,
        right: 42,
        bottom: 42,
      ),
    );
  }

  void _retry() {
    _styleTimeout?.cancel();
    setState(() {
      _controller = null;
      _styleReady = false;
      _mapFailed = false;
      _mapRevision += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final RouteMapGeometry? geometry = _geometry;
    if (_decodeError != null) {
      return _RouteMessage(
        height: widget.height,
        icon: Icons.broken_image_outlined,
        message: 'Route preview unavailable',
      );
    }
    if (geometry == null || geometry.isEmpty) {
      return _RouteMessage(
        height: widget.height,
        icon: Icons.route_outlined,
        message: 'No outdoor route for this activity',
      );
    }

    final String semantics =
        'Activity route, ${(geometry.distanceM / 1000).toStringAsFixed(1)} kilometres';
    if (!_supportsMapLibre || _mapFailed) {
      return Semantics(
        image: true,
        label: semantics,
        child: SizedBox(
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              RouteShapePreview(geometry: geometry),
              if (_mapFailed)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _OfflineNotice(onRetry: _retry),
                ),
            ],
          ),
        ),
      );
    }

    final RouteCoordinate initial = geometry.bounds!.centre;
    return Semantics(
      image: true,
      label: semantics,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              MapLibreMap(
                key: ValueKey<String>(
                  '${widget.encodedPolyline}:${widget.styleUrl}:$_mapRevision',
                ),
                styleString: widget.styleUrl ?? AppConfig.mapStyleUrl,
                initialCameraPosition: CameraPosition(
                  target: LatLng(initial.latitude, initial.longitude),
                  zoom: 13,
                ),
                onMapCreated: _onMapCreated,
                onStyleLoadedCallback: _onStyleLoaded,
                compassEnabled: widget.interactive,
                rotateGesturesEnabled: widget.interactive,
                scrollGesturesEnabled: widget.interactive,
                zoomGesturesEnabled: widget.interactive,
                tiltGesturesEnabled: false,
                dragEnabled: widget.interactive,
                myLocationEnabled: false,
                annotationOrder: const <AnnotationType>[
                  AnnotationType.line,
                  AnnotationType.circle,
                ],
              ),
              if (!_styleReady)
                const IgnorePointer(
                  child: ColoredBox(
                    color: AppColors.darkSurface,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// List/share image backed by the server-generated immutable PNG. If a legacy
/// activity has no thumbnail (or the image is offline), route geometry remains
/// visible through the same local fallback used by [ActivityRouteMap].
class ActivityRouteThumbnail extends StatelessWidget {
  const ActivityRouteThumbnail({
    required this.encodedPolyline,
    this.thumbnailUrl,
    this.splits = const <RouteSplit>[],
    this.height = 170,
    super.key,
  });

  final String? thumbnailUrl;
  final String encodedPolyline;
  final List<RouteSplit> splits;
  final double height;

  @override
  Widget build(BuildContext context) {
    RouteMapGeometry? geometry;
    try {
      geometry = RouteMapGeometry.decode(encodedPolyline, splits: splits);
    } on FormatException {
      geometry = null;
    }
    final Widget fallback = geometry == null || geometry.isEmpty
        ? _RouteMessage(
            height: height,
            icon: Icons.route_outlined,
            message: 'No route preview',
          )
        : RouteShapePreview(geometry: geometry);
    final String? resolved = AppConfig.resolveMediaUrl(thumbnailUrl);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        child: resolved == null
            ? fallback
            : Image.network(
                resolved,
                fit: BoxFit.cover,
                semanticLabel: 'Activity route preview',
                errorBuilder: (_, __, ___) => fallback,
                frameBuilder: (context, child, frame, synchronous) {
                  if (synchronous || frame != null) return child;
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      fallback,
                      const Center(child: CircularProgressIndicator()),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class RouteShapePreview extends StatelessWidget {
  const RouteShapePreview({required this.geometry, super.key});

  final RouteMapGeometry geometry;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: CustomPaint(
        painter: _RouteShapePainter(geometry),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RouteShapePainter extends CustomPainter {
  const _RouteShapePainter(this.geometry);

  final RouteMapGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0B0F0E),
    );
    final Paint grid = Paint()
      ..color = const Color(0xFF1C2421)
      ..strokeWidth = 1;
    for (double x = 24; x < size.width; x += 56) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 20; y < size.height; y += 56) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final _CanvasProjection projection =
        _CanvasProjection(geometry.coordinates, size);
    final List<Offset> route =
        geometry.coordinates.map(projection.project).toList(growable: false);
    if (route.isEmpty) return;
    final Path path = Path()..moveTo(route.first.dx, route.first.dy);
    for (final Offset point in route.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xCC020404)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.volt
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (final RouteCoordinate split in geometry.splitCoordinates) {
      final Offset point = projection.project(split);
      canvas.drawCircle(point, 5, Paint()..color = const Color(0xFF0B0F0E));
      canvas.drawCircle(
        point,
        5,
        Paint()
          ..color = AppColors.volt
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    _marker(canvas, route.first, AppColors.volt);
    _marker(canvas, route.last, const Color(0xFFF7F9F8));
  }

  void _marker(Canvas canvas, Offset point, Color colour) {
    canvas.drawCircle(point, 9, Paint()..color = const Color(0xCC020404));
    canvas.drawCircle(point, 6, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(covariant _RouteShapePainter oldDelegate) =>
      oldDelegate.geometry != geometry;
}

class _CanvasProjection {
  _CanvasProjection(List<RouteCoordinate> coordinates, Size size)
      : _size = size {
    double? previousX;
    for (final RouteCoordinate coordinate in coordinates) {
      final Offset raw = _mercator(coordinate);
      double x = raw.dx;
      if (previousX != null) {
        while (x - previousX > 0.5) {
          x -= 1;
        }
        while (x - previousX < -0.5) {
          x += 1;
        }
      }
      previousX = x;
      _source.add(Offset(x, raw.dy));
      _minX = math.min(_minX, x);
      _maxX = math.max(_maxX, x);
      _minY = math.min(_minY, raw.dy);
      _maxY = math.max(_maxY, raw.dy);
    }
  }

  final Size _size;
  final List<Offset> _source = <Offset>[];
  double _minX = double.infinity;
  double _maxX = double.negativeInfinity;
  double _minY = double.infinity;
  double _maxY = double.negativeInfinity;

  Offset project(RouteCoordinate coordinate) {
    final Offset raw = _mercator(coordinate);
    double x = raw.dx;
    final double centreX = (_minX + _maxX) / 2;
    while (x - centreX > 0.5) {
      x -= 1;
    }
    while (x - centreX < -0.5) {
      x += 1;
    }

    const double padding = 26;
    final double availableWidth = math.max(1, _size.width - padding * 2);
    final double availableHeight = math.max(1, _size.height - padding * 2);
    final double spanX = math.max(_maxX - _minX, 0.0000001);
    final double spanY = math.max(_maxY - _minY, 0.0000001);
    final double scale =
        math.min(availableWidth / spanX, availableHeight / spanY);
    final double drawnWidth = (_maxX - _minX) * scale;
    final double drawnHeight = (_maxY - _minY) * scale;
    final double offsetX = (_size.width - drawnWidth) / 2;
    final double offsetY = (_size.height - drawnHeight) / 2;
    return Offset(
      offsetX + (x - _minX) * scale,
      offsetY + (raw.dy - _minY) * scale,
    );
  }

  static Offset _mercator(RouteCoordinate coordinate) {
    final double latitude =
        coordinate.latitude.clamp(-85.05112878, 85.05112878);
    final double radians = latitude * math.pi / 180;
    return Offset(
      (coordinate.longitude + 180) / 360,
      (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) / 2,
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.darkSurface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Map offline — route still available',
                style: TextStyle(color: AppColors.darkTextPrimary),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _RouteMessage extends StatelessWidget {
  const _RouteMessage({
    required this.height,
    required this.icon,
    required this.message,
  });

  final double height;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.darkBorder),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: AppColors.darkTextSecondary),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(color: AppColors.darkTextSecondary),
          ),
        ],
      ),
    );
  }
}
