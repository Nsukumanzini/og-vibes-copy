import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/screens/lms_quiz_lockdown_screen.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  final List<QuizItem> _quizzes = [];

  @override
  void initState() {
    super.initState();
    _loadQuizzes();
  }

  Future<void> _loadQuizzes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await Supabase.instance.client
          .from('quizzes')
          .select('''
            id,
            title,
            description,
            lecturer_name,
            reward,
            duration_minutes,
            passing_score,
            quiz_date,
            published,
            questions:quiz_questions(
              id,
              question_text,
              option_a,
              option_b,
              option_c,
              option_d,
              correct_option,
              points,
              position
            )
          ''')
          .eq('published', true)
          .order('quiz_date', ascending: false);

      final rows = List<Map<String, dynamic>>.from(response as List<dynamic>? ?? []);
      if (!mounted) return;
      setState(() {
        _quizzes
          ..clear()
          ..addAll(rows.map(QuizItem.fromSupabaseRow));
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Quizzes'),
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text('Could not load quizzes right now.'),
            const SizedBox(height: 8),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadQuizzes, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_quizzes.isEmpty) {
      return const Center(
        child: Text('No quizzes are available right now. Lecturers can publish them from their dashboard.'),
      );
    }

    return ListView.separated(
      itemCount: _quizzes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final quiz = _quizzes[index];
        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _showQuizDetails(context, quiz),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          quiz.title,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${quiz.durationMinutes} min',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1565C0)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    quiz.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _chip(Icons.person_outline, 'By ${quiz.lecturerName}'),
                      _chip(Icons.card_giftcard_outlined, quiz.reward),
                      _chip(Icons.emoji_events_outlined, 'Pass ${quiz.passingScore}%'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () => _showQuizDetails(context, quiz),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Open Quiz'),
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

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF1565C0)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showQuizDetails(BuildContext context, QuizItem quiz) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: MediaQuery.of(context).viewInsets,
          child: SizedBox(
            height: 430,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    height: 4,
                    width: 56,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(quiz.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text('By ${quiz.lecturerName}', style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 12),
                      Text(quiz.description, style: const TextStyle(height: 1.5, color: Colors.black87)),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          _chip(Icons.timer_outlined, '${quiz.durationMinutes} min'),
                          _chip(Icons.emoji_events_outlined, 'Pass ${quiz.passingScore}%'),
                          _chip(Icons.card_giftcard_outlined, quiz.reward),
                        ],
                      ),
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
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => LmsQuizLockdownScreen(quiz: quiz.toMap())));
                            },
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Start Quiz'),
                          ),
                        ),
                      ])
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}

class QuizItem {
  QuizItem({
    required this.id,
    required this.title,
    required this.description,
    required this.lecturerName,
    required this.reward,
    required this.durationMinutes,
    required this.passingScore,
    required this.quizDate,
    required this.questions,
  });

  final String id;
  final String title;
  final String description;
  final String lecturerName;
  final String reward;
  final int durationMinutes;
  final int passingScore;
  final DateTime? quizDate;
  final List<QuizQuestion> questions;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'lecturer': lecturerName,
      'reward': reward,
      'duration_minutes': durationMinutes,
      'passing_score': passingScore,
      'quiz_date': quizDate?.toIso8601String(),
      'questions': questions.map((question) => question.toMap()).toList(),
    };
  }

  factory QuizItem.fromSupabaseRow(Map<String, dynamic> row) {
    final questions = (row['questions'] as List<dynamic>? ?? [])
        .map((question) => QuizQuestion.fromSupabaseRow(question as Map<String, dynamic>))
        .toList();

    return QuizItem(
      id: (row['id'] ?? '').toString(),
      title: (row['title'] ?? 'Untitled quiz').toString(),
      description: (row['description'] ?? 'No description provided').toString(),
      lecturerName: (row['lecturer_name'] ?? 'Lecturer').toString(),
      reward: (row['reward'] ?? 'Reward pending').toString(),
      durationMinutes: int.tryParse((row['duration_minutes'] ?? '0').toString()) ?? 0,
      passingScore: int.tryParse((row['passing_score'] ?? '0').toString()) ?? 0,
      quizDate: row['quiz_date'] is String ? DateTime.tryParse(row['quiz_date'] as String) : null,
      questions: questions,
    );
  }
}

class QuizQuestion {
  QuizQuestion({
    required this.id,
    required this.text,
    required this.options,
    required this.correctOption,
    required this.points,
    required this.position,
  });

  final String id;
  final String text;
  final List<String> options;
  final int correctOption;
  final int points;
  final int position;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'options': options,
      'answer': correctOption,
      'points': points,
      'position': position,
    };
  }

  factory QuizQuestion.fromSupabaseRow(Map<String, dynamic> row) {
    return QuizQuestion(
      id: (row['id'] ?? '').toString(),
      text: (row['question_text'] ?? '').toString(),
      options: [
        row['option_a']?.toString() ?? '',
        row['option_b']?.toString() ?? '',
        row['option_c']?.toString() ?? '',
        row['option_d']?.toString() ?? '',
      ].where((option) => option.isNotEmpty).toList(),
      correctOption: int.tryParse((row['correct_option'] ?? '0').toString()) ?? 0,
      points: int.tryParse((row['points'] ?? '1').toString()) ?? 1,
      position: int.tryParse((row['position'] ?? '0').toString()) ?? 0,
    );
  }
}

class QuizRunnerScreen extends StatefulWidget {
  final Map<String, dynamic> quiz;
  const QuizRunnerScreen({super.key, required this.quiz});

  @override
  State<QuizRunnerScreen> createState() => _QuizRunnerScreenState();
}

class _QuizRunnerScreenState extends State<QuizRunnerScreen> {
  int _index = 0;
  final Map<int, int> _answers = {};

  List<Map<String, dynamic>> get _questions => List<Map<String, dynamic>>.from(widget.quiz['questions'] ?? []);

  void _submitAnswer(int selected) {
    setState(() {
      _answers[_index] = selected;
    });
  }

  void _next() {
    if (_index < _questions.length - 1) {
      setState(() => _index++);
      return;
    }
    final score = _calculateScore();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => QuizResultScreen(score: score, total: _questions.length)));
  }

  int _calculateScore() {
    var s = 0;
    for (var i = 0; i < _questions.length; i++) {
      final correct = _questions[i]['answer'] as int?;
      if (correct != null && _answers[i] == correct) s++;
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final q = _questions[_index];
    final selected = _answers[_index];
    return VibeScaffold(
      appBar: AppBar(
        title: Text(widget.quiz['title'] ?? 'Quiz'),
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Question ${_index + 1} of ${_questions.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(q['text'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ...List<Widget>.generate((q['options'] as List).length, (i) {
              return RadioListTile<int>(
                title: Text(q['options'][i]),
                value: i,
                groupValue: selected,
                onChanged: (v) => _submitAnswer(v ?? 0),
              );
            }),
            const Spacer(),
            Row(children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: selected == null ? null : _next,
                  child: Text(_index < _questions.length - 1 ? 'Next' : 'Submit'),
                ),
              ),
            ])
          ],
        ),
      ),
    );
  }
}

class QuizResultScreen extends StatelessWidget {
  final int score;
  final int total;
  const QuizResultScreen({super.key, required this.score, required this.total});

  @override
  Widget build(BuildContext context) {
    final percent = (score / total * 100).round();
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Quiz Results'),
        leading: BackButton(onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$score / $total', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Text('$percent% correct', style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Done'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
