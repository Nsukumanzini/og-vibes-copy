import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class SrcVotingScreen extends StatefulWidget {
  const SrcVotingScreen({super.key});

  @override
  State<SrcVotingScreen> createState() => _SrcVotingScreenState();
}

class _SrcVotingScreenState extends State<SrcVotingScreen> {
  late Future<List<Map<String, dynamic>>> _candidatesFuture;
  String? _selectedCandidate;

  @override
  void initState() {
    super.initState();
    _candidatesFuture = _loadCandidates();
  }

  Future<List<Map<String, dynamic>>> _loadCandidates() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    return const [
      {
        'name': 'Thabo Mokoena',
        'slogan': 'Better Wi-Fi, Better Grades!',
        'course': 'IT NC(V) L4',
        'mockVotes': 45,
        'color': Color(0xFF2962FF),
      },
      {
        'name': 'Lerato Khumalo',
        'slogan': 'Student Safety First.',
        'course': 'Business Management N5',
        'mockVotes': 31,
        'color': Color(0xFF00ACC1),
      },
      {
        'name': 'Sibusiso Nkosi',
        'slogan': 'Fix Our NSFAS Allowances.',
        'course': 'Engineering N4',
        'mockVotes': 24,
        'color': Color(0xFFFF7043),
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('SRC Voting')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _candidatesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingState();
          }

          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _candidatesFuture = _loadCandidates();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry election feed'),
              ),
            );
          }

          final candidates = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              children: [
                _buildLiveStatusCard(),
                const SizedBox(height: 14),
                Expanded(child: _buildCandidateList(candidates)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: [
            Container(
              height: 122,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: 3,
                separatorBuilder: (context, _) => const SizedBox(height: 12),
                itemBuilder: (context, _) => Container(
                  height: 196,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Color(0xFF69F0AE),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Demo election preview',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Ermelo TVET College • SRC President Ballot',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: 0.71,
              minHeight: 8,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF69F0AE),
              ),
              backgroundColor: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sample turnout data • voting is not connected',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateList(List<Map<String, dynamic>> candidates) {
    return AnimationLimiter(
      child: ListView.separated(
        itemCount: candidates.length,
        separatorBuilder: (context, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final candidate = candidates[index];
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 400),
            child: SlideAnimation(
              verticalOffset: 24,
              child: FadeInAnimation(child: _buildCandidateCard(candidate)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCandidateCard(Map<String, dynamic> candidate) {
    final name = candidate['name'] as String;
    final slogan = candidate['slogan'] as String;
    final course = candidate['course'] as String;
    final mockVotes = candidate['mockVotes'] as int;
    final color = candidate['color'] as Color;
    final selected = _selectedCandidate == name;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected ? color.withValues(alpha: 0.65) : Colors.transparent,
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      course,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.verified, color: Colors.green, size: 22),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '"$slogan"',
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (mockVotes / 100).clamp(0.0, 1.0),
                    minHeight: 9,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    backgroundColor: color.withValues(alpha: 0.18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$mockVotes% mock',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _castVote(name),
              icon: const Icon(Icons.how_to_vote),
              label: Text(selected ? 'VOTE RECORDED' : 'VOTE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _castVote(String candidateName) async {
    setState(() => _selectedCandidate = candidateName);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Demo selection saved'),
          content: Text(
            'Your selection of $candidateName is stored only for this app session. '
            'It was not submitted as an official vote.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Demo only: your selection was not submitted as an official vote.',
        ),
      ),
    );
  }
}
