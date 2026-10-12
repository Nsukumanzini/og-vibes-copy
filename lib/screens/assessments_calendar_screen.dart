import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class AssessmentsCalendarScreen extends StatefulWidget {
  const AssessmentsCalendarScreen({super.key});

  @override
  State<AssessmentsCalendarScreen> createState() =>
      _AssessmentsCalendarScreenState();
}

class _AssessmentsCalendarScreenState
    extends State<AssessmentsCalendarScreen> {
  final List<_ScheduleItem> _items = <_ScheduleItem>[];
  final List<_ModuleRef> _modules = <_ModuleRef>[];
  final Set<String> _registeredModuleIds = <String>{};
  final Map<String, _LecturerProfile> _lecturers =
      <String, _LecturerProfile>{};

  StreamSubscription<List<Map<String, dynamic>>>? _quizSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _briefSubscription;
  Timer? _clock;
  _ScheduleView _view = _ScheduleView.calendar;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  String _moduleFilter = 'All';
  String _typeFilter = 'All';
  String _lecturerFilter = 'All';
  String _statusFilter = 'All';
  bool _myModulesOnly = true;
  bool _hasRegistrationMatch = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
    _listenForChanges();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _quizSubscription?.cancel();
    _briefSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSchedule({bool showLoader = true}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'You must be signed in to view assessments.';
      });
      return;
    }

    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
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
        Supabase.instance.client
            .from('profiles')
            .select('id, name, surname, photo_url, is_verified, role'),
        Supabase.instance.client
            .from('assessment_briefs')
            .select(
              'id, module_id, lecturer_id, level, title, subject, '
              'instructions, due_at, assessment_type, venue, '
              'duration_minutes, weight_percent, published',
            )
            .eq('published', true)
            .order('due_at', ascending: true),
        Supabase.instance.client
            .from('quizzes')
            .select(
              'id, module_id, lecturer_id, lecturer_name, title, description, '
              'quiz_date, duration_minutes, assessment_type, venue, '
              'weight_percent, published',
            )
            .eq('published', true)
            .order('quiz_date', ascending: true),
        Supabase.instance.client
            .from('assignment_submissions')
            .select(
              'id, brief_id, module_id, level, title, subject, due_date, '
              'status, submitted_at, grade',
            )
            .eq('user_id', user.id),
      ]);

      final profile = results[0] is Map
          ? Map<String, dynamic>.from(results[0] as Map)
          : <String, dynamic>{};
      final programmeRows = List<Map<String, dynamic>>.from(
        results[1] as List<dynamic>? ?? <dynamic>[],
      );
      final moduleRows = List<Map<String, dynamic>>.from(
        results[2] as List<dynamic>? ?? <dynamic>[],
      );
      final lecturerRows = List<Map<String, dynamic>>.from(
        results[3] as List<dynamic>? ?? <dynamic>[],
      );
      final briefRows = List<Map<String, dynamic>>.from(
        results[4] as List<dynamic>? ?? <dynamic>[],
      );
      final quizRows = List<Map<String, dynamic>>.from(
        results[5] as List<dynamic>? ?? <dynamic>[],
      );
      final submissionRows = List<Map<String, dynamic>>.from(
        results[6] as List<dynamic>? ?? <dynamic>[],
      );

      _buildAcademicContext(
        profile: profile,
        programmes: programmeRows,
        modules: moduleRows,
        lecturerRows: lecturerRows,
      );
      final submissions =
          submissionRows.map(_SubmissionSummary.fromRow).toList();
      final byBrief = <String, _SubmissionSummary>{
        for (final submission in submissions)
          if (submission.briefId.isNotEmpty) submission.briefId: submission,
      };
      final schedule = <_ScheduleItem>[
        ...briefRows.map(
          (row) => _ScheduleItem.fromBrief(
            row,
            submission: byBrief[_text(row['id'])],
            lecturer: _lecturers[_text(row['lecturer_id'])],
            module: _moduleById(_text(row['module_id'])),
          ),
        ),
        ...quizRows.map(
          (row) => _ScheduleItem.fromQuiz(
            row,
            lecturer: _lecturers[_text(row['lecturer_id'])],
            module: _moduleById(_text(row['module_id'])),
          ),
        ),
      ];

      final briefIds = briefRows.map((row) => _text(row['id'])).toSet();
      schedule.addAll(
        submissions
            .where(
              (submission) =>
                  submission.briefId.isEmpty ||
                  !briefIds.contains(submission.briefId),
            )
            .map(
              (submission) => _ScheduleItem.fromLegacySubmission(
                submission,
                module: _moduleById(submission.moduleId),
              ),
            ),
      );
      schedule.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(schedule);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  void _buildAcademicContext({
    required Map<String, dynamic> profile,
    required List<Map<String, dynamic>> programmes,
    required List<Map<String, dynamic>> modules,
    required List<Map<String, dynamic>> lecturerRows,
  }) {
    final department = _normalize(profile['department']);
    final level = _normalize(profile['level']);
    final programmeIds = programmes.where((programme) {
      final programmeName = _normalize(programme['name']);
      return department.isNotEmpty &&
          (department.contains(programmeName) ||
              programmeName.contains(department));
    }).map((programme) => _text(programme['id'])).toSet();

    _modules
      ..clear()
      ..addAll(modules.map(_ModuleRef.fromRow));
    _registeredModuleIds
      ..clear()
      ..addAll(
        _modules.where((module) {
          final moduleLevel = _normalize(module.level);
          return programmeIds.contains(module.programmeId) &&
              (level.isEmpty ||
                  level == moduleLevel ||
                  level.contains(moduleLevel) ||
                  moduleLevel.contains(level));
        }).map((module) => module.id),
      );
    _hasRegistrationMatch = _registeredModuleIds.isNotEmpty;
    if (!_hasRegistrationMatch) _myModulesOnly = false;

    _lecturers
      ..clear()
      ..addEntries(
        lecturerRows.map((row) {
          final fullName = <String>[
            _text(row['name']),
            _text(row['surname']),
          ].where((part) => part.isNotEmpty).join(' ');
          return MapEntry<String, _LecturerProfile>(
            _text(row['id']),
            _LecturerProfile(
              name: fullName.isEmpty ? 'Academic staff' : fullName,
              photoUrl: _text(row['photo_url']),
              verified: row['is_verified'] == true,
            ),
          );
        }),
      );
  }

  void _listenForChanges() {
    _quizSubscription = Supabase.instance.client
        .from('quizzes')
        .stream(primaryKey: <String>['id'])
        .listen((_) {
      if (mounted) unawaited(_loadSchedule(showLoader: false));
    }, onError: (_) {});
    _briefSubscription = Supabase.instance.client
        .from('assessment_briefs')
        .stream(primaryKey: <String>['id'])
        .listen((_) {
      if (mounted) unawaited(_loadSchedule(showLoader: false));
    }, onError: (_) {});
  }

  _ModuleRef? _moduleById(String id) {
    for (final module in _modules) {
      if (module.id == id) return module;
    }
    return null;
  }

  List<_ScheduleItem> get _visibleItems {
    return _items.where((item) {
      if (_myModulesOnly && _hasRegistrationMatch) {
        if (item.moduleId.isNotEmpty &&
            !_registeredModuleIds.contains(item.moduleId)) {
          return false;
        }
        if (item.moduleId.isEmpty) {
          final subject = _normalize(item.subject);
          final matches = _modules
              .where((module) => _registeredModuleIds.contains(module.id))
              .any(
                (module) =>
                    subject.contains(_normalize(module.name)) ||
                    subject.contains(_normalize(module.code)),
              );
          if (!matches) return false;
        }
      }
      if (_moduleFilter != 'All' && item.moduleId != _moduleFilter) {
        return false;
      }
      if (_typeFilter != 'All' && item.type != _typeFilter) return false;
      if (_lecturerFilter != 'All' &&
          item.lecturer.name != _lecturerFilter) {
        return false;
      }
      if (_statusFilter != 'All' && item.statusLabel != _statusFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  List<_ScheduleItem> _eventsForDay(DateTime day) {
    return _visibleItems
        .where((item) => isSameDay(item.scheduledAt.toLocal(), day))
        .toList();
  }

  List<_ScheduleItem> get _upcomingItems {
    final now = DateTime.now();
    return _visibleItems
        .where(
          (item) =>
              item.scheduledAt.toLocal().isAfter(now) && !item.isCompleted,
        )
        .toList();
  }

  _ScheduleItem? get _nextAssessment {
    final items = _upcomingItems
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return items.isEmpty ? null : items.first;
  }

  int get _weekCount {
    final now = DateTime.now();
    final end = now.add(const Duration(days: 7));
    return _upcomingItems
        .where((item) => item.scheduledAt.toLocal().isBefore(end))
        .length;
  }

  int get _overdueCount =>
      _visibleItems.where((item) => item.isOverdue).length;
  int get _completedCount =>
      _visibleItems.where((item) => item.isCompleted).length;

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Assessment Schedule'),
        backgroundColor: Colors.transparent,
        actions: <Widget>[
          IconButton(
            onPressed: _showFilters,
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Filter assessments',
          ),
          IconButton(
            onPressed: _loadSchedule,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh schedule',
          ),
        ],
      ),
      body: _isLoading && _items.isEmpty
          ? _buildLoadingState()
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null && _items.isEmpty) return _buildErrorState();
    return Column(
      children: <Widget>[
        Expanded(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(child: _buildHero()),
              SliverToBoxAdapter(child: _buildControls()),
              SliverFillRemaining(
                hasScrollBody: true,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(.025, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _view == _ScheduleView.calendar
                      ? _buildCalendarView()
                      : _buildAgendaView(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    final next = _nextAssessment;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
              right: -36,
              top: -54,
              child: Container(
                width: 175,
                height: 175,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.electricCyan.withValues(alpha: .13),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(
                      Icons.calendar_month_rounded,
                      color: AppColors.electricCyan,
                    ),
                    SizedBox(width: 9),
                    Text(
                      'OG ACADEMIC PLANNER',
                      style: TextStyle(
                        color: AppColors.electricCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Know what’s next.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Every test, quiz and deadline in one focused schedule.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    _heroStat(
                      '${_upcomingItems.length}',
                      'Upcoming',
                      AppColors.electricCyan,
                    ),
                    _heroStat('$_weekCount', 'This week', AppColors.ogGold),
                    _heroStat(
                      '$_overdueCount',
                      'Overdue',
                      Colors.redAccent,
                    ),
                    _heroStat(
                      '$_completedCount',
                      'Completed',
                      AppColors.success,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .18),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.timer_outlined,
                        color: AppColors.ogGold,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              next == null
                                  ? 'No upcoming assessment'
                                  : '${next.type} • ${next.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              next == null
                                  ? 'Your schedule is clear'
                                  : _countdown(next.scheduledAt),
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
    ).animate().fadeIn(duration: 420.ms).slideY(begin: .05, end: 0);
  }

  Widget _heroStat(String value, String label, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final filterCount = <bool>[
      _moduleFilter != 'All',
      _typeFilter != 'All',
      _lecturerFilter != 'All',
      _statusFilter != 'All',
    ].where((active) => active).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: <Widget>[
          _glass(
            padding: const EdgeInsets.all(5),
            child: SegmentedButton<_ScheduleView>(
              segments: const <ButtonSegment<_ScheduleView>>[
                ButtonSegment<_ScheduleView>(
                  value: _ScheduleView.calendar,
                  icon: Icon(Icons.calendar_month_rounded),
                  label: Text('Calendar'),
                ),
                ButtonSegment<_ScheduleView>(
                  value: _ScheduleView.agenda,
                  icon: Icon(Icons.view_agenda_outlined),
                  label: Text('Agenda'),
                ),
              ],
              selected: <_ScheduleView>{_view},
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? AppColors.vibeBlue
                      : Colors.transparent;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? Colors.white
                      : AppColors.textMuted;
                }),
                side: const WidgetStatePropertyAll(BorderSide.none),
              ),
              onSelectionChanged: (selection) {
                HapticFeedback.selectionClick();
                setState(() => _view = selection.first);
              },
            ),
          ),
          const SizedBox(height: 9),
          _glass(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                              _moduleFilter = 'All';
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
                        AppColors.vibeBlue.withValues(alpha: .14),
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
                    tooltip: 'Filters',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarView() {
    final selectedItems = _eventsForDay(_selectedDay);
    return LayoutBuilder(
      key: const ValueKey<String>('calendar'),
      builder: (context, constraints) {
        final calendar = _buildCalendar();
        final dayAgenda = _buildSelectedDayAgenda(selectedItems);
        if (constraints.maxWidth >= 900) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 6, child: calendar),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: dayAgenda),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
          children: <Widget>[
            calendar,
            const SizedBox(height: 14),
            dayAgenda,
          ],
        );
      },
    );
  }

  Widget _buildCalendar() {
    return _glass(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      child: TableCalendar<_ScheduleItem>(
        firstDay: DateTime(DateTime.now().year - 2),
        lastDay: DateTime(DateTime.now().year + 3, 12, 31),
        focusedDay: _focusedDay,
        selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
        eventLoader: _eventsForDay,
        startingDayOfWeek: StartingDayOfWeek.monday,
        availableCalendarFormats: const <CalendarFormat, String>{
          CalendarFormat.month: 'Month',
        },
        rowHeight: 48,
        daysOfWeekHeight: 30,
        headerStyle: const HeaderStyle(
          titleCentered: true,
          formatButtonVisible: false,
          titleTextStyle: TextStyle(
            color: AppColors.midnightInk,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
          leftChevronIcon: Icon(
            Icons.chevron_left_rounded,
            color: AppColors.vibeBlue,
          ),
          rightChevronIcon: Icon(
            Icons.chevron_right_rounded,
            color: AppColors.vibeBlue,
          ),
        ),
        daysOfWeekStyle: const DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
          weekendStyle: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          todayDecoration: BoxDecoration(
            color: AppColors.electricCyan.withValues(alpha: .18),
            shape: BoxShape.circle,
          ),
          todayTextStyle: const TextStyle(
            color: AppColors.vibeBlue,
            fontWeight: FontWeight.w900,
          ),
          selectedDecoration: const BoxDecoration(
            color: AppColors.vibeBlue,
            shape: BoxShape.circle,
          ),
          selectedTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
          markerDecoration: const BoxDecoration(
            color: AppColors.ogGold,
            shape: BoxShape.circle,
          ),
          markerSize: 6,
          markersMaxCount: 3,
          defaultTextStyle: const TextStyle(
            color: AppColors.midnightInk,
            fontWeight: FontWeight.w700,
          ),
          weekendTextStyle: const TextStyle(
            color: AppColors.midnightInk,
            fontWeight: FontWeight.w700,
          ),
        ),
        calendarBuilders: CalendarBuilders<_ScheduleItem>(
          markerBuilder: (context, day, events) {
            if (events.isEmpty) return null;
            return Positioned(
              bottom: 3,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: events
                    .take(3)
                    .map(
                      (event) => Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: event.typeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
          },
        ),
        onDaySelected: (selectedDay, focusedDay) {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        onPageChanged: (focusedDay) => _focusedDay = focusedDay,
      ),
    );
  }

  Widget _buildSelectedDayAgenda(List<_ScheduleItem> items) {
    return _glass(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _dayHeading(_selectedDay),
            style: const TextStyle(
              color: AppColors.midnightInk,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${items.length} assessment${items.length == 1 ? '' : 's'}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.event_available_rounded,
                      color: AppColors.vibeBlue,
                      size: 34,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No assessments scheduled',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List<Widget>.generate(
              items.length,
              (index) => Padding(
                padding: EdgeInsets.only(
                  bottom: index == items.length - 1 ? 0 : 10,
                ),
                child: _buildCompactItem(items[index], index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAgendaView() {
    final items = _visibleItems;
    if (items.isEmpty) {
      return _buildEmptyState(key: const ValueKey<String>('agenda-empty'));
    }
    final grouped = <DateTime, List<_ScheduleItem>>{};
    for (final item in items) {
      final local = item.scheduledAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      grouped.putIfAbsent(day, () => <_ScheduleItem>[]).add(item);
    }
    final days = grouped.keys.toList()..sort();
    return RefreshIndicator(
      key: const ValueKey<String>('agenda'),
      onRefresh: _loadSchedule,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
        itemCount: days.length,
        itemBuilder: (context, dayIndex) {
          final day = days[dayIndex];
          final dayItems = grouped[day]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 9),
                child: Row(
                  children: <Widget>[
                    Text(
                      _dayHeading(day),
                      style: const TextStyle(
                        color: AppColors.midnightInk,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Divider(
                        color: AppColors.glassBorder.withValues(alpha: .8),
                      ),
                    ),
                  ],
                ),
              ),
              ...List<Widget>.generate(
                dayItems.length,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildAgendaCard(
                    dayItems[index],
                    dayIndex * 2 + index,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCompactItem(_ScheduleItem item, int index) {
    return InkWell(
      onTap: () => _showDetails(item),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: item.typeColor.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: item.typeColor.withValues(alpha: .17)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 9,
              height: 42,
              decoration: BoxDecoration(
                color: item.typeColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.midnightInk,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.timeLabel} • ${item.type}',
                    style: TextStyle(
                      color: item.typeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    ).animate(delay: (45 * index).ms).fadeIn().slideX(begin: .04, end: 0);
  }

  Widget _buildAgendaCard(_ScheduleItem item, int index) {
    return InkWell(
      onTap: () => _showDetails(item),
      borderRadius: AppStyles.controlRadius,
      child: _glass(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Column(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: item.typeColor.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.typeIcon, color: item.typeColor),
                ),
                const SizedBox(height: 6),
                Text(
                  item.timeLabel,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.midnightInk,
                            fontSize: 16,
                            height: 1.22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _statusPill(item),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${item.moduleLabel} • ${item.type}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 11),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: <Widget>[
                      _metaPill(Icons.location_on_outlined, item.venueLabel),
                      if (item.durationMinutes != null)
                        _metaPill(
                          Icons.timelapse_rounded,
                          '${item.durationMinutes} min',
                        ),
                      if (item.weightPercent != null)
                        _metaPill(
                          Icons.percent_rounded,
                          '${_cleanNumber(item.weightPercent!)} weight',
                        ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Row(
                    children: <Widget>[
                      _lecturerAvatar(item.lecturer, radius: 14),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          item.lecturer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.midnightInk,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        item.isCompleted
                            ? 'Completed'
                            : _countdown(item.scheduledAt),
                        style: TextStyle(
                          color: item.isOverdue
                              ? AppColors.danger
                              : item.typeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: (45 * index).ms)
        .fadeIn(duration: 330.ms)
        .slideY(begin: .06, end: 0);
  }

  Widget _statusPill(_ScheduleItem item) {
    final color = item.isOverdue
        ? AppColors.danger
        : item.isCompleted
            ? AppColors.success
            : item.typeColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Text(
        item.statusLabel.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .35,
        ),
      ),
    );
  }

  Widget _metaPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.vibeBlue.withValues(alpha: .06),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: AppColors.vibeBlue, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lecturerAvatar(_LecturerProfile lecturer, {double radius = 20}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.vibeBlue.withValues(alpha: .11),
      backgroundImage:
          lecturer.photoUrl.isEmpty ? null : NetworkImage(lecturer.photoUrl),
      child: lecturer.photoUrl.isEmpty
          ? Text(
              lecturer.initials,
              style: TextStyle(
                color: AppColors.vibeBlue,
                fontSize: radius * .65,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }

  Future<void> _showDetails(_ScheduleItem item) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAFF),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: item.typeColor.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(item.typeIcon, color: item.typeColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: AppColors.midnightInk,
                            fontSize: 21,
                            height: 1.15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${item.moduleLabel} • ${item.type}',
                          style: TextStyle(
                            color: item.typeColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _detailRow(
                Icons.event_rounded,
                'Date and time',
                _formatDateTime(item.scheduledAt),
              ),
              _detailRow(
                Icons.location_on_outlined,
                'Venue',
                item.venueLabel,
              ),
              _detailRow(
                Icons.timelapse_rounded,
                'Duration',
                item.durationMinutes == null
                    ? 'To be announced'
                    : '${item.durationMinutes} minutes',
              ),
              _detailRow(
                Icons.percent_rounded,
                'Assessment weight',
                item.weightPercent == null
                    ? 'Not specified'
                    : '${_cleanNumber(item.weightPercent!)}%',
              ),
              const Divider(height: 24),
              Row(
                children: <Widget>[
                  _lecturerAvatar(item.lecturer, radius: 22),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                item.lecturer.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.midnightInk,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (item.lecturer.verified) ...<Widget>[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.verified_rounded,
                                color: AppColors.vibeBlue,
                                size: 17,
                              ),
                            ],
                          ],
                        ),
                        const Text(
                          'Assessment lecturer',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (item.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 17),
                const Text(
                  'Assessment details',
                  style: TextStyle(
                    color: AppColors.midnightInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.description,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: item.typeColor.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  item.isCompleted
                      ? 'Completed'
                      : _countdown(item.scheduledAt),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: item.isOverdue ? AppColors.danger : item.typeColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppColors.vibeBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.midnightInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFilters() async {
    HapticFeedback.selectionClick();
    var module = _moduleFilter;
    var type = _typeFilter;
    var lecturer = _lecturerFilter;
    var status = _statusFilter;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAFF),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Filter assessment schedule',
                  style: TextStyle(
                    color: AppColors.midnightInk,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _moduleOptions
                          .any((option) => option.value == module)
                      ? module
                      : 'All',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Module',
                    prefixIcon: Icon(Icons.menu_book_rounded),
                  ),
                  items: _moduleOptions,
                  onChanged: (value) =>
                      setSheetState(() => module = value ?? 'All'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _typeOptions.contains(type) ? type : 'All',
                        decoration:
                            const InputDecoration(labelText: 'Type'),
                        items: _typeOptions
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setSheetState(() => type = value ?? 'All'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            _statusOptions.contains(status) ? status : 'All',
                        decoration:
                            const InputDecoration(labelText: 'Status'),
                        items: _statusOptions
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setSheetState(() => status = value ?? 'All'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _lecturerOptions.contains(lecturer)
                      ? lecturer
                      : 'All',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Lecturer',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  items: _lecturerOptions
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
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _moduleFilter = module;
                      _typeFilter = type;
                      _lecturerFilter = lecturer;
                      _statusFilter = status;
                    });
                    HapticFeedback.mediumImpact();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Apply filters'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _moduleFilter = 'All';
                      _typeFilter = 'All';
                      _lecturerFilter = 'All';
                      _statusFilter = 'All';
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

  List<DropdownMenuItem<String>> get _moduleOptions {
    final allowed = _myModulesOnly && _hasRegistrationMatch
        ? _modules
            .where((module) => _registeredModuleIds.contains(module.id))
            .toList()
        : List<_ModuleRef>.from(_modules);
    allowed.sort((a, b) => a.displayName.compareTo(b.displayName));
    return <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(value: 'All', child: Text('All modules')),
      ...allowed.map(
        (module) => DropdownMenuItem<String>(
          value: module.id,
          child: Text(module.displayName, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
  }

  List<String> get _typeOptions {
    final values = _items.map((item) => item.type).toSet().toList()..sort();
    return <String>['All', ...values];
  }

  List<String> get _lecturerOptions {
    final values = _items
        .map((item) => item.lecturer.name)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return <String>['All', ...values];
  }

  List<String> get _statusOptions {
    return const <String>['All', 'Upcoming', 'Completed', 'Overdue'];
  }

  Widget _buildEmptyState({Key? key}) {
    return Center(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.vibeBlue.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: AppColors.vibeBlue,
                size: 36,
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'No assessments match',
              style: TextStyle(
                color: AppColors.midnightInk,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Published tests, assignments and quizzes will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
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
                color: AppColors.danger,
                size: 52,
              ),
              const SizedBox(height: 13),
              const Text(
                'Schedule temporarily unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.midnightInk,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Check your connection and try again.',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 15),
              FilledButton.icon(
                onPressed: _loadSchedule,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: <Widget>[
            Container(
              height: 265,
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
              height: 380,
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
            color: Colors.white.withValues(alpha: .80),
            borderRadius: AppStyles.controlRadius,
            border: Border.all(color: Colors.white.withValues(alpha: .90)),
            boxShadow: AppStyles.softShadow,
          ),
          child: child,
        ),
      ),
    );
  }

  String _countdown(DateTime value) {
    final difference = value.toLocal().difference(DateTime.now());
    if (difference.isNegative) {
      final late = difference.abs();
      if (late.inDays > 0) return '${late.inDays}d ago';
      if (late.inHours > 0) return '${late.inHours}h ago';
      return '${late.inMinutes}m ago';
    }
    if (difference.inDays > 0) {
      return 'In ${difference.inDays}d ${difference.inHours % 24}h';
    }
    if (difference.inHours > 0) {
      return 'In ${difference.inHours}h ${difference.inMinutes % 60}m';
    }
    return 'In ${difference.inMinutes}m ${difference.inSeconds % 60}s';
  }

  String _dayHeading(DateTime day) {
    final now = DateTime.now();
    if (isSameDay(day, now)) return 'Today';
    if (isSameDay(day, now.add(const Duration(days: 1)))) return 'Tomorrow';
    const weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
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
    return '${weekdays[day.weekday - 1]}, ${day.day} ${months[day.month - 1]}';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
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
    return '${local.day} ${months[local.month - 1]} ${local.year} • '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _cleanNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';
  static String _normalize(dynamic value) =>
      _text(value).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

enum _ScheduleView { calendar, agenda }

class _ScheduleItem {
  const _ScheduleItem({
    required this.id,
    required this.moduleId,
    required this.moduleLabel,
    required this.subject,
    required this.title,
    required this.description,
    required this.type,
    required this.scheduledAt,
    required this.venue,
    required this.durationMinutes,
    required this.weightPercent,
    required this.lecturer,
    required this.completed,
    required this.overdue,
  });

  final String id;
  final String moduleId;
  final String moduleLabel;
  final String subject;
  final String title;
  final String description;
  final String type;
  final DateTime scheduledAt;
  final String venue;
  final int? durationMinutes;
  final double? weightPercent;
  final _LecturerProfile lecturer;
  final bool completed;
  final bool overdue;

  bool get isCompleted => completed;
  bool get isOverdue => overdue && !completed;
  String get statusLabel =>
      isCompleted ? 'Completed' : isOverdue ? 'Overdue' : 'Upcoming';
  String get venueLabel => venue.isEmpty ? 'Venue TBA' : venue;
  String get timeLabel {
    final local = scheduledAt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Color get typeColor {
    switch (type.toLowerCase()) {
      case 'exam':
        return AppColors.danger;
      case 'test':
        return const Color(0xFF7E57C2);
      case 'practical':
        return AppColors.success;
      case 'assignment':
        return AppColors.warning;
      case 'quiz':
        return AppColors.vibeBlue;
      default:
        return const Color(0xFF546E7A);
    }
  }

  IconData get typeIcon {
    switch (type.toLowerCase()) {
      case 'exam':
        return Icons.fact_check_rounded;
      case 'test':
        return Icons.edit_note_rounded;
      case 'practical':
        return Icons.science_outlined;
      case 'assignment':
        return Icons.assignment_outlined;
      case 'quiz':
        return Icons.quiz_outlined;
      default:
        return Icons.event_note_rounded;
    }
  }

  factory _ScheduleItem.fromBrief(
    Map<String, dynamic> row, {
    required _SubmissionSummary? submission,
    required _LecturerProfile? lecturer,
    required _ModuleRef? module,
  }) {
    final date = DateTime.tryParse(
          _AssessmentsCalendarScreenState._text(row['due_at']),
        ) ??
        DateTime.now();
    final status = submission?.status ?? '';
    final completed = status == 'submitted' || status == 'graded';
    return _ScheduleItem(
      id: _AssessmentsCalendarScreenState._text(row['id']),
      moduleId: _AssessmentsCalendarScreenState._text(row['module_id']),
      moduleLabel: module?.displayName ??
          _AssessmentsCalendarScreenState._text(row['subject']),
      subject: _AssessmentsCalendarScreenState._text(row['subject']),
      title: _AssessmentsCalendarScreenState._text(row['title']),
      description:
          _AssessmentsCalendarScreenState._text(row['instructions']),
      type: _canonicalType(
        _AssessmentsCalendarScreenState._text(row['assessment_type']),
        fallback: 'Assignment',
      ),
      scheduledAt: date,
      venue: _AssessmentsCalendarScreenState._text(row['venue']),
      durationMinutes:
          int.tryParse(row['duration_minutes']?.toString() ?? ''),
      weightPercent:
          double.tryParse(row['weight_percent']?.toString() ?? ''),
      lecturer: lecturer ?? const _LecturerProfile(name: 'Academic staff'),
      completed: completed,
      overdue: date.toLocal().isBefore(DateTime.now()) && !completed,
    );
  }

  factory _ScheduleItem.fromQuiz(
    Map<String, dynamic> row, {
    required _LecturerProfile? lecturer,
    required _ModuleRef? module,
  }) {
    final date = DateTime.tryParse(
          _AssessmentsCalendarScreenState._text(row['quiz_date']),
        ) ??
        DateTime.now();
    final lecturerName =
        _AssessmentsCalendarScreenState._text(row['lecturer_name']);
    return _ScheduleItem(
      id: _AssessmentsCalendarScreenState._text(row['id']),
      moduleId: _AssessmentsCalendarScreenState._text(row['module_id']),
      moduleLabel: module?.displayName ?? 'General',
      subject: module?.name ?? 'Quiz',
      title: _AssessmentsCalendarScreenState._text(row['title']),
      description:
          _AssessmentsCalendarScreenState._text(row['description']),
      type: _canonicalType(
        _AssessmentsCalendarScreenState._text(row['assessment_type']),
        fallback: 'Quiz',
      ),
      scheduledAt: date,
      venue: _AssessmentsCalendarScreenState._text(row['venue']),
      durationMinutes:
          int.tryParse(row['duration_minutes']?.toString() ?? ''),
      weightPercent:
          double.tryParse(row['weight_percent']?.toString() ?? ''),
      lecturer: lecturer ??
          _LecturerProfile(
            name: lecturerName.isEmpty ? 'Academic staff' : lecturerName,
          ),
      completed: date.toLocal().isBefore(DateTime.now()),
      overdue: false,
    );
  }

  factory _ScheduleItem.fromLegacySubmission(
    _SubmissionSummary submission, {
    required _ModuleRef? module,
  }) {
    final date = submission.dueDate ?? submission.submittedAt ?? DateTime.now();
    final completed =
        submission.status == 'submitted' || submission.status == 'graded';
    return _ScheduleItem(
      id: submission.id,
      moduleId: submission.moduleId,
      moduleLabel: module?.displayName ?? submission.subject,
      subject: submission.subject,
      title: submission.title,
      description: '',
      type: 'Assignment',
      scheduledAt: date,
      venue: 'Online submission',
      durationMinutes: null,
      weightPercent: null,
      lecturer: const _LecturerProfile(name: 'Academic staff'),
      completed: completed,
      overdue: date.toLocal().isBefore(DateTime.now()) && !completed,
    );
  }

  static String _canonicalType(String value, {required String fallback}) {
    final clean = value.trim();
    if (clean.isEmpty) return fallback;
    return '${clean[0].toUpperCase()}${clean.substring(1).toLowerCase()}';
  }
}

class _SubmissionSummary {
  const _SubmissionSummary({
    required this.id,
    required this.briefId,
    required this.moduleId,
    required this.title,
    required this.subject,
    required this.status,
    required this.dueDate,
    required this.submittedAt,
  });

  final String id;
  final String briefId;
  final String moduleId;
  final String title;
  final String subject;
  final String status;
  final DateTime? dueDate;
  final DateTime? submittedAt;

  factory _SubmissionSummary.fromRow(Map<String, dynamic> row) {
    final due = DateTime.tryParse(
      _AssessmentsCalendarScreenState._text(row['due_date']),
    );
    return _SubmissionSummary(
      id: _AssessmentsCalendarScreenState._text(row['id']),
      briefId: _AssessmentsCalendarScreenState._text(row['brief_id']),
      moduleId: _AssessmentsCalendarScreenState._text(row['module_id']),
      title: _AssessmentsCalendarScreenState._text(row['title']),
      subject: _AssessmentsCalendarScreenState._text(row['subject']),
      status:
          _AssessmentsCalendarScreenState._text(row['status']).toLowerCase(),
      dueDate: due == null
          ? null
          : DateTime(due.year, due.month, due.day, 23, 59, 59),
      submittedAt: DateTime.tryParse(
        _AssessmentsCalendarScreenState._text(row['submitted_at']),
      ),
    );
  }
}

class _ModuleRef {
  const _ModuleRef({
    required this.id,
    required this.programmeId,
    required this.level,
    required this.name,
    required this.code,
  });

  final String id;
  final String programmeId;
  final String level;
  final String name;
  final String code;

  String get displayName => code.isEmpty ? name : '$code • $name';

  factory _ModuleRef.fromRow(Map<String, dynamic> row) {
    return _ModuleRef(
      id: _AssessmentsCalendarScreenState._text(row['id']),
      programmeId:
          _AssessmentsCalendarScreenState._text(row['programme_id']),
      level: _AssessmentsCalendarScreenState._text(row['level']),
      name: _AssessmentsCalendarScreenState._text(row['name']),
      code: _AssessmentsCalendarScreenState._text(row['code']),
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
