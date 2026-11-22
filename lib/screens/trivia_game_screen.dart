import 'package:og_vibes_student/utils/theme_constants.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class TriviaGameScreen extends StatefulWidget {
  const TriviaGameScreen({super.key});

  @override
  State<TriviaGameScreen> createState() => _TriviaGameScreenState();
}

class _TriviaGameScreenState extends State<TriviaGameScreen> {
  late Future<Map<String, dynamic>> _triviaFuture;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _triviaFuture = _loadTrivia();
  }

  Future<Map<String, dynamic>> _loadTrivia() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    return const {
      'title': 'Campus Tech Trivia',
      'question': 'What does HTML stand for?',
      'answers': [
        'Hyperlinks and Text Markup Language',
        'HyperText Markup Language',
        'Home Tool Markup Language',
        'HighText Machine Language',
      ],
      'correctIndex': 1,
      'leaderboard': [
        {'name': 'Sipho', 'points': 4500},
        {'name': 'You', 'points': 4100},
        {'name': 'Lerato', 'points': 3900},
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.surface, AppColors.auroraCanvas, AppColors.blueTint],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _triviaFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return _buildLoading();
              }
              if (!snapshot.hasData || snapshot.hasError) {
                return Center(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _triviaFuture = _loadTrivia();
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry trivia load'),
                  ),
                );
              }

              final data = snapshot.data!;
              final answers = (data['answers'] as List<dynamic>).cast<String>();
              final leaderboard = (data['leaderboard'] as List<dynamic>)
                  .cast<Map<String, dynamic>>();

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['title'] as String,
                      style: const TextStyle(
                        color: AppColors.midnightInk,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildQuestionCard(
                      data['question'] as String,
                      answers,
                      data['correctIndex'] as int,
                    ),
                    const SizedBox(height: 16),
                    _buildLeaderboard(leaderboard),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionCard(
    String question,
    List<String> answers,
    int correctIndex,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Question',
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            question,
            style: const TextStyle(
              color: AppColors.midnightInk,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(answers.length, (index) {
            final selected = _selectedIndex == index;
            final isCorrect = index == correctIndex;
            final showResult = _selectedIndex != null;

            Color bg = AppColors.surface;
            if (showResult && isCorrect) {
              bg = const Color(0xFF2E7D32);
            } else if (showResult && selected && !isCorrect) {
              bg = Colors.redAccent;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () {
                  setState(() => _selectedIndex = index);
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    answers[index],
                    style: const TextStyle(
                      color: AppColors.midnightInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLeaderboard(List<Map<String, dynamic>> leaderboard) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.midnightInk,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Leaderboard',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(leaderboard.length, (index) {
            final row = leaderboard[index];
            final medal = switch (index) {
              0 => '🥇',
              1 => '🥈',
              _ => '🥉',
            };
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(medal, style: const TextStyle(fontSize: 22)),
              title: Text(
                '${index + 1}. ${row['name']}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: row['name'] == 'You'
                      ? const Color(0xFF2457F5)
                      : Colors.black87,
                ),
              ),
              trailing: Text(
                '${row['points']} pts',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Shimmer.fromColors(
        baseColor: AppColors.glassBorder,
        highlightColor: AppColors.blueTint,
        child: Column(
          children: [
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: AppColors.midnightInk,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: AppColors.midnightInk,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
