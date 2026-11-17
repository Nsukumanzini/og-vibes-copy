import 'package:flutter/material.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({super.key});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  static const String _deckTitle = 'Computer Practice N4 - Core Terms';

  static const List<Map<String, String>> _flashcards = <Map<String, String>>[
    {
      'question': 'What is RAM?',
      'answer':
          'Random Access Memory. Volatile memory used to store active data.',
    },
    {
      'question': 'Define a Sole Trader.',
      'answer':
          'A business owned and run by one person where there is no legal distinction between the owner and the business entity.',
    },
    {
      'question': 'What is an Operating System?',
      'answer':
          'System software that manages computer hardware and software resources.',
    },
  ];

  int _currentIndex = 0;
  bool _showAnswer = false;
  bool _completed = false;

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Flashcards')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _deckTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF102027),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _completed
                  ? 'Deck completed'
                  : 'Card ${_currentIndex + 1} of ${_flashcards.length}',
              style: const TextStyle(
                color: Color(0xFF607D8B),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _completed ? 1 : (_currentIndex + 1) / _flashcards.length,
              minHeight: 8,
              borderRadius: BorderRadius.circular(99),
              backgroundColor: const Color(0xFFE3ECF5),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF1565C0),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _completed ? _buildCompletedState() : _buildFlashcard(),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _completed ? null : _nextCard,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Needs Review'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC62828),
                      side: const BorderSide(color: Color(0xFFC62828)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _completed ? null : _nextCard,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Got It'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashcard() {
    final Map<String, String> card = _flashcards[_currentIndex];

    return InkWell(
      onTap: () {
        setState(() {
          _showAnswer = !_showAnswer;
        });
      },
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: _showAnswer
              ? const LinearGradient(
                  colors: <Color>[Color(0xFF2E7D32), Color(0xFF43A047)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : const LinearGradient(
                  colors: <Color>[Color(0xFF0D47A1), Color(0xFF1976D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _showAnswer ? 'Answer' : 'Question',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.touch_app_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                  child: Text(
                    _showAnswer ? card['answer']! : card['question']!,
                    key: ValueKey<String>(
                      _showAnswer ? 'a-$_currentIndex' : 'q-$_currentIndex',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tap card to flip',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedState() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE7F1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.emoji_events_rounded,
            size: 56,
            color: Color(0xFF2E7D32),
          ),
          const SizedBox(height: 14),
          const Text(
            'Deck completed! Great studying.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF102027),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _currentIndex = 0;
                _showAnswer = false;
                _completed = false;
              });
            },
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Restart Deck'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1565C0),
              side: const BorderSide(color: Color(0xFF1565C0)),
            ),
          ),
        ],
      ),
    );
  }

  void _nextCard() {
    if (_currentIndex == _flashcards.length - 1) {
      setState(() {
        _completed = true;
        _showAnswer = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deck completed! Great studying.')),
      );
      return;
    }

    setState(() {
      _currentIndex++;
      _showAnswer = false;
    });
  }
}
