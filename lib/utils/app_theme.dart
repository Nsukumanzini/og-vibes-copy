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
    final glassFill = surface.withValues(alpha: dark ? .74 : .76);
    final glassEdge = Colors.white.withValues(alpha: dark ? .16 : .82);
    final controlEdge = BorderSide(color: glassEdge, width: 1);
    final controlShape = RoundedRectangleBorder(
      borderRadius: AppStyles.controlRadius,
      side: controlEdge,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.vibeBlue,
      brightness: brightness,
      primary: dark ? AppColors.blueLight : AppColors.vibeBlue,
      secondary: AppColors.deepBlue,
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
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: _OgPageTransitionsBuilder(),
          TargetPlatform.iOS: _OgPageTransitionsBuilder(),
          TargetPlatform.macOS: _OgPageTransitionsBuilder(),
          TargetPlatform.windows: _OgPageTransitionsBuilder(),
          TargetPlatform.linux: _OgPageTransitionsBuilder(),
        },
      ),
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
        shadowColor: AppColors.deepBlue.withValues(alpha: dark ? .2 : .1),
        shape: RoundedRectangleBorder(
          borderRadius: AppStyles.bentoRadius,
          side: BorderSide(color: glassEdge, width: 1.2),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(
          color: muted.withValues(alpha: 0.8),
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: muted,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.ogGold, width: 1.6),
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
          backgroundColor: AppColors.vibeBlue.withValues(alpha: .88),
          foregroundColor: AppColors.textOnBrand,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: controlShape,
          side: controlEdge,
          animationDuration: const Duration(milliseconds: 190),
          enableFeedback: true,
          elevation: 1,
          shadowColor: AppColors.deepBlue.withValues(alpha: .2),
          overlayColor: Colors.white.withValues(alpha: .12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.vibeBlue.withValues(alpha: .88),
          foregroundColor: AppColors.textOnBrand,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          elevation: 2,
          shadowColor: AppColors.deepBlue.withValues(alpha: .2),
          side: controlEdge,
          shape: controlShape,
          animationDuration: const Duration(milliseconds: 190),
          enableFeedback: true,
          overlayColor: Colors.white.withValues(alpha: .12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.vibeBlue,
          backgroundColor: glassFill.withValues(alpha: .74),
          minimumSize: const Size(48, 52),
          side: BorderSide(color: border.withValues(alpha: .62)),
          shape: controlShape,
          animationDuration: const Duration(milliseconds: 190),
          enableFeedback: true,
          overlayColor: AppColors.vibeBlue.withValues(alpha: .08),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark ? AppColors.blueLight : AppColors.deepBlue,
          backgroundColor: glassFill.withValues(alpha: .28),
          side: BorderSide(color: glassEdge.withValues(alpha: .6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          animationDuration: const Duration(milliseconds: 190),
          enableFeedback: true,
          overlayColor: AppColors.vibeBlue.withValues(alpha: .08),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.square(48)),
          foregroundColor: WidgetStatePropertyAll(foreground),
          backgroundColor: WidgetStatePropertyAll(
            glassFill.withValues(alpha: .62),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: glassEdge.withValues(alpha: .7)),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          animationDuration: const Duration(milliseconds: 190),
          enableFeedback: true,
          overlayColor: WidgetStatePropertyAll(
            AppColors.vibeBlue.withValues(alpha: .09),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: glassEdge.withValues(alpha: .74)),
        backgroundColor: glassFill,
        selectedColor: AppColors.blueTint.withValues(alpha: .78),
        shape: RoundedRectangleBorder(borderRadius: AppStyles.pillRadius),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: glassFill.withValues(alpha: .9),
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: glassEdge),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: glassFill.withValues(alpha: .94),
        modalBackgroundColor: glassFill.withValues(alpha: .94),
        surfaceTintColor: Colors.transparent,
        elevation: 14,
        modalElevation: 18,
        showDragHandle: true,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          side: BorderSide(color: glassEdge),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: glassFill.withValues(alpha: .94),
        surfaceTintColor: Colors.transparent,
        elevation: 14,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: glassEdge),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.vibeBlue.withValues(alpha: .9),
        foregroundColor: Colors.white,
        elevation: 4,
        focusElevation: 6,
        hoverElevation: 6,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: glassEdge, width: 1.2),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: glassFill.withValues(alpha: .88),
        elevation: 0,
        selectedItemColor: AppColors.vibeBlue,
        unselectedItemColor: muted,
        selectedIconTheme: const IconThemeData(size: 26),
        unselectedIconTheme: const IconThemeData(size: 23),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: glassFill.withValues(alpha: .52),
        collapsedBackgroundColor: glassFill.withValues(alpha: .32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: glassEdge.withValues(alpha: .72)),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: glassEdge.withValues(alpha: .72)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.midnightInk.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: glassEdge.withValues(alpha: .5)),
        ),
        textStyle: const TextStyle(color: Colors.white),
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

class _OgPageTransitionsBuilder extends PageTransitionsBuilder {
  const _OgPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;

    final enterCurve = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    final leaveCurve = secondaryAnimation.drive(
      CurveTween(curve: Curves.easeInCubic),
    );
    final incomingPosition = Tween<Offset>(
      begin: const Offset(.035, 0),
      end: Offset.zero,
    ).animate(enterCurve);
    final outgoingPosition = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-.018, 0),
    ).animate(leaveCurve);
    final outgoingOpacity = Tween<double>(
      begin: 1,
      end: .94,
    ).animate(leaveCurve);

    return SlideTransition(
      position: outgoingPosition,
      child: FadeTransition(
        opacity: outgoingOpacity,
        child: SlideTransition(
          position: incomingPosition,
          child: FadeTransition(opacity: enterCurve, child: child),
        ),
      ),
    );
  }
}
