import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:flutter/material.dart';

import '../services/content_service.dart';

class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key});

  static const _fallback = <Map<String, dynamic>>[
    {
      'version': '1.0.0',
      'title': 'Safer, faster and easier to use',
      'subtitle':
          'A private Document Wallet, clearer notifications, video posts, group calls and a more personal news feed.',
    },
    {
      'version': 'Preview release',
      'title': 'One campus workspace',
      'subtitle':
          'Academic resources, module groups, chats, calls, live classes and campus services in one app.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Version updates', style: TextStyle(color: AppColors.midnightInk)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.midnightInk),
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.surface, AppColors.auroraCanvas, AppColors.blueTint],
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: ContentService.loadSection('version_updates', fallback: _fallback),
            builder: (context, snapshot) {
              final updates = (snapshot.data ?? _fallback)
                  .map(_ReleaseNote.fromRow)
                  .toList(growable: false);
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemCount: updates.length,
                itemBuilder: (context, index) => _UpdateTimelineItem(
                  release: updates[index],
                  drawLine: index != updates.length - 1,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _UpdateTimelineItem extends StatelessWidget {
  const _UpdateTimelineItem({required this.release, required this.drawLine});

  final _ReleaseNote release;
  final bool drawLine;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: AppColors.midnightInk, shape: BoxShape.circle),
            ),
            if (drawLine) Container(width: 2, height: 90, color: AppColors.glassBorder),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(release.version, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.ogGold)),
                const SizedBox(height: 6),
                Text(release.title, style: const TextStyle(color: AppColors.midnightInk, fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(release.subtitle, style: const TextStyle(color: AppColors.textMuted)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReleaseNote {
  const _ReleaseNote({required this.version, required this.title, required this.subtitle});

  factory _ReleaseNote.fromRow(Map<String, dynamic> row) {
    String text(dynamic value, String fallback) {
      final result = value?.toString().trim() ?? '';
      return result.isEmpty ? fallback : result;
    }

    return _ReleaseNote(
      version: text(row['version'] ?? row['slug'], 'Update'),
      title: text(row['title'], 'OG Vibes update'),
      subtitle: text(
        row['subtitle'] ?? row['body'] ?? row['description'],
        'Open OG Vibes to explore the latest improvements.',
      ),
    );
  }

  final String version;
  final String title;
  final String subtitle;
}
