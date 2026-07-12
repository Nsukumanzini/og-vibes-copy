import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/splash_screen.dart';
import 'screens/incoming_call_screen.dart';
import 'services/call_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await _loadDotEnv();

  final supabaseUrl = _getEnvValue('SUPABASE_URL');
  final supabaseAnonKey = _getEnvValue('SUPABASE_ANON_KEY');
  // ignore: avoid_print
  print('Loaded env: SUPABASE_URL=${supabaseUrl.isEmpty ? "NOT SET" : "set"}, SUPABASE_ANON_KEY=${supabaseAnonKey.isEmpty ? "NOT SET" : "set"}, dotenvInitialized=${dotenv.isInitialized}');

  // Initialize Supabase early so screens and services can safely use it.
  try {
    if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      // ignore: avoid_print
      print('✓ Supabase initialized successfully.');
    } else {
      // ignore: avoid_print
      print('⚠ Supabase keys not provided. For web, build with: flutter run -d edge --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...');
    }
  } catch (e, st) {
    // ignore: avoid_print
    print('Supabase initialization failed in main: $e');
    // ignore: avoid_print
    print(st);
  }

  // Global error handling to capture runtime exceptions in web console.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // Print to console so browser DevTools will show the stack trace.
    // ignore: avoid_print
    print('FlutterError: ${details.exceptionAsString()}');
    // ignore: avoid_print
    print(details.stack);
  };

  runApp(const MyApp());
}

String _getEnvValue(String key) {
  if (dotenv.isInitialized) {
    final value = dotenv.env[key];
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return String.fromEnvironment(key);
}

Future<void> _loadDotEnv() async {
  const envPaths = ['assets/env.local'];
  for (final envFile in envPaths) {
    try {
      final envContent = await rootBundle.loadString(envFile);
      // ignore: avoid_print
      print('Loaded $envFile asset content length: ${envContent.length}');
      dotenv.loadFromString(envString: envContent);
      // ignore: avoid_print
      print('Loaded env from asset file: $envFile');
      return;
    } catch (e) {
      // ignore: avoid_print
      print('Could not load asset $envFile: $e');
    }
  }

  const dotenvPaths = ['assets/env.local'];
  for (final envFile in dotenvPaths) {
    try {
      await dotenv.load(fileName: envFile);
      // ignore: avoid_print
      print('Loaded $envFile via flutter_dotenv.');
      return;
    } catch (e) {
      // ignore: avoid_print
      print('Could not load $envFile with flutter_dotenv: $e');
    }
  }

  // ignore: avoid_print
  print('No dotenv file loaded. Using compile-time defines if provided.');
}


class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final CallService _callService = CallService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _isShowingIncomingCall = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForIncomingCalls();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _listenForIncomingCalls();
    }
  }

  void _listenForIncomingCalls() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    _callService.listenForIncomingCalls(
      currentUserId: currentUserId,
      onIncoming: (call) {
        if (_isShowingIncomingCall) return;
        _isShowingIncomingCall = true;
        final navigator = _navigatorKey.currentState;
        if (navigator == null) return;

        navigator.push(
          MaterialPageRoute(
            builder: (_) => IncomingCallScreen(
              contactName: call['caller_id']?.toString() ?? 'Someone',
              callType: call['type']?.toString() ?? 'audio',
              onAccept: () {
                navigator.pop();
                _isShowingIncomingCall = false;
              },
              onDecline: () {
                navigator.pop();
                _isShowingIncomingCall = false;
              },
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // --- SIGNUP SCREEN PALETTE ---
    const primaryBlue = Color(0xFF2962FF); // The "Vibe" Blue
    const accentCyan = Color(0xFF00E5FF); // The Blob/Accent color
    const navyText = Color(0xFF0D47A1); // Headers
    const bgTop = Color(0xFFF5F7FA); // Gradient Start

    const fontFallback = ['NotoColorEmoji', 'NotoSansSymbols2', 'NotoSans'];

    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgTop, // Fallback color
      primaryColor: primaryBlue,

      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentCyan,
        surface: Colors.white,
        onSurface: Colors.black87,
      ),
    );

    // --- TYPOGRAPHY ---
    final textTheme = GoogleFonts.poppinsTextTheme(baseTheme.textTheme)
        .copyWith(
          // Match the Signup Headers
          headlineSmall: GoogleFonts.poppins(
            color: navyText,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: GoogleFonts.poppins(
            color: navyText,
            fontWeight: FontWeight.w600,
          ),
        );

    TextStyle? addFallback(TextStyle? style) {
      return style?.copyWith(fontFamilyFallback: fontFallback);
    }

    final fallbackTextTheme = textTheme.copyWith(
      displayLarge: addFallback(textTheme.displayLarge),
      bodyLarge: addFallback(textTheme.bodyLarge),
      bodyMedium: addFallback(textTheme.bodyMedium),
    );

    final themed = baseTheme.copyWith(
      textTheme: fallbackTextTheme,

      // 1. APP BAR
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(
          color: Colors.grey[800],
        ), // Back buttons are dark grey
        titleTextStyle: GoogleFonts.poppins(
          color: navyText,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),

      // 2. INPUT FIELDS (Match Signup Exactly)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey[50], // The specific off-white from Signup
        contentPadding: const EdgeInsets.symmetric(
          vertical: 20,
          horizontal: 20,
        ),
        labelStyle: TextStyle(color: Colors.grey[600]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none, // Default is clean
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryBlue, width: 1.5),
        ),
        prefixIconColor: Colors.grey[600],
      ),

      // 3. BUTTONS (Rounded & Shadowed)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 8,
          shadowColor: primaryBlue.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),

      // 4. CARDS
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.05), // Very subtle shadow
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );

    return MaterialApp(
      title: 'OG Vibes',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: themed,
      home: const SplashScreen(),
      builder: (context, child) {
        // Error boundary wrapper
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.0)),
          child: child ?? const SizedBox(),
        );
      },
    );
  }
}
