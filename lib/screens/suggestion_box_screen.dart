import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import '../services/offline_data_adapter.dart';

class SuggestionBoxScreen extends StatefulWidget {
  const SuggestionBoxScreen({super.key});

  @override
  State<SuggestionBoxScreen> createState() => _SuggestionBoxScreenState();
}

class _SuggestionBoxScreenState extends State<SuggestionBoxScreen> {
  final TextEditingController _ideaController = TextEditingController();
  bool _sending = false;
  late final ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _ideaController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Suggestion Box',
          style: TextStyle(color: AppColors.midnightInk),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.midnightInk),
      ),
      extendBodyBehindAppBar: false,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.surface, AppColors.auroraCanvas, AppColors.blueTint],
          ),
        ),
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  TextField(
                    controller: _ideaController,
                    minLines: 8,
                    maxLines: 16,
                    style: const TextStyle(color: AppColors.midnightInk),
                    cursorColor: AppColors.midnightInk,
                    decoration: InputDecoration(
                      labelText: 'Share your campus-changing idea...',
                      labelStyle: const TextStyle(color: AppColors.textMuted),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white30),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.midnightInk),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.vibeBlue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: _sending ? null : _sendIdea,
                      child: Text(
                        _sending ? 'Sending…' : 'Send suggestion',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.midnightInk,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 25,
              maxBlastForce: 20,
              minBlastForce: 5,
              gravity: 0.3,
              emissionFrequency: 0.05,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendIdea() async {
    if (_sending) return;
    final idea = _ideaController.text.trim();
    if (idea.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe your idea first.')),
      );
      return;
    }
    final user = OfflineData.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to send your idea.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await OfflineData.instance.client.from('suggestion_submissions').insert({
        'user_id': user.id,
        'category': 'product_idea',
        'message': idea,
      });
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context)) _confettiController.play();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks! Your idea has been saved.')),
      );
      _ideaController.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not send your suggestion. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
