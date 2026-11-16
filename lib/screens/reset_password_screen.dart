import 'package:flutter/material.dart';

import '../utils/theme_constants.dart';
import 'home_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  bool _hidden = true;

  @override
  void dispose() { _password.dispose(); _confirm.dispose(); super.dispose(); }

  Future<void> _save() async {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create a new password')),
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(width: 64, height: 64, decoration: BoxDecoration(gradient: AppStyles.brandGradient, borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 34)),
        const SizedBox(height: 20), const Text('Secure your account', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8), const Text('Choose a strong password you have not used elsewhere.'), const SizedBox(height: 24),
        TextField(controller: _password, obscureText: _hidden, decoration: InputDecoration(labelText: 'New password', prefixIcon: const Icon(Icons.lock_outline_rounded), suffixIcon: IconButton(onPressed: () => setState(() => _hidden = !_hidden), icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
        const SizedBox(height: 14), TextField(controller: _confirm, obscureText: _hidden, onSubmitted: (_) => _save(), decoration: const InputDecoration(labelText: 'Confirm new password', prefixIcon: Icon(Icons.verified_user_outlined))),
        const SizedBox(height: 22), FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.shield_rounded), label: const Text('Update password')),
      ]))),
    )))),
  );
}
