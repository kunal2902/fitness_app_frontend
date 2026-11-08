import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_dimens.dart';
import 'app_typography.dart';

export 'app_colors.dart';
export 'app_dimens.dart';
export 'app_typography.dart';

/// Builds the two [ThemeData] objects the app runs on.
///
/// Dark uses a near-black canvas and white actions. Light inverts those
/// roles while keeping the same surface hierarchy and controls.
class AppTheme {
  const AppTheme._();

  static final ThemeData dark = _build(Brightness.dark);
  static final ThemeData light = _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final AppPalette palette = isDark ? AppPalette.dark : AppPalette.light;

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      primaryContainer: palette.surfaceHigh,
      onPrimaryContainer: palette.textPrimary,
      secondary: palette.textTertiary,
      onSecondary: palette.onAccent,
      secondaryContainer: palette.surfaceHigh,
      onSecondaryContainer: palette.textPrimary,
      tertiary: palette.textSecondary,
      onTertiary: palette.onAccent,
      tertiaryContainer: palette.surfaceAlt,
      onTertiaryContainer: palette.textPrimary,
      error: palette.danger,
      onError: isDark ? palette.bg : Colors.white,
      errorContainer: Color.alphaBlend(
        palette.danger.withValues(alpha: 0.12),
        palette.surface,
      ),
      onErrorContainer: palette.danger,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      onSurfaceVariant: palette.textSecondary,
      surfaceContainerLowest: palette.bg,
      surfaceContainerLow: palette.surface,
      surfaceContainer: palette.surfaceAlt,
      surfaceContainerHigh: palette.surfaceHigh,
      surfaceContainerHighest: palette.surfaceHigh,
      inverseSurface: palette.accent,
      onInverseSurface: palette.onAccent,
      inversePrimary: palette.onAccent,
      surfaceTint: Colors.transparent,
      outline: palette.borderStrong,
      outlineVariant: palette.border,
    );

    final TextTheme textTheme = AppTypography.textTheme(
      palette.textPrimary,
      palette.textSecondary,
    );
    const buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.rMd);
    final cardShape = RoundedRectangleBorder(
      borderRadius: AppRadius.rMd,
      side: BorderSide(color: palette.border),
    );
    final modalShape = RoundedRectangleBorder(
      borderRadius: AppRadius.rLg,
      side: BorderSide(color: palette.border),
    );
    final Color barrier = Colors.black.withValues(alpha: isDark ? 0.72 : 0.55);
    final ButtonStyle primaryButton = FilledButton.styleFrom(
      backgroundColor: palette.accent,
      foregroundColor: palette.onAccent,
      disabledBackgroundColor: palette.surfaceHigh,
      disabledForegroundColor: palette.textTertiary,
      minimumSize: const Size(48, AppSize.buttonHeightSm),
      elevation: 0,
      shape: buttonShape,
      textStyle: textTheme.labelLarge,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: AppTypography.fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.surface,
      cardColor: palette.surface,
      splashFactory: InkRipple.splashFactory,
      extensions: <ThemeExtension<dynamic>>[palette],
      appBarTheme: AppBarTheme(
        backgroundColor: palette.bg,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: palette.textPrimary),
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle:
            (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: palette.bg,
          systemNavigationBarDividerColor: palette.border,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      iconTheme:
          IconThemeData(color: palette.textSecondary, size: AppSize.iconMd),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: barrier,
        shape: modalShape,
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        modalBackgroundColor: palette.surface,
        modalBarrierColor: barrier,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
          side: BorderSide(color: palette.border),
        ),
        showDragHandle: true,
        dragHandleColor: palette.borderStrong,
        dragHandleSize: const Size(32, 3),
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(maxWidth: 640),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: cardShape,
        textStyle: textTheme.bodyLarge,
        iconColor: palette.textPrimary,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.textSecondary,
        textColor: palette.textPrimary,
        selectedColor: palette.accent,
        selectedTileColor: palette.surfaceHigh,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rSm),
      ),
      filledButtonTheme: FilledButtonThemeData(style: primaryButton),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: primaryButton.copyWith(
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(48, AppSize.buttonHeight),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          disabledForegroundColor: palette.textTertiary,
          minimumSize: const Size(48, AppSize.buttonHeightSm),
          side: BorderSide(color: palette.borderStrong),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: buttonShape,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceAlt,
        selectedColor: palette.surfaceHigh,
        secondarySelectedColor: palette.surfaceHigh,
        disabledColor: palette.surface,
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium,
        checkmarkColor: palette.accent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        pressElevation: 0,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? palette.accent
                : palette.borderStrong,
          ),
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rSm),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: palette.surfaceAlt,
          foregroundColor: palette.textSecondary,
          selectedBackgroundColor: palette.accent,
          selectedForegroundColor: palette.onAccent,
          disabledBackgroundColor: palette.surfaceHigh,
          disabledForegroundColor: palette.textTertiary,
          side: BorderSide(color: palette.borderStrong),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.rSm),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: palette.textTertiary),
        labelStyle:
            textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
        floatingLabelStyle:
            textTheme.labelMedium?.copyWith(color: palette.accent),
        errorStyle: textTheme.bodySmall?.copyWith(color: palette.danger),
        prefixIconColor: palette.textTertiary,
        suffixIconColor: palette.textTertiary,
        border: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: palette.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: palette.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: palette.accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.rMd,
          borderSide: BorderSide(color: palette.danger, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceHigh,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: palette.textPrimary,
        ),
        actionTextColor: palette.accent,
        behavior: SnackBarBehavior.floating,
        shape: cardShape,
        elevation: 0,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accent,
        inactiveTrackColor: palette.border,
        thumbColor: palette.accent,
        overlayColor: palette.accent.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.border,
        circularTrackColor: palette.border,
      ),
      textTheme: textTheme,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.accent,
        selectionColor: palette.accent.withValues(alpha: 0.25),
        selectionHandleColor: palette.accent,
      ),
    );
  }
}

/// Sugar so widgets can read design tokens without ceremony.
///
/// ```dart
/// Text('Hi', style: context.text.titleLarge);
/// Container(color: context.palette.surface);
/// ```
extension ThemeContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get scheme => Theme.of(this).colorScheme;
  AppPalette get palette =>
      theme.extension<AppPalette>() ??
      (isDark ? AppPalette.dark : AppPalette.light);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
