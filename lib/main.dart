import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/incoming_call_screen.dart';
import 'screens/active_call_screen.dart';
import 'services/call_service.dart';
import 'services/push_notification_service.dart';
import 'services/theme_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemePreferences.initialise();

  try {
    final supported = kIsWeb || defaultTargetPlatform == TargetPlatform.android;
    if (supported && (!kIsWeb || DefaultFirebaseOptions.webIsConfigured)) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (error, stackTrace) {
    debugPrint('Firebase initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  // ignore: avoid_print
  print('Loaded web configuration: SUPABASE_URL=${supabaseUrl.isEmpty ? "NOT SET" : "set"}, SUPABASE_ANON_KEY=${supabaseAnonKey.isEmpty ? "NOT SET" : "set"}');

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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final CallService _callService = CallService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<CallNotificationAction>? _callActionSubscription;
  bool _isShowingIncomingCall = false;
  String? _incomingUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _callActionSubscription = PushNotificationService.actions.listen(
      (action) => unawaited(_handleCallNotificationAction(action)),
    );
    if (Firebase.apps.isNotEmpty) {
      unawaited(PushNotificationService.initialise());
    }
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session?.user.id == null) {
        _incomingUserId = null;
        _callService.dispose();
      } else {
        _listenForIncomingCalls();
        if (Firebase.apps.isNotEmpty) {
          unawaited(PushNotificationService.registerCurrentDevice());
        }
      }
    });
    if (Supabase.instance.client.auth.currentUser != null) {
      _listenForIncomingCalls();
      if (Firebase.apps.isNotEmpty) {
        unawaited(PushNotificationService.registerCurrentDevice());
      }
    }
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
    if (_incomingUserId == currentUserId) return;
    _incomingUserId = currentUserId;

    _callService.listenForIncomingCalls(
      currentUserId: currentUserId,
      onIncoming: (call) => unawaited(_showIncomingCall(call)),
    );
    unawaited(_restorePendingCall());
  }

  Future<void> _restorePendingCall() async {
    final pending = await _callService.pendingIncomingCalls();
    if (pending.isNotEmpty) await _showIncomingCall(pending.first);
  }

  Future<void> _handleCallNotificationAction(
    CallNotificationAction action,
  ) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      final call = await Supabase.instance.client
          .from('calls')
          .select()
          .eq('id', action.callId)
          .maybeSingle();
      if (call == null || call['status'] != 'ringing') return;
      if (action.action == 'decline') {
        await _callService.declineCall(action.callId);
        return;
      }
      await _showIncomingCall(
        Map<String, dynamic>.from(call),
        autoAccept: action.action == 'accept',
      );
    } catch (error) {
      debugPrint('Unable to process call notification action: $error');
    }
  }

  Future<void> _showIncomingCall(
    Map<String, dynamic> call, {
    bool autoAccept = false,
  }) async {
    if (_isShowingIncomingCall || call['status'] != 'ringing') return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _isShowingIncomingCall = true;
    var name = 'OG Vibes student';
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('name,surname,nickname')
          .eq('id', call['caller_id'])
          .maybeSingle();
      final nickname = profile?['nickname']?.toString().trim() ?? '';
      final full = [profile?['name'], profile?['surname']]
          .whereType<String>()
          .where((part) => part.trim().isNotEmpty)
          .join(' ');
      name = nickname.isNotEmpty ? nickname : (full.isNotEmpty ? full : name);
    } catch (_) {}
    if (!mounted) {
      _isShowingIncomingCall = false;
      return;
    }
    if (autoAccept) {
      try {
        final session = await _callService.acceptIncomingCall(call);
        await navigator.push(MaterialPageRoute(
          builder: (_) => ActiveCallScreen(
            session: session,
            contactName: name,
          ),
        ));
      } catch (_) {
        final context = _navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to connect this call. Please try again.'),
            ),
          );
        }
      } finally {
        _isShowingIncomingCall = false;
      }
      return;
    }
    navigator.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => IncomingCallScreen(
        contactName: name,
        callType: call['type']?.toString() ?? 'audio',
        onAccept: () async {
          navigator.pop();
          try {
            final session = await _callService.acceptIncomingCall(call);
            await navigator.push(MaterialPageRoute(
              builder: (_) => ActiveCallScreen(
                session: session,
                contactName: name,
              ),
            ));
          } catch (_) {
            final context = _navigatorKey.currentContext;
            if (context != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Unable to connect this call. Please try again.')),
              );
            }
          } finally {
            _isShowingIncomingCall = false;
          }
        },
        onDecline: () async {
          navigator.pop();
          await _callService.declineCall(call['id'].toString());
          _isShowingIncomingCall = false;
        },
      ),
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _callActionSubscription?.cancel();
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

    final darkBase = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.dark,
        primary: const Color(0xFF7FA2FF),
        secondary: accentCyan,
        surface: const Color(0xFF0D1B31),
      ),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemePreferences.mode,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'OG Vibes',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        theme: AppTheme.decorate(themed),
        darkTheme: AppTheme.decorate(darkBase),
        themeMode: themeMode,
        home: const SplashScreen(),
        builder: (context, child) => child ?? const SizedBox(),
      ),
    );
  }
}
