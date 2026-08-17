import 'package:flutter/material.dart';

/// Type scale for the app.
///
/// To swap in a custom font later (e.g. a bundled Inter / Sora), add it to
/// `pubspec.yaml` under `fonts:` and set [fontFamily] below — every style
/// inherits from it, so nothing else needs to change.
class AppTypography {
  const AppTypography._();

  /// Leave null to use the platform default (SF Pro on iOS, Roboto on
  /// Android). Set to a bundled family name to rebrand in one line.
  static const String? fontFamily = null;

  static TextTheme textTheme(Color primary, Color secondary) {
    return TextTheme(
      // Hero numbers and onboarding headlines.
      displayLarge: TextStyle(
        fontSize: 40,
        height: 1.1,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        color: primary,
      ),
      displayMedium: TextStyle(
        fontSize: 34,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: primary,
      ),
      displaySmall: TextStyle(
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: primary,
      ),

      // Section headers.
      headlineLarge: TextStyle(
        fontSize: 26,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: primary,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: primary,
      ),
      headlineSmall: TextStyle(
        fontSize: 19,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: primary,
      ),

      // Titles inside cards and list rows.
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: primary,
      ),

      // Body copy.
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),

      // Buttons, chips, captions.
      labelLarge: TextStyle(
        fontSize: 16,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: primary,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: secondary,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: secondary,
      ),
    );
  }
}
