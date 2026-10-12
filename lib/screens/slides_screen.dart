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

enum _SlideSort { newest, oldest, title, subject, recentlyOpened }

class SlidesScreen extends StatefulWidget {
  const SlidesScreen({super.key});

  @override
  State<SlidesScreen> createState() => _SlidesScreenState();
}

class _SlidesScreenState extends State<SlidesScreen> {
  final Map<String, Map<String, List<Map<String, String>>>> _library = {};
  final List<Map<String, String>> _allSlides = [];
  final Map<String, Map<String, String>> _lecturersByModule = {};
  final Map<String, DateTime> _recentlyOpened = {};
  final Set<String> _preparingDownloads = {};
  final TextEditingController _globalSearchController = TextEditingController();
  StreamSubscription<List<Map<String, dynamic>>>? _slidesSubscription;

  String? _selectedLevel;
  String? _selectedSubject;
  String _subjectQuery = '';
  String _globalQuery = '';
  _SlideSort _sort = _SlideSort.newest;
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
    _globalSearchController.dispose();
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
          .select(
            'id, level, subject, title, url, created_at, updated_at, module_id',
          )
          .order('level', ascending: true)
          .order('subject', ascending: true)
          .order('title', ascending: true) as List<dynamic>?;

      await _loadLecturers();
      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(raw ?? []);
      setState(() {
        _allSlides
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

  void _listenForSlides() {
    _slidesSubscription = Supabase.instance.client
        .from('lecture_slides')
        .stream(primaryKey: ['id'])
        .listen((rows) {
          if (!mounted) return;
          setState(() {
            _allSlides
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

  Future<void> _refreshSlides() async {
    await _loadSlides();
  }

  Future<void> _loadLecturers() async {
    try {
      final raw = await Supabase.instance.client.from('module_lecturers').select(
            'module_id, profiles!module_lecturers_lecturer_id_fkey('
            'name, surname, photo_url)',
          ) as List<dynamic>;
      _lecturersByModule.clear();
      for (final value in raw) {
        final row = Map<String, dynamic>.from(value as Map);
        final moduleId = row['module_id']?.toString() ?? '';
        final profile = row['profiles'] is Map
            ? Map<String, dynamic>.from(row['profiles'] as Map)
            : <String, dynamic>{};
        final name = [
          profile['name']?.toString().trim(),
          profile['surname']?.toString().trim(),
        ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
        if (moduleId.isNotEmpty && name.isNotEmpty) {
          _lecturersByModule[moduleId] = {
            'lecturer': name,
            'lecturer_photo': profile['photo_url']?.toString() ?? '',
          };
        }
      }
    } catch (_) {
      _lecturersByModule.clear();
    }
  }

  Map<String, Map<String, List<Map<String, String>>>> _buildLibraryFromRows(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, List<Map<String, String>>>>{};

    for (final row in rows) {
      final slide = _slideFromRow(row);
      final level = slide['level']!;
      final subject = slide['subject']!;

      grouped.putIfAbsent(level, () => <String, List<Map<String, String>>>{});
      grouped[level]!.putIfAbsent(subject, () => <Map<String, String>>[]);
      grouped[level]![subject]!.add(slide);
    }

    return grouped;
  }

  List<Map<String, String>> _flattenRows(List<Map<String, dynamic>> rows) {
    return rows.map(_slideFromRow).toList();
  }

  Map<String, String> _slideFromRow(Map<String, dynamic> row) {
    final moduleId = _text(row['module_id'], '');
    final lecturer = _lecturersByModule[moduleId] ?? const {};
    return {
      'id': _text(row['id'], ''),
      'level': _text(row['level'], 'Uncategorized'),
      'subject': _text(row['subject'], 'General'),
      'title': _text(row['title'], 'Slide'),
      'url': _text(row['url'], ''),
      'created_at': _text(row['created_at'], ''),
      'updated_at': _text(row['updated_at'], ''),
      'module_id': moduleId,
      'lecturer': lecturer['lecturer'] ?? 'Course team',
      'lecturer_photo': lecturer['lecturer_photo'] ?? '',
    };
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
      _subjectQuery = '';
    });
  }

  List<Map<String, String>> _searchResults() {
    final query = _globalQuery.trim().toLowerCase();
    if (query.isEmpty) return [];
    return _sortSlides(
      _allSlides.where((slide) {
        return [
          slide['title'],
          slide['subject'],
          slide['level'],
          slide['lecturer'],
        ].join(' ').toLowerCase().contains(query);
      }).toList(),
    );
  }

  List<Map<String, String>> _sortSlides(List<Map<String, String>> slides) {
    final sorted = List<Map<String, String>>.from(slides);
    int compare(Map<String, String> a, Map<String, String> b) {
      return switch (_sort) {
        _SlideSort.newest =>
          (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
        _SlideSort.oldest =>
          (a['created_at'] ?? '').compareTo(b['created_at'] ?? ''),
        _SlideSort.title => (a['title'] ?? '')
            .toLowerCase()
            .compareTo((b['title'] ?? '').toLowerCase()),
        _SlideSort.subject => (a['subject'] ?? '')
            .toLowerCase()
            .compareTo((b['subject'] ?? '').toLowerCase()),
        _SlideSort.recentlyOpened =>
          (_recentlyOpened[b['id']] ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
            _recentlyOpened[a['id']] ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
      };
    }

    sorted.sort(compare);
    return sorted;
  }

  String _sortLabel(_SlideSort sort) {
    return switch (sort) {
      _SlideSort.newest => 'Newest first',
      _SlideSort.oldest => 'Oldest first',
      _SlideSort.title => 'Title A–Z',
      _SlideSort.subject => 'Subject A–Z',
      _SlideSort.recentlyOpened => 'Recently opened',
    };
  }

  String? _freshnessLabel(Map<String, String> slide) {
    final createdAt = DateTime.tryParse(slide['created_at'] ?? '');
    final updatedAt = DateTime.tryParse(slide['updated_at'] ?? '');
    final now = DateTime.now();
    if (updatedAt != null &&
        createdAt != null &&
        updatedAt.difference(createdAt).abs() > const Duration(minutes: 5) &&
        now.difference(updatedAt) <= const Duration(days: 14)) {
      return 'UPDATED';
    }
    if (createdAt != null &&
        now.difference(createdAt) <= const Duration(days: 14)) {
      return 'NEW';
    }
    return null;
  }

  Future<void> _openSlide(Map<String, String> slide) async {
    final url = slide['url'] ?? '';
    if (url.isEmpty) {
      _showMessage('No URL is available for this slide yet.');
      return;
    }
    HapticFeedback.lightImpact();
    final id = slide['id'] ?? url;
    setState(() => _recentlyOpened[id] = DateTime.now());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfViewerScreen(
          url: url,
          title: slide['title'] ?? 'Lecture slide',
        ),
      ),
    );
  }

  Future<void> _downloadSlide(Map<String, String> slide) async {
    final url = slide['url'] ?? '';
    final id = slide['id'] ?? url;
    if (_preparingDownloads.contains(id)) return;
    if (url.isEmpty) {
      _showMessage('No download link is available for this slide yet.');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showMessage('This download link is invalid.');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _preparingDownloads.add(id));
    _showMessage('Preparing ${slide['title'] ?? 'your slides'}…');
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
              onSelected: (_) {
                HapticFeedback.selectionClick();
                setState(() => _selectedLevel = level);
              },
              selectedColor: AppColors.vibeBlue,
              labelStyle: TextStyle(
                color: _selectedLevel == level
                    ? Colors.white
                    : AppColors.midnightInk,
                fontWeight: FontWeight.w700,
              ),
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
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedSubject = subj);
                  },
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

  Widget _buildSlidesList(BuildContext context) {
    final slides = _selectedLevel != null && _selectedSubject != null
        ? _sortSlides(_library[_selectedLevel!]![_selectedSubject!] ?? [])
        : <Map<String, String>>[];
    return _buildSlideCollection(
      title: '$_selectedSubject resources',
      subtitle: '$_selectedLevel  •  Slides & summaries',
      slides: slides,
    );
  }

  Widget _buildGlobalSearchResults() {
    final slides = _searchResults();
    return _buildSlideCollection(
      title: 'Search results',
      subtitle: '${slides.length} matches for “${_globalQuery.trim()}”',
      slides: slides,
    );
  }

  Widget _buildSlideCollection({
    required String title,
    required String subtitle,
    required List<Map<String, String>> slides,
  }) {
    if (slides.isEmpty) {
      return _glassPanel(
        padding: const EdgeInsets.all(28),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.slideshow_outlined,
                size: 50,
                color: AppColors.vibeBlue,
              ),
              SizedBox(height: 12),
              Text(
                'No lecture slides found',
                style: TextStyle(
                  color: AppColors.midnightInk,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Try another search or choose a different subject.',
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
          '${slides.length} RESOURCE${slides.length == 1 ? '' : 'S'}',
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
            itemCount: slides.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final slide = slides[index];
              final id = slide['id'] ?? slide['url'] ?? '';
              final preparing = _preparingDownloads.contains(id);
              final freshness = _freshnessLabel(slide);
              final lecturerPhoto = slide['lecturer_photo'] ?? '';
              return _glassPanel(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.vibeBlue,
                              Color(0xFF7A5AF8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.vibeBlue.withValues(alpha: 0.22),
                              blurRadius: 16,
                              offset: const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.slideshow_rounded,
                          color: Colors.white,
                        ),
                      ),
                      if (freshness != null)
                        Positioned(
                          left: -5,
                          bottom: -7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: freshness == 'NEW'
                                  ? AppColors.success
                                  : AppColors.warning,
                              borderRadius: AppStyles.pillRadius,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Text(
                              freshness,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(
                    slide['title'] ?? 'Lecture slide',
                    style: const TextStyle(
                      color: AppColors.midnightInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor:
                              AppColors.vibeBlue.withValues(alpha: 0.12),
                          backgroundImage: lecturerPhoto.isNotEmpty
                              ? NetworkImage(lecturerPhoto)
                              : null,
                          child: lecturerPhoto.isEmpty
                              ? const Icon(
                                  Icons.person_outline_rounded,
                                  size: 14,
                                  color: AppColors.vibeBlue,
                                )
                              : null,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '${slide['lecturer'] ?? 'Course team'}  •  '
                            '${slide['subject'] ?? _selectedSubject ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Slide actions',
                    onSelected: (value) {
                      if (value == 'view') _openSlide(slide);
                      if (value == 'download') _downloadSlide(slide);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'view',
                        child: ListTile(
                          leading: Icon(Icons.visibility_outlined),
                          title: Text('View slides'),
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
                  onTap: () => _openSlide(slide),
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

  Widget _buildHero() {
    final subjectCount = _library.values
        .expand((subjects) => subjects.keys)
        .toSet()
        .length;
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
                Color(0xFF4C55D9),
                AppColors.vibeBlue,
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
                    color: AppColors.electricCyan.withValues(alpha: 0.17),
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
                      'OG VIBES LECTURE LIBRARY',
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
                    'Everything from class,\nready when you are.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    [
                      _selectedLevel,
                      _selectedSubject,
                    ].whereType<String>().join('  •  ').isEmpty
                        ? 'Slides, summaries and lecturer resources'
                        : [
                            _selectedLevel,
                            _selectedSubject,
                          ].whereType<String>().join('  •  '),
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
                        Icons.slideshow_outlined,
                        '${_allSlides.length} resources',
                      ),
                      _heroMetric(
                        Icons.menu_book_outlined,
                        '$subjectCount subjects',
                      ),
                      _heroMetric(
                        Icons.person_outline_rounded,
                        '${_lecturersByModule.length} lecturers',
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

  Widget _buildSearchAndSort() {
    return _glassPanel(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = TextField(
            controller: _globalSearchController,
            onChanged: (value) => setState(() => _globalQuery = value),
            decoration: InputDecoration(
              hintText: 'Search slides, subjects or lecturers',
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
          final sort = DropdownButtonFormField<_SlideSort>(
            initialValue: _sort,
            isExpanded: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.sort_rounded),
              labelText: 'Sort',
            ),
            items: _SlideSort.values
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
            HapticFeedback.selectionClick();
            if (_globalQuery.isNotEmpty) {
              _globalSearchController.clear();
              setState(() => _globalQuery = '');
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
              _buildHero(),
              const SizedBox(height: 12),
              _buildSearchAndSort(),
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
                      '$_selectedLevel|$_selectedSubject|$_globalQuery|$_sort',
                    ),
                    child: _globalQuery.trim().isNotEmpty
                        ? _buildGlobalSearchResults()
                        : _selectedLevel == null
                            ? _buildLevelSelector(context)
                            : (_selectedSubject == null
                                ? _buildSubjectList(context)
                                : _buildSlidesList(context)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
