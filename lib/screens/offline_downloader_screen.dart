import 'dart:async';

import 'package:flutter/material.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class OfflineDownloaderScreen extends StatefulWidget {
  const OfflineDownloaderScreen({super.key});

  @override
  State<OfflineDownloaderScreen> createState() =>
      _OfflineDownloaderScreenState();
}

class _OfflineDownloaderScreenState extends State<OfflineDownloaderScreen> {
  final List<_LearningPack> _packs = const <_LearningPack>[
    _LearningPack(
      title: 'N4 Maths Complete Offline Pack',
      details: 'Includes Notes, Past Papers, Flashcards',
      size: '45MB',
      color: Color(0xFF1565C0),
      icon: Icons.school_rounded,
    ),
    _LearningPack(
      title: 'Computer Practice Practical Guides',
      details: 'Step-by-step practical support material',
      size: '12MB',
      color: Color(0xFF00897B),
      icon: Icons.computer_rounded,
    ),
  ];

  late final List<_DownloadStatus> _statuses;
  late final List<double> _progress;
  final List<Timer?> _timers = <Timer?>[];

  @override
  void initState() {
    super.initState();
    _statuses = List<_DownloadStatus>.filled(
      _packs.length,
      _DownloadStatus.idle,
    );
    _progress = List<double>.filled(_packs.length, 0);
    _timers.addAll(List<Timer?>.filled(_packs.length, null));
  }

  @override
  void dispose() {
    for (final Timer? timer in _timers) {
      timer?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Offline Downloader')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: <Widget>[
          _buildHeader(),
          const SizedBox(height: 14),
          ...List<Widget>.generate(_packs.length, _buildPackCard),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0D47A1), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Text(
        'Zero-Data Learning Packs',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildPackCard(int index) {
    final _LearningPack pack = _packs[index];
    final _DownloadStatus status = _statuses[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3EAF2)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: pack.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(pack.icon, color: pack.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      pack.title,
                      style: const TextStyle(
                        color: Color(0xFF102027),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pack.details,
                      style: const TextStyle(
                        color: Color(0xFF607D8B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Size: ${pack.size}',
                      style: const TextStyle(
                        color: Color(0xFF455A64),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildActionArea(index, status),
        ],
      ),
    );
  }

  Widget _buildActionArea(int index, _DownloadStatus status) {
    switch (status) {
      case _DownloadStatus.idle:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _startDownload(index),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.download_rounded),
            label: const Text(
              'Download to Device',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );
      case _DownloadStatus.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress[index],
                minHeight: 10,
                backgroundColor: const Color(0xFFE3ECF5),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF1565C0),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Downloading... ${(_progress[index] * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                color: Color(0xFF546E7A),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        );
      case _DownloadStatus.downloaded:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Downloaded ✓',
              style: TextStyle(
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
    }
  }

  void _startDownload(int index) {
    if (_statuses[index] != _DownloadStatus.idle) {
      return;
    }

    setState(() {
      _statuses[index] = _DownloadStatus.downloading;
      _progress[index] = 0;
    });

    const int totalMs = 2000;
    const int tickMs = 80;
    final int totalTicks = totalMs ~/ tickMs;
    int currentTick = 0;

    _timers[index]?.cancel();
    _timers[index] = Timer.periodic(const Duration(milliseconds: tickMs), (
      Timer timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      currentTick++;
      final double next = (currentTick / totalTicks).clamp(0, 1).toDouble();

      setState(() {
        _progress[index] = next;
      });

      if (currentTick >= totalTicks) {
        timer.cancel();
        setState(() {
          _progress[index] = 1;
          _statuses[index] = _DownloadStatus.downloaded;
        });
      }
    });
  }
}

enum _DownloadStatus { idle, downloading, downloaded }

class _LearningPack {
  const _LearningPack({
    required this.title,
    required this.details,
    required this.size,
    required this.color,
    required this.icon,
  });

  final String title;
  final String details;
  final String size;
  final Color color;
  final IconData icon;
}
