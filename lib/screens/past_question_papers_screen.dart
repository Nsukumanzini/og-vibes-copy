import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pdf_viewer_screen.dart';

enum _PaperSort { newest, oldest, title, subject, mostViewed }

class PastQuestionPapersScreen extends StatefulWidget {
  const PastQuestionPapersScreen({super.key});

  @override
  State<PastQuestionPapersScreen> createState() => _PastQuestionPapersScreenState();
}

class _PastQuestionPapersScreenState extends State<PastQuestionPapersScreen> {
  final Map<String, Map<String, Map<String, Map<String, List<Map<String, String>>>>>> _library = {};
  final List<Map<String, String>> _allPapers = [];
  final Map<String, int> _viewCounts = {};
  final Set<String> _preparingDownloads = {};
  final TextEditingController _globalSearchController = TextEditingController();
  StreamSubscription<List<Map<String, dynamic>>>? _papersSubscription;

  String? _selectedLevel;
  String? _selectedSubject;
  String? _selectedYear;
  String? _selectedExamType;
  String _subjectQuery = '';
  String _globalQuery = '';
  _PaperSort _sort = _PaperSort.newest;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPapers();
    _listenForPapers();
  }

  @override
  void dispose() {
    _papersSubscription?.cancel();
    _globalSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadPapers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final raw = await Supabase.instance.client
          .from('past_papers')
          .select('id, level, subject, year, exam_type, title, url, created_at')
          .order('level', ascending: true)
          .order('subject', ascending: true)
          .order('year', ascending: true)
          .order('exam_type', ascending: true)
          .order('title', ascending: true) as List<dynamic>;

      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(raw);
      setState(() {
        _allPapers
          ..clear()
          ..addAll(_flattenRows(rows));
        _library
          ..clear()
          ..addAll(_buildLibraryFromRows(rows));
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

  void _listenForPapers() {
    _papersSubscription = Supabase.instance.client
        .from('past_papers')
        .stream(primaryKey: ['id'])
        .listen((rows) {
          if (!mounted) return;
          setState(() {
            _allPapers
              ..clear()
              ..addAll(_flattenRows(rows));
            _library
              ..clear()
              ..addAll(_buildLibraryFromRows(List<Map<String, dynamic>>.from(rows)));
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

  Future<void> _refreshPapers() async {
    await _loadPapers();
  }

  Map<String, Map<String, Map<String, Map<String, List<Map<String, String>>>>>> _buildLibraryFromRows(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, Map<String, Map<String, List<Map<String, String>>>>>>{};

    for (final row in rows) {
      final level = _text(row['level'], 'Uncategorized');
      final subject = _text(row['subject'], 'General');
      final year = _text(row['year'], 'Unknown');
      final examType = _text(row['exam_type'], 'Other');
      final title = _text(row['title'], 'Document');
      final url = _text(row['url'], '');
      final id = _text(row['id'], '$level-$subject-$year-$title');
      final createdAt = _text(row['created_at'], '');

      grouped.putIfAbsent(level, () => <String, Map<String, Map<String, List<Map<String, String>>>>>{});
      grouped[level]!.putIfAbsent(subject, () => <String, Map<String, List<Map<String, String>>>>{});
      grouped[level]![subject]!.putIfAbsent(year, () => <String, List<Map<String, String>>>{});
      grouped[level]![subject]![year]!.putIfAbsent(examType, () => <Map<String, String>>[]);
      grouped[level]![subject]![year]![examType]!.add({
        'id': id,
        'level': level,
        'subject': subject,
        'year': year,
        'exam_type': examType,
        'title': title,
        'url': url,
        'created_at': createdAt,
      });
    }

    return grouped;
  }

  List<Map<String, String>> _flattenRows(List<Map<String, dynamic>> rows) {
    return rows.map((row) {
      final level = _text(row['level'], 'Uncategorized');
      final subject = _text(row['subject'], 'General');
      final year = _text(row['year'], 'Unknown');
      final title = _text(row['title'], 'Document');
      return <String, String>{
        'id': _text(row['id'], '$level-$subject-$year-$title'),
        'level': level,
        'subject': subject,
        'year': year,
        'exam_type': _text(row['exam_type'], 'Other'),
        'title': title,
        'url': _text(row['url'], ''),
        'created_at': _text(row['created_at'], ''),
      };
    }).toList();
  }

  String _text(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  void _resetToLevels() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedLevel = null;
      _selectedSubject = null;
      _selectedYear = null;
      _selectedExamType = null;
      _subjectQuery = '';
    });
  }

  void _onLevelSelected(String level) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedLevel = level;
      _selectedSubject = null;
      _selectedYear = null;
      _selectedExamType = null;
      _subjectQuery = '';
    });
  }

  void _onSubjectSelected(String subject) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedSubject = subject;
      _selectedYear = null;
      _selectedExamType = null;
    });
  }

  void _onYearSelected(String year) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedYear = year;
      _selectedExamType = null;
    });
  }

  void _onExamTypeSelected(String exam) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedExamType = exam;
    });
  }

  List<String> _levels() => _library.keys.toList();

  List<String> _subjectsForSelectedLevel() {
    if (_selectedLevel == null) return [];
    return _library[_selectedLevel!]!.keys.toList();
  }

  List<String> _yearsForSelectedSubject() {
    if (_selectedLevel == null || _selectedSubject == null) return [];
    final subjMap = _library[_selectedLevel!]![_selectedSubject!];
    if (subjMap == null) return [];
    return subjMap.keys.toList();
  }

  List<String> _examTypesForSelectedYear() {
    if (_selectedLevel == null || _selectedSubject == null || _selectedYear == null) return [];
    final map = _library[_selectedLevel!]![_selectedSubject!]![_selectedYear!];
    if (map == null) return [];
    return map.keys.toList();
  }

  List<Map<String, String>> _filesForSelectedExam() {
    if (_selectedLevel == null || _selectedSubject == null || _selectedYear == null || _selectedExamType == null) return [];
    final list = _library[_selectedLevel!]![_selectedSubject!]![_selectedYear!]![_selectedExamType!];
    return _sortPapers(list ?? []);
  }

  List<Map<String, String>> _searchResults() {
    final query = _globalQuery.trim().toLowerCase();
    if (query.isEmpty) return [];
    return _sortPapers(
      _allPapers.where((paper) {
        final searchable = [
          paper['title'],
          paper['subject'],
          paper['year'],
          paper['exam_type'],
          paper['level'],
        ].join(' ').toLowerCase();
        return searchable.contains(query);
      }).toList(),
    );
  }

  List<Map<String, String>> _sortPapers(List<Map<String, String>> papers) {
    final sorted = List<Map<String, String>>.from(papers);
    int compare(Map<String, String> a, Map<String, String> b) {
      return switch (_sort) {
        _PaperSort.newest =>
          (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
        _PaperSort.oldest =>
          (a['created_at'] ?? '').compareTo(b['created_at'] ?? ''),
        _PaperSort.title => (a['title'] ?? '')
            .toLowerCase()
            .compareTo((b['title'] ?? '').toLowerCase()),
        _PaperSort.subject => (a['subject'] ?? '')
            .toLowerCase()
            .compareTo((b['subject'] ?? '').toLowerCase()),
        _PaperSort.mostViewed => (_viewCounts[b['id']] ?? 0)
            .compareTo(_viewCounts[a['id']] ?? 0),
      };
    }

    sorted.sort(compare);
    return sorted;
  }

  String _sortLabel(_PaperSort sort) {
    return switch (sort) {
      _PaperSort.newest => 'Newest first',
      _PaperSort.oldest => 'Oldest first',
      _PaperSort.title => 'Title A–Z',
      _PaperSort.subject => 'Subject A–Z',
      _PaperSort.mostViewed => 'Most viewed',
    };
  }

  String get _selectionLabel {
    return [
      _selectedLevel,
      _selectedSubject,
      _selectedYear,
      _selectedExamType,
    ].whereType<String>().join('  •  ');
  }

  Future<void> _openPaper(Map<String, String> paper) async {
    final url = paper['url'] ?? '';
    if (url.isEmpty) {
      _showMessage('No URL is available for this paper yet.');
      return;
    }
    HapticFeedback.lightImpact();
    final id = paper['id'] ?? url;
    setState(() => _viewCounts[id] = (_viewCounts[id] ?? 0) + 1);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfViewerScreen(
          url: url,
          title: paper['title'] ?? 'Document',
        ),
      ),
    );
  }

  Future<void> _downloadPaper(Map<String, String> paper) async {
    final url = paper['url'] ?? '';
    final id = paper['id'] ?? url;
    if (_preparingDownloads.contains(id)) return;
    if (url.isEmpty) {
      _showMessage('No download link is available for this paper yet.');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showMessage('This download link is invalid.');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _preparingDownloads.add(id));
    _showMessage('Preparing ${paper['title'] ?? 'your paper'}…');
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      _showMessage(
        launched
            ? 'Download opened in your browser.'
            : 'Could not start the download. Please try again.',
      );
    } catch (_) {
      if (mounted) {
        _showMessage('Download failed. Check your connection and retry.');
      }
    } finally {
      if (mounted) setState(() => _preparingDownloads.remove(id));
    }
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
        title: const Text('Past Question Papers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refreshPapers,
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_selectedExamType != null) {
              setState(() => _selectedExamType = null);
              return;
            }
            if (_selectedYear != null) {
              setState(() => _selectedYear = null);
              return;
            }
            if (_selectedSubject != null) {
              setState(() => _selectedSubject = null);
              return;
            }
            if (_selectedLevel != null) {
              _resetToLevels();
              return;
            }
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            children: [
              _buildHero(context),
              const SizedBox(height: 12),
              _buildSearchAndSort(context),
              const SizedBox(height: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  reverseDuration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.045, 0.02),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(
                      '$_selectedLevel|$_selectedSubject|$_selectedYear|'
                      '$_selectedExamType|$_globalQuery|$_sort',
                    ),
                    child: _buildCurrentStep(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final viewed = _viewCounts.values.fold<int>(0, (total, value) => total + value);
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
                Color(0xFF2089D8),
              ],
            ),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            boxShadow: AppStyles.glassShadow,
          ),
          child: Stack(
            children: [
              Positioned(
                right: -30,
                top: -46,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.electricCyan.withValues(alpha: 0.2),
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
                      'OG VIBES STUDY LIBRARY',
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
                    'Past papers,\nsmarter preparation.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _selectionLabel.isEmpty
                        ? 'Explore every available level and subject'
                        : _selectionLabel,
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
                        '${_allPapers.length} papers',
                      ),
                      _heroMetric(Icons.layers_outlined, '${_levels().length} levels'),
                      _heroMetric(Icons.visibility_outlined, '$viewed viewed'),
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

  Widget _buildSearchAndSort(BuildContext context) {
    return _glassPanel(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = TextField(
            controller: _globalSearchController,
            onChanged: (value) => setState(() => _globalQuery = value),
            decoration: InputDecoration(
              hintText: 'Search every paper, subject or year',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _globalQuery.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _globalSearchController.clear();
                        setState(() => _globalQuery = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          );
          final sort = DropdownButtonFormField<_PaperSort>(
            initialValue: _sort,
            isExpanded: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.sort_rounded),
              labelText: 'Sort',
            ),
            items: _PaperSort.values
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(_sortLabel(value)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              HapticFeedback.selectionClick();
              setState(() => _sort = value);
            },
          );

          if (constraints.maxWidth >= 620) {
            return Row(
              children: [
                Expanded(flex: 2, child: search),
                const SizedBox(width: 10),
                SizedBox(width: 205, child: sort),
              ],
            );
          }
          return Column(
            children: [
              search,
              const SizedBox(height: 8),
              sort,
            ],
          );
        },
      ),
    );
  }

  Widget _buildCurrentStep(BuildContext context) {
    if (_isLoading && _library.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _library.isEmpty) {
      return _buildErrorState(context);
    }

    if (_globalQuery.trim().isNotEmpty) return _buildGlobalSearchResults(context);
    if (_selectedLevel == null) return _buildLevelSelector(context);
    if (_selectedSubject == null) return _buildSubjectList(context);
    if (_selectedYear == null) return _buildYearList(context);
    if (_selectedExamType == null) return _buildExamTypeList(context);
    return _buildFilesList(context);
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 52, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              'Unable to load past papers right now.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Please try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshPapers,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelSelector(BuildContext context) {
    final levels = _levels();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose your level / semester', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: levels.map((level) {
            return ChoiceChip(
              label: Text(level),
              selected: _selectedLevel == level,
              onSelected: (_) => _onLevelSelected(level),
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(color: _selectedLevel == level ? Colors.white : Colors.black87),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSubjectList(BuildContext context) {
    final subjects = _subjectsForSelectedLevel().where((s) => s.toLowerCase().contains(_subjectQuery.toLowerCase())).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Level: $_selectedLevel', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search subject...'),
          onChanged: (v) => setState(() => _subjectQuery = v),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: subjects.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final subj = subjects[index];
              return _glassPanel(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.vibeBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: AppColors.vibeBlue,
                    ),
                  ),
                  title: Text(subj, style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _onSubjectSelected(subj),
                ),
              )
                  .animate(delay: (45 * index).ms)
                  .fadeIn(duration: 300.ms)
                  .slideX(begin: 0.03, end: 0);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildYearList(BuildContext context) {
    final years = _yearsForSelectedSubject();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$_selectedSubject • Select year', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: years.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final year = years[index];
              return _glassPanel(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.electricCyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: AppColors.vibeBlue,
                    ),
                  ),
                  title: Text(year, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Tap to see available exam types'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _onYearSelected(year),
                ),
              )
                  .animate(delay: (45 * index).ms)
                  .fadeIn(duration: 300.ms)
                  .slideX(begin: 0.03, end: 0);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildExamTypeList(BuildContext context) {
    final exams = _examTypesForSelectedYear();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$_selectedSubject • $_selectedYear', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: exams.map((exam) {
            return ElevatedButton(
              onPressed: () => _onExamTypeSelected(exam),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(exam),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFilesList(BuildContext context) {
    final files = _filesForSelectedExam();
    return _buildPaperCollection(
      context,
      title: '$_selectedSubject papers',
      subtitle: '$_selectedYear  •  $_selectedExamType',
      files: files,
    );
  }

  Widget _buildGlobalSearchResults(BuildContext context) {
    final results = _searchResults();
    return _buildPaperCollection(
      context,
      title: 'Search results',
      subtitle: '${results.length} matches for “${_globalQuery.trim()}”',
      files: results,
    );
  }

  Widget _buildPaperCollection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Map<String, String>> files,
  }) {
    if (files.isEmpty) {
      return _glassPanel(
        padding: const EdgeInsets.all(28),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: AppColors.vibeBlue,
              ),
              SizedBox(height: 12),
              Text(
                'No matching papers',
                style: TextStyle(
                  color: AppColors.midnightInk,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Try another search or change your selection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${files.length} DOCUMENT${files.length == 1 ? '' : 'S'}',
          style: const TextStyle(
            color: AppColors.vibeBlue,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.midnightInk,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: files.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final file = files[index];
              final id = file['id'] ?? file['url'] ?? '';
              final preparing = _preparingDownloads.contains(id);
              return _glassPanel(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.vibeBlue, Color(0xFF4A82FB)],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.vibeBlue.withValues(alpha: 0.22),
                          blurRadius: 16,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    file['title'] ?? 'Document',
                    style: const TextStyle(
                      color: AppColors.midnightInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${file['subject'] ?? _selectedSubject ?? ''}  •  '
                      '${file['year'] ?? _selectedYear ?? ''}  •  '
                      '${file['exam_type'] ?? _selectedExamType ?? ''}\n'
                      '${_viewCounts[id] ?? 0} views this session',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        height: 1.45,
                      ),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Paper actions',
                    onSelected: (value) {
                      if (value == 'view') _openPaper(file);
                      if (value == 'download') _downloadPaper(file);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'view',
                        child: ListTile(
                          leading: Icon(Icons.visibility_outlined),
                          title: Text('View paper'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'download',
                        enabled: !preparing,
                        child: ListTile(
                          leading: preparing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download_rounded),
                          title: Text(
                            preparing ? 'Preparing…' : 'Download',
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _openPaper(file),
                ),
              )
                  .animate(delay: (45 * index).ms)
                  .fadeIn(duration: 320.ms)
                  .slideX(begin: 0.035, end: 0);
            },
          ),
        ),
      ],
    );
  }

  Widget _glassPanel({
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return ClipRRect(
      borderRadius: AppStyles.bentoRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.86),
            ),
            boxShadow: AppStyles.glassShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}
