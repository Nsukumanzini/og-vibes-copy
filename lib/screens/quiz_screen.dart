import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/screens/lms_quiz_lockdown_screen.dart';
import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<QuizItem> _quizzes = <QuizItem>[];
  final List<QuizAttempt> _attempts = <QuizAttempt>[];
  final List<ModuleRef> _modules = <ModuleRef>[];
  final Set<String> _registeredModuleIds = <String>{};
  final Map<String, LecturerProfile> _lecturers =
      <String, LecturerProfile>{};

  Timer? _clock;
  StreamSubscription<List<Map<String, dynamic>>>? _quizSubscription;
  String _search = '';
  String _moduleFilter = 'All';
  String _lecturerFilter = 'All';
  String _difficultyFilter = 'All';
  String _statusFilter = 'All';
  String _dateFilter = 'Any date';
  bool _myModulesOnly = true;
  bool _hasRegistrationMatch = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          HapticFeedback.selectionClick();
        }
      });
    _loadDashboard();
    _listenForChanges();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _quizSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard({bool showLoader = true}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'You must be signed in to view quizzes.';
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
            .select('id, name, surname, photo_url, is_verified'),
        Supabase.instance.client.from('quizzes').select('''
          id,
          module_id,
          lecturer_id,
          title,
          description,
          lecturer_name,
          reward,
          duration_minutes,
          passing_score,
          quiz_date,
          available_from,
          closes_at,
          difficulty,
          max_attempts,
          randomize_questions,
          randomize_options,
          secure_mode,
          reward_points,
          instructions,
          results_release,
          published,
          questions:quiz_questions(
            id,
            quiz_id,
            question_text,
            option_a,
            option_b,
            option_c,
            option_d,
            points,
            position
          )
        ''').eq('published', true).order('quiz_date', ascending: true),
        Supabase.instance.client
            .from('quiz_attempts')
            .select(
              'id, quiz_id, user_id, attempt_number, status, started_at, '
              'expires_at, completed_at, question_order, current_question, '
              'focus_violations, score_points, total_points, percentage, '
              'passed, reward_points',
            )
            .eq('user_id', user.id)
            .order('started_at', ascending: false),
      ]);

      _buildAcademicContext(
        profile: results[0] is Map
            ? Map<String, dynamic>.from(results[0] as Map)
            : <String, dynamic>{},
        programmes: List<Map<String, dynamic>>.from(
          results[1] as List<dynamic>? ?? <dynamic>[],
        ),
        moduleRows: List<Map<String, dynamic>>.from(
          results[2] as List<dynamic>? ?? <dynamic>[],
        ),
        lecturerRows: List<Map<String, dynamic>>.from(
          results[3] as List<dynamic>? ?? <dynamic>[],
        ),
      );
      final quizRows = List<Map<String, dynamic>>.from(
        results[4] as List<dynamic>? ?? <dynamic>[],
      );
      final attemptRows = List<Map<String, dynamic>>.from(
        results[5] as List<dynamic>? ?? <dynamic>[],
      );
      final attempts = attemptRows.map(QuizAttempt.fromRow).toList();
      final quizzes = quizRows
          .map(
            (row) => QuizItem.fromSupabaseRow(
              row,
              module: _moduleById(_text(row['module_id'])),
              lecturer: _lecturers[_text(row['lecturer_id'])],
              attempts: attempts
                  .where((attempt) => attempt.quizId == _text(row['id']))
                  .toList(),
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _attempts
          ..clear()
          ..addAll(attempts);
        _quizzes
          ..clear()
          ..addAll(quizzes);
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
    required List<Map<String, dynamic>> moduleRows,
    required List<Map<String, dynamic>> lecturerRows,
  }) {
    final department = _normalize(profile['department']);
    final level = _normalize(profile['level']);
    final programmeIds = programmes.where((programme) {
      final name = _normalize(programme['name']);
      return department.isNotEmpty &&
          (department.contains(name) || name.contains(department));
    }).map((programme) => _text(programme['id'])).toSet();

    _modules
      ..clear()
      ..addAll(moduleRows.map(ModuleRef.fromRow));
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
          final name = <String>[
            _text(row['name']),
            _text(row['surname']),
          ].where((part) => part.isNotEmpty).join(' ');
          return MapEntry<String, LecturerProfile>(
            _text(row['id']),
            LecturerProfile(
              name: name.isEmpty ? 'Academic staff' : name,
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
      if (mounted) unawaited(_loadDashboard(showLoader: false));
    }, onError: (_) {});
  }

  ModuleRef? _moduleById(String id) {
    for (final module in _modules) {
      if (module.id == id) return module;
    }
    return null;
  }

  List<QuizItem> get _filteredQuizzes {
    final now = DateTime.now();
    return _quizzes.where((quiz) {
      if (_myModulesOnly && _hasRegistrationMatch) {
        if (quiz.moduleId.isNotEmpty &&
            !_registeredModuleIds.contains(quiz.moduleId)) {
          return false;
        }
      }
      final query = _search.trim().toLowerCase();
      if (query.isNotEmpty &&
          !quiz.title.toLowerCase().contains(query) &&
          !quiz.moduleLabel.toLowerCase().contains(query) &&
          !quiz.lecturer.name.toLowerCase().contains(query) &&
          !quiz.description.toLowerCase().contains(query)) {
        return false;
      }
      if (_moduleFilter != 'All' && quiz.moduleId != _moduleFilter) {
        return false;
      }
      if (_lecturerFilter != 'All' &&
          quiz.lecturer.name != _lecturerFilter) {
        return false;
      }
      if (_difficultyFilter != 'All' &&
          quiz.difficulty != _difficultyFilter) {
        return false;
      }
      if (_statusFilter != 'All' && quiz.statusLabel != _statusFilter) {
        return false;
      }
      if (_dateFilter == 'Today' &&
          !isSameDate(quiz.availableAt.toLocal(), now)) {
        return false;
      }
      if (_dateFilter == 'Next 7 days' &&
          (quiz.availableAt.toLocal().isBefore(now) ||
              quiz.availableAt
                  .toLocal()
                  .isAfter(now.add(const Duration(days: 7))))) {
        return false;
      }
      return true;
    }).toList();
  }

  List<QuizItem> get _availableQuizzes =>
      _filteredQuizzes.where((quiz) => quiz.isAvailable).toList();
  List<QuizItem> get _upcomingQuizzes =>
      _filteredQuizzes.where((quiz) => quiz.isUpcoming).toList();
  List<QuizItem> get _completedQuizzes =>
      _filteredQuizzes.where((quiz) => quiz.hasCompletedAttempt).toList();
  List<QuizAttempt> get _completedAttempts =>
      _attempts.where((attempt) => attempt.status == 'completed').toList();

  double get _averageScore {
    final completed = _completedAttempts
        .where((attempt) => attempt.percentage != null)
        .toList();
    if (completed.isEmpty) return 0;
    return completed.fold<double>(
          0,
          (total, attempt) => total + attempt.percentage!,
        ) /
        completed.length;
  }

  int get _rewardTotal => _completedAttempts.fold<int>(
        0,
        (total, attempt) => total + attempt.rewardPoints,
      );

  int get _passStreak {
    final completed = List<QuizAttempt>.from(_completedAttempts)
      ..sort((a, b) {
        final aDate = a.completedAt ?? a.startedAt;
        final bDate = b.completedAt ?? b.startedAt;
        return bDate.compareTo(aDate);
      });
    var streak = 0;
    for (final attempt in completed) {
      if (attempt.passed == true) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Quiz'),
        backgroundColor: Colors.transparent,
        actions: <Widget>[
          IconButton(
            onPressed: _showFilters,
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Filter quizzes',
          ),
          IconButton(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh quizzes',
          ),
        ],
      ),
      body: _isLoading && _quizzes.isEmpty
          ? _buildLoadingState()
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null && _quizzes.isEmpty) return _buildErrorState();
    return Column(
      children: <Widget>[
        Expanded(
          child: NestedScrollView(
            headerSliverBuilder: (_, _) => <Widget>[
              SliverToBoxAdapter(child: _buildHero()),
              SliverToBoxAdapter(child: _buildSearchAndModuleFilter()),
              SliverToBoxAdapter(child: _buildTabs()),
            ],
            body: TabBarView(
              controller: _tabController,
              children: <Widget>[
                _buildQuizGrid(
                  _availableQuizzes,
                  'No quizzes are currently available.',
                  _QuizCardMode.available,
                ),
                _buildQuizGrid(
                  _upcomingQuizzes,
                  'No upcoming quizzes match these filters.',
                  _QuizCardMode.upcoming,
                ),
                _buildQuizGrid(
                  _completedQuizzes,
                  'You have not completed a quiz yet.',
                  _QuizCardMode.completed,
                ),
                _buildResultsTab(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    final next = _upcomingQuizzes.isEmpty
        ? null
        : (List<QuizItem>.from(_upcomingQuizzes)
              ..sort((a, b) => a.availableAt.compareTo(b.availableAt)))
            .first;
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
              right: -38,
              top: -56,
              child: Container(
                width: 180,
                height: 180,
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
                    Icon(Icons.bolt_rounded, color: AppColors.electricCyan),
                    SizedBox(width: 9),
                    Text(
                      'OG QUIZ ARENA',
                      style: TextStyle(
                        color: AppColors.electricCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.25,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Think fast. Learn deeper.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Secure attempts, instant progress and meaningful rewards.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    _heroStat(
                      '${_availableQuizzes.length}',
                      'Available',
                      AppColors.electricCyan,
                    ),
                    _heroStat(
                      '${_upcomingQuizzes.length}',
                      'Upcoming',
                      AppColors.ogGold,
                    ),
                    _heroStat(
                      '${_completedAttempts.length}',
                      'Completed',
                      AppColors.success,
                    ),
                    _heroStat(
                      '${_averageScore.round()}%',
                      'Average',
                      const Color(0xFFB8A5FF),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .17),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        next == null
                            ? Icons.emoji_events_outlined
                            : Icons.timer_outlined,
                        color: AppColors.ogGold,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              next == null
                                  ? '$_passStreak quiz pass streak • $_rewardTotal points'
                                  : 'Next: ${next.title}',
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
                                  ? 'Keep building your momentum'
                                  : _countdown(next.availableAt),
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

  Widget _buildSearchAndModuleFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: _glass(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                hintText: 'Search quizzes, modules or lecturers',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          setState(() => _search = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .68),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
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
                IconButton.filledTonal(
                  onPressed: _showFilters,
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'More filters',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _glass(
        padding: const EdgeInsets.all(5),
        child: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
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
            Tab(text: 'Available ${_availableQuizzes.length}'),
            Tab(text: 'Upcoming ${_upcomingQuizzes.length}'),
            Tab(text: 'Completed ${_completedQuizzes.length}'),
            Tab(text: 'Results ${_completedAttempts.length}'),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizGrid(
    List<QuizItem> quizzes,
    String emptyText,
    _QuizCardMode mode,
  ) {
    if (quizzes.isEmpty) return _buildEmptyState(emptyText);
    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 850) {
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 110),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 520,
                mainAxisExtent: 385,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: quizzes.length,
              itemBuilder: (_, index) =>
                  _buildQuizCard(quizzes[index], index, mode),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 110),
            itemCount: quizzes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 13),
            itemBuilder: (_, index) =>
                _buildQuizCard(quizzes[index], index, mode),
          );
        },
      ),
    );
  }

  Widget _buildQuizCard(QuizItem quiz, int index, _QuizCardMode mode) {
    final attempt = quiz.latestAttempt;
    final accent = mode == _QuizCardMode.completed
        ? AppColors.success
        : mode == _QuizCardMode.upcoming
            ? AppColors.warning
            : AppColors.vibeBlue;
    return _glass(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: mode == _QuizCardMode.completed
                      ? const LinearGradient(
                          colors: <Color>[
                            AppColors.success,
                            Color(0xFF42C997),
                          ],
                        )
                      : AppStyles.brandGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  mode == _QuizCardMode.completed
                      ? Icons.workspace_premium_rounded
                      : Icons.quiz_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            quiz.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.midnightInk,
                              fontSize: 17,
                              height: 1.18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _difficultyPill(quiz.difficulty),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      quiz.moduleLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            quiz.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              height: 1.4,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              _metaPill(Icons.timer_outlined, '${quiz.durationMinutes} min'),
              _metaPill(
                Icons.emoji_events_outlined,
                'Pass ${quiz.passingScore}%',
              ),
              _metaPill(
                Icons.help_outline_rounded,
                '${quiz.questions.length} questions',
              ),
              _metaPill(
                Icons.replay_rounded,
                '${quiz.attempts.length}/${quiz.maxAttempts} attempts',
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: <Widget>[
              _lecturerAvatar(quiz.lecturer),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        quiz.lecturer.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.midnightInk,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (quiz.lecturer.verified) ...<Widget>[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified_rounded,
                        color: AppColors.vibeBlue,
                        size: 15,
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                mode == _QuizCardMode.completed
                    ? '${attempt?.percentage?.round() ?? 0}%'
                    : _countdown(
                        mode == _QuizCardMode.upcoming
                            ? quiz.availableAt
                            : quiz.closesAt,
                      ),
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const Spacer(),
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            child: mode == _QuizCardMode.completed
                ? OutlinedButton.icon(
                    onPressed: attempt == null
                        ? null
                        : () => _openResult(quiz, attempt),
                    icon: const Icon(Icons.insights_rounded),
                    label: const Text('View result'),
                  )
                : mode == _QuizCardMode.upcoming
                    ? FilledButton.tonalIcon(
                        onPressed: () => _showQuizDetails(quiz),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('View quiz details'),
                      )
                    : FilledButton.icon(
                        onPressed: quiz.canAttempt
                            ? () => _showQuizDetails(quiz)
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.vibeBlue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: Icon(
                          quiz.inProgressAttempt == null
                              ? Icons.play_arrow_rounded
                              : Icons.restore_rounded,
                        ),
                        label: Text(
                          quiz.inProgressAttempt == null
                              ? 'Open quiz'
                              : 'Resume secure attempt',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
          ),
        ],
      ),
    )
        .animate(delay: (45 * index).ms)
        .fadeIn(duration: 340.ms)
        .slideY(begin: .06, end: 0);
  }

  Widget _buildResultsTab() {
    final attempts = List<QuizAttempt>.from(_completedAttempts)
      ..sort((a, b) {
        final aDate = a.completedAt ?? a.startedAt;
        final bDate = b.completedAt ?? b.startedAt;
        return bDate.compareTo(aDate);
      });
    if (attempts.isEmpty) {
      return _buildEmptyState('Complete a quiz to unlock your results.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 110),
      children: <Widget>[
        _buildAchievementStrip(),
        const SizedBox(height: 13),
        ...List<Widget>.generate(attempts.length, (index) {
          final attempt = attempts[index];
          final quiz = _quizzes.where((quiz) => quiz.id == attempt.quizId);
          if (quiz.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildResultCard(quiz.first, attempt, index),
          );
        }),
      ],
    );
  }

  Widget _buildAchievementStrip() {
    return _glass(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          _achievement(
            Icons.local_fire_department_rounded,
            '$_passStreak',
            'Pass streak',
            AppColors.danger,
          ),
          _achievement(
            Icons.stars_rounded,
            '$_rewardTotal',
            'Reward points',
            AppColors.warning,
          ),
          _achievement(
            Icons.insights_rounded,
            '${_averageScore.round()}%',
            'Average',
            AppColors.vibeBlue,
          ),
        ],
      ),
    );
  }

  Widget _achievement(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.midnightInk,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(QuizItem quiz, QuizAttempt attempt, int index) {
    final color = attempt.passed == true ? AppColors.success : AppColors.danger;
    return InkWell(
      onTap: () => _openResult(quiz, attempt),
      borderRadius: AppStyles.controlRadius,
      child: _glass(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 55,
              height: 55,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  CircularProgressIndicator(
                    value: (attempt.percentage ?? 0) / 100,
                    strokeWidth: 6,
                    backgroundColor: color.withValues(alpha: .10),
                    color: color,
                  ),
                  Text(
                    '${attempt.percentage?.round() ?? 0}%',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    quiz.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.midnightInk,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${attempt.passed == true ? 'Passed' : 'Not passed'} • '
                    'Attempt ${attempt.attemptNumber} • '
                    '+${attempt.rewardPoints} points',
                    style: TextStyle(
                      color: color,
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
    )
        .animate(delay: (45 * index).ms)
        .fadeIn()
        .slideX(begin: .04, end: 0);
  }

  Widget _difficultyPill(String difficulty) {
    final color = difficulty.toLowerCase() == 'advanced'
        ? AppColors.danger
        : difficulty.toLowerCase() == 'easy'
            ? AppColors.success
            : AppColors.vibeBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Text(
        difficulty.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
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

  Widget _lecturerAvatar(LecturerProfile lecturer, {double radius = 14}) {
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

  Future<void> _showQuizDetails(QuizItem quiz) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAFF),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: AppStyles.brandGradient,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Icon(Icons.quiz_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          quiz.title,
                          style: const TextStyle(
                            color: AppColors.midnightInk,
                            fontSize: 21,
                            height: 1.15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          quiz.moduleLabel,
                          style: const TextStyle(
                            color: AppColors.vibeBlue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _difficultyPill(quiz.difficulty),
                ],
              ),
              const SizedBox(height: 17),
              Text(
                quiz.description,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _metaPill(
                    Icons.timer_outlined,
                    '${quiz.durationMinutes} minutes',
                  ),
                  _metaPill(
                    Icons.emoji_events_outlined,
                    '${quiz.passingScore}% pass mark',
                  ),
                  _metaPill(
                    Icons.help_outline_rounded,
                    '${quiz.questions.length} questions',
                  ),
                  _metaPill(
                    Icons.replay_rounded,
                    '${quiz.maxAttempts} attempt${quiz.maxAttempts == 1 ? '' : 's'}',
                  ),
                  _metaPill(
                    Icons.stars_rounded,
                    '${quiz.rewardPoints} reward points',
                  ),
                ],
              ),
              const SizedBox(height: 17),
              _rule(
                Icons.save_outlined,
                'Answers save automatically after every selection.',
              ),
              _rule(
                Icons.shuffle_rounded,
                quiz.randomizeQuestions || quiz.randomizeOptions
                    ? 'Questions or options are randomized per attempt.'
                    : 'Questions follow the lecturer’s published order.',
              ),
              _rule(
                Icons.shield_outlined,
                quiz.secureMode
                    ? 'Secure mode records focus and app-switch events.'
                    : 'Standard quiz mode is enabled.',
              ),
              if (quiz.instructions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                const Text(
                  'Lecturer instructions',
                  style: TextStyle(
                    color: AppColors.midnightInk,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  quiz.instructions,
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
                  color: quiz.isUpcoming
                      ? AppColors.warning.withValues(alpha: .09)
                      : AppColors.vibeBlue.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  quiz.isUpcoming
                      ? 'Opens ${_countdown(quiz.availableAt)}'
                      : quiz.isClosed
                          ? 'This quiz is closed'
                          : 'Closes ${_countdown(quiz.closesAt)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: quiz.isUpcoming
                        ? AppColors.warning
                        : AppColors.vibeBlue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: quiz.canAttempt
                          ? () {
                              Navigator.pop(sheetContext);
                              _launchSecureQuiz(quiz);
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.vibeBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: Icon(
                        quiz.inProgressAttempt == null
                            ? Icons.lock_rounded
                            : Icons.restore_rounded,
                      ),
                      label: Text(
                        quiz.inProgressAttempt == null
                            ? 'Enter secure quiz'
                            : 'Resume attempt',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rule(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: AppColors.vibeBlue, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchSecureQuiz(QuizItem quiz) async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LmsQuizLockdownScreen(quiz: quiz.toMap()),
      ),
    );
    if (completed == true && mounted) {
      await _loadDashboard(showLoader: false);
      _tabController.animateTo(3);
    }
  }

  void _openResult(QuizItem quiz, QuizAttempt attempt) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuizResultScreen(
          quizTitle: quiz.title,
          passingScore: quiz.passingScore,
          result: QuizResultData.fromAttempt(attempt),
          popWithCompletion: false,
        ),
      ),
    );
  }

  Future<void> _showFilters() async {
    HapticFeedback.selectionClick();
    var module = _moduleFilter;
    var lecturer = _lecturerFilter;
    var difficulty = _difficultyFilter;
    var status = _statusFilter;
    var date = _dateFilter;
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
                  'Filter quizzes',
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: difficulty,
                        decoration:
                            const InputDecoration(labelText: 'Difficulty'),
                        items: _difficultyOptions
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setSheetState(
                          () => difficulty = value ?? 'All',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration:
                            const InputDecoration(labelText: 'Status'),
                        items: const <String>[
                          'All',
                          'Available',
                          'Upcoming',
                          'Completed',
                          'Closed',
                        ]
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
                  initialValue: date,
                  decoration: const InputDecoration(labelText: 'Date'),
                  items: const <String>['Any date', 'Today', 'Next 7 days']
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
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _moduleFilter = module;
                      _lecturerFilter = lecturer;
                      _difficultyFilter = difficulty;
                      _statusFilter = status;
                      _dateFilter = date;
                    });
                    Navigator.pop(context);
                    HapticFeedback.mediumImpact();
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Apply filters'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _moduleFilter = 'All';
                      _lecturerFilter = 'All';
                      _difficultyFilter = 'All';
                      _statusFilter = 'All';
                      _dateFilter = 'Any date';
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
    final modules = _myModulesOnly && _hasRegistrationMatch
        ? _modules
            .where((module) => _registeredModuleIds.contains(module.id))
            .toList()
        : List<ModuleRef>.from(_modules);
    modules.sort((a, b) => a.displayName.compareTo(b.displayName));
    return <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(value: 'All', child: Text('All modules')),
      ...modules.map(
        (module) => DropdownMenuItem<String>(
          value: module.id,
          child: Text(module.displayName, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
  }

  List<String> get _lecturerOptions {
    final values = _quizzes
        .map((quiz) => quiz.lecturer.name)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return <String>['All', ...values];
  }

  List<String> get _difficultyOptions {
    final values = _quizzes.map((quiz) => quiz.difficulty).toSet().toList()
      ..sort();
    return <String>['All', ...values];
  }

  Widget _buildEmptyState(String text) {
    return Center(
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
                Icons.quiz_outlined,
                color: AppColors.vibeBlue,
                size: 36,
              ),
            ),
            const SizedBox(height: 15),
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
                color: AppColors.danger,
                size: 52,
              ),
              const SizedBox(height: 13),
              const Text(
                'Quizzes are temporarily unavailable',
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
                onPressed: _loadDashboard,
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
              height: 270,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppStyles.bentoRadius,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppStyles.controlRadius,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 330,
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

  String _countdown(DateTime? value) {
    if (value == null) return 'No closing date';
    final difference = value.toLocal().difference(DateTime.now());
    if (difference.isNegative) return 'Closed';
    if (difference.inDays > 0) {
      return 'In ${difference.inDays}d ${difference.inHours % 24}h';
    }
    if (difference.inHours > 0) {
      return 'In ${difference.inHours}h ${difference.inMinutes % 60}m';
    }
    return 'In ${difference.inMinutes}m ${difference.inSeconds % 60}s';
  }

  static bool isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static String _text(dynamic value) => value?.toString().trim() ?? '';
  static String _normalize(dynamic value) =>
      _text(value).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

enum _QuizCardMode { available, upcoming, completed }

class QuizItem {
  const QuizItem({
    required this.id,
    required this.moduleId,
    required this.moduleLabel,
    required this.title,
    required this.description,
    required this.lecturer,
    required this.reward,
    required this.durationMinutes,
    required this.passingScore,
    required this.availableAt,
    required this.closesAt,
    required this.difficulty,
    required this.maxAttempts,
    required this.randomizeQuestions,
    required this.randomizeOptions,
    required this.secureMode,
    required this.rewardPoints,
    required this.instructions,
    required this.resultsRelease,
    required this.questions,
    required this.attempts,
  });

  final String id;
  final String moduleId;
  final String moduleLabel;
  final String title;
  final String description;
  final LecturerProfile lecturer;
  final String reward;
  final int durationMinutes;
  final int passingScore;
  final DateTime availableAt;
  final DateTime? closesAt;
  final String difficulty;
  final int maxAttempts;
  final bool randomizeQuestions;
  final bool randomizeOptions;
  final bool secureMode;
  final int rewardPoints;
  final String instructions;
  final String resultsRelease;
  final List<QuizQuestion> questions;
  final List<QuizAttempt> attempts;

  bool get isUpcoming => availableAt.toLocal().isAfter(DateTime.now());
  bool get isClosed =>
      closesAt != null && closesAt!.toLocal().isBefore(DateTime.now());
  bool get hasCompletedAttempt =>
      attempts.any((attempt) => attempt.status == 'completed');
  bool get isAvailable =>
      !isUpcoming &&
      !isClosed &&
      (inProgressAttempt != null || attempts.length < maxAttempts);
  bool get canAttempt => isAvailable && questions.isNotEmpty;
  String get statusLabel => hasCompletedAttempt
      ? 'Completed'
      : isUpcoming
          ? 'Upcoming'
          : isClosed
              ? 'Closed'
              : 'Available';

  QuizAttempt? get inProgressAttempt {
    for (final attempt in attempts) {
      if (attempt.status == 'in_progress') return attempt;
    }
    return null;
  }

  QuizAttempt? get latestAttempt {
    if (attempts.isEmpty) return null;
    final sorted = List<QuizAttempt>.from(attempts)
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sorted.first;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'module_id': moduleId,
      'module_label': moduleLabel,
      'title': title,
      'description': description,
      'lecturer': lecturer.name,
      'reward': reward,
      'duration_minutes': durationMinutes,
      'passing_score': passingScore,
      'available_at': availableAt.toIso8601String(),
      'closes_at': closesAt?.toIso8601String(),
      'difficulty': difficulty,
      'max_attempts': maxAttempts,
      'randomize_questions': randomizeQuestions,
      'randomize_options': randomizeOptions,
      'secure_mode': secureMode,
      'reward_points': rewardPoints,
      'instructions': instructions,
      'results_release': resultsRelease,
      'questions': questions.map((question) => question.toMap()).toList(),
    };
  }

  factory QuizItem.fromSupabaseRow(
    Map<String, dynamic> row, {
    required ModuleRef? module,
    required LecturerProfile? lecturer,
    required List<QuizAttempt> attempts,
  }) {
    final lecturerName = _QuizScreenState._text(row['lecturer_name']);
    final date = DateTime.tryParse(_QuizScreenState._text(row['available_from'])) ??
        DateTime.tryParse(_QuizScreenState._text(row['quiz_date'])) ??
        DateTime.now();
    final questions = List<Map<String, dynamic>>.from(
      row['questions'] as List<dynamic>? ?? <dynamic>[],
    ).map(QuizQuestion.fromSupabaseRow).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return QuizItem(
      id: _QuizScreenState._text(row['id']),
      moduleId: _QuizScreenState._text(row['module_id']),
      moduleLabel: module?.displayName ?? 'General',
      title: _QuizScreenState._text(row['title']).isEmpty
          ? 'Untitled quiz'
          : _QuizScreenState._text(row['title']),
      description: _QuizScreenState._text(row['description']).isEmpty
          ? 'No description provided'
          : _QuizScreenState._text(row['description']),
      lecturer: lecturer ??
          LecturerProfile(
            name: lecturerName.isEmpty ? 'Academic staff' : lecturerName,
          ),
      reward: _QuizScreenState._text(row['reward']),
      durationMinutes:
          int.tryParse(row['duration_minutes']?.toString() ?? '') ?? 30,
      passingScore:
          int.tryParse(row['passing_score']?.toString() ?? '') ?? 50,
      availableAt: date,
      closesAt:
          DateTime.tryParse(_QuizScreenState._text(row['closes_at'])),
      difficulty: _QuizScreenState._text(row['difficulty']).isEmpty
          ? 'Standard'
          : _QuizScreenState._text(row['difficulty']),
      maxAttempts: int.tryParse(row['max_attempts']?.toString() ?? '') ?? 1,
      randomizeQuestions: row['randomize_questions'] != false,
      randomizeOptions: row['randomize_options'] != false,
      secureMode: row['secure_mode'] != false,
      rewardPoints:
          int.tryParse(row['reward_points']?.toString() ?? '') ?? 0,
      instructions: _QuizScreenState._text(row['instructions']),
      resultsRelease: _QuizScreenState._text(row['results_release']).isEmpty
          ? 'immediate'
          : _QuizScreenState._text(row['results_release']),
      questions: questions,
      attempts: attempts,
    );
  }
}

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.quizId,
    required this.text,
    required this.options,
    required this.points,
    required this.position,
  });

  final String id;
  final String quizId;
  final String text;
  final List<String> options;
  final int points;
  final int position;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'quiz_id': quizId,
        'text': text,
        'options': options,
        'points': points,
        'position': position,
      };

  factory QuizQuestion.fromSupabaseRow(Map<String, dynamic> row) {
    return QuizQuestion(
      id: _QuizScreenState._text(row['id']),
      quizId: _QuizScreenState._text(row['quiz_id']),
      text: _QuizScreenState._text(row['question_text']),
      options: <String>[
        _QuizScreenState._text(row['option_a']),
        _QuizScreenState._text(row['option_b']),
        _QuizScreenState._text(row['option_c']),
        _QuizScreenState._text(row['option_d']),
      ].where((option) => option.isNotEmpty).toList(),
      points: int.tryParse(row['points']?.toString() ?? '') ?? 1,
      position: int.tryParse(row['position']?.toString() ?? '') ?? 0,
    );
  }

  factory QuizQuestion.fromMap(Map<String, dynamic> row) {
    return QuizQuestion(
      id: _QuizScreenState._text(row['id']),
      quizId: _QuizScreenState._text(row['quiz_id']),
      text: _QuizScreenState._text(row['text']),
      options: List<String>.from(row['options'] as List<dynamic>? ?? <dynamic>[]),
      points: int.tryParse(row['points']?.toString() ?? '') ?? 1,
      position: int.tryParse(row['position']?.toString() ?? '') ?? 0,
    );
  }
}

class QuizAttempt {
  const QuizAttempt({
    required this.id,
    required this.quizId,
    required this.userId,
    required this.attemptNumber,
    required this.status,
    required this.startedAt,
    required this.expiresAt,
    required this.completedAt,
    required this.questionOrder,
    required this.currentQuestion,
    required this.focusViolations,
    required this.scorePoints,
    required this.totalPoints,
    required this.percentage,
    required this.passed,
    required this.rewardPoints,
  });

  final String id;
  final String quizId;
  final String userId;
  final int attemptNumber;
  final String status;
  final DateTime startedAt;
  final DateTime expiresAt;
  final DateTime? completedAt;
  final List<String> questionOrder;
  final int currentQuestion;
  final int focusViolations;
  final double? scorePoints;
  final double? totalPoints;
  final double? percentage;
  final bool? passed;
  final int rewardPoints;

  factory QuizAttempt.fromRow(Map<String, dynamic> row) {
    return QuizAttempt(
      id: _QuizScreenState._text(row['id']),
      quizId: _QuizScreenState._text(row['quiz_id']),
      userId: _QuizScreenState._text(row['user_id']),
      attemptNumber:
          int.tryParse(row['attempt_number']?.toString() ?? '') ?? 1,
      status: _QuizScreenState._text(row['status']),
      startedAt:
          DateTime.tryParse(_QuizScreenState._text(row['started_at'])) ??
              DateTime.now(),
      expiresAt:
          DateTime.tryParse(_QuizScreenState._text(row['expires_at'])) ??
              DateTime.now(),
      completedAt:
          DateTime.tryParse(_QuizScreenState._text(row['completed_at'])),
      questionOrder: List<String>.from(
        row['question_order'] as List<dynamic>? ?? <dynamic>[],
      ),
      currentQuestion:
          int.tryParse(row['current_question']?.toString() ?? '') ?? 0,
      focusViolations:
          int.tryParse(row['focus_violations']?.toString() ?? '') ?? 0,
      scorePoints:
          double.tryParse(row['score_points']?.toString() ?? ''),
      totalPoints:
          double.tryParse(row['total_points']?.toString() ?? ''),
      percentage: double.tryParse(row['percentage']?.toString() ?? ''),
      passed: row['passed'] as bool?,
      rewardPoints:
          int.tryParse(row['reward_points']?.toString() ?? '') ?? 0,
    );
  }
}

class QuizRunnerScreen extends StatefulWidget {
  const QuizRunnerScreen({super.key, required this.quiz});

  final Map<String, dynamic> quiz;

  @override
  State<QuizRunnerScreen> createState() => _QuizRunnerScreenState();
}

class _QuizRunnerScreenState extends State<QuizRunnerScreen>
    with WidgetsBindingObserver {
  final Map<String, int> _answers = <String, int>{};
  final Map<String, List<int>> _optionOrders = <String, List<int>>{};
  final Set<String> _savedAnswers = <String>{};
  final Random _random = Random();

  List<QuizQuestion> _questions = <QuizQuestion>[];
  QuizAttempt? _attempt;
  Timer? _timer;
  int _index = 0;
  int _secondsRemaining = 0;
  int _focusViolations = 0;
  double _questionScale = 1;
  bool _isInitializing = true;
  bool _isSubmitting = false;
  bool _isSaving = false;
  bool _offlineRecoveryActive = false;
  String? _errorMessage;

  String get _quizId => _QuizScreenState._text(widget.quiz['id']);
  String get _quizTitle => _QuizScreenState._text(widget.quiz['title']);
  bool get _secureMode => widget.quiz['secure_mode'] != false;
  bool get _randomizeQuestions =>
      widget.quiz['randomize_questions'] != false;
  bool get _randomizeOptions => widget.quiz['randomize_options'] != false;
  int get _passingScore =>
      int.tryParse(widget.quiz['passing_score']?.toString() ?? '') ?? 50;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_secureMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _initializeAttempt();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!_secureMode || _isInitializing || _isSubmitting) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      unawaited(_recordSecurityEvent(
        state == AppLifecycleState.paused ? 'app_paused' : 'focus_lost',
      ));
    }
  }

  Future<void> _initializeAttempt() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Your session has expired. Sign in and try again.';
      });
      return;
    }
    try {
      final rawQuestions = List<Map<String, dynamic>>.from(
        widget.quiz['questions'] as List<dynamic>? ?? <dynamic>[],
      );
      final sourceQuestions = rawQuestions.map(QuizQuestion.fromMap).toList();
      if (sourceQuestions.isEmpty) {
        throw StateError('This quiz has no published questions.');
      }

      final existingRows = await Supabase.instance.client
          .from('quiz_attempts')
          .select(
            'id, quiz_id, user_id, attempt_number, status, started_at, '
            'expires_at, completed_at, question_order, current_question, '
            'focus_violations, score_points, total_points, percentage, '
            'passed, reward_points',
          )
          .eq('quiz_id', _quizId)
          .eq('user_id', user.id)
          .eq('status', 'in_progress')
          .order('started_at', ascending: false)
          .limit(1);
      final rows = List<Map<String, dynamic>>.from(
        existingRows as List<dynamic>? ?? <dynamic>[],
      );

      if (rows.isNotEmpty) {
        _attempt = QuizAttempt.fromRow(rows.first);
        _questions = _orderQuestions(
          sourceQuestions,
          _attempt!.questionOrder,
        );
        _index = _attempt!.currentQuestion.clamp(0, _questions.length - 1);
        _focusViolations = _attempt!.focusViolations;
      } else {
        final ordered = List<QuizQuestion>.from(sourceQuestions);
        if (_randomizeQuestions) ordered.shuffle(_random);
        final inserted = await Supabase.instance.client
            .from('quiz_attempts')
            .insert(<String, dynamic>{
              'quiz_id': _quizId,
              'user_id': user.id,
              'attempt_number': 1,
              'expires_at': DateTime.now()
                  .add(
                    Duration(
                      minutes: int.tryParse(
                            widget.quiz['duration_minutes']?.toString() ?? '',
                          ) ??
                          30,
                    ),
                  )
                  .toUtc()
                  .toIso8601String(),
              'question_order':
                  ordered.map((question) => question.id).toList(),
            })
            .select(
              'id, quiz_id, user_id, attempt_number, status, started_at, '
              'expires_at, completed_at, question_order, current_question, '
              'focus_violations, score_points, total_points, percentage, '
              'passed, reward_points',
            )
            .single();
        _attempt = QuizAttempt.fromRow(inserted);
        _questions = ordered;
      }

      await _restoreAnswers();
      _secondsRemaining = max(
        0,
        _attempt!.expiresAt.toLocal().difference(DateTime.now()).inSeconds,
      );
      _startTimer();
      if (!mounted) return;
      setState(() => _isInitializing = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _errorMessage = _friendlyError(error);
      });
    }
  }

  List<QuizQuestion> _orderQuestions(
    List<QuizQuestion> source,
    List<String> order,
  ) {
    if (order.isEmpty) return source;
    final byId = <String, QuizQuestion>{
      for (final question in source) question.id: question,
    };
    final result = order
        .map((id) => byId[id])
        .whereType<QuizQuestion>()
        .toList();
    for (final question in source) {
      if (!result.any((existing) => existing.id == question.id)) {
        result.add(question);
      }
    }
    return result;
  }

  Future<void> _restoreAnswers() async {
    if (_attempt == null) return;
    try {
      final raw = await Supabase.instance.client
          .from('quiz_attempt_answers')
          .select(
            'question_id, selected_option, question_position, option_order',
          )
          .eq('attempt_id', _attempt!.id);
      for (final row in List<Map<String, dynamic>>.from(
        raw as List<dynamic>? ?? <dynamic>[],
      )) {
        final questionId = _QuizScreenState._text(row['question_id']);
        _answers[questionId] =
            int.tryParse(row['selected_option']?.toString() ?? '') ?? 0;
        _optionOrders[questionId] = List<int>.from(
          row['option_order'] as List<dynamic>? ?? <dynamic>[],
        );
        _savedAnswers.add(questionId);
      }
    } catch (_) {
      _offlineRecoveryActive = true;
    }

    final preferences = await SharedPreferences.getInstance();
    final cached = preferences.getString(_cacheKey);
    if (cached == null) return;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(cached) as Map);
      final cachedAnswers = Map<String, dynamic>.from(
        data['answers'] as Map? ?? <String, dynamic>{},
      );
      for (final entry in cachedAnswers.entries) {
        _answers.putIfAbsent(
          entry.key,
          () => int.tryParse(entry.value.toString()) ?? 0,
        );
      }
      final cachedOrders = Map<String, dynamic>.from(
        data['option_orders'] as Map? ?? <String, dynamic>{},
      );
      for (final entry in cachedOrders.entries) {
        _optionOrders.putIfAbsent(
          entry.key,
          () => List<int>.from(entry.value as List<dynamic>),
        );
      }
      _offlineRecoveryActive =
          _answers.keys.any((key) => !_savedAnswers.contains(key));
    } catch (_) {}
  }

  String get _cacheKey => 'quiz_attempt_${_attempt?.id ?? _quizId}';

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _isSubmitting) return;
      setState(() {
        _secondsRemaining = max(0, _secondsRemaining - 1);
      });
      if (_secondsRemaining == 300 ||
          _secondsRemaining == 60 ||
          _secondsRemaining == 30) {
        HapticFeedback.vibrate();
      }
      if (_secondsRemaining == 0) {
        _timer?.cancel();
        unawaited(_submitQuiz(autoSubmitted: true));
      }
    });
  }

  QuizQuestion get _currentQuestion => _questions[_index];

  List<int> _orderFor(QuizQuestion question) {
    return _optionOrders.putIfAbsent(question.id, () {
      final order = List<int>.generate(question.options.length, (index) => index);
      if (_randomizeOptions) order.shuffle(_random);
      return order;
    });
  }

  Future<void> _selectAnswer(int originalOption) async {
    final question = _currentQuestion;
    setState(() {
      _answers[question.id] = originalOption;
      _savedAnswers.remove(question.id);
      _isSaving = true;
    });
    HapticFeedback.selectionClick();
    await _cacheAnswers();
    try {
      await Supabase.instance.client.from('quiz_attempt_answers').upsert(
        <String, dynamic>{
          'attempt_id': _attempt!.id,
          'question_id': question.id,
          'selected_option': originalOption,
          'question_position': _index,
          'option_order': _orderFor(question),
        },
        onConflict: 'attempt_id,question_id',
      );
      await Supabase.instance.client
          .from('quiz_attempts')
          .update(<String, dynamic>{'current_question': _index})
          .eq('id', _attempt!.id);
      if (!mounted) return;
      setState(() {
        _savedAnswers.add(question.id);
        _offlineRecoveryActive = false;
        _isSaving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _offlineRecoveryActive = true;
        _isSaving = false;
      });
    }
  }

  Future<void> _cacheAnswers() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _cacheKey,
      jsonEncode(<String, dynamic>{
        'answers': _answers,
        'option_orders': _optionOrders,
        'index': _index,
      }),
    );
  }

  Future<void> _retryUnsavedAnswers() async {
    final unsaved = _answers.keys
        .where((questionId) => !_savedAnswers.contains(questionId))
        .toList();
    for (final questionId in unsaved) {
      final position =
          _questions.indexWhere((question) => question.id == questionId);
      if (position < 0) continue;
      try {
        await Supabase.instance.client.from('quiz_attempt_answers').upsert(
          <String, dynamic>{
            'attempt_id': _attempt!.id,
            'question_id': questionId,
            'selected_option': _answers[questionId],
            'question_position': position,
            'option_order': _orderFor(_questions[position]),
          },
          onConflict: 'attempt_id,question_id',
        );
        _savedAnswers.add(questionId);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _offlineRecoveryActive =
            _answers.keys.any((key) => !_savedAnswers.contains(key));
      });
    }
  }

  void _goToQuestion(int index) {
    if (index < 0 || index >= _questions.length) return;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
    unawaited(
      Supabase.instance.client
          .from('quiz_attempts')
          .update(<String, dynamic>{'current_question': index})
          .eq('id', _attempt!.id),
    );
  }

  Future<void> _recordSecurityEvent(String eventType) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _attempt == null) return;
    setState(() => _focusViolations++);
    try {
      await Supabase.instance.client.from('quiz_security_events').insert(
        <String, dynamic>{
          'attempt_id': _attempt!.id,
          'user_id': user.id,
          'event_type': eventType,
          'details': <String, dynamic>{
            'question_index': _index,
            'occurred_at': DateTime.now().toUtc().toIso8601String(),
          },
        },
      );
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.gpp_bad_rounded,
          color: AppColors.danger,
          size: 42,
        ),
        title: const Text('Focus change recorded'),
        content: Text(
          'Secure quiz mode detected that this assessment lost focus. '
          'Event $_focusViolations has been saved with your attempt.',
          textAlign: TextAlign.center,
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Return to quiz'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSubmit() async {
    final unanswered = _questions.length - _answers.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit quiz?'),
        content: Text(
          unanswered == 0
              ? 'All answers are saved. Your score will be calculated securely.'
              : '$unanswered question${unanswered == 1 ? '' : 's'} remain '
                  'unanswered. You can still submit.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Review answers'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit now'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _submitQuiz();
  }

  Future<void> _submitQuiz({bool autoSubmitted = false}) async {
    if (_isSubmitting || _attempt == null) return;
    setState(() => _isSubmitting = true);
    _timer?.cancel();
    await _retryUnsavedAnswers();
    if (_offlineRecoveryActive) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Some answers are still offline. Reconnect before submitting.',
          ),
        ),
      );
      return;
    }
    try {
      final raw = await Supabase.instance.client.rpc(
        'submit_quiz_attempt',
        params: <String, dynamic>{'p_attempt_id': _attempt!.id},
      );
      final rows = List<Map<String, dynamic>>.from(
        raw as List<dynamic>? ?? <dynamic>[],
      );
      if (rows.isEmpty) throw StateError('No result returned');
      final result = QuizResultData.fromRow(rows.first);
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_cacheKey);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<bool, void>(
        MaterialPageRoute<bool>(
          builder: (_) => QuizResultScreen(
            quizTitle: _quizTitle,
            passingScore: _passingScore,
            result: result,
            autoSubmitted: autoSubmitted,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = _friendlyError(error);
      });
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        backgroundColor: AppColors.midnightInk,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.electricCyan),
        ),
      );
    }
    if (_errorMessage != null && _attempt == null) {
      return Scaffold(
        backgroundColor: AppColors.auroraCanvas,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.danger,
                  size: 52,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.midnightInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 15),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Return'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _showLeaveWarning();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft):
              () => _goToQuestion(_index - 1),
          const SingleActivator(LogicalKeyboardKey.arrowRight):
              () => _goToQuestion(_index + 1),
          const SingleActivator(LogicalKeyboardKey.digit1):
              () => _selectVisibleOption(0),
          const SingleActivator(LogicalKeyboardKey.digit2):
              () => _selectVisibleOption(1),
          const SingleActivator(LogicalKeyboardKey.digit3):
              () => _selectVisibleOption(2),
          const SingleActivator(LogicalKeyboardKey.digit4):
              () => _selectVisibleOption(3),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: AppColors.auroraCanvas,
            body: SafeArea(
              child: Column(
                children: <Widget>[
                  _buildRunnerHeader(),
                  if (_offlineRecoveryActive) _buildRecoveryBanner(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth >= 950) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              SizedBox(width: 275, child: _buildPalette()),
                              Expanded(child: _buildQuestionArea()),
                            ],
                          );
                        }
                        return _buildQuestionArea(showPaletteButton: true);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRunnerHeader() {
    final warning = _secondsRemaining <= 60
        ? AppColors.danger
        : _secondsRemaining <= 300
            ? AppColors.warning
            : AppColors.electricCyan;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(gradient: AppStyles.brandGradient),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                onPressed: _showLeaveWarning,
                color: Colors.white,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Leave quiz',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _quizTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _secureMode
                          ? 'Secure mode • $_focusViolations focus events'
                          : 'Standard quiz mode',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(
                  () => _questionScale =
                      max(.85, _questionScale - .1),
                ),
                color: Colors.white,
                icon: const Icon(Icons.text_decrease_rounded),
                tooltip: 'Decrease text size',
              ),
              IconButton(
                onPressed: () => setState(
                  () => _questionScale =
                      min(1.4, _questionScale + .1),
                ),
                color: Colors.white,
                icon: const Icon(Icons.text_increase_rounded),
                tooltip: 'Increase text size',
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: warning.withValues(alpha: .16),
                  borderRadius: AppStyles.pillRadius,
                  border: Border.all(color: warning.withValues(alpha: .45)),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.timer_outlined, color: warning, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      _formatTimer(_secondsRemaining),
                      style: TextStyle(
                        color: warning,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (_index + 1) / _questions.length,
              minHeight: 6,
              backgroundColor: Colors.white12,
              color: AppColors.electricCyan,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecoveryBanner() {
    return Material(
      color: AppColors.warning.withValues(alpha: .14),
      child: InkWell(
        onTap: _retryUnsavedAnswers,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: <Widget>[
              Icon(Icons.cloud_off_rounded, color: AppColors.warning, size: 19),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Answers are safe on this device. Tap to sync when connected.',
                  style: TextStyle(
                    color: Color(0xFF775700),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.sync_rounded, color: AppColors.warning, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionArea({bool showPaletteButton = false}) {
    final question = _currentQuestion;
    final order = _orderFor(question);
    final selected = _answers[question.id];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Question ${_index + 1} of ${_questions.length}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _isSaving
                    ? const Row(
                        key: ValueKey<String>('saving'),
                        children: <Widget>[
                          SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Saving',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        key: ValueKey<String>(
                          _savedAnswers.contains(question.id)
                              ? 'saved'
                              : 'local',
                        ),
                        children: <Widget>[
                          Icon(
                            _savedAnswers.contains(question.id)
                                ? Icons.cloud_done_outlined
                                : Icons.phone_android_rounded,
                            color: _savedAnswers.contains(question.id)
                                ? AppColors.success
                                : AppColors.warning,
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _savedAnswers.contains(question.id)
                                ? 'Saved'
                                : 'Saved locally',
                            style: TextStyle(
                              color: _savedAnswers.contains(question.id)
                                  ? AppColors.success
                                  : AppColors.warning,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
              ),
              if (showPaletteButton) ...<Widget>[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _showPaletteSheet,
                  icon: const Icon(Icons.grid_view_rounded),
                  tooltip: 'Question navigator',
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Container(
                  key: ValueKey<String>(question.id),
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 850),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .88),
                    borderRadius: AppStyles.bentoRadius,
                    border: Border.all(color: Colors.white),
                    boxShadow: AppStyles.glassShadow,
                  ),
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(_questionScale),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          question.text,
                          style: const TextStyle(
                            color: AppColors.midnightInk,
                            fontSize: 20,
                            height: 1.35,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ...List<Widget>.generate(order.length, (visibleIndex) {
                          final originalIndex = order[visibleIndex];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AnswerTile(
                              shortcut: visibleIndex + 1,
                              label: question.options[originalIndex],
                              selected: selected == originalIndex,
                              onTap: () => _selectAnswer(originalIndex),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _index == 0 ? null : () => _goToQuestion(_index - 1),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Previous'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : _index == _questions.length - 1
                          ? _confirmSubmit
                          : () => _goToQuestion(_index + 1),
                  style: FilledButton.styleFrom(
                    backgroundColor: _index == _questions.length - 1
                        ? AppColors.success
                        : AppColors.vibeBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _index == _questions.length - 1
                              ? Icons.task_alt_rounded
                              : Icons.arrow_forward_rounded,
                        ),
                  label: Text(
                    _index == _questions.length - 1
                        ? 'Submit quiz'
                        : 'Next question',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPalette() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 16, 0, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.midnightInk,
        borderRadius: AppStyles.controlRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Question navigator',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${_answers.length} answered • '
            '${_questions.length - _answers.length} unanswered',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _questions.length,
              itemBuilder: (_, index) => _paletteButton(index),
            ),
          ),
          const Row(
            children: <Widget>[
              _PaletteLegend(AppColors.electricCyan, 'Current'),
              SizedBox(width: 10),
              _PaletteLegend(AppColors.success, 'Answered'),
              SizedBox(width: 10),
              _PaletteLegend(Colors.white24, 'Empty'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paletteButton(int index, {bool closeSheet = false}) {
    final current = index == _index;
    final answered = _answers.containsKey(_questions[index].id);
    return InkWell(
      onTap: () {
        if (closeSheet) Navigator.of(context).pop();
        _goToQuestion(index);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: current
              ? AppColors.electricCyan
              : answered
                  ? AppColors.success
                  : Colors.white10,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: current ? Colors.white : Colors.white12,
          ),
        ),
        child: Text(
          '${index + 1}',
          style: TextStyle(
            color: current ? AppColors.midnightInk : Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Future<void> _showPaletteSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.midnightInk,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Question navigator',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _questions.length,
                itemBuilder: (_, index) =>
                    _paletteButton(index, closeSheet: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectVisibleOption(int visibleIndex) {
    final order = _orderFor(_currentQuestion);
    if (visibleIndex < order.length) {
      unawaited(_selectAnswer(order[visibleIndex]));
    }
  }

  Future<void> _showLeaveWarning() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave secure quiz?'),
        content: const Text(
          'Your saved answers will remain available when you resume, but the '
          'quiz timer will continue running.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue quiz'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context, false);
  }

  String _friendlyError(Object error) {
    final value = error.toString().toLowerCase();
    if (value.contains('maximum attempts')) {
      return 'You have used all allowed attempts for this quiz.';
    }
    if (value.contains('not yet available')) {
      return 'This quiz is not available yet.';
    }
    if (value.contains('closed')) return 'This quiz has already closed.';
    if (value.contains('permission') || value.contains('policy')) {
      return 'Your session could not authorize this quiz attempt.';
    }
    return 'The secure quiz could not load. Check your connection and retry.';
  }

  String _formatTimer(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

class QuizResultData {
  const QuizResultData({
    required this.scorePoints,
    required this.totalPoints,
    required this.percentage,
    required this.passed,
    required this.rewardPoints,
    required this.focusViolations,
  });

  final double scorePoints;
  final double totalPoints;
  final double percentage;
  final bool passed;
  final int rewardPoints;
  final int focusViolations;

  factory QuizResultData.fromRow(Map<String, dynamic> row) {
    return QuizResultData(
      scorePoints:
          double.tryParse(row['score_points']?.toString() ?? '') ?? 0,
      totalPoints:
          double.tryParse(row['total_points']?.toString() ?? '') ?? 0,
      percentage: double.tryParse(row['percentage']?.toString() ?? '') ?? 0,
      passed: row['passed'] == true,
      rewardPoints:
          int.tryParse(row['reward_points']?.toString() ?? '') ?? 0,
      focusViolations:
          int.tryParse(row['focus_violations']?.toString() ?? '') ?? 0,
    );
  }

  factory QuizResultData.fromAttempt(QuizAttempt attempt) {
    return QuizResultData(
      scorePoints: attempt.scorePoints ?? 0,
      totalPoints: attempt.totalPoints ?? 0,
      percentage: attempt.percentage ?? 0,
      passed: attempt.passed == true,
      rewardPoints: attempt.rewardPoints,
      focusViolations: attempt.focusViolations,
    );
  }
}

class QuizResultScreen extends StatelessWidget {
  const QuizResultScreen({
    super.key,
    required this.quizTitle,
    required this.passingScore,
    required this.result,
    this.autoSubmitted = false,
    this.popWithCompletion = true,
  });

  final String quizTitle;
  final int passingScore;
  final QuizResultData result;
  final bool autoSubmitted;
  final bool popWithCompletion;

  @override
  Widget build(BuildContext context) {
    final color = result.passed ? AppColors.success : AppColors.danger;
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Quiz Result'),
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 40),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 650),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .84),
              borderRadius: AppStyles.bentoRadius,
              border: Border.all(color: Colors.white),
              boxShadow: AppStyles.glassShadow,
            ),
            child: Column(
              children: <Widget>[
                Icon(
                  result.passed
                      ? Icons.emoji_events_rounded
                      : Icons.auto_graph_rounded,
                  color: color,
                  size: 64,
                )
                    .animate(onPlay: (controller) => controller.repeat(reverse: true))
                    .scaleXY(begin: .94, end: 1.06, duration: 900.ms),
                const SizedBox(height: 12),
                Text(
                  result.passed ? 'Quiz passed!' : 'Keep building.',
                  style: TextStyle(
                    color: color,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  quizTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (autoSubmitted) ...<Widget>[
                  const SizedBox(height: 8),
                  const Text(
                    'Time expired, so your saved answers were submitted.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: result.percentage / 100),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => SizedBox(
                    width: 150,
                    height: 150,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        CircularProgressIndicator(
                          value: value,
                          strokeWidth: 13,
                          backgroundColor: color.withValues(alpha: .10),
                          color: color,
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '${(value * 100).round()}%',
                              style: const TextStyle(
                                color: AppColors.midnightInk,
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${_score(result.scorePoints)} / '
                              '${_score(result.totalPoints)} pts',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: <Widget>[
                    _resultStat(
                      Icons.flag_outlined,
                      '$passingScore%',
                      'Pass mark',
                      AppColors.vibeBlue,
                    ),
                    _resultStat(
                      Icons.stars_rounded,
                      '+${result.rewardPoints}',
                      'Reward',
                      AppColors.warning,
                    ),
                    _resultStat(
                      Icons.shield_outlined,
                      '${result.focusViolations}',
                      'Focus events',
                      AppColors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      popWithCompletion ? true : null,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.vibeBlue,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    icon: const Icon(Icons.done_rounded),
                    label: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 450.ms).slideY(begin: .05, end: 0),
        ),
      ),
    );
  }

  Widget _resultStat(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.midnightInk,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  static String _score(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({
    required this.shortcut,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int shortcut;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Option $shortcut: $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.vibeBlue.withValues(alpha: .10)
                : const Color(0xFFF7F9FD),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.vibeBlue : AppColors.glassBorder,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.vibeBlue : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        selected ? AppColors.vibeBlue : AppColors.glassBorder,
                  ),
                ),
                child: Text(
                  '$shortcut',
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textMuted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.midnightInk,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: selected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        key: ValueKey<String>('selected'),
                        color: AppColors.vibeBlue,
                      )
                    : const Icon(
                        Icons.radio_button_unchecked_rounded,
                        key: ValueKey<String>('empty'),
                        color: AppColors.textMuted,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteLegend extends StatelessWidget {
  const _PaletteLegend(this.color, this.label);

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

class ModuleRef {
  const ModuleRef({
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

  factory ModuleRef.fromRow(Map<String, dynamic> row) {
    return ModuleRef(
      id: _QuizScreenState._text(row['id']),
      programmeId: _QuizScreenState._text(row['programme_id']),
      level: _QuizScreenState._text(row['level']),
      name: _QuizScreenState._text(row['name']),
      code: _QuizScreenState._text(row['code']),
    );
  }
}

class LecturerProfile {
  const LecturerProfile({
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
