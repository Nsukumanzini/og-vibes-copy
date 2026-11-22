import 'package:og_vibes_student/utils/theme_constants.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class MissMrVibesScreen extends StatefulWidget {
  const MissMrVibesScreen({super.key});

  @override
  State<MissMrVibesScreen> createState() => _MissMrVibesScreenState();
}

class _MissMrVibesScreenState extends State<MissMrVibesScreen> {
  late Future<List<Map<String, dynamic>>> _contestantsFuture;

  @override
  void initState() {
    super.initState();
    _contestantsFuture = _loadContestants();
  }

  Future<List<Map<String, dynamic>>> _loadContestants() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    return const [
      {
        'name': 'Siyabonga',
        'course': 'IT L4',
        'votes': 340,
        'accent': Color(0xFF2457F5),
      },
      {
        'name': 'Nomsa',
        'course': 'Hospitality',
        'votes': 412,
        'accent': AppColors.deepBlue,
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.surface, AppColors.auroraCanvas, AppColors.blueTint],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _contestantsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return _buildLoading();
              }
              if (!snapshot.hasData || snapshot.hasError) {
                return Center(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _contestantsFuture = _loadContestants();
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry gallery load'),
                  ),
                );
              }

              final contestants = snapshot.data!;
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                itemCount: contestants.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Miss & Mr Vibes Voting Gallery',
                        style: TextStyle(
                          color: AppColors.midnightInk,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                        ),
                      ),
                    );
                  }
                  return _ContestantCard(contestant: contestants[index - 1]);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      child: Shimmer.fromColors(
        baseColor: AppColors.glassBorder,
        highlightColor: AppColors.blueTint,
        child: ListView.separated(
          itemCount: 2,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, _) => Container(
            height: 230,
            decoration: BoxDecoration(
              color: AppColors.midnightInk,
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContestantCard extends StatelessWidget {
  const _ContestantCard({required this.contestant});

  final Map<String, dynamic> contestant;

  @override
  Widget build(BuildContext context) {
    final accent = contestant['accent'] as Color;
    final votes = contestant['votes'] as int;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: AppColors.surface,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 110,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0.65)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: Icon(Icons.emoji_events, color: Colors.white, size: 44),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Contestant: ${contestant['name']} (${contestant['course']})',
            style: const TextStyle(
              color: AppColors.midnightInk,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$votes Votes',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vote cast successfully!')),
                );
              },
              icon: const Icon(Icons.favorite),
              label: const Text('Vote'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
