import 'package:flutter/material.dart';

/// Centralized color palette for the OG Vibes / OG Scholar Enterprise app.
/// Covers both the consumer "OG Vibes" brand and the enterprise LMS "OG Scholar" theme.
class AppColors {
  AppColors._(); // Prevent instantiation.

  // ── Primary Brand ──────────────────────────────────────────────────────────

  /// Deep Blue – main brand primary.
  static const Color deepBlue = Color(0xFF0D47A1);
  static const Color vibeBlue = Color(0xFF2457F5);
  static const Color electricCyan = Color(0xFF7FA2FF);
  static const Color midnightInk = Color(0xFF07172F);
  static const Color blueLight = Color(0xFF7FA2FF);
  static const Color blueTint = Color(0xFFE8F0FF);
  static const Color cyanTint = Color(0xFFE8F0FF);
  static const Color goldTint = Color(0xFFFFF6D6);

  /// OG Gold / Accent Yellow – secondary brand accent.
  static const Color ogGold = Color(0xFFFFC107);

  // ── Enterprise LMS Palette ─────────────────────────────────────────────────

  /// Navy Blue – the dark surface used across the LMS shell.
  static const Color navyBlue = Color(0xFF0A192F);

  /// Slate Grey – muted text and secondary labels in the LMS.
  static const Color slateGrey = Color(0xFF8892B0);

  /// Crisp White – high-contrast text and icon colour on dark surfaces.
  static const Color crispWhite = Color(0xFFFFFFFF);

  // ── Backgrounds ────────────────────────────────────────────────────────────

  /// Off-White – page background for light / consumer mode.
  static const Color backgroundLight = Color(0xFFF5F7FA);
  static const Color auroraCanvas = Color(0xFFF3F7FF);
  static const Color glassBorder = Color(0xFFDCE7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF7F9FD);
  static const Color canvasDark = Color(0xFF071323);
  static const Color surfaceDark = Color(0xFF172944);
  static const Color borderDark = Color(0xFF304663);
  static const Color textOnDark = Color(0xFFF4F7FF);
  static const Color textMutedDark = Color(0xFFAAB7CD);
  static const Color textOnBrand = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFF66758F);
  static const Color success = Color(0xFF159A6B);
  static const Color warning = Color(0xFFE2A500);
  static const Color danger = Color(0xFFD83A52);
  static const Color academicIndigo = Color(0xFF2457F5);
  static const Color academicViolet = Color(0xFF2457F5);
  static const Color academicMagenta = Color(0xFF2457F5);
  static const Color academicOrange = Color(0xFFFFC107);
  static const Color academicEmerald = Color(0xFF2457F5);
  static const Color academicTeal = Color(0xFF2457F5);

  // ── Semantic application tokens ───────────────────────────────────────────
  // Prefer these names in screens. Brand aliases above remain available for
  // artwork and identity-specific surfaces.
  static const Color primary = vibeBlue;
  static const Color primaryStrong = deepBlue;
  static const Color primaryAction = Color(0xFF2962FF);
  static const Color academicAccent = electricCyan;
  static const Color accent = ogGold;
  static const Color info = Color(0xFF00A6C7);
  static const Color canvas = auroraCanvas;
  static const Color surfaceElevated = surface;
  static const Color surfaceSoft = Color(0xFFF8FAFF);
  static const Color surfaceBlue = Color(0xFFE3F2FD);
  static const Color onSurface = midnightInk;
  static const Color onSurfaceMuted = textMuted;
  static const Color outline = glassBorder;
  static const Color successSurface = Color(0xFFE8F7F1);
  static const Color warningSurface = Color(0xFFFFF7DC);
  static const Color dangerSurface = Color(0xFFFFECEF);
  static const Color dangerLight = Color(0xFFF45B69);
  static const Color successLight = Color(0xFF42C997);
  static const Color warningText = Color(0xFF775700);
  static const Color neutralMuted = Color(0xFFB7C2D4);
  static const Color surfaceDarkAlt = Color(0xFF263B59);
  static const Color overlayDark = Color(0xF2071323);

  /// Deep Dark – page background for the enterprise LMS dark mode.
  static const Color backgroundDark = Color(0xFF020C1B);
}

/// Centralized style tokens for the Bento Box / Glassmorphism design system.
class AppStyles {
  AppStyles._(); // Prevent instantiation.

  // ── Shape ──────────────────────────────────────────────────────────────────

  /// Standard corner radius applied to all Bento Card surfaces.
  static final BorderRadius bentoRadius = BorderRadius.circular(24.0);
  static final BorderRadius controlRadius = BorderRadius.circular(18.0);
  static final BorderRadius pillRadius = BorderRadius.circular(999.0);
  static final BorderRadius smallRadius = BorderRadius.circular(16.0);

  static const double touchTarget = 48;
  static const double listBlur = 0;
  static const double heroBlur = 10;

  // ── Elevation / Shadow ─────────────────────────────────────────────────────

  /// Subtle soft shadow that lifts Bento Cards off the background without
  /// feeling heavy – 5 % black opacity, 15 px blur, shifted 8 px downward.
  static final List<BoxShadow> softShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 15.0,
      offset: const Offset(0, 8),
    ),
  ];

  static final List<BoxShadow> glassShadow = [
    BoxShadow(
      color: AppColors.deepBlue.withValues(alpha: 0.08),
      blurRadius: 32,
      offset: const Offset(0, 14),
    ),
  ];

  static const LinearGradient brandGradient = LinearGradient(
    colors: [AppColors.midnightInk, AppColors.vibeBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient auroraGradient = LinearGradient(
    colors: [Color(0xFFF8FAFF), AppColors.auroraCanvas, Color(0xFFF3F7FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Compatibility name retained for existing screens; all entries use the brand palette.
  static const List<LinearGradient> academicRainbowGradients = <LinearGradient>[
    LinearGradient(colors: <Color>[AppColors.deepBlue, AppColors.vibeBlue]),
    LinearGradient(colors: <Color>[AppColors.vibeBlue, AppColors.blueLight]),
    LinearGradient(colors: <Color>[AppColors.midnightInk, AppColors.deepBlue]),
    LinearGradient(colors: <Color>[AppColors.deepBlue, AppColors.vibeBlue]),
    LinearGradient(colors: <Color>[AppColors.vibeBlue, AppColors.blueLight]),
    LinearGradient(colors: <Color>[AppColors.ogGold, AppColors.goldTint]),
    LinearGradient(colors: <Color>[AppColors.deepBlue, AppColors.vibeBlue]),
    LinearGradient(colors: <Color>[AppColors.vibeBlue, AppColors.blueLight]),
    LinearGradient(colors: <Color>[AppColors.midnightInk, AppColors.deepBlue]),
  ];
}
