import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android declares only the required read-only health permissions', () {
    final String manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    const List<String> required = <String>[
      'android.permission.ACTIVITY_RECOGNITION',
      'android.permission.health.READ_STEPS',
      'android.permission.health.READ_ACTIVE_CALORIES_BURNED',
      'android.permission.health.READ_RESTING_HEART_RATE',
      'android.permission.health.READ_OXYGEN_SATURATION',
      'android.permission.health.READ_WEIGHT',
      'android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND',
      'com.google.android.apps.healthdata',
      'androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE',
      'android.intent.action.VIEW_PERMISSION_USAGE',
    ];
    for (final String value in required) {
      expect(manifest, contains(value), reason: 'Missing $value');
    }
    expect(manifest, isNot(contains('android.permission.health.WRITE_')));
    expect(
      manifest,
      isNot(
        contains(
          'android:name="android.permission.ACCESS_BACKGROUND_LOCATION"',
        ),
      ),
    );

    final String activity = File(
      'android/app/src/main/kotlin/com/fitnessapp/fitness_app/MainActivity.kt',
    ).readAsStringSync();
    expect(activity, contains('FlutterFragmentActivity'));
    expect(activity, contains('requestActivityRecognition'));

    final String gradle =
        File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('minSdk = 28'));
  });

  test('iOS enables HealthKit, descriptions, background id and iOS 15', () {
    final String info = File('ios/Runner/Info.plist').readAsStringSync();
    expect(info, contains('NSHealthShareUsageDescription'));
    expect(info, contains('NSHealthUpdateUsageDescription'));
    expect(info, contains('BGTaskSchedulerPermittedIdentifiers'));
    expect(info, contains('com.fitnessapp.health.sync'));

    final String entitlements =
        File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(entitlements, contains('com.apple.developer.healthkit'));

    final String project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(
      'IPHONEOS_DEPLOYMENT_TARGET = 15.0;'.allMatches(project),
      hasLength(3),
    );
    expect(
      'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
          .allMatches(project),
      hasLength(3),
    );
  });
}
