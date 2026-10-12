import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'package:og_vibes_student/models/live_session.dart';
import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:og_vibes_student/utils/youtube_url.dart';

class LiveClassroomScreen extends StatefulWidget {
  const LiveClassroomScreen({super.key, required this.session});

  final LiveSession session;

  @override
  State<LiveClassroomScreen> createState() => _LiveClassroomScreenState();
}

class _LiveClassroomScreenState extends State<LiveClassroomScreen>
    with WidgetsBindingObserver {
  late final YoutubePlayerController _player;
  StreamSubscription<YoutubePlayerValue>? _videoSubscription;
  Timer? _attendanceTimer;
  int _secondsElapsed = 0;
  bool _attendanceLoaded = false;
  bool _isPlaying = false;
  bool _isForeground = true;
  bool _isSyncing = false;

  int get _requiredSeconds => widget.session.requiredAttendanceSeconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final videoId = youtubeVideoId(widget.session.youtubeUrl)!;
    _player = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: widget.session.isLive,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        enableCaption: true,
        strictRelatedVideos: true,
      ),
    );
    _videoSubscription = _player.listen((state) {
      _isPlaying = state.playerState == PlayerState.playing;
    });
    _loadAttendance();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
  }

  Future<void> _loadAttendance() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final row = await Supabase.instance.client
            .from('online_class_attendance')
            .select('seconds_attended')
            .eq('class_id', widget.session.id)
            .eq('user_id', user.id)
            .maybeSingle();
        _secondsElapsed = int.tryParse('${row?['seconds_attended'] ?? 0}') ?? 0;
      } catch (_) {
        // A later sync retries without interrupting playback.
      }
    }
    if (!mounted) return;
    setState(() => _attendanceLoaded = true);
    _attendanceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPlaying || !_isForeground || !mounted) return;
      setState(() => _secondsElapsed++);
      if (_secondsElapsed % 15 == 0) unawaited(_persistAttendance());
    });
  }

  Future<void> _persistAttendance() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _isSyncing) return;
    _isSyncing = true;
    try {
      await Supabase.instance.client
          .from('online_class_attendance')
          .upsert(<String, dynamic>{
            'user_id': user.id,
            'class_id': widget.session.id,
            'seconds_attended': _secondsElapsed,
            'required_seconds': _requiredSeconds,
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
            'completed_at': _secondsElapsed >= _requiredSeconds
                ? DateTime.now().toUtc().toIso8601String()
                : null,
          }, onConflict: 'user_id,class_id');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _openInYoutube() async {
    final uri = Uri.parse(widget.session.youtubeUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attendanceTimer?.cancel();
    _videoSubscription?.cancel();
    unawaited(_persistAttendance());
    _player.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_secondsElapsed / _requiredSeconds).clamp(0.0, 1.0);
    final complete = progress >= 1;
    return Scaffold(
      backgroundColor: AppColors.midnightInk,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.session.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.session.isLive ? 'LIVE ON YOUTUBE' : 'YOUTUBE CLASS',
              style: TextStyle(
                color: widget.session.isLive
                    ? Colors.redAccent
                    : Colors.white60,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _openInYoutube,
            icon: const Icon(Icons.open_in_new_rounded),
            tooltip: 'Open in YouTube',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: YoutubePlayer(controller: _player),
            ),
          ),
          const SizedBox(height: 18),
          _infoCard(),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: .13)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      complete ? Icons.verified_rounded : Icons.timer_outlined,
                      color: complete ? AppColors.success : AppColors.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        !_attendanceLoaded
                            ? 'Loading attendance'
                            : complete
                            ? 'Attendance requirement completed'
                            : _isPlaying
                            ? 'Attendance is being recorded'
                            : 'Play the class to record attendance',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(20),
                  backgroundColor: Colors.white12,
                  color: complete ? AppColors.success : AppColors.vibeBlue,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_format(_secondsElapsed)} watched • ${_format(_requiredSeconds)} required',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Attendance increases only while this YouTube video is playing and OG Vibes is in the foreground.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            AppColors.vibeBlue.withValues(alpha: .32),
            const Color(0xFF6B3DF5).withValues(alpha: .18),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.session.topic,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: <Widget>[
              _meta(Icons.menu_book_rounded, widget.session.module),
              _meta(Icons.person_rounded, widget.session.lecturer),
              _meta(Icons.schedule_rounded, widget.session.time),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(icon, size: 16, color: Colors.white70),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  String _format(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }
}
