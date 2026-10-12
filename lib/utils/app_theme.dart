import 'package:flutter/material.dart';

import 'theme_constants.dart';

/// The single source of truth for OG Vibes Material styling.
class AppTheme {
  AppTheme._();

  static const List<String> _fallbacks = <String>[
    'NotoColorEmoji',
    'NotoSansSymbols2',
    'NotoSans',
  ];

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final foreground = dark ? AppColors.textOnDark : AppColors.midnightInk;
    final muted = dark ? AppColors.textMutedDark : AppColors.textMuted;
    final surface = dark ? AppColors.surfaceDark : AppColors.surface;
    final canvas = dark ? AppColors.canvasDark : AppColors.auroraCanvas;
    final border = dark ? AppColors.borderDark : AppColors.glassBorder;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.vibeBlue,
      brightness: brightness,
      primary: dark ? AppColors.blueLight : AppColors.vibeBlue,
      secondary: AppColors.electricCyan,
      tertiary: AppColors.ogGold,
      error: AppColors.danger,
      surface: surface,
      onSurface: foreground,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      fontFamily: 'Poppins',
      fontFamilyFallback: _fallbacks,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    final textTheme = base.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
      fontFamily: 'Poppins',
      fontFamilyFallback: _fallbacks,
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: AppStyles.controlRadius,
      borderSide: BorderSide(color: border),
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          color: foreground,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: AppColors.deepBlue.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: AppStyles.bentoRadius,
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(
          color: muted.withValues(alpha: 0.8),
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: muted,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.vibeBlue, width: 1.6),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: AppStyles.controlRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.vibeBlue,
          foregroundColor: AppColors.textOnBrand,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: AppStyles.controlRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.vibeBlue,
          minimumSize: const Size(48, 52),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: AppStyles.controlRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size.square(48)),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: border),
        backgroundColor: surface,
        selectedColor: AppColors.blueTint,
        shape: RoundedRectangleBorder(borderRadius: AppStyles.pillRadius),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.midnightInk,
        contentTextStyle: const TextStyle(
          color: AppColors.textOnBrand,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppStyles.smallRadius),
        insetPadding: const EdgeInsets.all(16),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.vibeBlue,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
    );
  }
}
