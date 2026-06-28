import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'live_classroom_screen.dart';
import 'package:og_vibes_student/models/live_session.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class OnlineClassesScreen extends StatefulWidget {
  const OnlineClassesScreen({super.key});

  @override
  State<OnlineClassesScreen> createState() => _OnlineClassesScreenState();
}

class _OnlineClassesScreenState extends State<OnlineClassesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<_OnlineClassSession> _sessions = [];
  StreamSubscription<List<Map<String, dynamic>>>? _sessionSubscription;

  String _selectedModule = 'All';
  bool _reminderSet = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSessions();
    _listenForSessionChanges();
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final raw = await Supabase.instance.client
          .from('online_classes')
          .select(
            'id, module, subject, topic, scheduled_at, status, lecturer, url, resource_title, resource_url, recording_url, duration_minutes, created_at',
          )
          .order('scheduled_at', ascending: true);

      final rows = List<Map<String, dynamic>>.from(raw as List<dynamic>? ?? []);
      final sessions = rows.map(_OnlineClassSession.fromRow).toList();

      if (!mounted) return;
      setState(() {
        _sessions
          ..clear()
          ..addAll(sessions);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  void _listenForSessionChanges() {
    _sessionSubscription = Supabase.instance.client
        .from('online_classes')
        .stream(primaryKey: ['id'])
        .listen((rows) {
      if (!mounted) return;
      setState(() {
        _sessions
          ..clear()
          ..addAll(rows.map((row) => _OnlineClassSession.fromRow(Map<String, dynamic>.from(row))));
        _isLoading = false;
        _errorMessage = null;
      });
    }, onError: (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    });
  }

  List<String> get _availableModules {
    final modules = _sessions
        .map((session) => session.module)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    modules.sort();
    return <String>['All', ...modules];
  }

  List<_OnlineClassSession> get _visibleSessions {
    final selectedModule = _selectedModule;
    return _sessions.where((session) {
      if (selectedModule == 'All') return true;
      return session.module == selectedModule;
    }).toList();
  }

  List<_OnlineClassSession> get _liveSessions => _visibleSessions.where((session) => session.status == 'live').toList();
  List<_OnlineClassSession> get _upcomingSessions => _visibleSessions.where((session) => session.status == 'upcoming').toList();
  List<_OnlineClassSession> get _recordingSessions => _visibleSessions.where((session) => session.status == 'recording').toList();

  Future<void> _refreshSessions() async {
    await _loadSessions();
  }

  Future<void> _openLink(String? link) async {
    if (link == null || link.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No link available for this item.')),
      );
      return;
    }

    final uri = Uri.tryParse(link);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid URL.')),
      );
      return;
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the link.')),
      );
    }
  }

  LiveSession _buildLiveSession(_OnlineClassSession session) {
    return LiveSession(
      subject: session.subject,
      topic: session.topic,
      time: session.scheduledAtFormatted,
      isLive: session.status == 'live',
      lecturer: session.lecturer,
    );
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Online Classes'),
        actions: [
          IconButton(
            onPressed: _refreshSessions,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh sessions',
          ),
        ],
      ),
      body: _isLoading && _sessions.isEmpty
          ? _buildLoadingState()
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null && _sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
              const SizedBox(height: 16),
              const Text(
                'Could not load online classes.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Try again later.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _refreshSessions,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        _buildTopBanner(),
        _buildModuleFilterRow(),
        const SizedBox(height: 10),
        _buildTabBar(),
        const SizedBox(height: 10),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: <Widget>[
              _buildLiveNowTab(),
              _buildUpcomingTab(),
              _buildRecordingsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModuleFilterRow() {
    final modules = _availableModules;
    return SizedBox(
      height: 54,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: modules.length,
        separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final module = modules[index];
          final selected = module == _selectedModule;
          return ChoiceChip(
            label: Text(module),
            selected: selected,
            onSelected: (_) => setState(() => _selectedModule = module),
            selectedColor: const Color(0xFF1565C0),
            backgroundColor: Colors.white,
            side: BorderSide(
              color: selected ? Colors.transparent : const Color(0xFFE0E0E0),
            ),
            labelStyle: TextStyle(
              color: selected ? Colors.white : const Color(0xFF263238),
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Online Classes',
                  style: TextStyle(
                    color: Color(0xFF102027),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_sessions.length} sessions · ${_liveSessions.length} live now',
                  style: const TextStyle(
                    color: Color(0xFF546E7A),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      labelColor: const Color(0xFF0D47A1),
      unselectedLabelColor: const Color(0xFF546E7A),
      indicatorColor: const Color(0xFF0D47A1),
      tabs: const <Tab>[
        Tab(text: 'Live Now'),
        Tab(text: 'Upcoming'),
        Tab(text: 'Recordings'),
      ],
    );
  }

  Widget _buildLiveNowTab() {
    final sessions = _liveSessions;
    if (sessions.isEmpty) {
      return _buildEmptyTab('No live classes are currently available.');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
      itemCount: sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _buildLiveCard(session);
      },
    );
  }

  Widget _buildUpcomingTab() {
    final sessions = _upcomingSessions;
    if (sessions.isEmpty) {
      return _buildEmptyTab('No upcoming online classes found.');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
      itemCount: sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _buildUpcomingCard(session);
      },
    );
  }

  Widget _buildRecordingsTab() {
    final sessions = _recordingSessions;
    if (sessions.isEmpty) {
      return _buildEmptyTab('No recordings available yet.');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
      itemCount: sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _buildRecordingCard(session);
      },
    );
  }

  Widget _buildLiveCard(_OnlineClassSession session) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'LIVE: ${session.subject}',
            style: const TextStyle(
              color: Color(0xFFB71C1C),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Topic: ${session.topic}',
            style: const TextStyle(
              color: Color(0xFF455A64),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Lecturer: ${session.lecturer}',
            style: const TextStyle(color: Color(0xFF455A64), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFB74D)),
            ),
            child: const Text(
              'DHET Rule: 30-Min Minimum Attendance Required',
              style: TextStyle(
                color: Color(0xFFE65100),
                fontWeight: FontWeight.w800,
                fontSize: 12.8,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute<Widget>(
                  builder: (_) => LiveClassroomScreen(session: _buildLiveSession(session)),
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.play_circle_fill_rounded),
              label: const Text(
                'Join Class',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingCard(_OnlineClassSession session) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${session.subject} • ${session.module}',
                      style: const TextStyle(
                        color: Color(0xFF102027),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.scheduledAtFormatted,
                      style: const TextStyle(
                        color: Color(0xFF546E7A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _toggleReminder,
                icon: Icon(
                  _reminderSet ? Icons.notifications_active : Icons.notifications_none,
                  color: _reminderSet ? const Color(0xFFF9A825) : const Color(0xFF607D8B),
                ),
              ),
            ],
          ),
          if (session.resourceTitle != null) ...[
            const SizedBox(height: 14),
            const Text(
              'Pre-Class Materials',
              style: TextStyle(
                color: Color(0xFF263238),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Color(0xFFD32F2F),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      session.resourceTitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF37474F),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _openLink(session.resourceUrl),
                    icon: const Icon(Icons.download_rounded),
                    tooltip: 'Open material',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordingCard(_OnlineClassSession session) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            session.subject,
            style: const TextStyle(
              color: Color(0xFF102027),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Recorded on ${session.scheduledAtFormatted} • ${session.durationMinutes ?? 'Unknown'} mins',
            style: const TextStyle(
              color: Color(0xFF546E7A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openLink(session.recordingUrl),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text(
                'Watch Recording',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleReminder() {
    setState(() {
      _reminderSet = !_reminderSet;
    });

    if (_reminderSet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder set! We will notify you 15 minutes before class.'),
        ),
      );
    }
  }

  Widget _buildEmptyTab(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF546E7A), fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE3E7EE)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              height: 118,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 4,
                separatorBuilder: (BuildContext context, int index) {
                  return const SizedBox(width: 8);
                },
                itemBuilder: (BuildContext context, int index) {
                  return Container(
                    width: 110,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineClassSession {
  const _OnlineClassSession({
    required this.id,
    required this.module,
    required this.subject,
    required this.topic,
    required this.scheduledAt,
    required this.status,
    required this.lecturer,
    required this.url,
    this.resourceTitle,
    this.resourceUrl,
    this.recordingUrl,
    this.durationMinutes,
  });

  final String id;
  final String module;
  final String subject;
  final String topic;
  final DateTime? scheduledAt;
  final String status;
  final String lecturer;
  final String url;
  final String? resourceTitle;
  final String? resourceUrl;
  final String? recordingUrl;
  final int? durationMinutes;

  String get scheduledAtFormatted {
    if (scheduledAt == null) return 'TBA';
    return '${scheduledAt!.day.toString().padLeft(2, '0')}/${scheduledAt!.month.toString().padLeft(2, '0')} ${scheduledAt!.hour.toString().padLeft(2, '0')}:${scheduledAt!.minute.toString().padLeft(2, '0')}';
  }

  factory _OnlineClassSession.fromRow(Map<String, dynamic> row) {
    final scheduledAtValue = row['scheduled_at'];
    DateTime? scheduledAt;
    if (scheduledAtValue is String) {
      scheduledAt = DateTime.tryParse(scheduledAtValue);
    } else if (scheduledAtValue is DateTime) {
      scheduledAt = scheduledAtValue;
    }

    return _OnlineClassSession(
      id: (row['id'] ?? '').toString(),
      module: (row['module'] ?? 'General').toString().trim(),
      subject: (row['subject'] ?? 'Untitled Class').toString().trim(),
      topic: (row['topic'] ?? 'No topic').toString().trim(),
      scheduledAt: scheduledAt,
      status: (row['status'] ?? 'upcoming').toString().trim().toLowerCase(),
      lecturer: (row['lecturer'] ?? 'Staff').toString().trim(),
      url: (row['url'] ?? '').toString().trim(),
      resourceTitle: row['resource_title']?.toString().trim(),
      resourceUrl: row['resource_url']?.toString().trim(),
      recordingUrl: row['recording_url']?.toString().trim(),
      durationMinutes: row['duration_minutes'] is int ? row['duration_minutes'] as int : int.tryParse((row['duration_minutes'] ?? '').toString()),
    );
  }
}
