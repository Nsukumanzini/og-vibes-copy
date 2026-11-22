import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:shimmer/shimmer.dart';
import '../services/offline_data_adapter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/download_history_service.dart';
import '../services/academic_file_service.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

import 'pdf_viewer_screen.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final List<_TimetableItem> _timetables = [];
  StreamSubscription<List<Map<String, dynamic>>>? _timetableSubscription;

  List<String> _levels = [];
  List<String> _programmes = [];
  List<String> _modules = [];

  String? _selectedLevel;
  String? _selectedProgramme;
  String? _selectedModule;
  final Set<String> _preparingDocuments = {};

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTimetables();
    _listenForTimetables();
  }

  @override
  void dispose() {
    _timetableSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadTimetables() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await OfflineData.instance.client
          .from('timetables')
          .select(
            'id, level, programme, module, group_name, title, url, '
            'storage_path, created_at, updated_at',
          )
          .order('level', ascending: true)
          .order('programme', ascending: true)
          .order('group_name', ascending: true)
          .order('title', ascending: true);

      final rows = (response as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _timetables
          ..clear()
          ..addAll(rows.map(_TimetableItem.fromRow));
        _rebuildFilterOptions();
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

  void _listenForTimetables() {
    _timetableSubscription = OfflineData.instance.client
        .from('timetables')
        .stream(primaryKey: ['id'])
        .listen(
          (rows) {
            if (!mounted) return;
            setState(() {
              _timetables
                ..clear()
                ..addAll(
                  rows.map(
                    (row) =>
                        _TimetableItem.fromRow(Map<String, dynamic>.from(row)),
                  ),
                );
              _rebuildFilterOptions();
              _isLoading = false;
              _errorMessage = null;
            });
          },
          onError: (error) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _errorMessage = error.toString();
            });
          },
        );
  }

  Future<void> _refreshTimetables() async {
    await _loadTimetables();
  }

  void _rebuildFilterOptions() {
    final levels =
        _timetables
            .map((item) => item.level.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    if (_selectedLevel != null && !levels.contains(_selectedLevel)) {
      _selectedLevel = null;
    }

    final programmes =
        _selectedLevel == null
              ? <String>[]
              : _timetables
                    .where((item) => item.level == _selectedLevel)
                    .map((item) => item.programme.trim())
                    .where((value) => value.isNotEmpty)
                    .toSet()
                    .toList()
          ..sort();

    if (_selectedProgramme != null &&
        !programmes.contains(_selectedProgramme)) {
      _selectedProgramme = null;
    }

    final modules =
        (_selectedLevel == null || _selectedProgramme == null)
              ? <String>[]
              : _timetables
                    .where(
                      (item) =>
                          item.level == _selectedLevel &&
                          item.programme == _selectedProgramme,
                    )
                    .map((item) => item.module.trim())
                    .where((value) => value.isNotEmpty)
                    .toSet()
                    .toList()
          ..sort();

    if (_selectedModule != null && !modules.contains(_selectedModule)) {
      _selectedModule = null;
    }

    _levels = levels;
    _programmes = programmes;
    _modules = modules;
  }

  List<_TimetableItem> get _filteredTimetables {
    return _timetables.where((item) {
      final matchesLevel =
          _selectedLevel == null || item.level == _selectedLevel;
      final matchesProgramme =
          _selectedProgramme == null || item.programme == _selectedProgramme;
      final matchesModule =
          _selectedModule == null || item.module == _selectedModule;
      return matchesLevel && matchesProgramme && matchesModule;
    }).toList();
  }

  Future<void> _openTimetable(_TimetableItem item) async {
    HapticFeedback.lightImpact();
    final resolvedUrl = await _resolveTimetableUrl(item);
    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null || uri.toString().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This timetable does not have a valid link yet.'),
        ),
      );
      return;
    }

    if (item.storagePath.isNotEmpty ||
        resolvedUrl.toLowerCase().contains('.pdf')) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(url: resolvedUrl, title: item.title),
        ),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this timetable link.')),
      );
    }
  }

  String? _freshnessLabel(_TimetableItem item) {
    final now = DateTime.now();
    if (item.updatedAt.difference(item.createdAt).abs() >
            const Duration(minutes: 5) &&
        now.difference(item.updatedAt) <= const Duration(days: 14)) {
      return 'UPDATED';
    }
    if (now.difference(item.createdAt) <= const Duration(days: 14)) {
      return 'NEW';
    }
    return null;
  }

  Future<void> _downloadTimetable(_TimetableItem item) async {
    if (_preparingDocuments.contains(item.id)) return;
    HapticFeedback.mediumImpact();
    setState(() => _preparingDocuments.add(item.id));
    _showMessage('Preparing the timetable download…');
    try {
      final resolvedUrl = await _resolveTimetableUrl(item);
      if (!mounted) return;
      final launched = await AcademicFileService.download(
        resolvedUrl,
        '${item.title}.pdf',
      );
      if (launched) {
        await DownloadHistoryService.record(
          sourceType: 'timetable',
          sourceId: item.id,
          title: item.title,
          url: item.url,
          storagePath: item.storagePath,
        );
      }
      if (!mounted) return;
      _showMessage(
        launched
            ? 'Timetable saved or sent to your browser downloads.'
            : 'Download cancelled.',
      );
    } catch (_) {
      if (mounted) {
        _showMessage('Could not prepare the document. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _preparingDocuments.remove(item.id));
    }
  }

  Future<String> _resolveTimetableUrl(_TimetableItem item) async {
    if (item.storagePath.isNotEmpty) {
      return OfflineData.instance.client.storage
          .from('academic-content')
          .createSignedUrl(item.storagePath, 600);
    }
    return item.url;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Timetable'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh timetables',
            onPressed: _refreshTimetables,
          ),
        ],
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        color: Colors.transparent,
        child: _isLoading && _timetables.isEmpty
            ? _buildLoading()
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null && _timetables.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.vibeBlue,
              ),
              const SizedBox(height: 12),
              const Text(
                'Unable to load timetables right now.',
                style: TextStyle(
                  color: AppColors.midnightInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Please try again.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _refreshTimetables,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 14),
              _buildFilterSection(),
            ],
          ),
        ),
        Expanded(
          child: _filteredTimetables.isEmpty
              ? _buildEmptyState()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1050
                        ? 3
                        : constraints.maxWidth >= 680
                        ? 2
                        : 1;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        mainAxisExtent: 244,
                      ),
                      itemCount: _filteredTimetables.length,
                      itemBuilder: (context, index) {
                        final item = _filteredTimetables[index];
                        return _TimetableCard(
                              item: item,
                              preparing: _preparingDocuments.contains(item.id),
                              freshness: _freshnessLabel(item),
                              onView: () => _openTimetable(item),
                              onDownload: () => _downloadTimetable(item),
                            )
                            .animate(delay: (45 * index).ms)
                            .fadeIn(duration: 340.ms)
                            .slideY(begin: 0.05, end: 0);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final selection = [
      _selectedLevel,
      _selectedProgramme,
      _selectedModule,
    ].whereType<String>().join('  •  ');
    return ClipRRect(
      borderRadius: AppStyles.bentoRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.midnightInk,
                AppColors.vibeBlue,
                Color(0xFF2457F5),
              ],
            ),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            boxShadow: AppStyles.glassShadow,
          ),
          child: Stack(
            children: [
              Positioned(
                right: -25,
                top: -42,
                child: Container(
                  width: 145,
                  height: 145,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.electricCyan.withValues(alpha: 0.18),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.13),
                      borderRadius: AppStyles.pillRadius,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Text(
                      'MY ACADEMIC TIMETABLES',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  const Text(
                    'Your schedule documents,\nbeautifully organised.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    selection.isEmpty
                        ? 'Filter by level, course and module'
                        : selection,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.76),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _heroMetric(
                        Icons.description_outlined,
                        '${_timetables.length} PDFs',
                      ),
                      _heroMetric(
                        Icons.school_outlined,
                        '${_programmes.length} courses',
                      ),
                      _heroMetric(
                        Icons.menu_book_outlined,
                        '${_modules.length} modules',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 420.ms).slideY(begin: 0.06, end: 0);
  }

  Widget _heroMetric(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: AppStyles.pillRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.electricCyan),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return _glassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_levels.isNotEmpty)
            _filterChips(
              label: 'Level',
              options: _levels,
              selected: _selectedLevel,
              onSelected: (level) {
                _selectedLevel = level;
                _selectedProgramme = null;
                _selectedModule = null;
                _rebuildFilterOptions();
              },
            ),
          if (_selectedLevel != null && _programmes.isNotEmpty) ...[
            const SizedBox(height: 12),
            _filterChips(
              label: 'Course',
              options: _programmes,
              selected: _selectedProgramme,
              onSelected: (programme) {
                _selectedProgramme = programme;
                _selectedModule = null;
                _rebuildFilterOptions();
              },
            ),
          ],
          if (_selectedProgramme != null && _modules.isNotEmpty) ...[
            const SizedBox(height: 12),
            _filterChips(
              label: 'Module',
              options: _modules,
              selected: _selectedModule,
              onSelected: (module) => _selectedModule = module,
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChips({
    required String label,
    required List<String> options,
    required String? selected,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.midnightInk,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final active = selected == option;
            return ChoiceChip(
              label: Text(option),
              selected: active,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                setState(() => onSelected(option));
              },
              selectedColor: AppColors.vibeBlue,
              backgroundColor: AppColors.auroraCanvas,
              side: BorderSide(
                color: active ? AppColors.vibeBlue : AppColors.glassBorder,
              ),
              labelStyle: TextStyle(
                color: active ? Colors.white : AppColors.midnightInk,
                fontWeight: FontWeight.w700,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _glassPanel({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppStyles.bentoRadius,
        border: Border.all(color: AppColors.outline),
        boxShadow: AppStyles.softShadow,
      ),
      child: child,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.description_outlined,
              size: 48,
              color: AppColors.vibeBlue,
            ),
            const SizedBox(height: 12),
            const Text(
              'No timetable found for this selection.',
              style: TextStyle(
                color: AppColors.midnightInk,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try another level, course, or module.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshTimetables,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh list'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 100),
      child: Shimmer.fromColors(
        baseColor: Colors.white.withValues(alpha: 0.52),
        highlightColor: Colors.white.withValues(alpha: 0.9),
        child: ListView.separated(
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, _) => Container(
            height: 122,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimetableCard extends StatelessWidget {
  const _TimetableCard({
    required this.item,
    required this.preparing,
    required this.freshness,
    required this.onView,
    required this.onDownload,
  });

  final _TimetableItem item;
  final bool preparing;
  final String? freshness;
  final VoidCallback onView;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: AppStyles.bentoRadius,
      child: InkWell(
        onTap: onView,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(color: AppColors.outline),
            boxShadow: AppStyles.glassShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.vibeBlue, AppColors.electricCyan],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.calendar_view_week_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.midnightInk,
                      ),
                    ),
                  ),
                  if (freshness != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: freshness == 'NEW'
                            ? AppColors.success
                            : AppColors.warning,
                        borderRadius: AppStyles.pillRadius,
                      ),
                      child: Text(
                        freshness!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _pill(item.level, AppColors.vibeBlue),
                  _pill(item.programme, AppColors.success),
                  _pill(item.module, AppColors.academicAccent),
                  if (item.groupName.isNotEmpty)
                    _pill(item.groupName, AppColors.warning),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onView,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('View PDF'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: preparing ? null : onDownload,
                      icon: preparing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(preparing ? 'Preparing…' : 'Download PDF'),
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

  Widget _pill(String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _TimetableItem {
  const _TimetableItem({
    required this.id,
    required this.level,
    required this.programme,
    required this.module,
    required this.groupName,
    required this.title,
    required this.url,
    required this.storagePath,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String level;
  final String programme;
  final String module;
  final String groupName;
  final String title;
  final String url;
  final String storagePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory _TimetableItem.fromRow(Map<String, dynamic> row) {
    return _TimetableItem(
      id: (row['id'] ?? '').toString(),
      level: (row['level'] ?? '').toString().trim(),
      programme: (row['programme'] ?? '').toString().trim(),
      module: (row['module'] ?? 'All modules').toString().trim(),
      groupName: (row['group_name'] ?? '').toString().trim(),
      title: (row['title'] ?? '').toString().trim(),
      url: (row['url'] ?? '').toString().trim(),
      storagePath: (row['storage_path'] ?? '').toString().trim(),
      createdAt:
          DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse((row['updated_at'] ?? '').toString()) ??
          DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
