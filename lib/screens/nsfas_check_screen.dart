import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class NsfasCheckScreen extends StatefulWidget {
  const NsfasCheckScreen({super.key});

  @override
  State<NsfasCheckScreen> createState() => _NsfasCheckScreenState();
}

class _NsfasCheckScreenState extends State<NsfasCheckScreen> {
  late Future<Map<String, String>> _nsfasFuture;

  @override
  void initState() {
    super.initState();
    _nsfasFuture = _loadMockNsfas();
  }

  Future<Map<String, String>> _loadMockNsfas() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    return const {
      'status': 'Funded - Active',
      'allowance': 'R 3,045',
      'lastPayout': '25 February 2026 - Cleared',
      'nextPayout': '25 March 2026 - Pending Verification',
      'institution': 'Ermelo TVET College',
    };
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('NSFAS Allowance Tracker')),
      body: FutureBuilder<Map<String, String>>(
        future: _nsfasFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingState();
          }

          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _nsfasFuture = _loadMockNsfas();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry status load'),
              ),
            );
          }

          return _buildDashboard(snapshot.data!);
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
              height: 170,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(Map<String, String> data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        children: [
          _buildStatusHero(data),
          const SizedBox(height: 14),
          _buildFundingDetails(data),
          const SizedBox(height: 14),
          _buildDownloadButton(),
        ],
      ),
    );
  }

  Widget _buildStatusHero(Map<String, String> data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data['institution'] ?? '',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF69F0AE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Funded - Active',
                  style: TextStyle(
                    color: Color(0xFF0D3C1C),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.verified_user, color: Colors.white, size: 24),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: 0.78,
              minHeight: 9,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF69F0AE),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Allowance release pipeline: 78% complete',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFundingDetails(Map<String, String> data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          _detailTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Monthly Allowance',
            value: data['allowance'] ?? '',
            color: const Color(0xFF2E7D32),
          ),
          const Divider(height: 22),
          _detailTile(
            icon: Icons.check_circle_outline,
            title: 'Last Payout',
            value: data['lastPayout'] ?? '',
            color: const Color(0xFF00ACC1),
          ),
          const Divider(height: 22),
          _detailTile(
            icon: Icons.pending_actions_outlined,
            title: 'Next Expected Payout',
            value: data['nextPayout'] ?? '',
            color: const Color(0xFFFF8F00),
          ),
        ],
      ),
    );
  }

  Widget _detailTile({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Generating PDF document...')),
          );
        },
        icon: const Icon(Icons.download_rounded),
        label: const Text('Download Proof of Funding'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2962FF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
