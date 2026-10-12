import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';

class IcassCheckerScreen extends StatefulWidget {
  const IcassCheckerScreen({super.key});

  @override
  State<IcassCheckerScreen> createState() => _IcassCheckerScreenState();
}

class _IcassCheckerScreenState extends State<IcassCheckerScreen> {
  final List<IcassMark> _marks = <IcassMark>[];
  final List<RegisteredModule> _registeredModules = <RegisteredModule>[];
  final Map<String, AcademicModule> _modules = <String, AcademicModule>{};

  bool _loading = true;
  String? _error;
  StudentContext? _student;
  int? _selectedYear;
  int? _selectedSemester;
  String _selectedStatus = 'all';

  SupabaseClient get _supabase => Supabase.instance.client;
  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard({bool showLoader = true}) async {
    final user = _user;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to view your ICASS marks.';
      });
      return;
    }
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final responses = await Future.wait<dynamic>(<Future<dynamic>>[
        _supabase
            .from('profiles')
            .select('id, name, surname, student_number, department, level')
            .eq('id', user.id)
            .maybeSingle(),
        _supabase
            .from('student_module_registrations')
            .select(
              'student_id, module_id, academic_year, semester, status, '
              'registered_at',
            )
            .eq('student_id', user.id)
            .neq('status', 'cancelled')
            .order('academic_year', ascending: false),
        _supabase
            .from('modules')
            .select('id, programme_id, level, name, code')
            .order('name'),
        _supabase
            .from('icass_marks')
            .select(
              'id, student_id, module_id, subject_name, lecturer_name, '
              'component_name, component_score, component_weight, '
              'mark_status, assessment_date, academic_year, semester, '
              'created_at, updated_at',
            )
            .eq('student_id', user.id)
            .order('assessment_date', ascending: false),
      ]);

      final profileRow = responses[0] == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(responses[0] as Map);
      final registrationRows =
          List<Map<String, dynamic>>.from(responses[1] as List<dynamic>);
      final moduleRows =
          List<Map<String, dynamic>>.from(responses[2] as List<dynamic>);
      final markRows =
          List<Map<String, dynamic>>.from(responses[3] as List<dynamic>);

      final modules = <String, AcademicModule>{
        for (final row in moduleRows)
          row['id'].toString(): AcademicModule.fromRow(row),
      };
      final registrations =
          registrationRows.map(RegisteredModule.fromRow).toList();
      final marks = markRows.map(IcassMark.fromRow).toList();
      final availableYears = <int>{
        ...registrations.map((item) => item.academicYear),
        ...marks.map((item) => item.academicYear),
      }.toList()
        ..sort((a, b) => b.compareTo(a));

      if (!mounted) return;
      setState(() {
        _student = StudentContext.fromRow(profileRow, user);
        _modules
          ..clear()
          ..addAll(modules);
        _registeredModules
          ..clear()
          ..addAll(registrations);
        _marks
          ..clear()
          ..addAll(marks);
        if (_selectedYear == null ||
            !availableYears.contains(_selectedYear)) {
          _selectedYear = availableYears.isEmpty
              ? DateTime.now().year
              : availableYears.first;
        }
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

  List<int> get _availableYears {
    final values = <int>{
      ..._registeredModules.map((item) => item.academicYear),
      ..._marks.map((item) => item.academicYear),
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    return values.isEmpty ? <int>[DateTime.now().year] : values;
  }

  List<ModulePerformance> get _performances {
    final year = _selectedYear;
    if (year == null) return <ModulePerformance>[];

    final registrations = _registeredModules.where((registration) {
      if (registration.academicYear != year) return false;
      if (_selectedSemester != null &&
          registration.semester != _selectedSemester) {
        return false;
      }
      return true;
    }).toList();

    final filteredMarks = _marks.where((mark) {
      if (mark.academicYear != year) return false;
      if (_selectedSemester != null && mark.semester != _selectedSemester) {
        return false;
      }
      if (_selectedStatus != 'all' &&
          mark.status != _selectedStatus) {
        return false;
      }
      return true;
    }).toList();

    final moduleIds = <String>{
      ...registrations.map((item) => item.moduleId),
      ...filteredMarks
          .map((item) => item.moduleId)
          .whereType<String>(),
    };
    final subjectOnly = filteredMarks
        .where((item) => item.moduleId == null)
        .map((item) => item.subjectName)
        .toSet();

    final performances = <ModulePerformance>[];
    for (final moduleId in moduleIds) {
      final module = _modules[moduleId] ??
          AcademicModule(
            id: moduleId,
            name: filteredMarks
                .where((item) => item.moduleId == moduleId)
                .map((item) => item.subjectName)
                .firstOrNull ??
                'Registered module',
            code: '',
            level: '',
          );
      final marks = filteredMarks
          .where((item) => item.moduleId == moduleId)
          .toList();
      performances.add(ModulePerformance(module: module, marks: marks));
    }
    for (final subject in subjectOnly) {
      performances.add(
        ModulePerformance(
          module: AcademicModule(
            id: 'subject:$subject',
            name: subject,
            code: '',
            level: '',
          ),
          marks: filteredMarks
              .where(
                (item) =>
                    item.moduleId == null && item.subjectName == subject,
              )
              .toList(),
        ),
      );
    }
    performances.sort((a, b) {
      final riskOrder = a.band.rank.compareTo(b.band.rank);
      if (riskOrder != 0) return riskOrder;
      return a.module.displayName.compareTo(b.module.displayName);
    });
    return performances;
  }

  DashboardSummary get _summary => DashboardSummary.from(_performances);

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text(
          'ICASS Marks',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh marks',
            onPressed: () => _loadDashboard(showLoader: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.vibeBlue),
            )
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: () => _loadDashboard(showLoader: false),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final desktop = constraints.maxWidth >= 980;
                      return CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: <Widget>[
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              desktop ? 34 : 16,
                              8,
                              desktop ? 34 : 16,
                              16,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: Center(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 1180),
                                  child: Column(
                                    children: <Widget>[
                                      _buildHero(desktop: desktop),
                                      const SizedBox(height: 16),
                                      _buildFilters(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _buildPerformanceGrid(desktop: desktop),
                          const SliverToBoxAdapter(child: SizedBox(height: 40)),
                        ],
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildHero({required bool desktop}) {
    final summary = _summary;
    final firstName = _student?.firstName ?? 'Student';
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final hero = Container(
      width: double.infinity,
      padding: EdgeInsets.all(desktop ? 28 : 22),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: AppStyles.bentoRadius,
        boxShadow: AppStyles.glassShadow,
      ),
      child: desktop
          ? Row(
              children: <Widget>[
                Expanded(child: _buildHeroCopy(firstName, summary)),
                const SizedBox(width: 24),
                _buildScoreOrb(summary),
                const SizedBox(width: 24),
                _buildHeroMetrics(summary),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildHeroCopy(firstName, summary),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    _buildScoreOrb(summary, compact: true),
                    const SizedBox(width: 15),
                    Expanded(child: _buildHeroMetrics(summary)),
                  ],
                ),
              ],
            ),
    );
    return reduceMotion
        ? hero
        : hero.animate().fadeIn(duration: 420.ms).slideY(begin: .07, end: 0);
  }

  Widget _buildHeroCopy(String firstName, DashboardSummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.auto_graph_rounded,
              color: AppColors.electricCyan,
              size: 18,
            ),
            SizedBox(width: 7),
            Text(
              'OG ACADEMIC PULSE',
              style: TextStyle(
                color: AppColors.electricCyan,
                fontSize: 11,
                letterSpacing: 1.25,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Keep your momentum,\n$firstName.',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            height: 1.1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          summary.hasScores
              ? summary.band.heroMessage
              : 'Your registered modules are ready. Marks will appear as soon as they are published.',
          style: const TextStyle(
            color: Colors.white70,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildScoreOrb(DashboardSummary summary, {bool compact = false}) {
    final size = compact ? 104.0 : 132.0;
    return Semantics(
      label: summary.hasScores
          ? 'Current ICASS average ${summary.average.toStringAsFixed(1)} percent'
          : 'No captured marks yet',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            SizedBox.square(
              dimension: size,
              child: CircularProgressIndicator(
                value: summary.hasScores ? summary.average / 100 : 0,
                strokeWidth: compact ? 8 : 10,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  summary.hasScores
                      ? summary.band.color
                      : AppColors.electricCyan,
                ),
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  summary.hasScores
                      ? summary.average.toStringAsFixed(1)
                      : '—',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 24 : 31,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'AVERAGE',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroMetrics(DashboardSummary summary) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        _HeroMetric(
          icon: Icons.menu_book_outlined,
          value: '${summary.moduleCount}',
          label: 'Modules',
        ),
        _HeroMetric(
          icon: Icons.verified_outlined,
          value: '${summary.capturedCount}',
          label: 'Published',
        ),
        _HeroMetric(
          icon: summary.riskCount > 0
              ? Icons.warning_amber_rounded
              : Icons.shield_outlined,
          value: '${summary.riskCount}',
          label: 'At risk',
          warning: summary.riskCount > 0,
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return _GlassCard(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 660;
          final year = DropdownButtonFormField<int>(
            initialValue: _selectedYear,
            decoration: const InputDecoration(
              labelText: 'Academic year',
              prefixIcon: Icon(Icons.calendar_today_outlined),
            ),
            items: _availableYears
                .map(
                  (value) => DropdownMenuItem<int>(
                    value: value,
                    child: Text('$value'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              HapticFeedback.selectionClick();
              setState(() => _selectedYear = value);
            },
          );
          final semester = DropdownButtonFormField<int?>(
            initialValue: _selectedSemester,
            decoration: const InputDecoration(
              labelText: 'Academic period',
              prefixIcon: Icon(Icons.school_outlined),
            ),
            items: const <DropdownMenuItem<int?>>[
              DropdownMenuItem(value: null, child: Text('All semesters')),
              DropdownMenuItem(value: 1, child: Text('Semester 1')),
              DropdownMenuItem(value: 2, child: Text('Semester 2')),
              DropdownMenuItem(value: 3, child: Text('Annual')),
            ],
            onChanged: (value) {
              HapticFeedback.selectionClick();
              setState(() => _selectedSemester = value);
            },
          );
          final status = DropdownButtonFormField<String>(
            initialValue: _selectedStatus,
            decoration: const InputDecoration(
              labelText: 'Mark status',
              prefixIcon: Icon(Icons.fact_check_outlined),
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'all', child: Text('All statuses')),
              DropdownMenuItem(value: 'moderated', child: Text('Moderated')),
              DropdownMenuItem(value: 'captured', child: Text('Captured')),
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'missing', child: Text('Missing')),
            ],
            onChanged: (value) {
              HapticFeedback.selectionClick();
              setState(() => _selectedStatus = value ?? 'all');
            },
          );

          if (narrow) {
            return Column(
              children: <Widget>[
                year,
                const SizedBox(height: 10),
                semester,
                const SizedBox(height: 10),
                status,
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: year),
              const SizedBox(width: 10),
              Expanded(child: semester),
              const SizedBox(width: 10),
              Expanded(child: status),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPerformanceGrid({required bool desktop}) {
    final performances = _performances;
    if (performances.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(
          icon: Icons.insights_outlined,
          title: 'No modules for this period',
          subtitle:
              'Try another academic year, semester, or mark-status filter.',
          onReset: () => setState(() {
            _selectedYear = _availableYears.first;
            _selectedSemester = null;
            _selectedStatus = 'all';
          }),
        ),
      );
    }
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: desktop ? 34 : 16),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1040
                    ? 3
                    : constraints.maxWidth >= 680
                        ? 2
                        : 1;
                final width =
                    (constraints.maxWidth - ((columns - 1) * 14)) / columns;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: List<Widget>.generate(
                    performances.length,
                    (index) {
                      final card = SizedBox(
                        width: width,
                        child: _ModuleCard(
                          performance: performances[index],
                          onTap: () =>
                              _showModuleDetails(performances[index]),
                        ),
                      );
                      if (MediaQuery.disableAnimationsOf(context)) return card;
                      return card
                          .animate(delay: (index * 45).ms)
                          .fadeIn(duration: 320.ms)
                          .slideY(begin: .06, end: 0);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showModuleDetails(ModulePerformance performance) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        minChildSize: .55,
        maxChildSize: .94,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ModuleIcon(
                  color: performance.band.color,
                  label: performance.module.initials,
                  size: 58,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        performance.module.displayName,
                        style: const TextStyle(
                          color: AppColors.midnightInk,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        performance.hasScores
                            ? '${performance.average.toStringAsFixed(1)}% • '
                                '${performance.band.label}'
                            : 'Awaiting published marks',
                        style: TextStyle(
                          color: performance.band.color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (performance.marks.isEmpty)
              const _StatusNotice(
                icon: Icons.schedule_outlined,
                title: 'Marks not published yet',
                message:
                    'This registered module will update when official ICASS marks are released.',
                color: AppColors.warning,
              )
            else
              ...performance.marks.map(
                (mark) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AssessmentCard(mark: mark),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return _EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'ICASS marks could not load',
      subtitle: _error!,
      onReset: _loadDashboard,
      actionLabel: 'Try again',
    );
  }

  static String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('Socket') || text.contains('Network')) {
      return 'Check your internet connection and try again.';
    }
    if (text.contains('permission denied') ||
        text.contains('row-level security')) {
      return 'Your marks are protected, but this session no longer has access. Sign in again.';
    }
    return text.replaceFirst('PostgrestException(message: ', '').split(',').first;
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppStyles.bentoRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .78),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(color: Colors.white.withValues(alpha: .88)),
            boxShadow: AppStyles.softShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.performance,
    required this.onTap,
  });

  final ModulePerformance performance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final band = performance.band;
    return Semantics(
      button: true,
      label: performance.hasScores
          ? '${performance.module.displayName}, '
              '${performance.average.toStringAsFixed(1)} percent, ${band.label}'
          : '${performance.module.displayName}, marks pending',
      child: _GlassCard(
        child: InkWell(
          onTap: onTap,
          borderRadius: AppStyles.controlRadius,
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _ModuleIcon(
                      color: band.color,
                      label: performance.module.initials,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            performance.module.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.midnightInk,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            performance.lecturer,
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
                    _BandPill(band: band),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            performance.hasScores
                                ? performance.average.toStringAsFixed(1)
                                : '—',
                            style: const TextStyle(
                              color: AppColors.midnightInk,
                              fontSize: 31,
                              height: 1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            performance.hasScores
                                ? 'Current ICASS average'
                                : 'Awaiting marks',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${performance.publishedCount} published',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: AppStyles.pillRadius,
                  child: LinearProgressIndicator(
                    value:
                        performance.hasScores ? performance.average / 100 : 0,
                    minHeight: 8,
                    color: band.color,
                    backgroundColor: band.color.withValues(alpha: .12),
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: <Widget>[
                    _MiniStatus(
                      icon: Icons.verified_outlined,
                      value: '${performance.moderatedCount}',
                      label: 'Moderated',
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 14),
                    _MiniStatus(
                      icon: Icons.schedule_outlined,
                      value: '${performance.pendingCount}',
                      label: 'Pending',
                      color: AppColors.warning,
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.textMuted,
                      size: 19,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({required this.mark});

  final IcassMark mark;

  @override
  Widget build(BuildContext context) {
    final status = MarkStatusStyle.from(mark);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: AppStyles.controlRadius,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(status.icon, color: status.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  mark.componentName,
                  style: const TextStyle(
                    color: AppColors.midnightInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    status.label,
                    if (mark.weight > 0)
                      '${mark.weight.toStringAsFixed(mark.weight % 1 == 0 ? 0 : 1)}% weight',
                    if (mark.assessmentDate != null)
                      _formatDate(mark.assessmentDate!),
                  ].join(' • '),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            mark.score == null ? '—' : '${mark.score!.toStringAsFixed(1)}%',
            style: TextStyle(
              color: mark.score == null
                  ? AppColors.textMuted
                  : PerformanceBand.fromScore(mark.score!).color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleIcon extends StatelessWidget {
  const _ModuleIcon({
    required this.color,
    required this.label,
    this.size = 46,
  });

  final Color color;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[color, color.withValues(alpha: .72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * .31),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: .2),
            blurRadius: 13,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * .28,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BandPill extends StatelessWidget {
  const _BandPill({required this.band});

  final PerformanceBand band;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: band.color.withValues(alpha: .11),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(band.icon, size: 12, color: band.color),
          const SizedBox(width: 4),
          Text(
            band.label.toUpperCase(),
            style: TextStyle(
              color: band.color,
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatus extends StatelessWidget {
  const _MiniStatus({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          '$value $label',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.icon,
    required this.value,
    required this.label,
    this.warning = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            color: warning ? AppColors.ogGold : AppColors.electricCyan,
            size: 17,
          ),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusNotice extends StatelessWidget {
  const _StatusNotice({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: AppStyles.controlRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.midnightInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onReset,
    this.actionLabel = 'Reset filters',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onReset;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.vibeBlue.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.vibeBlue, size: 36),
            ),
            const SizedBox(height: 15),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class IcassMark {
  const IcassMark({
    required this.id,
    required this.studentId,
    required this.moduleId,
    required this.subjectName,
    required this.lecturerName,
    required this.componentName,
    required this.score,
    required this.weight,
    required this.status,
    required this.assessmentDate,
    required this.academicYear,
    required this.semester,
  });

  factory IcassMark.fromRow(Map<String, dynamic> row) => IcassMark(
        id: row['id'].toString(),
        studentId: row['student_id'].toString(),
        moduleId: _optional(row['module_id']),
        subjectName: row['subject_name']?.toString().trim() ?? 'Module',
        lecturerName:
            row['lecturer_name']?.toString().trim() ?? 'Module lecturer',
        componentName:
            row['component_name']?.toString().trim() ?? 'Assessment',
        score: _number(row['component_score']),
        weight: _number(row['component_weight']) ?? 0,
        status: row['mark_status']?.toString() ?? 'captured',
        assessmentDate: DateTime.tryParse(
          row['assessment_date']?.toString() ?? '',
        ),
        academicYear:
            int.tryParse(row['academic_year']?.toString() ?? '') ??
                DateTime.now().year,
        semester: int.tryParse(row['semester']?.toString() ?? '') ?? 1,
      );

  final String id;
  final String studentId;
  final String? moduleId;
  final String subjectName;
  final String lecturerName;
  final String componentName;
  final double? score;
  final double weight;
  final String status;
  final DateTime? assessmentDate;
  final int academicYear;
  final int semester;
}

class RegisteredModule {
  const RegisteredModule({
    required this.studentId,
    required this.moduleId,
    required this.academicYear,
    required this.semester,
    required this.status,
  });

  factory RegisteredModule.fromRow(Map<String, dynamic> row) =>
      RegisteredModule(
        studentId: row['student_id'].toString(),
        moduleId: row['module_id'].toString(),
        academicYear:
            int.tryParse(row['academic_year']?.toString() ?? '') ??
                DateTime.now().year,
        semester: int.tryParse(row['semester']?.toString() ?? '') ?? 1,
        status: row['status']?.toString() ?? 'active',
      );

  final String studentId;
  final String moduleId;
  final int academicYear;
  final int semester;
  final String status;
}

class AcademicModule {
  const AcademicModule({
    required this.id,
    required this.name,
    required this.code,
    required this.level,
  });

  factory AcademicModule.fromRow(Map<String, dynamic> row) => AcademicModule(
        id: row['id'].toString(),
        name: row['name']?.toString().trim() ?? 'Registered module',
        code: row['code']?.toString().trim() ?? '',
        level: row['level']?.toString().trim() ?? '',
      );

  final String id;
  final String name;
  final String code;
  final String level;

  String get displayName => code.isEmpty ? name : '$code • $name';
  String get initials {
    if (code.isNotEmpty) return code.substring(0, code.length.clamp(1, 3));
    return name
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word[0].toUpperCase())
        .join();
  }
}

class ModulePerformance {
  const ModulePerformance({
    required this.module,
    required this.marks,
  });

  final AcademicModule module;
  final List<IcassMark> marks;

  List<IcassMark> get scoredMarks =>
      marks.where((mark) => mark.score != null).toList();
  bool get hasScores => scoredMarks.isNotEmpty;

  double get average {
    final scored = scoredMarks;
    if (scored.isEmpty) return 0;
    final weighted = scored.where((mark) => mark.weight > 0).toList();
    final totalWeight =
        weighted.fold<double>(0, (sum, mark) => sum + mark.weight);
    if (weighted.isNotEmpty && totalWeight > 0) {
      return weighted.fold<double>(
            0,
            (sum, mark) => sum + (mark.score! * mark.weight),
          ) /
          totalWeight;
    }
    return scored.fold<double>(0, (sum, mark) => sum + mark.score!) /
        scored.length;
  }

  PerformanceBand get band =>
      hasScores ? PerformanceBand.fromScore(average) : PerformanceBand.pending;
  int get publishedCount =>
      marks.where((mark) => mark.score != null).length;
  int get moderatedCount =>
      marks.where((mark) => mark.status == 'moderated').length;
  int get pendingCount => marks
      .where((mark) => mark.status == 'pending' || mark.status == 'missing')
      .length;
  String get lecturer => marks
      .map((mark) => mark.lecturerName)
      .where((value) => value.isNotEmpty)
      .firstOrNull ??
      'Module lecturer';
}

class DashboardSummary {
  const DashboardSummary({
    required this.average,
    required this.moduleCount,
    required this.capturedCount,
    required this.riskCount,
    required this.hasScores,
  });

  factory DashboardSummary.from(List<ModulePerformance> performances) {
    final scored =
        performances.where((performance) => performance.hasScores).toList();
    final average = scored.isEmpty
        ? 0.0
        : scored.fold<double>(
              0,
              (sum, performance) => sum + performance.average,
            ) /
            scored.length;
    return DashboardSummary(
      average: average,
      moduleCount: performances.length,
      capturedCount: performances.fold<int>(
        0,
        (sum, performance) => sum + performance.publishedCount,
      ),
      riskCount: scored
          .where((performance) => performance.average < 40)
          .length,
      hasScores: scored.isNotEmpty,
    );
  }

  final double average;
  final int moduleCount;
  final int capturedCount;
  final int riskCount;
  final bool hasScores;

  PerformanceBand get band =>
      hasScores ? PerformanceBand.fromScore(average) : PerformanceBand.pending;
}

enum PerformanceBand {
  risk,
  focus,
  pass,
  distinction,
  pending;

  static PerformanceBand fromScore(double score) {
    if (score < 40) return risk;
    if (score < 50) return focus;
    if (score < 75) return pass;
    return distinction;
  }

  int get rank => switch (this) {
        risk => 0,
        focus => 1,
        pending => 2,
        pass => 3,
        distinction => 4,
      };

  String get label => switch (this) {
        risk => 'At risk',
        focus => 'Needs focus',
        pass => 'On track',
        distinction => 'Distinction',
        pending => 'Pending',
      };

  String get heroMessage => switch (this) {
        risk =>
          'Some modules need immediate attention. Start with the lowest result.',
        focus =>
          'You are close to a pass. Consistent improvement can change the outcome.',
        pass =>
          'You are currently on track. Keep building on this performance.',
        distinction =>
          'Excellent performance. You are currently in distinction territory.',
        pending =>
          'Published marks will appear here as they become available.',
      };

  Color get color => switch (this) {
        risk => AppColors.danger,
        focus => AppColors.warning,
        pass => AppColors.success,
        distinction => AppColors.ogGold,
        pending => AppColors.textMuted,
      };

  IconData get icon => switch (this) {
        risk => Icons.warning_amber_rounded,
        focus => Icons.trending_up_rounded,
        pass => Icons.check_circle_outline_rounded,
        distinction => Icons.workspace_premium_outlined,
        pending => Icons.schedule_outlined,
      };
}

class MarkStatusStyle {
  const MarkStatusStyle({
    required this.label,
    required this.color,
    required this.icon,
  });

  factory MarkStatusStyle.from(IcassMark mark) {
    return switch (mark.status) {
      'moderated' => const MarkStatusStyle(
          label: 'Moderated',
          color: AppColors.success,
          icon: Icons.verified_outlined,
        ),
      'pending' => const MarkStatusStyle(
          label: 'Pending',
          color: AppColors.warning,
          icon: Icons.schedule_outlined,
        ),
      'missing' => const MarkStatusStyle(
          label: 'Missing',
          color: AppColors.danger,
          icon: Icons.error_outline_rounded,
        ),
      _ => const MarkStatusStyle(
          label: 'Captured',
          color: AppColors.vibeBlue,
          icon: Icons.fact_check_outlined,
        ),
    };
  }

  final String label;
  final Color color;
  final IconData icon;
}

class StudentContext {
  const StudentContext({
    required this.firstName,
    required this.studentNumber,
    required this.department,
    required this.level,
  });

  factory StudentContext.fromRow(Map<String, dynamic> row, User user) {
    final name = row['name']?.toString().trim();
    return StudentContext(
      firstName: name?.isNotEmpty == true
          ? name!
          : user.email?.split('@').first ?? 'Student',
      studentNumber: row['student_number']?.toString() ?? '',
      department: row['department']?.toString() ?? '',
      level: row['level']?.toString() ?? '',
    );
  }

  final String firstName;
  final String studentNumber;
  final String department;
  final String level;
}

double? _number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

String? _optional(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String _formatDate(DateTime date) {
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
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
