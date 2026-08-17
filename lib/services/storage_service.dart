import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/storage_keys.dart';

/// Thin, typed wrapper over local persistence.
///
/// Two backends on purpose:
///  * **SharedPreferences** — non-sensitive state (draft answers, flags,
///    cached user JSON). Fast, synchronous reads after init.
///  * **FlutterSecureStorage** — auth tokens only (Keychain / EncryptedSharedPrefs).
///
/// Call [init] once during app bootstrap before anything reads from it.
class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  late final SharedPreferences _prefs;
  bool _ready = false;

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<void> init() async {
    if (_ready) return;
    _prefs = await SharedPreferences.getInstance();
    _ready = true;
  }

  bool get isReady => _ready;

  // -------------------------------------------------------------------------
  // Secure — tokens
  // -------------------------------------------------------------------------

  Future<String?> readAccessToken() =>
      _secure.read(key: StorageKeys.accessToken);

  Future<String?> readRefreshToken() =>
      _secure.read(key: StorageKeys.refreshToken);

  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secure.write(key: StorageKeys.accessToken, value: accessToken);
    await _secure.write(key: StorageKeys.refreshToken, value: refreshToken);
  }

  Future<void> writeAccessToken(String accessToken) =>
      _secure.write(key: StorageKeys.accessToken, value: accessToken);

  Future<void> clearTokens() async {
    await _secure.delete(key: StorageKeys.accessToken);
    await _secure.delete(key: StorageKeys.refreshToken);
  }

  // -------------------------------------------------------------------------
  // Preferences — primitives
  // -------------------------------------------------------------------------

  String? getString(String key) => _ready ? _prefs.getString(key) : null;

  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);

  bool getBool(String key, {bool fallback = false}) =>
      _ready ? (_prefs.getBool(key) ?? fallback) : fallback;

  Future<bool> setBool(String key, {required bool value}) =>
      _prefs.setBool(key, value);

  Future<bool> remove(String key) => _prefs.remove(key);

  // -------------------------------------------------------------------------
  // Preferences — JSON helpers
  // -------------------------------------------------------------------------

  Map<String, dynamic>? getJson(String key) {
    final String? raw = getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      // Corrupt entry — drop it rather than crash on next launch.
      _prefs.remove(key);
      return null;
    }
  }

  Future<bool> setJson(String key, Map<String, dynamic> value) =>
      setString(key, jsonEncode(value));

  // -------------------------------------------------------------------------
  // Bulk
  // -------------------------------------------------------------------------

  /// Wipes session state but keeps device-level preferences such as the
  /// chosen theme and the "has seen welcome" flag.
  Future<void> clearSession() async {
    await clearTokens();
    for (final String key in StorageKeys.clearOnLogout) {
      await _prefs.remove(key);
    }
  }

  Future<void> clearAll() async {
    await clearTokens();
    await _prefs.clear();
  }
}
