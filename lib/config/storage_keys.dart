/// Keys used by `StorageService` (SharedPreferences + secure storage).
///
/// Namespaced so a future migration can wipe a whole group cleanly.
class StorageKeys {
  const StorageKeys._();

  // --- Secure storage (tokens only) ---
  static const String accessToken = 'auth.access_token';
  static const String refreshToken = 'auth.refresh_token';

  // --- SharedPreferences ---
  static const String userJson = 'auth.user';
  static const String isLoggedIn = 'auth.is_logged_in';

  static const String hasSeenWelcome = 'app.has_seen_welcome';
  static const String themeMode = 'app.theme_mode';
  static const String onboardingDraft = 'onboarding.draft';
  static const String onboardingCompleted = 'onboarding.completed';
  static const String preferredHeightUnit = 'prefs.height_unit';
  static const String preferredWeightUnit = 'prefs.weight_unit';

  /// Everything cleared on logout.
  static const List<String> clearOnLogout = <String>[
    accessToken,
    refreshToken,
    userJson,
    isLoggedIn,
  ];
}
