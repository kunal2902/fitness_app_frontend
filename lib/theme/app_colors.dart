import 'package:flutter/material.dart';

/// Central colour palette for the app.
///
/// The palette is dark-first (the product is an athletic / performance app,
/// which reads best on a near-black canvas) but every semantic token has a
/// light counterpart so `AppTheme.light` stays fully usable.
///
/// Never hard-code a hex value in a widget — add a semantic token here.
class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------

  /// Primary brand accent — "volt". High-energy, reads as athletic.
  /// Always pair with [onVolt] for text sitting on top of it.
  static const Color volt = Color(0xFFC6FF3D);
  static const Color voltDim = Color(0xFFA6DC22);
  static const Color voltBright = Color(0xFFDFFF6B);

  /// Volt is too light for text on a white background — use this instead.
  static const Color voltDeep = Color(0xFF6E9B0A);

  /// Text/icon colour that sits on top of [volt].
  static const Color onVolt = Color(0xFF0A0F03);

  /// Secondary accent — used for links, informational states, charts.
  static const Color electric = Color(0xFF4C7DFF);
  static const Color electricDim = Color(0xFF3A63D6);

  /// Warm accent — streaks, energy, "personal best" moments.
  static const Color ember = Color(0xFFFF6B2C);
  static const Color emberDim = Color(0xFFFF4D2E);

  // ---------------------------------------------------------------------
  // Feedback
  // ---------------------------------------------------------------------

  static const Color success = Color(0xFF27D986);
  static const Color warning = Color(0xFFFFB020);
  static const Color danger = Color(0xFFFF4D4F);
  static const Color info = electric;

  // ---------------------------------------------------------------------
  // Dark neutrals (default experience)
  // ---------------------------------------------------------------------

  static const Color darkBg = Color(0xFF07090D);
  static const Color darkSurface = Color(0xFF10141C);
  static const Color darkSurfaceAlt = Color(0xFF171C26);
  static const Color darkSurfaceHigh = Color(0xFF1F2632);
  static const Color darkBorder = Color(0xFF2A3140);
  static const Color darkBorderStrong = Color(0xFF3A4353);
  static const Color darkTextPrimary = Color(0xFFF4F7FB);
  static const Color darkTextSecondary = Color(0xFF9AA4B8);
  static const Color darkTextTertiary = Color(0xFF6B7488);

  // ---------------------------------------------------------------------
  // Light neutrals
  // ---------------------------------------------------------------------

  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFF6F8FB);
  static const Color lightSurfaceAlt = Color(0xFFEEF2F7);
  static const Color lightSurfaceHigh = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightBorderStrong = Color(0xFFCBD5E1);
  static const Color lightTextPrimary = Color(0xFF0B1220);
  static const Color lightTextSecondary = Color(0xFF5A6478);
  static const Color lightTextTertiary = Color(0xFF8A94A6);

  // ---------------------------------------------------------------------
  // Gradients
  // ---------------------------------------------------------------------

  static const LinearGradient voltGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[voltBright, voltDim],
  );

  static const LinearGradient emberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[ember, emberDim],
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[darkSurfaceHigh, darkSurface],
  );

  /// Soft glow placed behind hero elements on onboarding screens.
  static const RadialGradient voltGlow = RadialGradient(
    colors: <Color>[Color(0x33C6FF3D), Color(0x00C6FF3D)],
  );
}

/// Palette resolved for the current [Brightness].
///
/// Attach with `Theme.of(context).extension<AppPalette>()!` or the
/// `context.palette` helper in `app_theme.dart`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceHigh,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.cardGradient,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceHigh;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color onAccent;
  final LinearGradient cardGradient;

  static const AppPalette dark = AppPalette(
    bg: AppColors.darkBg,
    surface: AppColors.darkSurface,
    surfaceAlt: AppColors.darkSurfaceAlt,
    surfaceHigh: AppColors.darkSurfaceHigh,
    border: AppColors.darkBorder,
    borderStrong: AppColors.darkBorderStrong,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textTertiary: AppColors.darkTextTertiary,
    accent: AppColors.volt,
    onAccent: AppColors.onVolt,
    cardGradient: AppColors.darkCardGradient,
  );

  static const AppPalette light = AppPalette(
    bg: AppColors.lightBg,
    surface: AppColors.lightSurface,
    surfaceAlt: AppColors.lightSurfaceAlt,
    surfaceHigh: AppColors.lightSurfaceHigh,
    border: AppColors.lightBorder,
    borderStrong: AppColors.lightBorderStrong,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textTertiary: AppColors.lightTextTertiary,
    accent: AppColors.voltDeep,
    onAccent: Colors.white,
    cardGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[AppColors.lightSurfaceHigh, AppColors.lightSurface],
    ),
  );

  @override
  AppPalette copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceHigh,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? onAccent,
    LinearGradient? cardGradient,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      cardGradient: cardGradient ?? this.cardGradient,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      cardGradient:
          LinearGradient.lerp(cardGradient, other.cardGradient, t) ??
              cardGradient,
    );
  }
}
