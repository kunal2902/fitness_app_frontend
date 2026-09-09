import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/tracking_models.dart';

abstract interface class TrackingRecorder {
  bool get isSupported;

  Future<TrackingPermissionSnapshot> permissionStatus();
  Future<TrackingPermissionSnapshot> requestPermissions();
  Future<void> openAppSettings();
  Future<void> openLocationSettings();
  Future<TrackingSessionSnapshot> currentSession();
  Future<void> start();
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> discard();
  Future<List<TrackingPoint>> points(String sessionId);
}

class TrackingRecorderException implements Exception {
  const TrackingRecorderException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class PlatformTrackingRecorder implements TrackingRecorder {
  PlatformTrackingRecorder({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.fitnessapp/tracking_recorder';
  final MethodChannel _channel;

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<TrackingPermissionSnapshot> permissionStatus() async {
    if (!isSupported) {
      return const TrackingPermissionSnapshot.unsupported();
    }
    return TrackingPermissionSnapshot.fromMap(
      await _mapCall('permissionStatus'),
    );
  }

  @override
  Future<TrackingPermissionSnapshot> requestPermissions() async {
    if (!isSupported) {
      return const TrackingPermissionSnapshot.unsupported();
    }
    return TrackingPermissionSnapshot.fromMap(
      await _mapCall('requestPermissions'),
    );
  }

  @override
  Future<TrackingSessionSnapshot> currentSession() async {
    if (!isSupported) return const TrackingSessionSnapshot.idle();
    return TrackingSessionSnapshot.fromMap(await _mapCall('getSession'));
  }

  @override
  Future<void> start() => _voidCall('start');

  @override
  Future<void> pause() => _voidCall('pause');

  @override
  Future<void> resume() => _voidCall('resume');

  @override
  Future<void> stop() => _voidCall('stop');

  @override
  Future<void> discard() => _voidCall('discard');

  @override
  Future<void> openAppSettings() => _voidCall('openAppSettings');

  @override
  Future<void> openLocationSettings() => _voidCall('openLocationSettings');

  @override
  Future<List<TrackingPoint>> points(String sessionId) async {
    if (!isSupported) return const <TrackingPoint>[];
    final Object? raw = await _invoke(
      'getSessionPoints',
      <String, Object?>{'sessionId': sessionId},
    );
    if (raw is! List) {
      throw const TrackingRecorderException(
        'The recorder returned invalid route data.',
        code: 'BAD_TRACKING_DATA',
      );
    }
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(TrackingPoint.fromMap)
        .toList(growable: false);
  }

  Future<Map<Object?, Object?>> _mapCall(String method) async {
    final Object? raw = await _invoke(method);
    if (raw is! Map) {
      throw const TrackingRecorderException(
        'The recorder returned an invalid response.',
        code: 'BAD_TRACKING_DATA',
      );
    }
    return Map<Object?, Object?>.from(raw);
  }

  Future<void> _voidCall(String method) async {
    if (!isSupported) {
      throw const TrackingRecorderException(
        'Workout recording is currently available on Android.',
        code: 'TRACKING_UNSUPPORTED',
      );
    }
    await _invoke(method);
  }

  Future<Object?> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      throw TrackingRecorderException(
        error.message ?? 'The workout recorder could not complete that action.',
        code: error.code,
      );
    } on MissingPluginException {
      throw const TrackingRecorderException(
        'Restart the app to finish enabling workout recording.',
        code: 'TRACKING_PLUGIN_MISSING',
      );
    }
  }
}
