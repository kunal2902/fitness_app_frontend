/// Build flavours. Pass with:
/// `flutter run --dart-define=APP_ENV=staging --dart-define=API_BASE_URL=...`
enum AppEnvironment { dev, staging, prod }

/// Single source of truth for anything environment-dependent.
///
/// Nothing here should ever be read from a widget directly — services take
/// what they need from [AppConfig] at construction time.
class AppConfig {
  const AppConfig._();

  static const String _envName =
      String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static AppEnvironment get environment {
    switch (_envName) {
      case 'prod':
        return AppEnvironment.prod;
      case 'staging':
        return AppEnvironment.staging;
      default:
        return AppEnvironment.dev;
    }
  }

  static bool get isDev => environment == AppEnvironment.dev;
  static bool get isProd => environment == AppEnvironment.prod;

  static const String appName = 'Fitness App';

  /// Base URL of the Node/Express backend.
  ///
  /// Defaults are the local dev server. Note the Android emulator cannot
  /// reach `localhost` — it maps the host machine to `10.0.2.2`. On a
  /// physical device use your machine's LAN IP.
  static const String _definedBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static String get apiBaseUrl {
    if (_definedBaseUrl.isNotEmpty) return _definedBaseUrl;
    switch (environment) {
      case AppEnvironment.prod:
        return 'https://api.fitnessapp.com/api/v1';
      case AppEnvironment.staging:
        return 'https://staging-api.fitnessapp.com/api/v1';
      case AppEnvironment.dev:
        // Android emulator loopback. Use http://localhost:3000 for the
        // iOS simulator, or your machine's LAN IP for a physical device.
        return 'http://10.0.2.2:3000/api/v1';
    }
  }

  /// Origin that serves uploaded files.
  ///
  /// Avatars are served from `/uploads/...`, which sits *outside* the API
  /// prefix, so the prefix has to come off the base URL. The backend stores
  /// a relative path rather than an absolute URL precisely so the same
  /// record works from an emulator, a LAN device and production.
  static String get mediaBaseUrl {
    final String base = apiBaseUrl;
    final int index = base.indexOf('/api/');
    return index == -1 ? base : base.substring(0, index);
  }

  /// Turns whatever the server put in `avatarUrl` into something
  /// [Image.network] can load. Absolute URLs pass through untouched, so a
  /// future move to S3 or a CDN needs no client change.
  static String? resolveMediaUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$mediaBaseUrl${path.startsWith('/') ? '' : '/'}$path';
  }

  /// Socket.IO attaches to the server root, not under the API prefix, so
  /// this is the bare origin.
  static String get socketUrl => mediaBaseUrl;

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 60);

  /// Keep in sync with MAX_AVATAR_BYTES on the backend.
  static const int maxAvatarBytes = 5 * 1024 * 1024;

  /// Downscale before upload — a modern phone camera produces 4–8 MB files
  /// that would be rejected, and an avatar is never rendered above ~200 px.
  static const int avatarMaxDimension = 1024;
  static const int avatarJpegQuality = 88;

  /// Log HTTP traffic. Never on in release.
  static bool get enableNetworkLogs => !isProd;

  // Validation rules shared with the backend — keep the two in sync.
  static const int usernameMinLength = 3;
  static const int usernameMaxLength = 20;
  static const int passwordMinLength = 8;
  static const int passwordMaxLength = 64;
  static const int fullNameMinLength = 2;
  static const int fullNameMaxLength = 60;

  // Physical bounds for the onboarding pickers.
  static const double minHeightCm = 120;
  static const double maxHeightCm = 230;
  static const double defaultHeightCm = 172;

  static const double minWeightKg = 30;
  static const double maxWeightKg = 200;
  static const double defaultWeightKg = 70;

  static const int maxGoalSelections = 3;

  // --- Calls ---

  /// How long we ring before giving up. Must match CALL_RING_TIMEOUT_SECONDS
  /// on the backend, or one side gives up while the other is still ringing.
  static const Duration callRingTimeout = Duration(seconds: 45);

  /// How long to keep trying to re-establish media before ending the call.
  static const Duration callReconnectGrace = Duration(seconds: 20);

  /// How long the "Connecting…" phase may last before the call is failed.
  ///
  /// Nothing else bounds it: a peer connection that never receives an
  /// offer stays in `new` forever and never reports `failed`, so without
  /// this the callee waits with the camera on until they give up.
  /// Generous — ICE on a bad cellular link genuinely can take 15s.
  static const Duration callConnectTimeout = Duration(seconds: 40);

  /// Typing indicators expire locally too — a stale "typing…" left behind
  /// by a dropped socket is worse than a missed one.
  static const Duration typingIndicatorTimeout = Duration(seconds: 4);
  static const Duration typingThrottle = Duration(milliseconds: 1500);

  static const int chatPageSize = 30;
}
