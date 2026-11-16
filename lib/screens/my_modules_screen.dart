import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/offline_cache_service.dart';

import 'assessments_calendar_screen.dart';
import 'online_classes_screen.dart';
import 'quiz_screen.dart';
import 'slides_screen.dart';

class MyModulesScreen extends StatefulWidget {
  const MyModulesScreen({
    super.key,
    this.initialToken,
    this.highlightInvitationId,
  });

  final String? initialToken;
  final String? highlightInvitationId;

  @override
  State<MyModulesScreen> createState() => _MyModulesScreenState();
}

class _MyModulesScreenState extends State<MyModulesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  RealtimeChannel? _invitationChannel;
  bool _loading = true;
  bool _responding = false;
  String? _error;
  List<_ModuleRegistration> _active = const [];
  List<_ModuleRegistration> _completed = const [];
  List<_ModuleInvitation> _invitations = const [];
  _ModuleInvitationPreview? _linkPreview;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    if (widget.initialToken != null || widget.highlightInvitationId != null) {
      _tabs.index = 1;
    }
    unawaited(_load());
    _listenForInvitations();
  }

  void _listenForInvitations() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    _invitationChannel = _client.channel('module-invitations-$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'module_invitations',
        callback: (_) => unawaited(_load(silent: true)),
      )
      ..subscribe();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        throw const AuthException('Sign in to view your modules.');
      }
      List<dynamic> results;
      try {
        results = await Future.wait<dynamic>([
        _client
            .from('student_module_registrations')
            .select('''
              student_id, module_id, academic_year, semester, status, registered_at,
              modules!student_module_registrations_module_id_fkey(
                id, name, code, level,
                programmes!modules_programme_id_fkey(name),
                module_lecturers(lecturer_id, profiles!module_lecturers_lecturer_id_fkey(name, surname, nickname, photo_url))
              )
            ''')
            .eq('student_id', user.id)
            .order('registered_at', ascending: false)
            .limit(30),
        _client
            .from('module_invitations')
            .select('''
              id, module_id, lecturer_id, invited_email, academic_year, semester,
              status, expires_at, created_at,
              modules!module_invitations_module_id_fkey(name, code, level, programmes!modules_programme_id_fkey(name)),
              profiles!module_invitations_lecturer_id_fkey(name, surname, nickname, photo_url)
            ''')
            .order('created_at', ascending: false)
            .limit(30),
        ]);
        unawaited(
          OfflineCacheService.writeList(
            'my_modules',
            <Map<String, dynamic>>[{'results': results}],
            maxRecords: 1,
          ),
        );
      } catch (_) {
        final cached = await OfflineCacheService.readList('my_modules');
        if (cached.isEmpty || cached.first['results'] is! List) rethrow;
        results = List<dynamic>.from(cached.first['results'] as List);
      }
      final registrations = List<Map<String, dynamic>>.from(results[0] as List);
      final invitationRows = List<Map<String, dynamic>>.from(
        results[1] as List,
      );
      final parsedRegistrations = registrations
          .map(_ModuleRegistration.fromRow)
          .toList();
      _ModuleInvitationPreview? preview;
      if (widget.initialToken?.isNotEmpty == true) {
        final response = await _client.rpc(
          'preview_module_invitation',
          params: {'invitation_token': widget.initialToken},
        );
        final rows = List<Map<String, dynamic>>.from(
          response as List? ?? const [],
        );
        if (rows.isEmpty) {
          throw const PostgrestException(
            message:
                'This invitation link is invalid, expired, or belongs to another student.',
          );
        }
        preview = _ModuleInvitationPreview.fromRow(rows.first);
      }
      if (!mounted) return;
      setState(() {
        _active = parsedRegistrations
            .where((item) => item.status == 'active')
            .toList();
        _completed = parsedRegistrations
            .where((item) => item.status != 'active')
            .toList();
        _invitations = invitationRows.map(_ModuleInvitation.fromRow).toList();
        _linkPreview = preview;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _accept({_ModuleInvitation? invitation, String? token}) async {
    setState(() => _responding = true);
    try {
      await _client.rpc(
        'accept_module_invitation',
        params: {'invitation_id': invitation?.id, 'invitation_token': token},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${invitation?.moduleName ?? _linkPreview?.moduleName ?? 'Module'} added to My Modules.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _linkPreview = null;
      await _load(silent: true);
      _tabs.animateTo(0);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(error)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  Future<void> _decline(_ModuleInvitation invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline invitation?'),
        content: Text(
          'You will not be registered for ${invitation.moduleName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _responding = true);
    try {
      await _client.rpc(
        'decline_module_invitation',
        params: {'invitation_id': invitation.id},
      );
      await _load(silent: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    if (_invitationChannel != null) {
      unawaited(_client.removeChannel(_invitationChannel!));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FF),
      body: Stack(
        children: [
          const Positioned.fill(child: _AuroraBackground()),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                _buildTabs(),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : TabBarView(
                          controller: _tabs,
                          children: [
                            _RegistrationList(
                              items: _active,
                              emptyTitle: 'No active modules',
                              emptyBody:
                                  'Accepted lecturer invitations will appear here.',
                              onOpen: _openModule,
                            ),
                            _buildInvitations(),
                            _RegistrationList(
                              items: _completed,
                              emptyTitle: 'No module history',
                              emptyBody:
                                  'Completed or cancelled registrations will stay here.',
                              onOpen: _openModule,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 20, 12),
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MY LEARNING',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: Color(0xFF2563EB),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'My Modules',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.1,
                  ),
                ),
              ],
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton.filledTonal(
                tooltip: 'Refresh modules',
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
              if (_invitations.any((item) => item.status == 'pending'))
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final pending =
        _invitations.where((item) => item.status == 'pending').length +
        (_linkPreview == null ? 0 : 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white),
            ),
            child: TabBar(
              controller: _tabs,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1247A8), Color(0xFF2878E8)],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x332563EB),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF52637A),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
              tabs: [
                const Tab(text: 'Active'),
                Tab(
                  text: pending == 0 ? 'Invitations' : 'Invitations $pending',
                ),
                const Tab(text: 'History'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInvitations() {
    final pending = _invitations
        .where((item) => item.status == 'pending')
        .toList();
    if (pending.isEmpty && _linkPreview == null) {
      return const _EmptyState(
        icon: Icons.mark_email_read_outlined,
        title: 'You are all caught up',
        body: 'New module invitations from lecturers will appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 110),
        children: [
          if (_linkPreview != null)
            _InvitationCard.preview(
              preview: _linkPreview!,
              busy: _responding,
              onAccept: () => _accept(token: widget.initialToken),
            ),
          ...pending.map(
            (invitation) => Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _InvitationCard(
                invitation: invitation,
                highlighted: invitation.id == widget.highlightInvitationId,
                busy: _responding,
                onAccept: () => _accept(invitation: invitation),
                onDecline: () => _decline(invitation),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openModule(_ModuleRegistration module) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF7FAFF),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              module.displayName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Open learning resources available through your active registration.',
              style: TextStyle(color: Colors.blueGrey.shade600),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ResourceButton(
                  icon: Icons.slideshow_rounded,
                  label: 'Slides',
                  onTap: () => _pushResource(const SlidesScreen()),
                ),
                _ResourceButton(
                  icon: Icons.live_tv_rounded,
                  label: 'Online classes',
                  onTap: () => _pushResource(const OnlineClassesScreen()),
                ),
                _ResourceButton(
                  icon: Icons.quiz_rounded,
                  label: 'Quizzes',
                  onTap: () => _pushResource(const QuizScreen()),
                ),
                _ResourceButton(
                  icon: Icons.assignment_rounded,
                  label: 'Assessments',
                  onTap: () => _pushResource(const AssessmentsCalendarScreen()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _pushResource(Widget screen) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  static String _friendlyError(Object error) {
    if (error is PostgrestException) return error.message;
    if (error is AuthException) return error.message;
    return 'Unable to load modules right now. Check your connection and try again.';
  }
}

class _ModuleRegistration {
  const _ModuleRegistration({
    required this.moduleId,
    required this.name,
    required this.code,
    required this.level,
    required this.programme,
    required this.lecturer,
    required this.academicYear,
    required this.semester,
    required this.status,
    required this.registeredAt,
  });
  final String moduleId, name, level, programme, lecturer, status;
  final String? code;
  final int academicYear, semester;
  final DateTime? registeredAt;
  String get displayName => code?.isNotEmpty == true ? '$code · $name' : name;

  factory _ModuleRegistration.fromRow(Map<String, dynamic> row) {
    final module = Map<String, dynamic>.from(
      row['modules'] as Map? ?? const {},
    );
    final programme = Map<String, dynamic>.from(
      module['programmes'] as Map? ?? const {},
    );
    final assignments = List<Map<String, dynamic>>.from(
      module['module_lecturers'] as List? ?? const [],
    );
    var lecturer = 'Teaching team';
    if (assignments.isNotEmpty) {
      final profile = Map<String, dynamic>.from(
        assignments.first['profiles'] as Map? ?? const {},
      );
      final nickname = '${profile['nickname'] ?? ''}'.trim();
      final full = '${profile['name'] ?? ''} ${profile['surname'] ?? ''}'
          .trim();
      lecturer = nickname.isNotEmpty
          ? nickname
          : (full.isNotEmpty ? full : lecturer);
    }
    return _ModuleRegistration(
      moduleId: '${row['module_id']}',
      name: '${module['name'] ?? 'Module'}',
      code: module['code']?.toString(),
      level: '${module['level'] ?? 'Level'}',
      programme: '${programme['name'] ?? 'Programme'}',
      lecturer: lecturer,
      academicYear: row['academic_year'] as int? ?? DateTime.now().year,
      semester: row['semester'] as int? ?? 1,
      status: '${row['status'] ?? 'active'}',
      registeredAt: DateTime.tryParse('${row['registered_at'] ?? ''}'),
    );
  }
}

class _ModuleInvitation {
  const _ModuleInvitation({
    required this.id,
    required this.moduleName,
    required this.moduleCode,
    required this.level,
    required this.lecturerName,
    required this.academicYear,
    required this.semester,
    required this.status,
    required this.expiresAt,
  });
  final String id, moduleName, level, lecturerName, status;
  final String? moduleCode;
  final int academicYear, semester;
  final DateTime expiresAt;
  String get displayName =>
      moduleCode?.isNotEmpty == true ? '$moduleCode · $moduleName' : moduleName;
  factory _ModuleInvitation.fromRow(Map<String, dynamic> row) {
    final module = Map<String, dynamic>.from(
      row['modules'] as Map? ?? const {},
    );
    final profile = Map<String, dynamic>.from(
      row['profiles'] as Map? ?? const {},
    );
    final nickname = '${profile['nickname'] ?? ''}'.trim();
    final full = '${profile['name'] ?? ''} ${profile['surname'] ?? ''}'.trim();
    return _ModuleInvitation(
      id: '${row['id']}',
      moduleName: '${module['name'] ?? 'Module'}',
      moduleCode: module['code']?.toString(),
      level: '${module['level'] ?? 'Level'}',
      lecturerName: nickname.isNotEmpty
          ? nickname
          : (full.isNotEmpty ? full : 'Lecturer'),
      academicYear: row['academic_year'] as int? ?? DateTime.now().year,
      semester: row['semester'] as int? ?? 1,
      status: '${row['status'] ?? 'pending'}',
      expiresAt:
          DateTime.tryParse('${row['expires_at']}')?.toLocal() ??
          DateTime.now(),
    );
  }
}

class _ModuleInvitationPreview {
  const _ModuleInvitationPreview({
    required this.id,
    required this.moduleName,
    required this.moduleCode,
    required this.level,
    required this.lecturerName,
    required this.academicYear,
    required this.semester,
    required this.expiresAt,
  });
  final String id, moduleName, level, lecturerName;
  final String? moduleCode;
  final int academicYear, semester;
  final DateTime expiresAt;
  String get displayName =>
      moduleCode?.isNotEmpty == true ? '$moduleCode · $moduleName' : moduleName;
  factory _ModuleInvitationPreview.fromRow(Map<String, dynamic> row) =>
      _ModuleInvitationPreview(
        id: '${row['invitation_id']}',
        moduleName: '${row['module_name'] ?? 'Module'}',
        moduleCode: row['module_code']?.toString(),
        level: '${row['module_level'] ?? 'Level'}',
        lecturerName: '${row['lecturer_name'] ?? 'Lecturer'}',
        academicYear: row['academic_year'] as int? ?? DateTime.now().year,
        semester: row['semester'] as int? ?? 1,
        expiresAt:
            DateTime.tryParse('${row['expires_at']}')?.toLocal() ??
            DateTime.now(),
      );
}

class _RegistrationList extends StatelessWidget {
  const _RegistrationList({
    required this.items,
    required this.emptyTitle,
    required this.emptyBody,
    required this.onOpen,
  });
  final List<_ModuleRegistration> items;
  final String emptyTitle, emptyBody;
  final ValueChanged<_ModuleRegistration> onOpen;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyState(
        icon: Icons.auto_stories_outlined,
        title: emptyTitle,
        body: emptyBody,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 110),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => onOpen(item),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .82),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140D47A1),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1247A8), Color(0xFF26B9D6)],
                    ),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${item.programme} · ${item.level}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF62748A),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.lecturer} · ${item.academicYear} / S${item.semester}',
                        style: const TextStyle(
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 17,
                  color: Color(0xFF8A9AAF),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    this.highlighted = false,
  }) : preview = null;
  const _InvitationCard.preview({
    required this.preview,
    required this.busy,
    required this.onAccept,
  }) : invitation = null,
       onDecline = null,
       highlighted = true;
  final _ModuleInvitation? invitation;
  final _ModuleInvitationPreview? preview;
  final bool busy, highlighted;
  final VoidCallback onAccept;
  final VoidCallback? onDecline;
  @override
  Widget build(BuildContext context) {
    final title = invitation?.displayName ?? preview!.displayName;
    final lecturer = invitation?.lecturerName ?? preview!.lecturerName;
    final year = invitation?.academicYear ?? preview!.academicYear;
    final semester = invitation?.semester ?? preview!.semester;
    final expiry = invitation?.expiresAt ?? preview!.expiresAt;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: highlighted
              ? const [Color(0xFFFFFFFF), Color(0xFFE7F4FF)]
              : const [Color(0xFFFFFFFF), Color(0xFFF7FAFF)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: highlighted ? const Color(0xFF65BCEB) : Colors.white,
          width: highlighted ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A2563EB),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D47A1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MODULE INVITATION',
                      style: TextStyle(
                        color: Color(0xFF2563EB),
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '$lecturer invited you to join this module. Accepting securely activates classes, quizzes, slides, assessments and marks for this module.',
            style: const TextStyle(
              color: Color(0xFF56677B),
              height: 1.55,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                icon: Icons.calendar_month_rounded,
                label: '$year · Semester $semester',
              ),
              _Pill(
                icon: Icons.timer_outlined,
                label:
                    'Expires ${MaterialLocalizations.of(context).formatShortDate(expiry)}',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              if (onDecline != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onDecline,
                    child: const Text('Decline'),
                  ),
                ),
              if (onDecline != null) const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: busy ? null : onAccept,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_rounded),
                  label: Text(busy ? 'Please wait…' : 'Accept module'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF2563EB)),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF36506F),
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

class _ResourceButton extends StatelessWidget {
  const _ResourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 18, color: const Color(0xFF2563EB)),
    label: Text(label),
    onPressed: onTap,
    side: const BorderSide(color: Color(0xFFD7E5FA)),
    backgroundColor: Colors.white,
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title, body;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 58, color: const Color(0xFF8BA9CF)),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B7D93), height: 1.5),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function({bool silent}) onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 54,
            color: Color(0xFFB84A5A),
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => onRetry(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _AuroraBackground extends StatelessWidget {
  const _AuroraBackground();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE7F1FF), Color(0xFFF7FAFF), Color(0xFFE8FBFA)],
      ),
    ),
  );
}
