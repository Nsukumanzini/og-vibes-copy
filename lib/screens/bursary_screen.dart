import 'package:og_vibes_student/utils/theme_constants.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class BursaryScreen extends StatefulWidget {
  const BursaryScreen({super.key});

  @override
  State<BursaryScreen> createState() => _BursaryScreenState();
}

class _BursaryScreenState extends State<BursaryScreen> {
  late Future<List<Map<String, String>>> _bursaryFuture;

  @override
  void initState() {
    super.initState();
    _bursaryFuture = _loadBursaries();
  }

  Future<List<Map<String, String>>> _loadBursaries() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    return const [
      {
        'title': 'NSFAS 2026 Late Appeals',
        'subtitle': 'Closing in 2 days, High Priority',
        'tag': 'HIGH PRIORITY',
        'tagColor': 'red',
        'details': 'For students needing urgent funding reinstatement support.',
      },
      {
        'title': 'MICT SETA IT Learnership',
        'subtitle': 'Stipend: R3500/m, IT Students Only',
        'tag': 'IT TRACK',
        'tagColor': 'blue',
        'details':
            'Industry pathway with practical placements around Mpumalanga.',
      },
      {
        'title': 'Allan Gray Orbis Foundation Fellowship',
        'subtitle': 'Degree pathway funding',
        'tag': 'LONG-TERM',
        'tagColor': 'green',
        'details': 'Leadership and tertiary degree progression support.',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Bursary Radar'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.surface, AppColors.auroraCanvas, AppColors.blueTint],
          ),
        ),
        child: FutureBuilder<List<Map<String, String>>>(
          future: _bursaryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _buildLoading();
            }
            if (!snapshot.hasData || snapshot.hasError) {
              return Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _bursaryFuture = _loadBursaries();
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry bursary load'),
                ),
              );
            }

            final opportunities = snapshot.data!;
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              itemCount: opportunities.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) =>
                  _BursaryCard(data: opportunities[index]),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Shimmer.fromColors(
        baseColor: AppColors.glassBorder,
        highlightColor: AppColors.blueTint,
        child: ListView.separated(
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (_, _) => Container(
            height: 178,
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

class _BursaryCard extends StatelessWidget {
  const _BursaryCard({required this.data});

  final Map<String, String> data;

  @override
  Widget build(BuildContext context) {
    final tagColor = switch (data['tagColor']) {
      'red' => const Color(0xFFE53935),
      'green' => const Color(0xFF2E7D32),
      _ => const Color(0xFF2457F5),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: AppColors.surface,
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data['title']!,
                  style: const TextStyle(
                    color: AppColors.midnightInk,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tagColor),
                ),
                child: Text(
                  data['tag']!,
                  style: TextStyle(
                    color: tagColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            data['subtitle']!,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(data['details']!, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Opening ${data['title']} details...'),
                  ),
                );
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('View Opportunity'),
            ),
          ),
        ],
      ),
    );
  }
}
