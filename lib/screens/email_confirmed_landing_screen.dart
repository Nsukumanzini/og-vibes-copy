import 'package:flutter/material.dart';
import '../services/offline_data_adapter.dart';

import 'home_screen.dart';
import 'login_screen.dart';

class EmailConfirmedLandingScreen extends StatelessWidget {
  const EmailConfirmedLandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var signedIn = false;
    try {
      signedIn = OfflineData.instance.client.auth.currentSession != null;
    } catch (_) {
      // The confirmation page can still render in an unconfigured preview.
    }
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF07172F), Color(0xFF2457F5), Color(0xFF2457F5)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000A24),
                        blurRadius: 40,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.65, end: 1),
                        duration: const Duration(milliseconds: 850),
                        curve: Curves.elasticOut,
                        builder: (_, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: Container(
                          width: 92,
                          height: 92,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFF19C37D), Color(0xFF2457F5)],
                            ),
                          ),
                          child: const Icon(
                            Icons.verified_rounded,
                            color: Colors.white,
                            size: 54,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Email confirmed',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: const Color(0xFF07172F),
                              fontWeight: FontWeight.w800,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your OG Vibes account is ready. You can safely return to the app and join your campus community.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          height: 1.55,
                          color: Color(0xFF2457F5),
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => signedIn
                                      ? const HomeScreen()
                                      : const LoginScreen(),
                                ),
                                (_) => false,
                              ),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            signedIn ? 'Open OG Vibes' : 'Return to sign in',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
