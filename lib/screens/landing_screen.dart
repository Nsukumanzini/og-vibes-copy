import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:og_vibes_student/screens/home_screen.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';

import 'login_screen.dart';
import 'signup_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {
  static const _taglines = <String>[
    'Feeling lonely? Find new friends here.',
    'Find all academic resources in one place.',
    'Study smarter, not harder.',
  ];

  bool _animationsEnabled = false;
  late AnimationController _bounceController;
  Animation<double>? _bounceAnimation;
  late AnimationController _ambientController;
  Timer? _taglineTimer;
  int _taglineIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startLandingAnimations();
    });
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _ambientController.dispose();
    _taglineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          _animationsEnabled
              ? AnimatedBuilder(
                  animation: _ambientController,
                  builder: (context, child) {
                    final t = _ambientController.value;
                    final top = Color.lerp(
                      const Color(0xFFE9F1FF),
                      const Color(0xFFE0F7FA),
                      t,
                    )!;
                    final mid = Color.lerp(
                      const Color(0xFFDDE7FF),
                      const Color(0xFFE3F2FD),
                      1 - t,
                    )!;
                    final bottom = Color.lerp(
                      const Color(0xFFF5F7FA),
                      const Color(0xFFF0F4FF),
                      t,
                    )!;
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [top, mid, bottom],
                        ),
                      ),
                    );
                  },
                )
              : Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFE9F1FF),
                        Color(0xFFE3F2FD),
                        Color(0xFFF5F7FA),
                      ],
                    ),
                  ),
                ),
          _buildFloatingBlobs(),
          _buildSparkles(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeroCard(theme),
                    const SizedBox(height: 28),
                    _buildCtas(context),
                    const SizedBox(height: 16),
                    _buildApplyOnlineCard(theme),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildLogoCircle(),
            const SizedBox(height: 18),
            Text(
              'Welcome to OG Vibes',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0D47A1),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                _taglines[_taglineIndex],
                key: ValueKey(_taglineIndex),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: const [
                _TrustBadge(label: 'Official student platform'),
                _TrustBadge(label: 'Trusted by campuses'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoCircle() {
    final circle = Container(
      height: 110,
      width: 110,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFF2962FF),
          width: 3,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF42A5F5),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset(
            'assets/images/logo.jpeg',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );

    if (!_animationsEnabled || _bounceAnimation == null) {
      return circle;
    }

    return ScaleTransition(
      scale: _bounceAnimation!,
      child: circle,
    );
  }

  Widget _buildCtas(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            icon: const Icon(Icons.login),
            label: const Text('Login'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SignupScreen()));
            },
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Create Account'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final authService = AuthService();
                    await authService.signInAnonymously();
                    if (!mounted) return;
                    navigator.pushReplacement(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  } catch (_) {
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Guest login is not available with Supabase.')),
                    );
                  }
                },
            icon: const Icon(Icons.person_outline),
            label: const Text('Continue as Guest'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingBlobs() {
    if (!_animationsEnabled) {
      return Stack(
        children: [
          Positioned(
            top: -80,
            left: -40,
            child: _blob(const Color(0xFF2962FF), 220),
          ),
          Positioned(
            top: 120,
            right: -60,
            child: _blob(const Color(0xFF00B0FF), 180),
          ),
          Positioned(
            bottom: -60,
            left: 40,
            child: _blob(const Color(0xFF26C6DA), 200),
          ),
        ],
      );
    }

    return AnimatedBuilder(
      animation: _ambientController,
      builder: (context, child) {
        final t = _ambientController.value;
        final offset = 12 * sin(t * pi * 2);
        return Stack(
          children: [
            Positioned(
              top: -80 + offset,
              left: -40,
              child: _blob(const Color(0xFF2962FF), 220),
            ),
            Positioned(
              top: 120 - offset,
              right: -60,
              child: _blob(const Color(0xFF00B0FF), 180),
            ),
            Positioned(
              bottom: -60 + offset,
              left: 40,
              child: _blob(const Color(0xFF26C6DA), 200),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSparkles() {
    if (!_animationsEnabled) {
      return const SizedBox.shrink();
    }

    final points = [
      const Offset(0.85, 0.12),
      const Offset(0.72, 0.22),
      const Offset(0.9, 0.3),
      const Offset(0.15, 0.18),
    ];
    return AnimatedBuilder(
      animation: _ambientController,
      builder: (context, child) {
        final t = _ambientController.value;
        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: points.map((point) {
                final opacity = 0.3 + (0.5 * (0.5 + 0.5 * sin(t * pi * 2)));
                final size = 6 + 4 * (0.5 + 0.5 * cos(t * pi * 2));
                return Positioned(
                  left: constraints.maxWidth * point.dx,
                  top: constraints.maxHeight * point.dy,
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.7),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }

  Widget _blob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.25), Colors.transparent],
        ),
      ),
    );
  }

  void _startLandingAnimations() {
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _bounceAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOutBack),
    );
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    _bounceController.repeat(reverse: true);
    _ambientController.repeat();
    _taglineTimer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (!mounted) return;
      setState(() {
        _taglineIndex = (_taglineIndex + 1) % _taglines.length;
      });
    });
    setState(() {
      _animationsEnabled = true;
    });
  }

  Widget _buildApplyOnlineCard(ThemeData theme) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _openOnlineApplication,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFE3F2FD),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFBBDEFB)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/background.jpeg',
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Apply to study here',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0D47A1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Start your application online.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _openOnlineApplication() async {
    const url =
        'https://ienabler.gscollege.edu.za/pls/prodi41/gen.gw1pkg.gw1view';
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBBDEFB)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0D47A1),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
