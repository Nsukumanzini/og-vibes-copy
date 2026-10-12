import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme_constants.dart';

/// Shared presentation layer for the OG Vibes "Aurora Glass" redesign.
///
/// It deliberately contains no navigation, data access, authentication or
/// feature logic.
class AppTheme {
  AppTheme._();

  static ThemeData decorate(ThemeData base) {
    final isDark = base.brightness == Brightness.dark;
    final foreground =
        isDark ? const Color(0xFFF4F7FF) : AppColors.midnightInk;
    final muted = isDark ? const Color(0xFFAAB7CD) : AppColors.textMuted;
    final surface = isDark ? const Color(0xFF172944) : Colors.white;
    final glassFill = isDark
        ? const Color(0xE61A2C49)
        : Colors.white.withValues(alpha: 0.78);
    final glassBorder =
        isDark ? const Color(0xFF304663) : AppColors.glassBorder;
    final OutlineInputBorder fieldBorder = OutlineInputBorder(
      borderRadius: AppStyles.controlRadius,
      borderSide: BorderSide(color: glassBorder),
    );

    return base.copyWith(
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF071323) : AppColors.auroraCanvas,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.vibeBlue,
        secondary: AppColors.electricCyan,
        tertiary: AppColors.ogGold,
        error: AppColors.danger,
        surface: surface,
        onSurface: foreground,
      ),
      textTheme: base.textTheme.copyWith(
        headlineSmall: GoogleFonts.poppins(
          color: foreground,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        titleLarge: GoogleFonts.poppins(
          color: foreground,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
        ),
        titleMedium: GoogleFonts.poppins(
          color: foreground,
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
        titleTextStyle: GoogleFonts.poppins(
          color: foreground,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: glassFill,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: AppColors.deepBlue.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: AppStyles.bentoRadius,
          side: BorderSide(color: glassBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        labelStyle: TextStyle(
          color: muted,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(
          color: muted.withValues(alpha: 0.74),
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: muted,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide:
              const BorderSide(color: AppColors.vibeBlue, width: 1.6),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.vibeBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              AppColors.vibeBlue.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: AppStyles.controlRadius,
          ),
          textStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.vibeBlue,
          minimumSize: const Size(0, 52),
          side: const BorderSide(color: AppColors.glassBorder),
          shape: RoundedRectangleBorder(
            borderRadius: AppStyles.controlRadius,
          ),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.midnightInk,
        contentTextStyle: GoogleFonts.poppins(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.all(16),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: glassBorder),
        backgroundColor: glassFill,
        selectedColor: AppColors.vibeBlue,
        shape: RoundedRectangleBorder(borderRadius: AppStyles.pillRadius),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.vibeBlue),
      dividerTheme: DividerThemeData(
        color: glassBorder,
        thickness: 1,
      ),
    );
  }
}
