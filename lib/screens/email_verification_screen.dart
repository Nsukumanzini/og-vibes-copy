import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/vibe_scaffold.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.email,
    this.profileImageBytes,
  });

  final String email;
  final Uint8List? profileImageBytes;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  late final ConfettiController _confettiController;
  Timer? _cooldownTimer;
  bool _isSending = false;
  bool _isVerifying = false;
  bool _verificationComplete = false;
  int _cooldownSeconds = 60;
  int _resendAttempts = 0;
  String? _errorMessage;

  static const int _resendLimit = 3;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(milliseconds: 1800),
    );
    _startCooldown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _confettiController.dispose();
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    if (_isVerifying || _verificationComplete) return;
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Enter the complete six-digit code.');
      _codeFocusNode.requestFocus();
      return;
    }

    setState(() {
      _errorMessage = 'Email verification is unavailable.';
      _codeController.clear();
      _codeFocusNode.requestFocus();
    });
  }

  Future<void> _resendVerificationCode() async {
    if (_isSending || _cooldownSeconds > 0) return;
    if (_resendAttempts >= _resendLimit) {
      setState(() {
        _errorMessage =
            'You have reached the resend limit. Please try again later.';
      });
      return;
    }

    setState(() {
      _isSending = false;
      _errorMessage = 'Email verification is unavailable.';
    });
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds -= 1);
      }
    });
  }

  Future<void> _cancel() async {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return VibeScaffold(
      body: Stack(
        alignment: Alignment.topCenter,
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: AnimatedSwitcher(
                    duration: MediaQuery.of(context).disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 450),
                    child: _verificationComplete
                        ? _buildWelcome(theme)
                        : _buildCodeEntry(theme),
                  ),
                ),
              ),
            ),
          ),
          ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.05,
            numberOfParticles: 28,
            gravity: 0.22,
            colors: const [
              Color(0xFFFFD740),
              Color(0xFF00D4FF),
              Color(0xFF7C4DFF),
              Colors.white,
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCodeEntry(ThemeData theme) {
    return Container(
      key: const ValueKey('email-code-entry'),
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000A24),
            blurRadius: 36,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFFFD740), Color(0xFFFFA000)],
              ),
            ),
            child: const Icon(
              Icons.password_rounded,
              size: 44,
              color: Color(0xFF071A3A),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Verify your email',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Enter the six-digit code sent to\n${widget.email}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, height: 1.5),
          ),
          const SizedBox(height: 8),
          const Text(
            'The code expires for your security. If you request another code, only the newest one will work. Check your spam folder if it is not in your inbox.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          const SizedBox(height: 24),
          Semantics(
            label: 'Six-digit email verification code',
            textField: true,
            child: TextField(
              controller: _codeController,
              focusNode: _codeFocusNode,
              enabled: !_isVerifying,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.oneTimeCode],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 10,
                color: Color(0xFF071A3A),
              ),
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _verifyCode(),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
              decoration: InputDecoration(
                counterText: '',
                hintText: '000000',
                hintStyle: TextStyle(
                  color: const Color(0xFF071A3A).withValues(alpha: 0.24),
                  letterSpacing: 10,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.96),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                errorText: _errorMessage,
                errorMaxLines: 3,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isVerifying ? null : _verifyCode,
              icon: _isVerifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_rounded),
              label: Text(
                _isVerifying ? 'Verifying securely…' : 'Verify and continue',
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _isSending || _cooldownSeconds > 0
                ? null
                : _resendVerificationCode,
            child: Text(
              _isSending
                  ? 'Sending…'
                  : _cooldownSeconds > 0
                  ? 'Send a new code in ${_cooldownSeconds}s'
                  : 'Didn’t receive it? Send a new code',
            ),
          ),
          TextButton(
            onPressed: _isVerifying ? null : _cancel,
            child: const Text('Use a different email'),
          ),
          const SizedBox(height: 4),
          const Text(
            'Need help? Info@ogtechnologies.co.za',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome(ThemeData theme) {
    return Container(
      key: const ValueKey('welcome'),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 80,
            color: Color(0xFF1769E0),
          ),
          const SizedBox(height: 18),
          Text(
            'Welcome to OG Vibes!',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: const Color(0xFF071A3A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your email is verified. We’re opening your campus feed now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF53627A), height: 1.5),
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }
}
