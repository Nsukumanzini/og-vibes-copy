import 'dart:async';

import 'package:flutter/material.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pdf_viewer_screen.dart';

class PastQuestionPapersScreen extends StatefulWidget {
  const PastQuestionPapersScreen({super.key});

  @override
  State<PastQuestionPapersScreen> createState() => _PastQuestionPapersScreenState();
}

class _PastQuestionPapersScreenState extends State<PastQuestionPapersScreen> {
  final Map<String, Map<String, Map<String, Map<String, List<Map<String, String>>>>>> _library = {};
  StreamSubscription<List<Map<String, dynamic>>>? _papersSubscription;

  String? _selectedLevel;
  String? _selectedSubject;
  String? _selectedYear;
  String? _selectedExamType;
  String _subjectQuery = '';
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
      setState(() {
        _library
          ..clear()
          ..addAll(_buildLibraryFromRows(List<Map<String, dynamic>>.from(raw)));
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
      final level = (row['level'] as String?)?.trim() ?? 'Uncategorized';
      final subject = (row['subject'] as String?)?.trim() ?? 'General';
      final year = (row['year'] as String?)?.trim() ?? 'Unknown';
      final examType = (row['exam_type'] as String?)?.trim() ?? 'Other';
      final title = (row['title'] as String?)?.trim() ?? 'Document';
      final url = (row['url'] as String?)?.trim() ?? '';

      grouped.putIfAbsent(level, () => <String, Map<String, Map<String, List<Map<String, String>>>>>{});
      grouped[level]!.putIfAbsent(subject, () => <String, Map<String, List<Map<String, String>>>>{});
      grouped[level]![subject]!.putIfAbsent(year, () => <String, List<Map<String, String>>>{});
      grouped[level]![subject]![year]!.putIfAbsent(examType, () => <Map<String, String>>[]);
      grouped[level]![subject]![year]![examType]!.add({'title': title, 'url': url});
    }

    return grouped;
  }

  void _resetToLevels() {
    setState(() {
      _selectedLevel = null;
      _selectedSubject = null;
      _selectedYear = null;
      _selectedExamType = null;
      _subjectQuery = '';
    });
  }

  void _onLevelSelected(String level) {
    setState(() {
      _selectedLevel = level;
      _selectedSubject = null;
      _selectedYear = null;
      _selectedExamType = null;
      _subjectQuery = '';
    });
  }

  void _onSubjectSelected(String subject) {
    setState(() {
      _selectedSubject = subject;
      _selectedYear = null;
      _selectedExamType = null;
    });
  }

  void _onYearSelected(String year) {
    setState(() {
      _selectedYear = year;
      _selectedExamType = null;
    });
  }

  void _onExamTypeSelected(String exam) {
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
    return list ?? [];
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
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: _buildCurrentStep(context),
        ),
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
              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text(subj, style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _onSubjectSelected(subj),
                ),
              );
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
              return Card(
                child: ListTile(
                  title: Text(year, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Tap to see available exam types'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _onYearSelected(year),
                ),
              );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$_selectedSubject • $_selectedYear • $_selectedExamType', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: files.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final file = files[index];
              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xFF2962FF), child: Icon(Icons.picture_as_pdf, color: Colors.white)),
                  title: Text(file['title']!, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(file['url'] ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          final url = file['url'] ?? '';
                          if (url.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No URL available')));
                            return;
                          }
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfViewerScreen(url: url, title: file['title'] ?? 'Document')));
                        },
                        icon: const Icon(Icons.visibility),
                        label: const Text('View'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () async {
                          final url = file['url'] ?? '';
                          if (url.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No URL available')));
                            return;
                          }
                          final uri = Uri.tryParse(url);
                          if (uri == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid URL')));
                            return;
                          }
                          final messenger = ScaffoldMessenger.of(context);
                          final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                          if (!launched) {
                            messenger.showSnackBar(const SnackBar(content: Text('Could not open URL')));
                          }
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Download'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
