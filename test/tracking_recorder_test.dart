import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/models/tracking_models.dart';
import 'package:fitness_app/screens/tracking/tracking_screen.dart';
import 'package:fitness_app/services/tracking_recorder.dart';
import 'package:fitness_app/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTrackingRecorder implements TrackingRecorder {
  @override
  bool isSupported = true;

  TrackingPermissionSnapshot permission = const TrackingPermissionSnapshot(
    supported: true,
    locationServicesEnabled: true,
    location: TrackingLocationPermission.notRequested,
    notifications: TrackingNotificationPermission.notRequested,
  );
  TrackingSessionSnapshot session = const TrackingSessionSnapshot.idle();
  int permissionRequests = 0;
  final List<String> controls = <String>[];

  @override
  Future<TrackingPermissionSnapshot> permissionStatus() async => permission;

  @override
  Future<TrackingPermissionSnapshot> requestPermissions() async {
    permissionRequests += 1;
    permission = const TrackingPermissionSnapshot(
      supported: true,
      locationServicesEnabled: true,
      location: TrackingLocationPermission.precise,
      notifications: TrackingNotificationPermission.granted,
    );
    return permission;
  }

  @override
  Future<TrackingSessionSnapshot> currentSession() async => session;

  @override
  Future<void> start() async {
    controls.add('start');
    session = TrackingSessionSnapshot(
      status: TrackingSessionStatus.recording,
      sessionId: 'session-1',
      startedAt: DateTime(2026, 9, 7, 6),
      elapsed: const Duration(minutes: 2, seconds: 3),
      distanceM: 1250,
      pointCount: 123,
    );
  }

  @override
  Future<void> pause() async {
    controls.add('pause');
    session = TrackingSessionSnapshot(
      status: TrackingSessionStatus.paused,
      sessionId: session.sessionId,
      startedAt: session.startedAt,
      elapsed: session.elapsed,
      distanceM: session.distanceM,
      pointCount: session.pointCount,
    );
  }

  @override
  Future<void> resume() async {
    controls.add('resume');
    session = TrackingSessionSnapshot(
      status: TrackingSessionStatus.recording,
      sessionId: session.sessionId,
      startedAt: session.startedAt,
      elapsed: session.elapsed,
      distanceM: session.distanceM,
      pointCount: session.pointCount,
    );
  }

  @override
  Future<void> stop() async {
    controls.add('stop');
    session = const TrackingSessionSnapshot.idle();
  }

  @override
  Future<void> discard() async {
    controls.add('discard');
    session = const TrackingSessionSnapshot.idle();
  }

  @override
  Future<void> openAppSettings() async => controls.add('app-settings');

  @override
  Future<void> openLocationSettings() async =>
      controls.add('location-settings');

  @override
  Future<List<TrackingPoint>> points(String sessionId) async =>
      const <TrackingPoint>[];
}

/// A recorder whose control commands can be held open, so the live poll runs
/// while a command is still in flight.
class GatedTrackingRecorder extends FakeTrackingRecorder {
  Completer<void>? gate;

  @override
  Future<void> pause() async {
    controls.add('pause');
    final Completer<void>? pending = gate;
    if (pending != null) await pending.future;
  }
}

