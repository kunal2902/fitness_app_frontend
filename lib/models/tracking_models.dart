import 'package:equatable/equatable.dart';

enum TrackingLocationPermission {
  notRequested,
  denied,
  deniedForever,
  approximate,
  precise;

  static TrackingLocationPermission fromWire(Object? raw) {
    return switch (raw) {
      'denied' => TrackingLocationPermission.denied,
      'deniedForever' => TrackingLocationPermission.deniedForever,
      'approximate' => TrackingLocationPermission.approximate,
      'precise' => TrackingLocationPermission.precise,
      _ => TrackingLocationPermission.notRequested,
    };
  }
}

enum TrackingNotificationPermission {
  notRequested,
  denied,
  deniedForever,
  granted,
  notRequired;

  static TrackingNotificationPermission fromWire(Object? raw) {
    return switch (raw) {
      'denied' => TrackingNotificationPermission.denied,
      'deniedForever' => TrackingNotificationPermission.deniedForever,
      'granted' => TrackingNotificationPermission.granted,
      'notRequired' => TrackingNotificationPermission.notRequired,
      _ => TrackingNotificationPermission.notRequested,
    };
  }
}

class TrackingPermissionSnapshot extends Equatable {
  const TrackingPermissionSnapshot({
    required this.supported,
    required this.locationServicesEnabled,
    required this.location,
    required this.notifications,
  });

  const TrackingPermissionSnapshot.unsupported()
      : supported = false,
        locationServicesEnabled = false,
        location = TrackingLocationPermission.notRequested,
        notifications = TrackingNotificationPermission.notRequested;

  final bool supported;
  final bool locationServicesEnabled;
  final TrackingLocationPermission location;
  final TrackingNotificationPermission notifications;

  bool get hasPreciseLocation => location == TrackingLocationPermission.precise;

  bool get hasNotifications =>
      notifications == TrackingNotificationPermission.granted ||
      notifications == TrackingNotificationPermission.notRequired;

  bool get canRecord =>
      supported &&
      locationServicesEnabled &&
      hasPreciseLocation &&
      hasNotifications;

  bool get needsAppSettings =>
      location == TrackingLocationPermission.deniedForever ||
      location == TrackingLocationPermission.approximate ||
      notifications == TrackingNotificationPermission.deniedForever;

  factory TrackingPermissionSnapshot.fromMap(Map<Object?, Object?> map) {
    return TrackingPermissionSnapshot(
      supported: map['supported'] as bool? ?? true,
      locationServicesEnabled: map['locationServicesEnabled'] as bool? ?? false,
      location: TrackingLocationPermission.fromWire(map['location']),
      notifications:
          TrackingNotificationPermission.fromWire(map['notifications']),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        supported,
        locationServicesEnabled,
        location,
        notifications,
      ];
}

enum TrackingSessionStatus {
  idle,
  acquiring,
  recording,
  paused;

  static TrackingSessionStatus fromWire(Object? raw) {
    return switch (raw) {
      'acquiring' => TrackingSessionStatus.acquiring,
      'recording' => TrackingSessionStatus.recording,
      'paused' => TrackingSessionStatus.paused,
      _ => TrackingSessionStatus.idle,
    };
  }
}

class TrackingSessionSnapshot extends Equatable {
  const TrackingSessionSnapshot({
    required this.status,
    this.sessionId,
    this.startedAt,
    this.elapsed = Duration.zero,
    this.distanceM = 0,
    this.pointCount = 0,
  });

  const TrackingSessionSnapshot.idle()
      : status = TrackingSessionStatus.idle,
        sessionId = null,
        startedAt = null,
        elapsed = Duration.zero,
        distanceM = 0,
        pointCount = 0;

  final TrackingSessionStatus status;
  final String? sessionId;
  final DateTime? startedAt;
  final Duration elapsed;
  final double distanceM;
  final int pointCount;

  bool get isActive => status != TrackingSessionStatus.idle;
  bool get isRecording => status == TrackingSessionStatus.recording;
  bool get isPaused => status == TrackingSessionStatus.paused;
  bool get isAcquiring => status == TrackingSessionStatus.acquiring;

  factory TrackingSessionSnapshot.fromMap(Map<Object?, Object?> map) {
    final TrackingSessionStatus status =
        TrackingSessionStatus.fromWire(map['status']);
    if (status == TrackingSessionStatus.idle) {
      return const TrackingSessionSnapshot.idle();
    }
    final int? startedAtMs = (map['startedAt'] as num?)?.toInt();
    return TrackingSessionSnapshot(
      status: status,
      sessionId: map['sessionId']?.toString(),
      startedAt: startedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(startedAtMs),
      elapsed: Duration(
        milliseconds: (map['elapsedMs'] as num?)?.toInt() ?? 0,
      ),
      distanceM: (map['distanceM'] as num?)?.toDouble() ?? 0,
      pointCount: (map['pointCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        status,
        sessionId,
        startedAt,
        elapsed,
        distanceM,
        pointCount,
      ];
}

class TrackingPoint extends Equatable {
  const TrackingPoint({
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
    required this.altitudeM,
    required this.accuracyM,
    required this.speedMps,
    required this.bearingDegrees,
    required this.acceptedForLiveDistance,
    required this.isMock,
    this.segmentIndex = 0,
  });

  final DateTime capturedAt;
  final double latitude;
  final double longitude;
  /// Null when the fix carried no altitude. Never 0 as a stand-in — the
  /// elevation profile has to be able to tell "sea level" from "unknown".
  final double? altitudeM;
  final double accuracyM;
  final double speedMps;
  final double bearingDegrees;

  /// Step 1's conservative live-distance flag. Step 2 will reprocess every
  /// raw point with pure Dart filtering and replace this provisional result.
  final bool acceptedForLiveDistance;
  final bool isMock;

  /// Increments on every resume. Distance is only ever accumulated within a
  /// segment, so a pause is never bridged by a straight line.
  final int segmentIndex;

  factory TrackingPoint.fromMap(Map<Object?, Object?> map) {
    return TrackingPoint(
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['capturedAt'] as num).toInt(),
      ),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitudeM: (map['altitudeM'] as num?)?.toDouble(),
      accuracyM: (map['accuracyM'] as num?)?.toDouble() ?? 0,
      speedMps: (map['speedMps'] as num?)?.toDouble() ?? 0,
      bearingDegrees: (map['bearingDegrees'] as num?)?.toDouble() ?? 0,
      acceptedForLiveDistance:
          (map['acceptedForLiveDistance'] as bool?) ?? false,
      isMock: (map['isMock'] as bool?) ?? false,
      segmentIndex: (map['segmentIndex'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        capturedAt,
        latitude,
        longitude,
        altitudeM,
        accuracyM,
        speedMps,
        bearingDegrees,
        acceptedForLiveDistance,
        isMock,
        segmentIndex,
      ];
}
