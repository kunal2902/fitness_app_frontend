import 'package:flutter/material.dart' show ChangeNotifier, ThemeMode;

import '../config/storage_keys.dart';
import '../models/auth_models.dart';
import '../models/onboarding_data.dart';
import '../models/user_model.dart';
import '../services/storage_service.dart';

/// Where the app is in its lifecycle, used by the router to decide the
/// landing screen on cold start.
enum AuthStatus { unknown, unauthenticated, authenticated }

/// The app-wide store.
///
/// Holds every entity that more than one screen needs — auth token, refresh
/// token, current user, onboarding draft, first-launch and theme flags —
/// and persists them through [StorageService].
///
/// Read it anywhere with `context.watch<AppStore>()` (rebuilds on change)
/// or `AppStore.instance` (no rebuild, e.g. inside a service call). BLoCs
/// write to it; widgets should mostly read.
class AppStore extends ChangeNotifier {
  AppStore._();

  static final AppStore instance = AppStore._();

  final StorageService _storage = StorageService.instance;

  // -------------------------------------------------------------------------
  // Auth entities
  // -------------------------------------------------------------------------

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  String? _accessToken;
  String? get accessToken => _accessToken;

  String? _refreshToken;
  String? get refreshToken => _refreshToken;

  UserModel? _user;
  UserModel? get user => _user;

  bool get isAuthenticated =>
      _status == AuthStatus.authenticated &&
      _accessToken != null &&
      _accessToken!.isNotEmpty;

  // -------------------------------------------------------------------------
  // Onboarding
  // -------------------------------------------------------------------------

  OnboardingData _onboardingDraft = OnboardingData.initial;
  OnboardingData get onboardingDraft => _onboardingDraft;

  bool _onboardingCompleted = false;
  bool get onboardingCompleted => _onboardingCompleted;

  // -------------------------------------------------------------------------
  // App-level flags
  // -------------------------------------------------------------------------

  bool _hasSeenWelcome = false;
  bool get hasSeenWelcome => _hasSeenWelcome;

  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;

  bool _bootstrapped = false;
  bool get isBootstrapped => _bootstrapped;

  // -------------------------------------------------------------------------
  // Bootstrap
  // -------------------------------------------------------------------------

  /// Rehydrates everything from disk. Called once from `main()` after
  /// `StorageService.init()`.
  Future<void> bootstrap() async {
    _accessToken = await _storage.readAccessToken();
    _refreshToken = await _storage.readRefreshToken();

    final Map<String, dynamic>? userJson =
        _storage.getJson(StorageKeys.userJson);
    _user = userJson != null ? UserModel.fromJson(userJson) : null;

    final Map<String, dynamic>? draft =
        _storage.getJson(StorageKeys.onboardingDraft);
    _onboardingDraft =
        draft != null ? OnboardingData.fromJson(draft) : OnboardingData.initial;

    _onboardingCompleted =
        _storage.getBool(StorageKeys.onboardingCompleted);
    _hasSeenWelcome = _storage.getBool(StorageKeys.hasSeenWelcome);

    final String? mode = _storage.getString(StorageKeys.themeMode);
    _themeMode = switch (mode) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };

    _status = (_accessToken != null && _accessToken!.isNotEmpty && _user != null)
        ? AuthStatus.authenticated
        : AuthStatus.unauthenticated;

    _bootstrapped = true;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Mutations — auth
  // -------------------------------------------------------------------------

  Future<void> setSession(AuthSession session) async {
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    _user = session.user;
    _status = AuthStatus.authenticated;

    await _storage.writeTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    await _storage.setJson(StorageKeys.userJson, session.user.toJson());
    await _storage.setBool(StorageKeys.isLoggedIn, value: true);

    notifyListeners();
  }

  Future<void> updateUser(UserModel user) async {
    _user = user;
    await _storage.setJson(StorageKeys.userJson, user.toJson());
    notifyListeners();
  }

  /// Clears the session but keeps device preferences (theme, welcome seen).
  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    _status = AuthStatus.unauthenticated;
    await _storage.clearSession();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Mutations — onboarding
  // -------------------------------------------------------------------------

  /// Persists the draft after every answer so a killed app resumes exactly
  /// where the user left off.
  Future<void> saveOnboardingDraft(OnboardingData data) async {
    _onboardingDraft = data;
    await _storage.setJson(StorageKeys.onboardingDraft, data.toJson());
    notifyListeners();
  }

  Future<void> markOnboardingCompleted({bool value = true}) async {
    _onboardingCompleted = value;
    await _storage.setBool(StorageKeys.onboardingCompleted, value: value);
    notifyListeners();
  }

  Future<void> clearOnboardingDraft() async {
    _onboardingDraft = OnboardingData.initial;
    await _storage.remove(StorageKeys.onboardingDraft);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Mutations — app flags
  // -------------------------------------------------------------------------

  Future<void> markWelcomeSeen() async {
    if (_hasSeenWelcome) return;
    _hasSeenWelcome = true;
    await _storage.setBool(StorageKeys.hasSeenWelcome, value: true);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _storage.setString(StorageKeys.themeMode, mode.name);
    notifyListeners();
  }
}
