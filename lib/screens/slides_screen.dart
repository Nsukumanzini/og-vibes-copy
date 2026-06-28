import 'dart:async';

import 'package:flutter/material.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pdf_viewer_screen.dart';

class SlidesScreen extends StatefulWidget {
  const SlidesScreen({super.key});

  @override
  State<SlidesScreen> createState() => _SlidesScreenState();
}

class _SlidesScreenState extends State<SlidesScreen> {
  final Map<String, Map<String, List<Map<String, String>>>> _library = {};
  StreamSubscription<List<Map<String, dynamic>>>? _slidesSubscription;

  String? _selectedLevel;
  String? _selectedSubject;
  String _subjectQuery = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSlides();
    _listenForSlides();
  }

  @override
  void dispose() {
    _slidesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSlides() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final raw = await Supabase.instance.client
          .from('lecture_slides')
          .select('id, level, subject, title, url, created_at')
          .order('level', ascending: true)
          .order('subject', ascending: true)
          .order('title', ascending: true) as List<dynamic>?;

      if (!mounted) return;
      setState(() {
        _library
          ..clear()
          ..addAll(_buildLibraryFromRows(List<Map<String, dynamic>>.from(raw ?? [])));
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

  void _listenForSlides() {
    _slidesSubscription = Supabase.instance.client
        .from('lecture_slides')
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

  Future<void> _refreshSlides() async {
    await _loadSlides();
  }

  Map<String, Map<String, List<Map<String, String>>>> _buildLibraryFromRows(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, List<Map<String, String>>>>{};

    for (final row in rows) {
      final level = (row['level'] as String?)?.trim() ?? 'Uncategorized';
      final subject = (row['subject'] as String?)?.trim() ?? 'General';
      final title = (row['title'] as String?)?.trim() ?? 'Slide';
      final url = (row['url'] as String?)?.trim() ?? '';

      grouped.putIfAbsent(level, () => <String, List<Map<String, String>>>{});
      grouped[level]!.putIfAbsent(subject, () => <Map<String, String>>[]);
      grouped[level]![subject]!.add({'title': title, 'url': url});
    }

    return grouped;
  }

  void _resetToLevels() {
    setState(() {
      _selectedLevel = null;
      _selectedSubject = null;
      _subjectQuery = '';
    });
  }

  Widget _buildLevelSelector(BuildContext context) {
    final levels = _library.keys.toList();
    if (_isLoading && _library.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _library.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text('Unable to load slides right now.'),
              const SizedBox(height: 8),
              Text(_errorMessage ?? 'Please try again.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _refreshSlides,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose your level', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: levels.map((level) {
            return ChoiceChip(
              label: Text(level),
              selected: _selectedLevel == level,
              onSelected: (_) => setState(() => _selectedLevel = level),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSubjectList(BuildContext context) {
    final subjects = (_selectedLevel != null ? _library[_selectedLevel!]!.keys.toList() : <String>[])
        .where((s) => s.toLowerCase().contains(_subjectQuery.toLowerCase()))
        .toList();
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
                child: ListTile(
                  title: Text(subj, style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() => _selectedSubject = subj),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSlidesList(BuildContext context) {
    final slides = _selectedLevel != null && _selectedSubject != null ? _library[_selectedLevel!]![_selectedSubject!] ?? [] : [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$_selectedSubject • Slides & Summaries', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: slides.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final slide = slides[index];
              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xFF6C63FF), child: Icon(Icons.slideshow, color: Colors.white)),
                  title: Text(slide['title'] ?? ''),
                  subtitle: Text('Summary / slides document'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          final url = slide['url'] ?? '';
                          if (url.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No URL available')));
                            return;
                          }
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfViewerScreen(url: url, title: slide['title'] ?? 'Document')));
                        },
                        icon: const Icon(Icons.visibility),
                        label: const Text('View'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () async {
                          final url = slide['url'] ?? '';
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

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Lecture Slides & Summaries'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refreshSlides,
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
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
          duration: const Duration(milliseconds: 240),
          child: _selectedLevel == null ? _buildLevelSelector(context) : (_selectedSubject == null ? _buildSubjectList(context) : _buildSlidesList(context)),
        ),
      ),
    );
  }
}
