plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")

    // Uncomment once android/app/google-services.json exists. Applying this
    // plugin WITHOUT that file fails the build outright, so it stays off
    // until Firebase is actually set up — see, in the backend repo,
    // docs/REALTIME_SETUP.md.
    // Background call ringing is the only thing that does not work until
    // then; everything else, including in-app calls, works without Firebase.
    // id("com.google.gms.google-services")
}

android {
    namespace = "com.fitnessapp.fitness_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.fitnessapp.fitness_app"

        // Health Connect is supported from Android 9 and health 13.x itself
        // requires API 26. API 28 keeps the declared app floor aligned with
        // the tracking module's actual availability contract.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // flutter_webrtc ships prebuilt .so files for the WebRTC native stack.
    // Without this, `flutter build apk` produces a single fat APK that is
    // ~40MB heavier than it needs to be on any given device.
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

flutter {
    source = "../.."
}
