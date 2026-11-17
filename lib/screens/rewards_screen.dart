import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  late Future<Map<String, dynamic>> _rewardsFuture;

  @override
  void initState() {
    super.initState();
    _rewardsFuture = _loadRewardsData();
  }

  Future<Map<String, dynamic>> _loadRewardsData() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    return const {
      'points': 1450,
      'rewards': [
        {'title': 'Free Coffee at Cafeteria', 'cost': 500, 'type': 'Food'},
        {'title': '1GB MTN Data', 'cost': 1200, 'type': 'Data'},
        {'title': 'Exclusive OG Vibes Cap', 'cost': 2500, 'type': 'Merch'},
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Vibe Rewards')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _rewardsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoading();
          }
          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _rewardsFuture = _loadRewardsData();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry rewards load'),
              ),
            );
          }

          final data = snapshot.data!;
          final points = data['points'] as int;
          final rewards = (data['rewards'] as List<dynamic>)
              .cast<Map<String, dynamic>>();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPointsHero(points),
                const SizedBox(height: 14),
                const Text(
                  'Available Rewards',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
                ...rewards.map(
                  (reward) => _RewardCard(
                    reward: reward,
                    points: points,
                    onRedeem: () {
                      final cost = reward['cost'] as int;
                      if (points < cost) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Not enough Vibe Points yet.'),
                          ),
                        );
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Redeem request sent for ${reward['title']}!',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPointsHero(int points) {
    final progress = (points / 2500).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF2962FF), Color(0xFF6A5AE0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2962FF).withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Vibe Points',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            points.toString(),
            style: const TextStyle(
              color: Color(0xFFFFEB3B),
              fontWeight: FontWeight.w900,
              fontSize: 44,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFFEB3B),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Progress toward premium merch rewards',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: [
            Container(
              height: 190,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            const SizedBox(height: 14),
            ...List.generate(
              3,
              (_) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                height: 94,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.reward,
    required this.points,
    required this.onRedeem,
  });

  final Map<String, dynamic> reward;
  final int points;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final cost = reward['cost'] as int;
    final affordable = points >= cost;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: affordable
              ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: affordable
                ? const Color(0xFF2E7D32).withValues(alpha: 0.15)
                : Colors.grey.withValues(alpha: 0.2),
            child: Icon(
              Icons.redeem,
              color: affordable ? const Color(0xFF2E7D32) : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reward['title'] as String,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${reward['cost']} pts',
                  style: TextStyle(
                    color: affordable ? const Color(0xFF2E7D32) : Colors.grey,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(onPressed: onRedeem, child: const Text('Redeem')),
        ],
      ),
    );
  }
}
