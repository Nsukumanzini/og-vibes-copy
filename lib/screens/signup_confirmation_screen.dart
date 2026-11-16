import 'package:flutter/material.dart';

import 'email_confirmed_landing_screen.dart';
import 'login_screen.dart';

/// Verifies the one-time link on the app's own domain, so Android App Links
/// can open the installed app before a browser consumes the email token.
class SignupConfirmationScreen extends StatefulWidget {
  const SignupConfirmationScreen({super.key, required this.tokenHash});
  final String tokenHash;

  @override
  State<SignupConfirmationScreen> createState() =>
      _SignupConfirmationScreenState();
}

class _SignupConfirmationScreenState extends State<SignupConfirmationScreen> {
  bool _confirmed = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _confirm();
  }

  Future<void> _confirm() async {
    if (mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmed) return const EmailConfirmedLandingScreen();
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm your email')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_failed) const CircularProgressIndicator(),
                if (_failed) const Icon(Icons.link_off_rounded, size: 48),
                const SizedBox(height: 20),
                Text(
                  _failed
                      ? 'This link has expired, was already used, or could not be verified. Try signing in, or request a new confirmation email.'
                      : 'Confirming your OG Vibes email…',
                  textAlign: TextAlign.center,
                ),
                if (_failed) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen(),
                      ),
                      (_) => false,
                    ),
                    child: const Text('Go to sign in'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
