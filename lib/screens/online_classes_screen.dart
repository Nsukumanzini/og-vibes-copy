import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:og_vibes_student/models/live_session.dart';
import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

import 'live_classroom_screen.dart';

class OnlineClassesScreen extends StatefulWidget {
  const OnlineClassesScreen({super.key});

  @override
  State<OnlineClassesScreen> createState() => _OnlineClassesScreenState();
}

class _OnlineClassesScreenState extends State<OnlineClassesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<_OnlineClassSession> _sessions = <_OnlineClassSession>[];
  final Map<String, _LecturerProfile> _lecturers =
      <String, _LecturerProfile>{};
  final Map<String, int> _reminders = <String, int>{};
  final Set<String> _registeredModules = <String>{};
  final Set<String> _reviewedResources = <String>{};
  final Set<String> _deviceReady = <String>{};

  StreamSubscription<List<Map<String, dynamic>>>? _sessionSubscription;
  Timer? _clock;
  String _selectedModule = 'All';
  String _selectedLecturer = 'All';
  String _selectedDate = 'Any date';
  String _selectedStatus = 'All';
  bool _myModulesOnly = true;
  bool _hasRegistrationMatch = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          HapticFeedback.selectionClick();
        }
      });
    _loadInitialData();
    _listenForSessionChanges();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _sessionSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await Future.wait(<Future<void>>[
        _loadAcademicContext(),
        _loadReminders(),
      ]);
      await _loadSessions();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _loadSessions() async {
    final raw = await Supabase.instance.client
        .from('online_classes')
        .select(
          'id, module, subject, topic, scheduled_at, status, lecturer, url, '
          'resource_title, resource_url, recording_url, duration_minutes, '
          'created_at',
        )
        .order('scheduled_at', ascending: true);
    final rows = List<Map<String, dynamic>>.from(raw as List<dynamic>? ?? []);
    if (!mounted) return;
    setState(() {
      _sessions
        ..clear()
        ..addAll(rows.map(_OnlineClassSession.fromRow));
      _isLoading = false;
      _errorMessage = null;
    });
  }

  Future<void> _loadAcademicContext() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      Supabase.instance.client
          .from('profiles')
          .select('department, level')
          .eq('id', user.id)
          .maybeSingle(),
      Supabase.instance.client.from('programmes').select('id, name'),
      Supabase.instance.client
          .from('modules')
          .select('id, programme_id, level, name, code'),
      Supabase.instance.client.from('module_lecturers').select(
            'module_id, profiles!module_lecturers_lecturer_id_fkey('
            'name, surname, photo_url, is_verified)',
          ),
    ]);

    final profile = results[0] is Map
        ? Map<String, dynamic>.from(results[0] as Map)
        : <String, dynamic>{};
    final programmes =
        List<Map<String, dynamic>>.from(results[1] as List<dynamic>? ?? []);
    final modules =
        List<Map<String, dynamic>>.from(results[2] as List<dynamic>? ?? []);
    final lecturerRows =
        List<Map<String, dynamic>>.from(results[3] as List<dynamic>? ?? []);

    final department = _normalized(profile['department']);
    final level = _normalized(profile['level']);
    final matchingProgrammeIds = programmes.where((programme) {
      final name = _normalized(programme['name']);
      return department.isNotEmpty &&
          (name.contains(department) || department.contains(name));
    }).map((programme) => programme['id']?.toString() ?? '').toSet();

    final lecturerByModuleId = <String, _LecturerProfile>{};
    for (final row in lecturerRows) {
      final profileRow = row['profiles'] is Map
          ? Map<String, dynamic>.from(row['profiles'] as Map)
          : <String, dynamic>{};
      final fullName = <String>[
        _clean(profileRow['name']),
        _clean(profileRow['surname']),
      ].where((part) => part.isNotEmpty).join(' ');
      if (fullName.isEmpty) continue;
      lecturerByModuleId[row['module_id']?.toString() ?? ''] =
          _LecturerProfile(
        name: fullName,
        photoUrl: _clean(profileRow['photo_url']),
        verified: profileRow['is_verified'] == true,
      );
    }

    _registeredModules.clear();
    _lecturers.clear();
    for (final module in modules) {
      final moduleId = module['id']?.toString() ?? '';
      final name = _clean(module['name']);
      final code = _clean(module['code']);
      final moduleLevel = _normalized(module['level']);
      final belongsToStudent =
          matchingProgrammeIds.contains(module['programme_id']?.toString()) &&
              (level.isEmpty ||
                  moduleLevel == level ||
                  moduleLevel.contains(level) ||
                  level.contains(moduleLevel));
      if (belongsToStudent) {
        if (name.isNotEmpty) _registeredModules.add(_normalized(name));
        if (code.isNotEmpty) _registeredModules.add(_normalized(code));
      }
      final lecturer = lecturerByModuleId[moduleId];
      if (lecturer != null) {
        if (name.isNotEmpty) _lecturers[_normalized(name)] = lecturer;
        if (code.isNotEmpty) _lecturers[_normalized(code)] = lecturer;
      }
    }
    _hasRegistrationMatch = _registeredModules.isNotEmpty;
    if (!_hasRegistrationMatch) _myModulesOnly = false;
  }

  Future<void> _loadReminders() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final raw = await Supabase.instance.client
        .from('online_class_reminders')
        .select('class_id, remind_minutes, enabled')
        .eq('enabled', true);
    _reminders
      ..clear()
      ..addEntries(
        List<Map<String, dynamic>>.from(raw as List<dynamic>? ?? [])
            .map((row) => MapEntry<String, int>(
                  row['class_id']?.toString() ?? '',
                  int.tryParse(row['remind_minutes'].toString()) ?? 15,
                ))
            .where((entry) => entry.key.isNotEmpty),
      );
  }

  void _listenForSessionChanges() {
    _sessionSubscription = Supabase.instance.client
        .from('online_classes')
        .stream(primaryKey: <String>['id'])
        .listen((rows) {
      if (!mounted) return;
      setState(() {
        _sessions
          ..clear()
          ..addAll(rows.map(_OnlineClassSession.fromRow))
          ..sort((a, b) {
            if (a.scheduledAt == null) return 1;
            if (b.scheduledAt == null) return -1;
            return a.scheduledAt!.compareTo(b.scheduledAt!);
          });
        _isLoading = false;
        _errorMessage = null;
      });
    }, onError: (Object error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    });
  }

  bool _isRegistered(_OnlineClassSession session) {
    if (!_hasRegistrationMatch) return true;
    final module = _normalized(session.module);
    final subject = _normalized(session.subject);
    return _registeredModules.any(
      (registered) =>
          registered == module ||
          registered == subject ||
          module.contains(registered) ||
          subject.contains(registered),
    );
  }

  _LecturerProfile _lecturerFor(_OnlineClassSession session) {
    final module = _normalized(session.module);
    final subject = _normalized(session.subject);
    return _lecturers[module] ??
        _lecturers[subject] ??
        _LecturerProfile(name: session.lecturer);
  }

  List<_OnlineClassSession> get _visibleSessions {
    return _sessions.where((session) {
      if (_myModulesOnly && !_isRegistered(session)) return false;
      if (_selectedModule != 'All' && session.module != _selectedModule) {
        return false;
      }
      final lecturer = _lecturerFor(session).name;
      if (_selectedLecturer != 'All' && lecturer != _selectedLecturer) {
        return false;
      }
      if (_selectedStatus != 'All' && session.status != _selectedStatus) {
        return false;
      }
      final date = session.scheduledAt?.toLocal();
      final now = DateTime.now();
      if (_selectedDate == 'Today' &&
          (date == null ||
              date.year != now.year ||
              date.month != now.month ||
              date.day != now.day)) {
        return false;
      }
      if (_selectedDate == 'Next 7 days' &&
          (date == null ||
              date.isBefore(now) ||
              date.isAfter(now.add(const Duration(days: 7))))) {
        return false;
      }
      return true;
    }).toList();
  }

  List<_OnlineClassSession> get _liveSessions =>
      _visibleSessions.where((session) => session.isLive).toList();
  List<_OnlineClassSession> get _upcomingSessions =>
      _visibleSessions.where((session) => session.isUpcoming).toList();
  List<_OnlineClassSession> get _recordingSessions => _visibleSessions
      .where((session) => session.isRecording)
      .toList()
      .reversed
      .toList();

  _OnlineClassSession? get _nextSession {
    final now = DateTime.now();
    final upcoming = _sessions
        .where(
          (session) =>
              session.scheduledAt != null &&
              session.scheduledAt!.toLocal().isAfter(now) &&
              (!_myModulesOnly || _isRegistered(session)),
        )
        .toList()
      ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  List<String> get _availableModules {
    final values = _sessions
        .where((session) => !_myModulesOnly || _isRegistered(session))
        .map((session) => session.module)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return <String>['All', ...values];
  }

  List<String> get _availableLecturers {
    final values = _sessions
        .where((session) => !_myModulesOnly || _isRegistered(session))
        .map((session) => _lecturerFor(session).name)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return <String>['All', ...values];
  }

  Future<void> _refreshSessions() async {
    HapticFeedback.mediumImpact();
    await _loadInitialData();
  }

  Future<void> _openLink(String? link) async {
    final uri = Uri.tryParse(link ?? '');
    if (uri == null || !uri.hasScheme) {
      _message('No valid link is available for this item.');
      return;
    }
    HapticFeedback.lightImpact();
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _message('Unable to open the link. Please try again.');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  LiveSession _buildLiveSession(_OnlineClassSession session) {
    return LiveSession(
      id: session.id,
      module: session.module,
      subject: session.subject,
      topic: session.topic,
      time: session.scheduledAtFormatted,
      isLive: session.isLive,
      lecturer: _lecturerFor(session).name,
    );
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Online Classes'),
        backgroundColor: Colors.transparent,
        actions: <Widget>[
          IconButton(
            onPressed: _showFilters,
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Filter classes',
          ),
          IconButton(
            onPressed: _refreshSessions,
            icon: const Icon(Icons.refresh_rounded),
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
      return _buildErrorState();
    }
    return Column(
      children: <Widget>[
        Expanded(
          child: NestedScrollView(
            headerSliverBuilder: (_, _) => <Widget>[
              SliverToBoxAdapter(child: _buildHero()),
              if (_liveSessions.isNotEmpty)
                SliverToBoxAdapter(child: _buildLivePulse()),
              SliverToBoxAdapter(child: _buildFilterSummary()),
              SliverToBoxAdapter(child: _buildTabBar()),
            ],
            body: TabBarView(
              controller: _tabController,
              children: <Widget>[
                _buildSessionList(
                  _liveSessions,
                  'No live classes right now.',
                  Icons.podcasts_rounded,
                ),
                _buildSessionList(
                  _upcomingSessions,
                  'No upcoming classes match these filters.',
                  Icons.event_available_rounded,
                ),
                _buildSessionList(
                  _recordingSessions,
                  'No class recordings are available yet.',
                  Icons.video_library_rounded,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    final next = _nextSession;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: AppStyles.brandGradient,
          borderRadius: AppStyles.bentoRadius,
          boxShadow: AppStyles.glassShadow,
        ),
        child: Stack(
          children: <Widget>[
            Positioned(
              right: -26,
              top: -38,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.electricCyan.withValues(alpha: 0.13),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(
                      Icons.cast_for_education_rounded,
                      color: AppColors.electricCyan,
                    ),
                    SizedBox(width: 9),
                    Text(
                      'OG LIVE LEARNING',
                      style: TextStyle(
                        color: AppColors.electricCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your classroom,\nwherever you are.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    _heroStat('${_liveSessions.length}', 'Live', Colors.redAccent),
                    _heroStat(
                      '${_upcomingSessions.length}',
                      'Upcoming',
                      AppColors.ogGold,
                    ),
                    _heroStat(
                      '${_recordingSessions.length}',
                      'Recorded',
                      AppColors.electricCyan,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.timer_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              next == null
                                  ? 'You are all caught up'
                                  : 'Next: ${next.subject}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              next == null
                                  ? 'No upcoming class scheduled'
                                  : _countdown(next.scheduledAt!),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 420.ms).slideY(begin: 0.06, end: 0);
  }

  Widget _heroStat(String value, String label, Color color) {
    return Expanded(
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white60, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLivePulse() {
    final session = _liveSessions.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _joinClass(session),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFFD52B45), Color(0xFFF45B69)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.danger.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              )
                  .animate(onPlay: (controller) => controller.repeat())
                  .fadeOut(duration: 850.ms)
                  .scaleXY(begin: 0.75, end: 1.35),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'LIVE NOW  •  ${session.subject}: ${session.topic}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSummary() {
    final filterCount = <bool>[
      _selectedModule != 'All',
      _selectedLecturer != 'All',
      _selectedDate != 'Any date',
      _selectedStatus != 'All',
    ].where((active) => active).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: _glass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilterChip(
                selected: _myModulesOnly,
                onSelected: _hasRegistrationMatch
                    ? (selected) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _myModulesOnly = selected;
                          _selectedModule = 'All';
                        });
                      }
                    : null,
                avatar: const Icon(Icons.school_rounded, size: 18),
                label: Text(
                  _hasRegistrationMatch
                      ? 'My registered modules'
                      : 'All modules • registration not matched',
                  overflow: TextOverflow.ellipsis,
                ),
                selectedColor:
                    AppColors.vibeBlue.withValues(alpha: 0.14),
                side: BorderSide.none,
              ),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: filterCount > 0,
              label: Text('$filterCount'),
              child: IconButton.filledTonal(
                onPressed: _showFilters,
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'More filters',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _glass(
        padding: const EdgeInsets.all(5),
        child: TabBar(
          controller: _tabController,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            gradient: AppStyles.brandGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
          tabs: <Tab>[
            Tab(text: 'Live ${_liveSessions.length}'),
            Tab(text: 'Upcoming ${_upcomingSessions.length}'),
            Tab(text: 'Recordings ${_recordingSessions.length}'),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionList(
    List<_OnlineClassSession> sessions,
    String emptyText,
    IconData emptyIcon,
  ) {
    if (sessions.isEmpty) return _buildEmptyTab(emptyText, emptyIcon);
    return RefreshIndicator(
      onRefresh: _refreshSessions,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 110),
        itemCount: sessions.length,
        separatorBuilder: (_, _) => const SizedBox(height: 13),
        itemBuilder: (_, index) => _buildSessionCard(sessions[index], index),
      ),
    );
  }

  Widget _buildSessionCard(_OnlineClassSession session, int index) {
    final lecturer = _lecturerFor(session);
    final isLive = session.isLive;
    final isRecording = session.isRecording;
    return _glass(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: isLive
                      ? const LinearGradient(
                          colors: <Color>[
                            AppColors.danger,
                            Color(0xFFFF7585),
                          ],
                        )
                      : AppStyles.brandGradient,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  isLive
                      ? Icons.podcasts_rounded
                      : isRecording
                          ? Icons.play_arrow_rounded
                          : Icons.calendar_month_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            session.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.midnightInk,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _statusPill(session),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.topic,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _metadataPill(Icons.menu_book_rounded, session.module),
              _metadataPill(
                Icons.schedule_rounded,
                session.scheduledAtFormatted,
              ),
              if (session.durationMinutes != null)
                _metadataPill(
                  Icons.timelapse_rounded,
                  '${session.durationMinutes} min',
                ),
            ],
          ),
          const SizedBox(height: 14),
          _lecturerRow(lecturer),
          if (isLive) ...<Widget>[
            const SizedBox(height: 14),
            _attendancePreview(),
          ],
          if (session.isUpcoming) ...<Widget>[
            const SizedBox(height: 14),
            _preClassPanel(session),
          ],
          const SizedBox(height: 15),
          Row(
            children: <Widget>[
              if (session.isUpcoming)
                IconButton.filledTonal(
                  onPressed: () => _configureReminder(session),
                  icon: Icon(
                    _reminders.containsKey(session.id)
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                  ),
                  tooltip: _reminders.containsKey(session.id)
                      ? 'Reminder: ${_reminders[session.id]} minutes'
                      : 'Set reminder',
                ),
              if (session.isUpcoming) const SizedBox(width: 10),
              Expanded(child: _primaryAction(session)),
            ],
          ),
        ],
      ),
    )
        .animate(delay: (45 * index).ms)
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.08, end: 0);
  }

  Widget _statusPill(_OnlineClassSession session) {
    final color = session.isLive
        ? AppColors.danger
        : session.isRecording
            ? AppColors.success
            : AppColors.vibeBlue;
    final text = session.isLive
        ? 'LIVE'
        : session.isRecording
            ? 'RECORDED'
            : 'UPCOMING';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .5,
        ),
      ),
    );
  }

  Widget _metadataPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.vibeBlue.withValues(alpha: 0.06),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: AppColors.vibeBlue),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lecturerRow(_LecturerProfile lecturer) {
    return Row(
      children: <Widget>[
        CircleAvatar(
          radius: 19,
          backgroundColor: AppColors.vibeBlue.withValues(alpha: 0.12),
          backgroundImage:
              lecturer.photoUrl.isEmpty ? null : NetworkImage(lecturer.photoUrl),
          child: lecturer.photoUrl.isEmpty
              ? Text(
                  lecturer.initials,
                  style: const TextStyle(
                    color: AppColors.vibeBlue,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      lecturer.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.midnightInk,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (lecturer.verified) ...<Widget>[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.verified_rounded,
                      color: AppColors.vibeBlue,
                      size: 16,
                    ),
                  ],
                ],
              ),
              const Text(
                'Class lecturer',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _attendancePreview() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.25),
        ),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.timer_outlined, color: AppColors.warning, size: 20),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              '30-minute attendance requirement • live timer and percentage '
              'start when you join',
              style: TextStyle(
                color: Color(0xFF845E00),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preClassPanel(_OnlineClassSession session) {
    final reminder = _reminders[session.id];
    final reviewed = _reviewedResources.contains(session.id);
    final ready = _deviceReady.contains(session.id);
    final done = <bool>[
      reminder != null,
      session.resourceTitle == null || reviewed,
      ready,
    ].where((value) => value).length;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showChecklist(session),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.success.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: <Widget>[
            Stack(
              alignment: Alignment.center,
              children: <Widget>[
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    value: done / 3,
                    strokeWidth: 4,
                    backgroundColor:
                        AppColors.success.withValues(alpha: 0.12),
                    color: AppColors.success,
                  ),
                ),
                Text(
                  '$done/3',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Pre-class checklist',
                    style: TextStyle(
                      color: AppColors.midnightInk,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    session.resourceTitle ?? 'Reminder • device check • ready',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _primaryAction(_OnlineClassSession session) {
    if (session.isLive) {
      return FilledButton.icon(
        onPressed: () => _joinClass(session),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.danger,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.play_circle_fill_rounded),
        label: const Text(
          'Join live class',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      );
    }
    if (session.isRecording) {
      return FilledButton.tonalIcon(
        onPressed: () => _openLink(session.recordingUrl),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text(
          'Watch recording',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: () => _showChecklist(session),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.vibeBlue,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      icon: const Icon(Icons.fact_check_outlined),
      label: Text(
        'Starts ${_countdown(session.scheduledAt)}',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }

  void _joinClass(_OnlineClassSession session) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute<Widget>(
        builder: (_) => LiveClassroomScreen(
          session: _buildLiveSession(session),
        ),
      ),
    );
  }

  Future<void> _configureReminder(_OnlineClassSession session) async {
    HapticFeedback.selectionClick();
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAFF),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Class reminder',
                style: TextStyle(
                  color: AppColors.midnightInk,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                session.subject,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              for (final minutes in <int>[5, 10, 15, 30, 60])
                RadioListTile<int>(
                  value: minutes,
                  groupValue: _reminders[session.id],
                  onChanged: (value) => Navigator.pop(context, value),
                  title: Text('$minutes minutes before'),
                ),
              if (_reminders.containsKey(session.id))
                ListTile(
                  leading: const Icon(
                    Icons.notifications_off_outlined,
                    color: AppColors.danger,
                  ),
                  title: const Text('Remove reminder'),
                  onTap: () => Navigator.pop(context, 0),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _message('Please sign in to manage reminders.');
      return;
    }
    try {
      if (choice == 0) {
        await Supabase.instance.client
            .from('online_class_reminders')
            .delete()
            .eq('class_id', session.id);
        if (mounted) setState(() => _reminders.remove(session.id));
        _message('Class reminder removed.');
      } else {
        await Supabase.instance.client.from('online_class_reminders').upsert(
          <String, dynamic>{
            'user_id': user.id,
            'class_id': session.id,
            'remind_minutes': choice,
            'enabled': true,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'user_id,class_id',
        );
        if (mounted) setState(() => _reminders[session.id] = choice);
        _message('Reminder set for $choice minutes before class.');
      }
      HapticFeedback.mediumImpact();
    } catch (_) {
      _message('The reminder could not be saved. Please try again.');
    }
  }

  Future<void> _showChecklist(_OnlineClassSession session) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8FAFF),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void update(VoidCallback change) {
            change();
            setSheetState(() {});
            setState(() {});
            HapticFeedback.selectionClick();
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    session.subject,
                    style: const TextStyle(
                      color: AppColors.midnightInk,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Get ready • ${_countdown(session.scheduledAt)}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: _reminders.containsKey(session.id),
                    onChanged: (_) {
                      Navigator.pop(context);
                      _configureReminder(session);
                    },
                    title: const Text('Class reminder set'),
                    subtitle: Text(
                      _reminders.containsKey(session.id)
                          ? '${_reminders[session.id]} minutes before'
                          : 'Tap to choose a reminder time',
                    ),
                  ),
                  CheckboxListTile(
                    value: session.resourceTitle == null ||
                        _reviewedResources.contains(session.id),
                    onChanged: session.resourceTitle == null
                        ? null
                        : (checked) => update(() {
                              if (checked == true) {
                                _reviewedResources.add(session.id);
                              } else {
                                _reviewedResources.remove(session.id);
                              }
                            }),
                    title: Text(
                      session.resourceTitle == null
                          ? 'No pre-class material required'
                          : 'Review ${session.resourceTitle}',
                    ),
                    secondary: session.resourceUrl == null
                        ? null
                        : IconButton(
                            onPressed: () => _openLink(session.resourceUrl),
                            icon: const Icon(Icons.open_in_new_rounded),
                          ),
                  ),
                  CheckboxListTile(
                    value: _deviceReady.contains(session.id),
                    onChanged: (checked) => update(() {
                      if (checked == true) {
                        _deviceReady.add(session.id);
                      } else {
                        _deviceReady.remove(session.id);
                      }
                    }),
                    title: const Text('Camera, audio and connection checked'),
                    subtitle: const Text('Use headphones where possible'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showFilters() async {
    HapticFeedback.selectionClick();
    var module = _selectedModule;
    var lecturer = _selectedLecturer;
    var date = _selectedDate;
    var status = _selectedStatus;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAFF),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Filter online classes',
                  style: TextStyle(
                    color: AppColors.midnightInk,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue:
                      _availableModules.contains(module) ? module : 'All',
                  decoration: const InputDecoration(
                    labelText: 'Module',
                    prefixIcon: Icon(Icons.menu_book_rounded),
                  ),
                  items: _availableModules
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setSheetState(() => module = value ?? 'All'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _availableLecturers.contains(lecturer)
                      ? lecturer
                      : 'All',
                  decoration: const InputDecoration(
                    labelText: 'Lecturer',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  items: _availableLecturers
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setSheetState(() => lecturer = value ?? 'All'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: date,
                        decoration: const InputDecoration(labelText: 'Date'),
                        items: <String>['Any date', 'Today', 'Next 7 days']
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setSheetState(() => date = value ?? 'Any date'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(value: 'All', child: Text('All')),
                          DropdownMenuItem(value: 'live', child: Text('Live')),
                          DropdownMenuItem(
                            value: 'upcoming',
                            child: Text('Upcoming'),
                          ),
                          DropdownMenuItem(
                            value: 'recording',
                            child: Text('Recorded'),
                          ),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => status = value ?? 'All'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedModule = module;
                      _selectedLecturer = lecturer;
                      _selectedDate = date;
                      _selectedStatus = status;
                    });
                    if (status == 'live') _tabController.animateTo(0);
                    if (status == 'upcoming') _tabController.animateTo(1);
                    if (status == 'recording') _tabController.animateTo(2);
                    Navigator.pop(context);
                    HapticFeedback.mediumImpact();
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Apply filters'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedModule = 'All';
                      _selectedLecturer = 'All';
                      _selectedDate = 'Any date';
                      _selectedStatus = 'All';
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Clear all filters'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _glass({
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) {
    return ClipRRect(
      borderRadius: AppStyles.controlRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: AppStyles.controlRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
            boxShadow: AppStyles.softShadow,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildEmptyTab(String text, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.vibeBlue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.vibeBlue, size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _glass(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.cloud_off_rounded,
                size: 52,
                color: AppColors.danger,
              ),
              const SizedBox(height: 14),
              const Text(
                'Classes are temporarily unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.midnightInk,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _refreshSessions,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
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
              height: 250,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppStyles.bentoRadius,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppStyles.controlRadius,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 260,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppStyles.controlRadius,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _countdown(DateTime? value) {
    if (value == null) return 'TBA';
    final difference = value.toLocal().difference(DateTime.now());
    if (difference.isNegative) return 'soon';
    if (difference.inDays > 0) {
      return 'in ${difference.inDays}d ${difference.inHours % 24}h';
    }
    if (difference.inHours > 0) {
      return 'in ${difference.inHours}h ${difference.inMinutes % 60}m';
    }
    return 'in ${difference.inMinutes}m ${difference.inSeconds % 60}s';
  }

  String _clean(dynamic value) => value?.toString().trim() ?? '';

  String _normalized(dynamic value) =>
      _clean(value).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
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

  bool get isLive => status == 'live';
  bool get isUpcoming => status == 'upcoming';
  bool get isRecording => status == 'recording' || status == 'recorded';

  String get scheduledAtFormatted {
    if (scheduledAt == null) return 'TBA';
    final local = scheduledAt!.toLocal();
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${local.day} ${months[local.month - 1]} • '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  factory _OnlineClassSession.fromRow(Map<String, dynamic> row) {
    final rawDate = row['scheduled_at'];
    final date = rawDate is DateTime
        ? rawDate
        : DateTime.tryParse(rawDate?.toString() ?? '');
    String? optional(dynamic value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    return _OnlineClassSession(
      id: row['id']?.toString() ?? '',
      module: optional(row['module']) ?? 'General',
      subject: optional(row['subject']) ?? 'Untitled class',
      topic: optional(row['topic']) ?? 'Topic to be announced',
      scheduledAt: date,
      status: (optional(row['status']) ?? 'upcoming').toLowerCase(),
      lecturer: optional(row['lecturer']) ?? 'Course team',
      url: optional(row['url']) ?? '',
      resourceTitle: optional(row['resource_title']),
      resourceUrl: optional(row['resource_url']),
      recordingUrl: optional(row['recording_url']),
      durationMinutes: row['duration_minutes'] is int
          ? row['duration_minutes'] as int
          : int.tryParse(row['duration_minutes']?.toString() ?? ''),
    );
  }
}

class _LecturerProfile {
  const _LecturerProfile({
    required this.name,
    this.photoUrl = '',
    this.verified = false,
  });

  final String name;
  final String photoUrl;
  final bool verified;

  String get initials {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'OG';
    return parts.map((part) => part[0].toUpperCase()).join();
  }
}
