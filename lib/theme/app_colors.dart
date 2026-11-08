import 'package:flutter/material.dart';

/// Central colour palette for the app.
///
/// Neutral interface surfaces with dedicated colors for feedback and data.
/// Read [AppPalette] for values that adapt to the current appearance.
class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------

  // Fixed fills for older marks and artwork. Controls use palette.accent so
  // their foreground and background invert together in light mode.
  static const Color volt = Colors.white;
  static const Color voltDim = Color(0xFFE0E0E0);
  static const Color voltBright = Colors.white;
  static const Color voltDeep = Color(0xFF121212);
  static const Color onVolt = Color(0xFF121212);

  /// Fixed blue for informational indicators and charts.
  static const Color electric = Color(0xFF4C7DFF);
  static const Color electricDim = Color(0xFF3A63D6);

  /// Energy and streak data.
  static const Color ember = Color(0xFFFF6B2C);
  static const Color emberDim = Color(0xFFFF4D2E);

  // ---------------------------------------------------------------------
  // Feedback
  // ---------------------------------------------------------------------

  static const Color success = Color(0xFF27D986);
  static const Color warning = Color(0xFFFFB020);
  static const Color danger = Color(0xFFFF4D4F);
  static const Color info = electric;
  static const Color darkDanger = Color(0xFFFF7B80);
  static const Color darkInfo = Color(0xFF91B0FF);
  static const Color lightSuccess = Color(0xFF14603B);
  static const Color lightWarning = Color(0xFF795000);
  static const Color lightDanger = Color(0xFFA81E2A);
  static const Color lightInfo = Color(0xFF2D55AE);

  // ---------------------------------------------------------------------
  // Dark neutrals (default experience)
  // ---------------------------------------------------------------------

  static const Color darkBg = Color(0xFF090909);
  static const Color darkSurface = Color(0xFF141414);
  static const Color darkSurfaceAlt = Color(0xFF1B1B1B);
  static const Color darkSurfaceHigh = Color(0xFF252525);
  static const Color darkBorder = Color(0xFF303030);
  static const Color darkBorderStrong = Color(0xFF767676);
  static const Color darkTextPrimary = Color(0xFFFAFAFA);
  static const Color darkTextSecondary = Color(0xFFC2C2C2);
  static const Color darkTextTertiary = Color(0xFFA0A0A0);

  // ---------------------------------------------------------------------
  // Light neutrals
  // ---------------------------------------------------------------------

  static const Color lightBg = Color(0xFFFAFAFA);
  static const Color lightSurface = Colors.white;
  static const Color lightSurfaceAlt = Color(0xFFF2F2F2);
  static const Color lightSurfaceHigh = Color(0xFFE8E8E8);
  static const Color lightBorder = Color(0xFFD9D9D9);
  static const Color lightBorderStrong = Color(0xFF777777);
  static const Color lightTextPrimary = Color(0xFF121212);
  static const Color lightTextSecondary = Color(0xFF454545);
  static const Color lightTextTertiary = Color(0xFF595959);

  // ---------------------------------------------------------------------
  // Gradients
  // ---------------------------------------------------------------------

  static const LinearGradient voltGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[volt, volt],
  );

  static const LinearGradient emberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[ember, emberDim],
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[darkSurface, darkSurface],
  );

  /// Neutral treatment for legacy decorative artwork.
  static const RadialGradient voltGlow = RadialGradient(
    colors: <Color>[Color(0x12FFFFFF), Color(0x00FFFFFF)],
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
    this.success = AppColors.success,
    this.warning = AppColors.warning,
    this.danger = AppColors.darkDanger,
    this.info = AppColors.darkInfo,
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
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

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
    accent: AppColors.lightTextPrimary,
    onAccent: Colors.white,
    cardGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[AppColors.lightSurface, AppColors.lightSurface],
    ),
    success: AppColors.lightSuccess,
    warning: AppColors.lightWarning,
    danger: AppColors.lightDanger,
    info: AppColors.lightInfo,
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
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
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
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
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
      cardGradient: LinearGradient.lerp(cardGradient, other.cardGradient, t) ??
          cardGradient,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}
