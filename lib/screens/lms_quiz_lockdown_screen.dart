import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:og_vibes_student/screens/quiz_screen.dart' show QuizRunnerScreen;

class LmsQuizLockdownScreen extends StatefulWidget {
  final Map<String, dynamic>? quiz;
  const LmsQuizLockdownScreen({super.key, this.quiz});

  @override
  State<LmsQuizLockdownScreen> createState() => _LmsQuizLockdownScreenState();
}

class _LmsQuizLockdownScreenState extends State<LmsQuizLockdownScreen> with WidgetsBindingObserver {
  bool _violationDetected = false;
  bool _quizStarted = false;

  static const Color _navy = Color(0xFF0A192F);
  static const Color _slate = Color(0xFF5B677A);
  static const Color _white = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Prefer immersive fullscreen to remove easy access to system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // likely the user attempted to switch apps or lock the device
      _showViolationModal();
    }
  }

  Future<void> _showViolationModal() async {
    if (!mounted) return;
    setState(() => _violationDetected = true);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Violation',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF7F1D1D),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Icon(
                    Icons.gpp_bad_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Violation Detected',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'You have left the exam environment. This incident has been logged and reported to the lecturer.',
                    style: TextStyle(
                      color: Color(0xFFFEE2E2),
                      fontSize: 17,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // on violation we just present message; quiz should be considered compromised in server logic
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF7F1D1D),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Return To Quiz',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _startQuiz() async {
    setState(() => _quizStarted = true);
    // Launch the secure quiz runner; keep lockdown screen underneath.
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuizRunnerScreen(quiz: widget.quiz ?? {})));
    // when quiz finishes, restore UI mode
    if (!mounted) return;
    setState(() => _quizStarted = false);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_quizStarted, // prevent back during quiz
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: _white,
          elevation: 0,
          title: const Text(
            'Secure Assessment Environment',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B0000),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '🔒 SECURE LOCKDOWN MODE ACTIVE. Do not switch apps.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD7DEE8)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120A192F),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.quiz?['title'] ?? 'Secure Quiz',
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('By ${widget.quiz?['lecturer'] ?? 'Lecturer'}', style: const TextStyle(color: _slate)),
                    const SizedBox(height: 18),
                    Text(widget.quiz?['description'] ?? 'This quiz will run in a secured environment.'),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Icon(Icons.timer_outlined, size: 18),
                      const SizedBox(width: 8),
                      const Text('Timed and proctored'),
                    ]),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _violationDetected ? null : _startQuiz,
                          child: const Text('Start Secure Quiz'),
                        ),
                      ),
                    ])
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.value,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCE3EE)),
      ),
      child: RadioListTile<int>(
        title: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF0A192F),
            fontWeight: FontWeight.w600,
          ),
        ),
        value: value,
        groupValue: selected,
        activeColor: const Color(0xFF0A192F),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        onChanged: onChanged,
      ),
    );
  }
}
