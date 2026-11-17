import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'services/accessibility_preferences.dart';
import 'services/safety_ui_state.dart';
import 'services/theme_preferences.dart';
import 'utils/app_theme.dart';
import 'widgets/panic_button.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
  unawaited(_initialiseLocalPreferences());
}

Future<void> _initialiseLocalPreferences() async {
  try {
    await Future.wait([
      ThemePreferences.initialise(),
      AccessibilityPreferences.initialise(),
    ]);
  } catch (error) {
    debugPrint('Local preferences could not be loaded: $error');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemePreferences.mode,
      builder: (context, themeMode, _) => ValueListenableBuilder<bool>(
        valueListenable: AccessibilityPreferences.reduceMotion,
        builder: (context, reduceMotion, _) => MaterialApp(
          navigatorKey: _rootNavigatorKey,
          title: 'OG Vibes',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          home: const SplashScreen(),
          builder: (context, child) {
            final platformMedia = MediaQuery.of(context);
            return MediaQuery(
              data: platformMedia.copyWith(
                disableAnimations:
                    platformMedia.disableAnimations || reduceMotion,
              ),
              child: ValueListenableBuilder<bool>(
                valueListenable: SafetyUiState.showFloatingAction,
                builder: (context, showFloatingAction, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    child ?? const SizedBox.shrink(),
                    if (showFloatingAction)
                      Positioned(
                        right: 14,
                        bottom:
                            (platformMedia.viewInsets.bottom > 0
                                ? platformMedia.viewInsets.bottom
                                : platformMedia.viewPadding.bottom) +
                            94,
                        child: PanicButton(navigatorKey: _rootNavigatorKey),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
