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

  /// The access token as of the last read from disk.
  ///
  /// May lag: `ApiClient` rotates tokens straight into secure storage
  /// without going through the store. Fine for the emptiness checks below,
  /// but never send this to the server — see [currentRefreshToken].
  String? get accessToken => _accessToken;

  String? _refreshToken;

  /// The cached refresh token, with the same caveat as [accessToken].
  String? get refreshToken => _refreshToken;

  UserModel? _user;
  UserModel? get user => _user;

  bool get isAuthenticated =>
      _status == AuthStatus.authenticated &&
      _accessToken != null &&
      _accessToken!.isNotEmpty;

  /// A token exists on disk, whether or not we can also describe the user.
  ///
  /// Bootstrap needs to tell "signed out" apart from "signed in but we lost
  /// the cached profile": the second still has a working token, and
  /// treating it as the first leaves that token on disk, attached to every
  /// request, while the UI behaves as though nobody is signed in.
  bool get hasSessionToken => _accessToken != null && _accessToken!.isNotEmpty;

  /// The live refresh token, read from storage rather than from the cache.
  ///
  /// Use this for anything the server will act on — revocation above all.
  /// `ApiClient` rotates the pair directly into secure storage, so the
  /// cached copy can be a generation behind, and asking the server to
  /// revoke a superseded token leaves the real session alive.
  Future<String?> currentRefreshToken() async {
    try {
      final String? stored = await _storage.readRefreshToken();
      if (stored != null && stored.isNotEmpty) {
        _refreshToken = stored;
        return stored;
      }
    } catch (_) {
      // Secure storage unavailable — fall back to the in-memory copy.
    }
    return _refreshToken;
  }

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
    final UserModel? cached =
        userJson != null ? UserModel.fromJson(userJson) : null;
    // An id-less record is a corrupt cache, not a user. Treating it as one
    // would show a signed-in shell belonging to nobody; discarding it lets
    // bootstrap re-fetch the profile from the token we still hold.
    _user = (cached != null && cached.id.isNotEmpty) ? cached : null;

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

  /// Completes a session that was recovered at launch: tokens were on disk
  /// but the cached profile was missing or corrupt, and `/auth/me` has just
  /// said who they belong to.
  Future<void> adoptRecoveredUser(UserModel user) async {
    _user = user;
    _status = AuthStatus.authenticated;
    await _storage.setJson(StorageKeys.userJson, user.toJson());
    await _storage.setBool(StorageKeys.isLoggedIn, value: true);
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
