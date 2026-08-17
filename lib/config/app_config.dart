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

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);

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
}
