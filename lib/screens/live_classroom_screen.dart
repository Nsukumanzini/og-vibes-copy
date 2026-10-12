import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/models/live_session.dart';
import 'package:og_vibes_student/utils/theme_constants.dart';

class LiveClassroomScreen extends StatefulWidget {
  const LiveClassroomScreen({super.key, required this.session});

  final LiveSession session;

  @override
  State<LiveClassroomScreen> createState() => _LiveClassroomScreenState();
}

class _LiveClassroomScreenState extends State<LiveClassroomScreen> {
  int _secondsElapsed = 0;
  bool _attendanceLoaded = false;
  bool _isSyncingAttendance = false;
  Timer? _timer;

  int get _requiredSeconds => widget.session.requiredAttendanceSeconds;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null && widget.session.id.isNotEmpty) {
      try {
        final row = await Supabase.instance.client
            .from('online_class_attendance')
            .select('seconds_attended')
            .eq('class_id', widget.session.id)
            .maybeSingle();
        _secondsElapsed =
            int.tryParse((row?['seconds_attended'] ?? 0).toString()) ?? 0;
        await _persistAttendance();
      } catch (_) {
        // Attendance continues locally if the connection is temporarily down.
      }
    }
    if (!mounted) return;
    setState(() => _attendanceLoaded = true);
    _startAttendanceTimer();
  }

  void _startAttendanceTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        return;
      }
      setState(() {
        _secondsElapsed++;
      });
      if (_secondsElapsed % 10 == 0) {
        _persistAttendance();
      }
    });
  }

  Future<void> _persistAttendance() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null ||
        widget.session.id.isEmpty ||
        _isSyncingAttendance) {
      return;
    }
    _isSyncingAttendance = true;
    try {
      await Supabase.instance.client.from('online_class_attendance').upsert(
        <String, dynamic>{
          'user_id': user.id,
          'class_id': widget.session.id,
          'seconds_attended': _secondsElapsed,
          'required_seconds': _requiredSeconds,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          'completed_at': _secondsElapsed >= _requiredSeconds
              ? DateTime.now().toUtc().toIso8601String()
              : null,
        },
        onConflict: 'user_id,class_id',
      );
    } catch (_) {
      // Keep counting locally; the next scheduled sync can recover.
    } finally {
      _isSyncingAttendance = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_persistAttendance());
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bool isPresent = _secondsElapsed >= _requiredSeconds;
    final double progress = (_secondsElapsed / _requiredSeconds).clamp(
      0.0,
      1.0,
    );

    return Scaffold(
      backgroundColor: AppColors.midnightInk,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildTopBar(),
            _buildAttendanceTracker(isPresent, progress),
            Expanded(child: _buildMainStage()),
            _buildParticipantGrid(),
            _buildControlBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 32,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.session.subject,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Row(
                  children: <Widget>[
                    Icon(Icons.lock, color: Colors.greenAccent, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'End-to-end encrypted',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red),
            ),
            child: const Row(
              children: <Widget>[
                Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                SizedBox(width: 4),
                Text(
                  'REC',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceTracker(bool isPresent, double progress) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPresent
              ? <Color>[
                  AppColors.success.withValues(alpha: 0.22),
                  AppColors.midnightInk,
                ]
              : <Color>[
                  AppColors.warning.withValues(alpha: 0.18),
                  AppColors.midnightInk,
                ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPresent
              ? Colors.green
              : Colors.orangeAccent.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    isPresent ? Icons.check_circle : Icons.timer_outlined,
                    color: isPresent ? Colors.green : Colors.orangeAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    !_attendanceLoaded
                        ? 'Loading attendance record'
                        : isPresent
                            ? 'NSFAS Register: Present'
                            : 'NSFAS Register: In Progress',
                    style: TextStyle(
                      color: isPresent ? Colors.green : Colors.orangeAccent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Text(
                '${_formatDuration(_secondsElapsed)} / '
                '${_formatDuration(_requiredSeconds)} '
                '(${(progress * 100).round()}%)',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade800,
              valueColor: AlwaysStoppedAnimation<Color>(
                isPresent ? Colors.green : Colors.orangeAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainStage() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text(
                  'Module 3: Business Plans',
                  style: TextStyle(
                    color: Color(0xFF0D47A1),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                _bulletPoint('Executive Summary'),
                _bulletPoint('Market Analysis & Strategy'),
                _bulletPoint('Operational Plan'),
                _bulletPoint('Financial Projections'),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.mic, color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.session.lecturer} (Presenting)',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_box, color: Color(0xFF1E88E5), size: 20),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantGrid() {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          _buildParticipantCam('SN', 'Sipho N.', isMuted: true),
          _buildParticipantCam(
            'DK',
            'David K.',
            isMuted: false,
            isSpeaking: true,
          ),
          _buildParticipantCam('LM', 'Lerato M.', isMuted: true),
          _buildParticipantCam('TM', 'Thandi M.', isMuted: true),
        ],
      ),
    );
  }

  Widget _buildParticipantCam(
    String initials,
    String name, {
    bool isMuted = true,
    bool isSpeaking = false,
  }) {
    return Container(
      width: 100,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSpeaking ? Colors.blue : Colors.transparent,
          width: 2,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.blue.shade800,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  isMuted ? Icons.mic_off : Icons.mic,
                  color: isMuted ? Colors.red : Colors.greenAccent,
                  size: 14,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _controlButton(Icons.videocam_off, 'Video', isOff: true),
          _controlButton(Icons.mic_off, 'Mic', isOff: true),
          _controlButton(
            Icons.present_to_all,
            'Share',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Lecturer permission required to share screen.',
                  ),
                ),
              );
            },
          ),
          _controlButton(Icons.chat_bubble_outline, 'Chat', badge: '3'),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text(
                'Leave',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton(
    IconData icon,
    String label, {
    bool isOff = false,
    String? badge,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isOff ? Colors.white24 : const Color(0xFF2C2C2C),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              if (badge != null)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
