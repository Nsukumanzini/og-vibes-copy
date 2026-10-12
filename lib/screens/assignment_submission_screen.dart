import 'dart:async';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class AssignmentSubmissionScreen extends StatefulWidget {
  const AssignmentSubmissionScreen({super.key});

  @override
  State<AssignmentSubmissionScreen> createState() =>
      _AssignmentSubmissionScreenState();
}

class _AssignmentSubmissionScreenState
    extends State<AssignmentSubmissionScreen>
    with SingleTickerProviderStateMixin {
  static const int _absoluteMaxFileSize = 50 * 1024 * 1024;
  static const List<String> _tabLabels = <String>[
    'All',
    'Due Soon',
    'Submitted',
    'Graded',
    'Overdue',
  ];
  static const Set<String> _blockedExtensions = <String>{
    'apk',
    'app',
    'bat',
    'cmd',
    'com',
    'dll',
    'dmg',
    'exe',
    'jar',
    'msi',
    'ps1',
    'scr',
  };

  late final TabController _tabController;
  final List<_AssessmentBrief> _briefs = <_AssessmentBrief>[];
  final List<_SubmissionItem> _submissions = <_SubmissionItem>[];
  final List<_ModuleRef> _modules = <_ModuleRef>[];
  final Set<String> _registeredModuleIds = <String>{};

  Timer? _clock;
  StreamSubscription<List<Map<String, dynamic>>>? _submissionSubscription;
  bool _isLoading = true;
  bool _myModulesOnly = true;
  bool _hasRegistrationMatch = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String _uploadStage = '';
  String? _errorMessage;
  String? _uploadError;
  Future<void> Function()? _retryUpload;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          HapticFeedback.selectionClick();
        }
      });
    _loadDashboard();
    _listenForSubmissionChanges();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _submissionSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard({bool showLoader = true}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'You must be signed in to view submissions.';
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
      await _loadAcademicContext(user.id);
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        Supabase.instance.client
            .from('assessment_briefs')
            .select(
              'id, module_id, level, title, subject, instructions, due_at, '
              'allow_late, max_file_size_bytes, published, created_at',
            )
            .eq('published', true)
            .order('due_at', ascending: true),
        Supabase.instance.client
            .from('assignment_submissions')
            .select(
              'id, user_id, brief_id, module_id, level, title, subject, '
              'due_date, status, storage_path, submitted_at, grade, feedback, '
              'file_name, file_size_bytes, file_fingerprint, mime_type, '
              'late_reason, extension_requested, extension_status, '
              'withdrawn_at, updated_at, upload_version',
            )
            .eq('user_id', user.id)
            .order('created_at', ascending: false),
      ]);

      final briefs = List<Map<String, dynamic>>.from(
        results[0] as List<dynamic>? ?? <dynamic>[],
      ).map(_AssessmentBrief.fromRow).toList();
      final submissions = List<Map<String, dynamic>>.from(
        results[1] as List<dynamic>? ?? <dynamic>[],
      ).map(_SubmissionItem.fromRow).toList();

      if (!mounted) return;
      setState(() {
        _briefs
          ..clear()
          ..addAll(briefs);
        _submissions
          ..clear()
          ..addAll(submissions);
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

  Future<void> _loadAcademicContext(String userId) async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      Supabase.instance.client
          .from('profiles')
          .select('department, level')
          .eq('id', userId)
          .maybeSingle(),
      Supabase.instance.client.from('programmes').select('id, name'),
      Supabase.instance.client
          .from('modules')
          .select('id, programme_id, level, name, code'),
    ]);

    final profile = results[0] is Map
        ? Map<String, dynamic>.from(results[0] as Map)
        : <String, dynamic>{};
    final programmes = List<Map<String, dynamic>>.from(
      results[1] as List<dynamic>? ?? <dynamic>[],
    );
    final moduleRows = List<Map<String, dynamic>>.from(
      results[2] as List<dynamic>? ?? <dynamic>[],
    );
    final department = _normalize(profile['department']);
    final level = _normalize(profile['level']);
    final programmeIds = programmes.where((programme) {
      final name = _normalize(programme['name']);
      return department.isNotEmpty &&
          (department.contains(name) || name.contains(department));
    }).map((programme) => _text(programme['id'])).toSet();

    _modules
      ..clear()
      ..addAll(moduleRows.map(_ModuleRef.fromRow));
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
  }

  void _listenForSubmissionChanges() {
    _submissionSubscription = Supabase.instance.client
        .from('assignment_submissions')
        .stream(primaryKey: <String>['id'])
        .listen((_) {
      if (mounted && !_isUploading) {
        unawaited(_loadDashboard(showLoader: false));
      }
    }, onError: (_) {});
  }

  List<_AssessmentEntry> get _entries {
    final byBrief = <String, _SubmissionItem>{
      for (final submission in _submissions)
        if (submission.briefId.isNotEmpty) submission.briefId: submission,
    };
    final entries = <_AssessmentEntry>[
      for (final brief in _briefs)
        _AssessmentEntry(brief: brief, submission: byBrief[brief.id]),
    ];
    final briefIds = _briefs.map((brief) => brief.id).toSet();
    entries.addAll(
      _submissions
          .where(
            (submission) =>
                submission.briefId.isEmpty ||
                !briefIds.contains(submission.briefId),
          )
          .map((submission) => _AssessmentEntry(submission: submission)),
    );
    entries.sort((a, b) {
      final aDate = a.deadline;
      final bDate = b.deadline;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    if (!_myModulesOnly || !_hasRegistrationMatch) return entries;
    return entries.where((entry) {
      if (entry.moduleId.isNotEmpty) {
        return _registeredModuleIds.contains(entry.moduleId);
      }
      final subject = _normalize(entry.subject);
      return _modules
          .where((module) => _registeredModuleIds.contains(module.id))
          .any(
            (module) =>
                subject.contains(_normalize(module.name)) ||
                subject.contains(_normalize(module.code)),
          );
    }).toList();
  }

  List<_AssessmentEntry> _entriesForTab(int index) {
    final entries = _entries;
    switch (index) {
      case 1:
        return entries.where((entry) => entry.isDueSoon).toList();
      case 2:
        return entries.where((entry) => entry.isSubmitted).toList();
      case 3:
        return entries.where((entry) => entry.isGraded).toList();
      case 4:
        return entries.where((entry) => entry.isOverdue).toList();
      default:
        return entries;
    }
  }

  int get _pendingCount => _entries
      .where(
        (entry) =>
            !entry.isSubmitted &&
            !entry.isGraded &&
            !entry.isOverdue &&
            !entry.isWithdrawn,
      )
      .length;
  int get _submittedCount =>
      _entries.where((entry) => entry.isSubmitted).length;
  int get _gradedCount => _entries.where((entry) => entry.isGraded).length;
  int get _overdueCount => _entries.where((entry) => entry.isOverdue).length;

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Assessment Submission'),
        backgroundColor: Colors.transparent,
        actions: <Widget>[
          IconButton(
            onPressed: _isUploading ? null : () => _loadDashboard(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh submissions',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _showManualAssessmentSheet,
        backgroundColor: AppColors.vibeBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text(
          'Upload',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _isLoading && _briefs.isEmpty && _submissions.isEmpty
          ? _buildLoadingState()
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null && _briefs.isEmpty && _submissions.isEmpty) {
      return _buildErrorState();
    }
    return Column(
      children: <Widget>[
        Expanded(
          child: NestedScrollView(
            headerSliverBuilder: (_, _) => <Widget>[
              SliverToBoxAdapter(child: _buildHero()),
              if (_isUploading || _uploadError != null)
                SliverToBoxAdapter(child: _buildUploadStatus()),
              SliverToBoxAdapter(child: _buildRegistrationFilter()),
              SliverToBoxAdapter(child: _buildTabs()),
            ],
            body: TabBarView(
              controller: _tabController,
              children: List<Widget>.generate(
                _tabLabels.length,
                (index) => _buildEntryGrid(_entriesForTab(index), index),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    final urgent = _entries
        .where((entry) => !entry.isSubmitted && entry.deadline != null)
        .toList()
      ..sort((a, b) => a.deadline!.compareTo(b.deadline!));
    final next = urgent.isEmpty ? null : urgent.first;
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
              right: -40,
              top: -55,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.electricCyan.withValues(alpha: 0.12),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(
                      Icons.workspace_premium_rounded,
                      color: AppColors.electricCyan,
                    ),
                    SizedBox(width: 9),
                    Text(
                      'OG ASSESSMENTS',
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
                  'Submit with confidence.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Secure uploads, clear deadlines and complete control.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    _heroStat('$_pendingCount', 'Pending', AppColors.ogGold),
                    _heroStat(
                      '$_submittedCount',
                      'Submitted',
                      AppColors.electricCyan,
                    ),
                    _heroStat('$_gradedCount', 'Graded', AppColors.success),
                    _heroStat('$_overdueCount', 'Overdue', Colors.redAccent),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.17),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        next?.isOverdue == true
                            ? Icons.warning_amber_rounded
                            : Icons.timer_outlined,
                        color: next?.isOverdue == true
                            ? Colors.redAccent.shade100
                            : AppColors.ogGold,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              next == null
                                  ? 'No outstanding deadlines'
                                  : next.title,
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
                                  ? 'Everything is up to date'
                                  : _countdown(next.deadline),
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

  Widget _buildRegistrationFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: _glass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilterChip(
                selected: _myModulesOnly,
                onSelected: _hasRegistrationMatch
                    ? (selected) {
                        HapticFeedback.selectionClick();
                        setState(() => _myModulesOnly = selected);
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
            IconButton.filledTonal(
              onPressed: _showSecurityInfo,
              icon: const Icon(Icons.shield_outlined),
              tooltip: 'Submission security',
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
          tabs: <Widget>[
            Tab(text: 'All ${_entries.length}'),
            Tab(text: 'Due Soon ${_entriesForTab(1).length}'),
            Tab(text: 'Submitted $_submittedCount'),
            Tab(text: 'Graded $_gradedCount'),
            Tab(text: 'Overdue $_overdueCount'),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryGrid(List<_AssessmentEntry> entries, int tabIndex) {
    if (entries.isEmpty) return _buildEmptyState(tabIndex);
    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 820;
          if (isWide) {
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 110),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 520,
                mainAxisExtent: 390,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: entries.length,
              itemBuilder: (_, index) =>
                  _buildAssessmentCard(entries[index], index),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 110),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 13),
            itemBuilder: (_, index) =>
                _buildAssessmentCard(entries[index], index),
          );
        },
      ),
    );
  }

  Widget _buildAssessmentCard(_AssessmentEntry entry, int index) {
    final status = _statusPresentation(entry);
    final deadlinePassed = entry.isOverdue;
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
                  gradient: deadlinePassed
                      ? const LinearGradient(
                          colors: <Color>[
                            AppColors.danger,
                            Color(0xFFFF7182),
                          ],
                        )
                      : AppStyles.brandGradient,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(status.icon, color: Colors.white),
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
                            entry.title,
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
                        _statusPill(status),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${entry.subject} • ${entry.level}',
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
          const SizedBox(height: 15),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: status.color.withValues(alpha: .18)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.schedule_rounded, color: status.color, size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.deadline == null
                            ? 'Deadline to be announced'
                            : _formatDate(entry.deadline!),
                        style: const TextStyle(
                          color: AppColors.midnightInk,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        entry.isSubmitted || entry.isGraded
                            ? entry.submission!.submittedAtFormatted
                            : _countdown(entry.deadline),
                        style: TextStyle(
                          color: status.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (entry.submission?.fileName.isNotEmpty == true) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.description_outlined,
                  color: AppColors.vibeBlue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.submission!.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.midnightInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _formatBytes(entry.submission!.fileSizeBytes),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
          if (entry.submission?.extensionRequested == true) ...<Widget>[
            const SizedBox(height: 11),
            _extensionBanner(entry.submission!),
          ],
          if (entry.isGraded && entry.submission?.feedback.isNotEmpty == true)
            ...<Widget>[
              const SizedBox(height: 11),
              Text(
                'Feedback: ${entry.submission!.feedback}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          const Spacer(),
          const SizedBox(height: 14),
          _buildCardActions(entry),
        ],
      ),
    )
        .animate(delay: (45 * index).ms)
        .fadeIn(duration: 350.ms)
        .slideY(begin: .07, end: 0);
  }

  Widget _buildCardActions(_AssessmentEntry entry) {
    if (entry.isGraded) {
      return Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              entry.submission?.grade ?? 'Graded',
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: entry.submission?.storagePath.isNotEmpty == true
                  ? () => _viewSubmission(entry.submission!)
                  : null,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('View file'),
            ),
          ),
        ],
      );
    }

    if (entry.isSubmitted) {
      final canChange = entry.canChangeBeforeDeadline;
      return Row(
        children: <Widget>[
          IconButton.filledTonal(
            onPressed: () => _viewSubmission(entry.submission!),
            icon: const Icon(Icons.visibility_outlined),
            tooltip: 'View uploaded file',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: canChange
                  ? () => _pickAndUpload(entry, replace: true)
                  : null,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Replace'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: canChange ? () => _confirmWithdraw(entry) : null,
            color: AppColors.danger,
            icon: const Icon(Icons.undo_rounded),
            tooltip: canChange
                ? 'Withdraw submission'
                : 'Deadline passed; withdrawal locked',
          ),
        ],
      );
    }

    if (entry.isOverdue && !entry.allowLate) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: entry.submission?.extensionRequested == true
              ? null
              : () => _requestExtension(entry),
          icon: const Icon(Icons.event_repeat_rounded),
          label: Text(
            entry.submission?.extensionRequested == true
                ? 'Extension requested'
                : 'Request extension',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => _pickAndUpload(entry),
        style: FilledButton.styleFrom(
          backgroundColor:
              entry.isOverdue ? AppColors.danger : AppColors.vibeBlue,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.upload_file_rounded),
        label: Text(
          entry.isOverdue ? 'Submit late with reason' : 'Upload submission',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _extensionBanner(_SubmissionItem submission) {
    final color = submission.extensionStatus == 'approved'
        ? AppColors.success
        : submission.extensionStatus == 'declined'
            ? AppColors.danger
            : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.event_repeat_rounded, color: color, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Extension ${submission.extensionStatus == 'none' ? 'pending' : submission.extensionStatus}',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(_StatusPresentation status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: .10),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Text(
        status.label.toUpperCase(),
        style: TextStyle(
          color: status.color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        ),
      ),
    );
  }

  _StatusPresentation _statusPresentation(_AssessmentEntry entry) {
    if (entry.isGraded) {
      return const _StatusPresentation(
        'Graded',
        AppColors.success,
        Icons.workspace_premium_rounded,
      );
    }
    if (entry.isSubmitted) {
      return const _StatusPresentation(
        'Submitted',
        AppColors.vibeBlue,
        Icons.task_alt_rounded,
      );
    }
    if (entry.isWithdrawn) {
      return const _StatusPresentation(
        'Withdrawn',
        AppColors.textMuted,
        Icons.undo_rounded,
      );
    }
    if (entry.isOverdue) {
      return const _StatusPresentation(
        'Overdue',
        AppColors.danger,
        Icons.assignment_late_rounded,
      );
    }
    if (entry.isDueSoon) {
      return const _StatusPresentation(
        'Due soon',
        AppColors.warning,
        Icons.timer_outlined,
      );
    }
    return const _StatusPresentation(
      'Upcoming',
      AppColors.vibeBlue,
      Icons.assignment_outlined,
    );
  }

  Future<void> _showManualAssessmentSheet() async {
    final titleController = TextEditingController();
    final subjectController = TextEditingController();
    DateTime? dueDate;
    _ModuleRef? selectedModule = _registeredModules.firstOrNull;
    final result = await showModalBottomSheet<_ManualAssessment>(
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
                  'Upload an assessment',
                  style: TextStyle(
                    color: AppColors.midnightInk,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Use this when your lecturer has not published a brief yet.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Assessment title',
                    prefixIcon: Icon(Icons.assignment_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    prefixIcon: Icon(Icons.menu_book_rounded),
                  ),
                ),
                if (_registeredModules.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<_ModuleRef>(
                    initialValue: selectedModule,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Registered module',
                    ),
                    items: _registeredModules
                        .map(
                          (module) => DropdownMenuItem<_ModuleRef>(
                            value: module,
                            child: Text(module.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setSheetState(() => selectedModule = value),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.glassBorder),
                  ),
                  leading: const Icon(Icons.event_outlined),
                  title: Text(
                    dueDate == null
                        ? 'Add due date (optional)'
                        : _formatDate(dueDate!),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate:
                          DateTime.now().add(const Duration(days: 7)),
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 365)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 730)),
                    );
                    if (selected != null) {
                      setSheetState(() => dueDate = selected);
                    }
                  },
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    final title = titleController.text.trim();
                    final subject = subjectController.text.trim();
                    if (title.isEmpty || subject.isEmpty) return;
                    Navigator.pop(
                      context,
                      _ManualAssessment(
                        title: title,
                        subject: subject,
                        level: selectedModule?.level ?? 'Unspecified',
                        moduleId: selectedModule?.id ?? '',
                        deadline: dueDate == null
                            ? null
                            : DateTime(
                                dueDate!.year,
                                dueDate!.month,
                                dueDate!.day,
                                23,
                                59,
                                59,
                              ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Choose document'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    titleController.dispose();
    subjectController.dispose();
    if (result == null) return;
    await _pickAndUpload(_AssessmentEntry(manual: result));
  }

  Future<void> _pickAndUpload(
    _AssessmentEntry entry, {
    bool replace = false,
  }) async {
    HapticFeedback.selectionClick();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final validation = _validateFile(file, entry, replace: replace);
    if (validation != null) {
      _showMessage(validation, isError: true);
      return;
    }
    final bytes = file.bytes!;
    final fingerprint = _fingerprint(bytes);
    final duplicate = _submissions.any(
      (submission) =>
          submission.id != entry.submission?.id &&
          submission.fileFingerprint == fingerprint &&
          submission.status != 'withdrawn' &&
          (submission.briefId == entry.brief?.id ||
              (submission.title == entry.title &&
                  submission.subject == entry.subject)),
    );
    if (duplicate) {
      _showMessage(
        'This exact document has already been uploaded for this assessment.',
        isError: true,
      );
      return;
    }

    String? lateReason;
    if (entry.isOverdue &&
        entry.submission?.extensionStatus != 'approved') {
      if (!entry.allowLate) {
        await _requestExtension(entry);
        return;
      }
      lateReason = await _askForLateReason(entry);
      if (lateReason == null) return;
    }

    Future<void> task() => _uploadDocument(
          entry: entry,
          file: file,
          bytes: bytes,
          fingerprint: fingerprint,
          lateReason: lateReason,
          replace: replace,
        );
    _retryUpload = task;
    await task();
  }

  String? _validateFile(
    PlatformFile file,
    _AssessmentEntry entry, {
    required bool replace,
  }) {
    if (file.bytes == null || file.bytes!.isEmpty || file.size <= 0) {
      return 'The selected document is empty or unreadable.';
    }
    final limit = entry.maxFileSize.clamp(1, _absoluteMaxFileSize);
    if (file.size > limit) {
      return 'This document is ${_formatBytes(file.size)}. The maximum is '
          '${_formatBytes(limit)}.';
    }
    final extension = (file.extension ?? '').toLowerCase();
    if (_blockedExtensions.contains(extension)) {
      return '.$extension files are applications, not documents, and cannot '
          'be submitted.';
    }
    if (!_knownDocumentLooksValid(extension, file.bytes!)) {
      return 'The document header does not match its .$extension extension. '
          'The file may be corrupted.';
    }
    if (replace && entry.submission == null) {
      return 'The original submission could not be found.';
    }
    return null;
  }

  bool _knownDocumentLooksValid(String extension, Uint8List bytes) {
    bool startsWith(List<int> signature) {
      if (bytes.length < signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[i] != signature[i]) return false;
      }
      return true;
    }

    if (extension == 'pdf') return startsWith(<int>[0x25, 0x50, 0x44, 0x46]);
    if (<String>{'docx', 'xlsx', 'pptx', 'odt', 'ods', 'odp', 'zip'}
        .contains(extension)) {
      return startsWith(<int>[0x50, 0x4B]);
    }
    if (extension == 'png') {
      return startsWith(<int>[0x89, 0x50, 0x4E, 0x47]);
    }
    if (<String>{'jpg', 'jpeg'}.contains(extension)) {
      return startsWith(<int>[0xFF, 0xD8, 0xFF]);
    }
    final inspectedLength = bytes.length.clamp(1, 4096);
    var nonZero = false;
    for (var i = 0; i < inspectedLength; i++) {
      if (bytes[i] != 0) {
        nonZero = true;
        break;
      }
    }
    return nonZero;
  }

  Future<void> _uploadDocument({
    required _AssessmentEntry entry,
    required PlatformFile file,
    required Uint8List bytes,
    required String fingerprint,
    required String? lateReason,
    required bool replace,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showMessage('Please sign in before submitting.', isError: true);
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadError = null;
      _uploadProgress = .12;
      _uploadStage = 'Validating document integrity';
    });

    String? newStoragePath;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      setState(() {
        _uploadProgress = .30;
        _uploadStage = 'Encrypting and uploading securely';
      });

      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      newStoragePath =
          '${user.id}/${DateTime.now().microsecondsSinceEpoch}_$safeName';
      await Supabase.instance.client.storage
          .from('assignment_submissions')
          .uploadBinary(
            newStoragePath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/octet-stream',
              upsert: false,
            ),
          );

      if (!mounted) return;
      setState(() {
        _uploadProgress = .78;
        _uploadStage = 'Saving submission record';
      });

      final row = <String, dynamic>{
        'user_id': user.id,
        'brief_id': entry.brief?.id,
        'module_id':
            entry.moduleId.isEmpty ? null : entry.moduleId,
        'level': entry.level,
        'title': entry.title,
        'subject': entry.subject,
        'due_date': entry.deadline?.toIso8601String().split('T').first,
        'status': 'submitted',
        'storage_path': newStoragePath,
        'document_url': null,
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
        'file_name': file.name,
        'file_size_bytes': file.size,
        'file_fingerprint': fingerprint,
        'mime_type': 'application/octet-stream',
        'late_reason': lateReason,
        'extension_requested': false,
        'upload_version': (entry.submission?.uploadVersion ?? 0) + 1,
      };

      if (replace && entry.submission != null) {
        await Supabase.instance.client
            .from('assignment_submissions')
            .update(row)
            .eq('id', entry.submission!.id);
      } else if (entry.submission != null &&
          entry.submission!.status == 'withdrawn') {
        await Supabase.instance.client
            .from('assignment_submissions')
            .update(row)
            .eq('id', entry.submission!.id);
      } else {
        await Supabase.instance.client
            .from('assignment_submissions')
            .insert(row);
      }

      final oldPath = entry.submission?.storagePath;
      if (replace &&
          oldPath != null &&
          oldPath.isNotEmpty &&
          oldPath != newStoragePath) {
        try {
          await Supabase.instance.client.storage
              .from('assignment_submissions')
              .remove(<String>[oldPath]);
        } catch (_) {
          // The new record is already safe; stale private cleanup can retry.
        }
      }

      if (!mounted) return;
      setState(() {
        _uploadProgress = 1;
        _uploadStage =
            replace ? 'Submission replaced' : 'Submission complete';
        _retryUpload = null;
      });
      HapticFeedback.heavyImpact();
      await _loadDashboard(showLoader: false);
      _showMessage(
        replace
            ? 'Your submission was replaced successfully.'
            : 'Assessment submitted successfully.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 650));
    } catch (error) {
      if (newStoragePath != null) {
        try {
          await Supabase.instance.client.storage
              .from('assignment_submissions')
              .remove(<String>[newStoragePath]);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _uploadError = _friendlyUploadError(error);
        _uploadStage = 'Upload interrupted';
      });
      HapticFeedback.vibrate();
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _viewSubmission(_SubmissionItem submission) async {
    if (submission.storagePath.isEmpty) {
      _showMessage('This submission has no document attached.', isError: true);
      return;
    }
    try {
      HapticFeedback.lightImpact();
      final signedUrl = await Supabase.instance.client.storage
          .from('assignment_submissions')
          .createSignedUrl(submission.storagePath, 60);
      final uri = Uri.tryParse(signedUrl);
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Unable to open signed document');
      }
    } catch (_) {
      _showMessage(
        'The secure document link could not be opened. Please try again.',
        isError: true,
      );
    }
  }

  Future<void> _confirmWithdraw(_AssessmentEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw submission?'),
        content: const Text(
          'Your uploaded document will be removed. You can submit again before '
          'the deadline.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep submission'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || entry.submission == null) return;
    try {
      await Supabase.instance.client
          .from('assignment_submissions')
          .update(<String, dynamic>{
            'status': 'withdrawn',
            'withdrawn_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', entry.submission!.id);
      if (entry.submission!.storagePath.isNotEmpty) {
        await Supabase.instance.client.storage
            .from('assignment_submissions')
            .remove(<String>[entry.submission!.storagePath]);
      }
      HapticFeedback.mediumImpact();
      await _loadDashboard(showLoader: false);
      _showMessage('Submission withdrawn. You may upload again before due.');
    } catch (error) {
      _showMessage(_friendlyUploadError(error), isError: true);
    }
  }

  Future<void> _requestExtension(_AssessmentEntry entry) async {
    final controller = TextEditingController();
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAFF),
      builder: (context) => Padding(
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
              'Request an extension',
              style: TextStyle(
                color: AppColors.midnightInk,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Explain why you could not submit ${entry.title} on time.',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason',
                alignLabelWithHint: true,
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                final value = controller.text.trim();
                if (value.length >= 10) Navigator.pop(context, value);
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send request'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (reason == null) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final values = <String, dynamic>{
        'extension_requested': true,
        'extension_status': 'none',
        'late_reason': reason,
        'status': 'pending',
      };
      if (entry.submission != null) {
        await Supabase.instance.client
            .from('assignment_submissions')
            .update(values)
            .eq('id', entry.submission!.id);
      } else {
        await Supabase.instance.client.from('assignment_submissions').insert(
          <String, dynamic>{
            ...values,
            'user_id': user.id,
            'brief_id': entry.brief?.id,
            'module_id':
                entry.moduleId.isEmpty ? null : entry.moduleId,
            'level': entry.level,
            'title': entry.title,
            'subject': entry.subject,
            'due_date': entry.deadline?.toIso8601String().split('T').first,
            'storage_path': null,
            'document_url': null,
          },
        );
      }
      await _loadDashboard(showLoader: false);
      HapticFeedback.mediumImpact();
      _showMessage('Your extension request was sent.');
    } catch (error) {
      _showMessage(_friendlyUploadError(error), isError: true);
    }
  }

  Future<String?> _askForLateReason(_AssessmentEntry entry) async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAFF),
      builder: (context) => Padding(
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
            const Row(
              children: <Widget>[
                Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                SizedBox(width: 9),
                Text(
                  'Late submission',
                  style: TextStyle(
                    color: AppColors.midnightInk,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${entry.title} is past its deadline. Your reason will be sent '
              'with the document.',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason for late submission',
                alignLabelWithHint: true,
              ),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.length >= 10) Navigator.pop(context, value);
              },
              child: const Text('Continue with upload'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Widget _buildUploadStatus() {
    final failed = _uploadError != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: _glass(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  failed ? Icons.cloud_off_rounded : Icons.cloud_upload_rounded,
                  color: failed ? AppColors.danger : AppColors.vibeBlue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        failed ? 'Upload needs attention' : _uploadStage,
                        style: const TextStyle(
                          color: AppColors.midnightInk,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        failed
                            ? _uploadError!
                            : '${(_uploadProgress * 100).round()}% complete',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (failed && _retryUpload != null)
                  TextButton.icon(
                    onPressed: () => _retryUpload?.call(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _isUploading && _uploadProgress == .30
                  ? null
                  : _uploadProgress,
              minHeight: 7,
              borderRadius: BorderRadius.circular(999),
              color: failed ? AppColors.danger : AppColors.vibeBlue,
              backgroundColor:
                  AppColors.vibeBlue.withValues(alpha: .08),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(int tabIndex) {
    final label = _tabLabels[tabIndex].toLowerCase();
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
                Icons.fact_check_outlined,
                color: AppColors.vibeBlue,
                size: 35,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'No $label assessments',
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Published assessments and your submissions will appear here.',
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
                'Submissions are temporarily unavailable',
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
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppStyles.controlRadius,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 310,
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

  void _showSecurityInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAFF),
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 0, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Your submission is protected',
                style: TextStyle(
                  color: AppColors.midnightInk,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 14),
              _SecurityPoint(
                Icons.lock_outline_rounded,
                'Private student-owned storage',
                'Only you and authorized academic staff can access the file.',
              ),
              _SecurityPoint(
                Icons.link_rounded,
                'Short-lived viewing links',
                'A fresh secure link is created only when you open a document.',
              ),
              _SecurityPoint(
                Icons.verified_user_outlined,
                'Protected academic records',
                'Students cannot alter grades, feedback, or extension decisions.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isError ? AppColors.danger : AppColors.success,
          content: Text(text),
        ),
      );
  }

  List<_ModuleRef> get _registeredModules {
    final values = _modules
        .where((module) => _registeredModuleIds.contains(module.id))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return values;
  }

  String _friendlyUploadError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('maximum allowed size') || text.contains('payload')) {
      return 'The document exceeds the 50 MB upload limit.';
    }
    if (text.contains('duplicate')) {
      return 'This document already exists for the assessment.';
    }
    if (text.contains('deadline') || text.contains('late reason')) {
      return 'The deadline has passed. Add a late reason or request an extension.';
    }
    if (text.contains('permission') ||
        text.contains('policy') ||
        text.contains('row-level')) {
      return 'Your session could not authorize this change. Sign in again.';
    }
    return 'The secure upload could not finish. Check your connection and retry.';
  }

  String _fingerprint(Uint8List bytes) {
    var hash = 0x811C9DC5;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return '${hash.toRadixString(16).padLeft(8, '0')}-${bytes.length}';
  }

  String _countdown(DateTime? deadline) {
    if (deadline == null) return 'Deadline TBA';
    final difference = deadline.toLocal().difference(DateTime.now());
    if (difference.isNegative) {
      final late = difference.abs();
      if (late.inDays > 0) return '${late.inDays}d overdue';
      if (late.inHours > 0) return '${late.inHours}h overdue';
      return '${late.inMinutes}m overdue';
    }
    if (difference.inDays > 0) {
      return 'Due in ${difference.inDays}d ${difference.inHours % 24}h';
    }
    if (difference.inHours > 0) {
      return 'Due in ${difference.inHours}h ${difference.inMinutes % 60}m';
    }
    return 'Due in ${difference.inMinutes}m ${difference.inSeconds % 60}s';
  }

  String _formatDate(DateTime value) {
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';
  static String _normalize(dynamic value) =>
      _text(value).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

class _AssessmentEntry {
  const _AssessmentEntry({this.brief, this.submission, this.manual});

  final _AssessmentBrief? brief;
  final _SubmissionItem? submission;
  final _ManualAssessment? manual;

  String get title => brief?.title ?? submission?.title ?? manual?.title ?? '';
  String get subject =>
      brief?.subject ?? submission?.subject ?? manual?.subject ?? '';
  String get level => brief?.level ?? submission?.level ?? manual?.level ?? '';
  String get moduleId =>
      brief?.moduleId ?? submission?.moduleId ?? manual?.moduleId ?? '';
  DateTime? get deadline =>
      brief?.dueAt ?? submission?.dueDate ?? manual?.deadline;
  bool get allowLate => brief?.allowLate ?? true;
  int get maxFileSize =>
      brief?.maxFileSizeBytes ??
      _AssignmentSubmissionScreenState._absoluteMaxFileSize;

  bool get isGraded => submission?.status == 'graded';
  bool get isSubmitted => submission?.status == 'submitted';
  bool get isWithdrawn => submission?.status == 'withdrawn';
  bool get isOverdue =>
      deadline != null &&
      deadline!.toLocal().isBefore(DateTime.now()) &&
      !isSubmitted &&
      !isGraded;
  bool get isDueSoon {
    if (deadline == null || isSubmitted || isGraded || isOverdue) return false;
    final difference = deadline!.toLocal().difference(DateTime.now());
    return difference <= const Duration(days: 7);
  }

  bool get canChangeBeforeDeadline =>
      deadline == null || deadline!.toLocal().isAfter(DateTime.now());
}

class _AssessmentBrief {
  const _AssessmentBrief({
    required this.id,
    required this.moduleId,
    required this.level,
    required this.title,
    required this.subject,
    required this.dueAt,
    required this.allowLate,
    required this.maxFileSizeBytes,
  });

  final String id;
  final String moduleId;
  final String level;
  final String title;
  final String subject;
  final DateTime dueAt;
  final bool allowLate;
  final int maxFileSizeBytes;

  factory _AssessmentBrief.fromRow(Map<String, dynamic> row) {
    return _AssessmentBrief(
      id: _AssignmentSubmissionScreenState._text(row['id']),
      moduleId: _AssignmentSubmissionScreenState._text(row['module_id']),
      level: _AssignmentSubmissionScreenState._text(row['level']),
      title: _AssignmentSubmissionScreenState._text(row['title']),
      subject: _AssignmentSubmissionScreenState._text(row['subject']),
      dueAt: DateTime.tryParse(
            _AssignmentSubmissionScreenState._text(row['due_at']),
          ) ??
          DateTime.now(),
      allowLate: row['allow_late'] == true,
      maxFileSizeBytes:
          int.tryParse(row['max_file_size_bytes']?.toString() ?? '') ??
              _AssignmentSubmissionScreenState._absoluteMaxFileSize,
    );
  }
}

class _SubmissionItem {
  const _SubmissionItem({
    required this.id,
    required this.briefId,
    required this.moduleId,
    required this.level,
    required this.title,
    required this.subject,
    required this.status,
    required this.storagePath,
    required this.fileName,
    required this.fileSizeBytes,
    required this.fileFingerprint,
    required this.submittedAt,
    required this.dueDate,
    required this.grade,
    required this.feedback,
    required this.extensionRequested,
    required this.extensionStatus,
    required this.uploadVersion,
  });

  final String id;
  final String briefId;
  final String moduleId;
  final String level;
  final String title;
  final String subject;
  final String status;
  final String storagePath;
  final String fileName;
  final int fileSizeBytes;
  final String fileFingerprint;
  final DateTime? submittedAt;
  final DateTime? dueDate;
  final String grade;
  final String feedback;
  final bool extensionRequested;
  final String extensionStatus;
  final int uploadVersion;

  String get submittedAtFormatted {
    if (submittedAt == null) return 'Submission time unavailable';
    final local = submittedAt!.toLocal();
    return 'Submitted ${local.day}/${local.month}/${local.year} at '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  factory _SubmissionItem.fromRow(Map<String, dynamic> row) {
    final dueRaw = _AssignmentSubmissionScreenState._text(row['due_date']);
    final dueDateValue = DateTime.tryParse(dueRaw);
    return _SubmissionItem(
      id: _AssignmentSubmissionScreenState._text(row['id']),
      briefId: _AssignmentSubmissionScreenState._text(row['brief_id']),
      moduleId: _AssignmentSubmissionScreenState._text(row['module_id']),
      level: _AssignmentSubmissionScreenState._text(row['level']),
      title: _AssignmentSubmissionScreenState._text(row['title']),
      subject: _AssignmentSubmissionScreenState._text(row['subject']),
      status: _AssignmentSubmissionScreenState._text(row['status']).toLowerCase(),
      storagePath:
          _AssignmentSubmissionScreenState._text(row['storage_path']),
      fileName: _AssignmentSubmissionScreenState._text(row['file_name']),
      fileSizeBytes:
          int.tryParse(row['file_size_bytes']?.toString() ?? '') ?? 0,
      fileFingerprint:
          _AssignmentSubmissionScreenState._text(row['file_fingerprint']),
      submittedAt: DateTime.tryParse(
        _AssignmentSubmissionScreenState._text(row['submitted_at']),
      ),
      dueDate: dueDateValue == null
          ? null
          : DateTime(
              dueDateValue.year,
              dueDateValue.month,
              dueDateValue.day,
              23,
              59,
              59,
            ),
      grade: _AssignmentSubmissionScreenState._text(row['grade']),
      feedback: _AssignmentSubmissionScreenState._text(row['feedback']),
      extensionRequested: row['extension_requested'] == true,
      extensionStatus:
          _AssignmentSubmissionScreenState._text(row['extension_status']),
      uploadVersion:
          int.tryParse(row['upload_version']?.toString() ?? '') ?? 1,
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
      id: _AssignmentSubmissionScreenState._text(row['id']),
      programmeId:
          _AssignmentSubmissionScreenState._text(row['programme_id']),
      level: _AssignmentSubmissionScreenState._text(row['level']),
      name: _AssignmentSubmissionScreenState._text(row['name']),
      code: _AssignmentSubmissionScreenState._text(row['code']),
    );
  }

  @override
  bool operator ==(Object other) => other is _ModuleRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class _ManualAssessment {
  const _ManualAssessment({
    required this.title,
    required this.subject,
    required this.level,
    required this.moduleId,
    required this.deadline,
  });

  final String title;
  final String subject;
  final String level;
  final String moduleId;
  final DateTime? deadline;
}

class _StatusPresentation {
  const _StatusPresentation(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;
}

class _SecurityPoint extends StatelessWidget {
  const _SecurityPoint(this.icon, this.title, this.description);

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.vibeBlue.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.vibeBlue, size: 20),
          ),
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
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.35,
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