void main() {
  Future<void> openTracking(
    WidgetTester tester,
    FakeTrackingRecorder recorder,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TrackingScreen(recorder: recorder),
      ),
    );
    await tester.pump();
  }

  test('wire models preserve permission, active-session and raw-point data',
      () {
    final TrackingPermissionSnapshot permission =
        TrackingPermissionSnapshot.fromMap(const <Object?, Object?>{
      'supported': true,
      'locationServicesEnabled': true,
      'location': 'precise',
      'notifications': 'notRequired',
    });
    expect(permission.canRecord, isTrue);

    final TrackingSessionSnapshot session =
        TrackingSessionSnapshot.fromMap(const <Object?, Object?>{
      'status': 'recording',
      'sessionId': 'route-1',
      'startedAt': 1_788_758_400_000,
      'elapsedMs': 65_000,
      'distanceM': 321.5,
      'pointCount': 60,
    });
    expect(session.isRecording, isTrue);
    expect(session.elapsed, const Duration(minutes: 1, seconds: 5));
    expect(session.distanceM, 321.5);

    final TrackingPoint point = TrackingPoint.fromMap(const <Object?, Object?>{
      'capturedAt': 1_788_758_400_000,
      'latitude': 28.6139,
      'longitude': 77.2090,
      'altitudeM': 216.0,
      'accuracyM': 8.0,
      'speedMps': 3.1,
      'bearingDegrees': 90.0,
      'acceptedForLiveDistance': true,
      'isMock': false,
    });
    expect(point.accuracyM, 8);
    expect(point.acceptedForLiveDistance, isTrue);
  });

  test('Android manifest inputs cannot merge background location permission',
      () {
    const String forbidden =
        'android:name="android.permission.ACCESS_BACKGROUND_LOCATION"';
    final String appManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(appManifest, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(
      appManifest,
      contains('android.permission.FOREGROUND_SERVICE_LOCATION'),
    );
    expect(appManifest, contains('android:foregroundServiceType="location"'));
    expect(appManifest, contains('android:name=".TrackingService"'));
    expect(appManifest, isNot(contains(forbidden)));

    final Map<String, dynamic> dependencies = jsonDecode(
      File('.flutter-plugins-dependencies').readAsStringSync(),
    ) as Map<String, dynamic>;
    final List<dynamic> androidPlugins =
        ((dependencies['plugins'] as Map<String, dynamic>)['android'] as List);
    final List<String> offenders = <String>[];
    for (final dynamic rawPlugin in androidPlugins) {
      final Map<String, dynamic> plugin = rawPlugin as Map<String, dynamic>;
      final Directory android = Directory('${plugin['path']}android');
      if (!android.existsSync()) continue;
      for (final FileSystemEntity entity in android.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('AndroidManifest.xml')) {
          continue;
        }
        if (entity.readAsStringSync().contains(forbidden)) {
          offenders.add('${plugin['name']}: ${entity.path}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'A plugin would inject background location into the merge.',
    );
  });

  test('platform recorder uses the native channel contract', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const MethodChannel channel =
        MethodChannel('com.fitnessapp/tracking_recorder-test');
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return switch (call.method) {
        'permissionStatus' => <String, Object?>{
            'supported': true,
            'locationServicesEnabled': true,
            'location': 'precise',
            'notifications': 'granted',
          },
        'getSessionPoints' => <Map<String, Object?>>[
            <String, Object?>{
              'capturedAt': 1_788_758_400_000,
              'latitude': 28.6,
              'longitude': 77.2,
              'accuracyM': 5.0,
              'acceptedForLiveDistance': true,
              'isMock': false,
            },
          ],
        _ => null,
      };
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final PlatformTrackingRecorder recorder =
        PlatformTrackingRecorder(channel: channel);

    expect((await recorder.permissionStatus()).canRecord, isTrue);
    await recorder.start();
    expect((await recorder.points('session-1')).single.latitude, 28.6);
    expect(calls.map((MethodCall call) => call.method), <String>[
      'permissionStatus',
      'start',
      'getSessionPoints',
    ]);
    expect(
      calls.last.arguments,
      <String, Object?>{'sessionId': 'session-1'},
    );
  });

  testWidgets('permission rationale appears before any system prompt',
      (WidgetTester tester) async {
    final FakeTrackingRecorder recorder = FakeTrackingRecorder();
    await openTracking(tester, recorder);

    expect(find.text('Allow precise location'), findsOneWidget);
    expect(find.textContaining('screen is off'), findsOneWidget);
    expect(recorder.permissionRequests, 0);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(recorder.permissionRequests, 1);
    expect(find.text('Start outdoor workout'), findsOneWidget);
  });

  testWidgets('start, pause, resume and finish retain live recorder state',
      (WidgetTester tester) async {
    final FakeTrackingRecorder recorder = FakeTrackingRecorder()
      ..permission = const TrackingPermissionSnapshot(
        supported: true,
        locationServicesEnabled: true,
        location: TrackingLocationPermission.precise,
        notifications: TrackingNotificationPermission.granted,
      );
    await openTracking(tester, recorder);

    await tester.tap(find.text('Start outdoor workout'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.text('RECORDING'), findsOneWidget);
    expect(find.text('02:03'), findsOneWidget);
    expect(find.text('1.25'), findsOneWidget);
    expect(find.text('123'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.text('RECORDING'), findsOneWidget);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('Finish workout?'), findsOneWidget);
    await tester.tap(find.text('Finish').last);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(
      recorder.controls,
      <String>['start', 'pause', 'resume', 'stop'],
    );
    expect(find.text('Start outdoor workout'), findsOneWidget);
    expect(find.text('Workout saved on this device'), findsOneWidget);
  });

  testWidgets('discard requires confirmation and removes the active session',
      (WidgetTester tester) async {
    final FakeTrackingRecorder recorder = FakeTrackingRecorder()
      ..permission = const TrackingPermissionSnapshot(
        supported: true,
        locationServicesEnabled: true,
        location: TrackingLocationPermission.precise,
        notifications: TrackingNotificationPermission.granted,
      )
      ..session = TrackingSessionSnapshot(
        status: TrackingSessionStatus.recording,
        sessionId: 'session-1',
        startedAt: DateTime(2026, 9, 7, 6),
      );
    await openTracking(tester, recorder);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard workout?'), findsOneWidget);
    expect(recorder.controls, isEmpty);
    await tester.tap(find.text('Discard').last);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    expect(recorder.controls, <String>['discard']);
    expect(find.text('Start outdoor workout'), findsOneWidget);
  });

  testWidgets('the live poll cannot re-dispatch a command already in flight',
      (WidgetTester tester) async {
    final GatedTrackingRecorder recorder = GatedTrackingRecorder()
      ..permission = const TrackingPermissionSnapshot(
        supported: true,
        locationServicesEnabled: true,
        location: TrackingLocationPermission.precise,
        notifications: TrackingNotificationPermission.granted,
      )
      ..session = TrackingSessionSnapshot(
        status: TrackingSessionStatus.recording,
        sessionId: 'session-1',
        startedAt: DateTime(2026, 9, 7, 6),
      );
    await openTracking(tester, recorder);
    expect(find.text('RECORDING'), findsOneWidget);

    final Completer<void> gate = Completer<void>();
    recorder.gate = gate;

    await tester.tap(find.text('Pause'));
    await tester.pump();

    // Two poll intervals elapse while the service has not answered yet. The
    // controls must stay disabled for the whole window.
    await tester.pump(const Duration(seconds: 2));
    expect(recorder.controls, <String>['pause']);

    final Finder pauseButton = find.widgetWithText(OutlinedButton, 'Pause');
    expect(tester.widget<OutlinedButton>(pauseButton).onPressed, isNull);

    gate.complete();
    recorder.gate = null;
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    expect(recorder.controls, <String>['pause']);
  });

}
