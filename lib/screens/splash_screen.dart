import 'dart:async';
import 'dart:math';
import 'dart:ui';


import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_screen.dart';
import 'landing_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _quotes = <String>[
    'Cs get degrees.',
    'Sleep is for the weak.',
    'Coffee > GPA.',
    'Party hard, submit harder.',
    'Due tomorrow? Do tonight.',
  ];
  static const _loadingMessages = <String>[
    'Checking Vibes...',
    'Syncing campus updates...',
    'Warming up the feed...',
    'Packing your study kit...',
    'Almost there...',
  ];

  late final String _quoteOfTheDay;
  bool _navigatedAway = false;
  String _loadingText = 'Checking Vibes...';
  late final AnimationController _logoController;
  late final Animation<double> _logoScale;
  late final AnimationController _logoEntranceController;
  late final Animation<double> _logoEntranceScale;
  late final Animation<double> _logoEntranceOpacity;
  late final AnimationController _underlineController;
  Timer? _loadingTimer;
  bool _showOfflineHint = false;

  @override
  void initState() {
    super.initState();
    _quoteOfTheDay = _quotes[Random().nextInt(_quotes.length)];
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _logoScale = Tween<double>(begin: 0.94, end: 1.04).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );
    _logoEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoEntranceScale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoEntranceController,
        curve: Curves.easeOutBack,
      ),
    );
    _logoEntranceOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoEntranceController, curve: Curves.easeOut),
    );
    _underlineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _logoEntranceController.forward();
    _startLoadingTicker();
    _initApp();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _logoEntranceController.dispose();
    _underlineController.dispose();
    _loadingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D47A1), Color(0xFF448AFF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              FadeTransition(
                opacity: _logoEntranceOpacity,
                child: ScaleTransition(
                  scale: _logoEntranceScale,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: _buildLogoCard(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'OG Vibes',
                style: GoogleFonts.poppins(
                  textStyle: theme.textTheme.headlineLarge,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedBuilder(
                animation: _underlineController,
                builder: (context, child) {
                  final width = 110 + (20 * _underlineController.value);
                  return Container(
                    width: width,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(40),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Modern campus life on tap',
                style: GoogleFonts.poppins(
                  textStyle: theme.textTheme.titleMedium,
                  color: Colors.white70,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      minHeight: 6,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _loadingText,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        textStyle: theme.textTheme.bodyMedium,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    if (_showOfflineHint) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.wifi_off, color: Colors.white70, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Offline mode enabled',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      '"$_quoteOfTheDay"',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        textStyle: theme.textTheme.bodyLarge,
                        color: Colors.white,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initApp() async {
    try {
      var supabaseUrl = dotenv.isInitialized ? dotenv.env['SUPABASE_URL'] : null;
      var supabaseAnonKey = dotenv.isInitialized ? dotenv.env['SUPABASE_ANON_KEY'] : null;
      
      // Fallback: try String.fromEnvironment (set via --dart-define at build time)
      if (supabaseUrl == null || supabaseUrl.isEmpty) {
        supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
      }
      if (supabaseAnonKey == null || supabaseAnonKey.isEmpty) {
        supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
      }
      
      // Log for debugging
      // ignore: avoid_print
      print('Supabase URL: ${supabaseUrl.isNotEmpty == true ? "set" : "NOT SET"}');
      // ignore: avoid_print
      print('Supabase Key: ${supabaseAnonKey.isNotEmpty == true ? "set" : "NOT SET"}');
      
      if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
        throw Exception('Supabase credentials not found. Set SUPABASE_URL and SUPABASE_ANON_KEY.');
      }

      // Supabase should already be initialized in main; guard against double-init.
      final session = Supabase.instance.client.auth.currentSession;
      final user = session?.user;

      if (mounted) {
        setState(() {
          _loadingText = 'Connecting to Supabase...';
        });
      }

      await Future.delayed(const Duration(milliseconds: 900));
      if (user != null) {
        await _navigateTo(const HomeScreen());
      } else {
        await _navigateTo(const LandingScreen());
      }
    } catch (e) {
      // ignore: avoid_print
      print('Init error: $e');
      if (!mounted) return;
      setState(() {
        _loadingText = 'Loading...';
        _showOfflineHint = true;
      });
      await Future.delayed(const Duration(milliseconds: 700));
      await _navigateTo(const LandingScreen());
    }
  }

  String _firstNameFrom(String? displayName) {
    if (displayName == null || displayName.isEmpty) {
      return 'Viber';
    }

    final parts = displayName.split(' ').where((part) => part.isNotEmpty);
    return parts.isNotEmpty ? parts.first : 'Viber';
  }

  Future<void> _navigateTo(Widget destination) async {
    if (!mounted || _navigatedAway) return;
    _navigatedAway = true;
    _loadingTimer?.cancel();
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 800),
        pageBuilder: (_, animation, secondaryAnimation) => destination,
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _startLoadingTicker() {
    var index = 0;
    _loadingTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted || _navigatedAway) return;
      index = (index + 1) % _loadingMessages.length;
      setState(() {
        _loadingText = _loadingMessages[index];
      });
    });
  }

  Widget _buildLogoCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 180,
          width: 180,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Image.asset(
                  'assets/images/logo.jpeg',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
