import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:og_vibes_student/screens/quiz_screen.dart'
    show QuizRunnerScreen;
import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class LmsQuizLockdownScreen extends StatefulWidget {
  const LmsQuizLockdownScreen({super.key, this.quiz});

  final Map<String, dynamic>? quiz;

  @override
  State<LmsQuizLockdownScreen> createState() =>
      _LmsQuizLockdownScreenState();
}

class _LmsQuizLockdownScreenState extends State<LmsQuizLockdownScreen> {
  bool _starting = false;

  Map<String, dynamic> get _quiz => widget.quiz ?? <String, dynamic>{};

  Future<void> _startQuiz() async {
    if (_starting) return;
    HapticFeedback.mediumImpact();
    setState(() => _starting = true);
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => QuizRunnerScreen(quiz: _quiz),
      ),
    );
    if (!mounted) return;
    if (completed == true) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    final secureMode = _quiz['secure_mode'] == true;
    final randomQuestions = _quiz['randomize_questions'] == true;
    final randomOptions = _quiz['randomize_options'] == true;
    final duration = (_quiz['duration_minutes'] as num?)?.toInt() ?? 30;
    final passMark = (_quiz['passing_score'] as num?)?.toInt() ?? 50;
    final attempts = (_quiz['max_attempts'] as num?)?.toInt() ?? 1;

    return VibeScaffold(
      appBar: AppBar(
        title: const Text(
          'Quiz briefing',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 920;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontal ? 40 : 18,
              12,
              horizontal ? 40 : 18,
              36,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  children: <Widget>[
                    _buildHero(
                      secureMode: secureMode,
                      duration: duration,
                      passMark: passMark,
                    ),
                    const SizedBox(height: 18),
                    if (horizontal)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            flex: 6,
                            child: _buildBriefingCard(
                              randomQuestions: randomQuestions,
                              randomOptions: randomOptions,
                              secureMode: secureMode,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 4,
                            child: _buildStartCard(
                              duration: duration,
                              passMark: passMark,
                              attempts: attempts,
                            ),
                          ),
                        ],
                      )
                    else ...<Widget>[
                      _buildBriefingCard(
                        randomQuestions: randomQuestions,
                        randomOptions: randomOptions,
                        secureMode: secureMode,
                      ),
                      const SizedBox(height: 18),
                      _buildStartCard(
                        duration: duration,
                        passMark: passMark,
                        attempts: attempts,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHero({
    required bool secureMode,
    required int duration,
    required int passMark,
  }) {
    final title = (_quiz['title'] ?? 'Secure quiz').toString();
    final module = (_quiz['module_name'] ??
            _quiz['module_code'] ??
            'Your registered module')
        .toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: AppStyles.bentoRadius,
        boxShadow: AppStyles.glassShadow,
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 18,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.bolt_rounded,
                      color: AppColors.electricCyan,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      secureMode ? 'OG SECURE ASSESSMENT' : 'OG QUIZ ARENA',
                      style: const TextStyle(
                        color: AppColors.electricCyan,
                        fontSize: 11,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 29,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  module,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _HeroMetric(
                icon: Icons.timer_outlined,
                value: '$duration min',
                label: 'Duration',
              ),
              const SizedBox(width: 10),
              _HeroMetric(
                icon: Icons.flag_outlined,
                value: '$passMark%',
                label: 'Pass mark',
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 420.ms).slideY(begin: .08, end: 0);
  }

  Widget _buildBriefingCard({
    required bool randomQuestions,
    required bool randomOptions,
    required bool secureMode,
  }) {
    final instructions = (_quiz['instructions'] ??
            _quiz['description'] ??
            'Read every question carefully and submit before time expires.')
        .toString();
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionTitle(
            icon: Icons.fact_check_outlined,
            title: 'Before you begin',
            subtitle: 'Your answers are protected and saved as you work.',
          ),
          const SizedBox(height: 20),
          Text(
            instructions,
            style: const TextStyle(
              color: AppColors.textMuted,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          _RuleRow(
            icon: Icons.cloud_done_outlined,
            title: 'Automatic answer saving',
            detail: 'Connection recovery keeps unsent answers on this device.',
            enabled: true,
          ),
          _RuleRow(
            icon: Icons.shuffle_rounded,
            title: 'Randomised experience',
            detail: randomQuestions || randomOptions
                ? 'Questions or answer choices may appear in a unique order.'
                : 'Questions follow the lecturer’s original sequence.',
            enabled: randomQuestions || randomOptions,
          ),
          _RuleRow(
            icon: Icons.shield_outlined,
            title: 'Focus monitoring',
            detail: secureMode
                ? 'Leaving the quiz is recorded as a focus event.'
                : 'Standard quiz mode is active.',
            enabled: secureMode,
          ),
          const _RuleRow(
            icon: Icons.keyboard_alt_outlined,
            title: 'Accessible controls',
            detail: 'Use 1–4 to answer and arrow keys to navigate.',
            enabled: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStartCard({
    required int duration,
    required int passMark,
    required int attempts,
  }) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionTitle(
            icon: Icons.rocket_launch_outlined,
            title: 'Ready to start?',
            subtitle: 'The timer begins after your attempt is created.',
          ),
          const SizedBox(height: 20),
          _InfoLine(label: 'Time limit', value: '$duration minutes'),
          _InfoLine(label: 'Pass requirement', value: '$passMark%'),
          _InfoLine(
            label: 'Allowed attempts',
            value: '$attempts ${attempts == 1 ? 'attempt' : 'attempts'}',
          ),
          const _InfoLine(label: 'Answer saving', value: 'Automatic'),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _starting ? null : _startQuiz,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.midnightInk,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(
                  borderRadius: AppStyles.controlRadius,
                ),
              ),
              icon: _starting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(
                _starting ? 'Preparing attempt…' : 'Start quiz',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed:
                  _starting ? null : () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppStyles.bentoRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .78),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(color: Colors.white.withValues(alpha: .85)),
            boxShadow: AppStyles.softShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        borderRadius: AppStyles.controlRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppColors.electricCyan, size: 19),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.vibeBlue.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppColors.vibeBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.midnightInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.enabled,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            icon,
            size: 20,
            color: enabled ? AppColors.success : AppColors.textMuted,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.midnightInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.midnightInk,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
