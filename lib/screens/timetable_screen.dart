import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
  List<String> _groups = [];

  String? _selectedLevel;
  String? _selectedProgramme;
  String? _selectedGroup;

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
      final response = await Supabase.instance.client
          .from('timetables')
          .select('id, level, programme, group_name, title, url, created_at')
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
    _timetableSubscription = Supabase.instance.client
        .from('timetables')
        .stream(primaryKey: ['id'])
        .listen((rows) {
          if (!mounted) return;
          setState(() {
            _timetables
              ..clear()
              ..addAll(rows.map((row) => _TimetableItem.fromRow(Map<String, dynamic>.from(row))));
            _rebuildFilterOptions();
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

  Future<void> _refreshTimetables() async {
    await _loadTimetables();
  }

  void _rebuildFilterOptions() {
    final levels = _timetables
        .map((item) => item.level.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    if (_selectedLevel != null && !levels.contains(_selectedLevel)) {
      _selectedLevel = null;
    }

    final programmes = _selectedLevel == null
        ? <String>[]
        : _timetables
            .where((item) => item.level == _selectedLevel)
            .map((item) => item.programme.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    if (_selectedProgramme != null && !programmes.contains(_selectedProgramme)) {
      _selectedProgramme = null;
    }

    final groups = (_selectedLevel == null || _selectedProgramme == null)
        ? <String>[]
        : _timetables
            .where((item) => item.level == _selectedLevel && item.programme == _selectedProgramme)
            .map((item) => item.groupName.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    if (_selectedGroup != null && !groups.contains(_selectedGroup)) {
      _selectedGroup = null;
    }

    _levels = levels;
    _programmes = programmes;
    _groups = groups;
  }

  List<_TimetableItem> get _filteredTimetables {
    return _timetables.where((item) {
      final matchesLevel = _selectedLevel == null || item.level == _selectedLevel;
      final matchesProgramme = _selectedProgramme == null || item.programme == _selectedProgramme;
      final matchesGroup = _selectedGroup == null || item.groupName == _selectedGroup;
      return matchesLevel && matchesProgramme && matchesGroup;
    }).toList();
  }

  Future<void> _openTimetable(_TimetableItem item) async {
    final uri = Uri.tryParse(item.url);
    if (uri == null || uri.toString().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This timetable does not have a valid link yet.')),
      );
      return;
    }

    if (item.url.toLowerCase().endsWith('.pdf')) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(url: item.url, title: item.title),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D47A1), Color(0xFF2962FF), Color(0xFF6200EA)],
          ),
        ),
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
              const Icon(Icons.error_outline, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              const Text(
                'Unable to load timetables right now.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Please try again.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
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
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
                  itemCount: _filteredTimetables.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _filteredTimetables[index];
                    return _TimetableCard(item: item, onTap: () => _openTimetable(item));
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'View uploaded timetables',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 6),
          Text(
            _selectedLevel == null
                ? 'Choose a level, programme, and group to view the timetable for that class.'
                : _selectedProgramme == null
                    ? 'Select a programme for $_selectedLevel.'
                    : _selectedGroup == null
                        ? 'Select a group for $_selectedProgramme.'
                        : 'Showing timetables for $_selectedLevel • $_selectedProgramme • $_selectedGroup',
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_levels.isNotEmpty) ...[
          const Text('Level', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _levels.map((level) {
              final selected = _selectedLevel == level;
              return ChoiceChip(
                label: Text(level),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _selectedLevel = level;
                    _selectedProgramme = null;
                    _selectedGroup = null;
                    _rebuildFilterOptions();
                  });
                },
                selectedColor: Colors.white,
                backgroundColor: Colors.white10,
                labelStyle: TextStyle(
                  color: selected ? Colors.black87 : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (_selectedLevel != null && _programmes.isNotEmpty) ...[
          const Text('Programme', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _programmes.map((programme) {
              final selected = _selectedProgramme == programme;
              return ChoiceChip(
                label: Text(programme),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _selectedProgramme = programme;
                    _selectedGroup = null;
                    _rebuildFilterOptions();
                  });
                },
                selectedColor: Colors.white,
                backgroundColor: Colors.white10,
                labelStyle: TextStyle(
                  color: selected ? Colors.black87 : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (_selectedProgramme != null && _groups.isNotEmpty) ...[
          const Text('Group / Class', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _groups.map((group) {
              final selected = _selectedGroup == group;
              return ChoiceChip(
                label: Text(group),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _selectedGroup = group;
                  });
                },
                selectedColor: Colors.white,
                backgroundColor: Colors.white10,
                labelStyle: TextStyle(
                  color: selected ? Colors.black87 : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description_outlined, size: 48, color: Colors.white),
            const SizedBox(height: 12),
            const Text(
              'No timetable found for this selection.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try another level, programme, or group.',
              style: TextStyle(color: Colors.white70),
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
        baseColor: Colors.white24,
        highlightColor: Colors.white38,
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
  const _TimetableCard({required this.item, required this.onTap});

  final _TimetableItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF00ACC1);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.25), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87),
                  ),
                ),
                const Icon(Icons.open_in_new, size: 18, color: Color(0xFF2962FF)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(item.level, accent),
                _pill(item.programme, const Color(0xFF43A047)),
                _pill(item.groupName, const Color(0xFFFF8F00)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 18, color: Colors.black54),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tap to view the timetable document',
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
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
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }
}

class _TimetableItem {
  const _TimetableItem({
    required this.id,
    required this.level,
    required this.programme,
    required this.groupName,
    required this.title,
    required this.url,
  });

  final String id;
  final String level;
  final String programme;
  final String groupName;
  final String title;
  final String url;

  factory _TimetableItem.fromRow(Map<String, dynamic> row) {
    return _TimetableItem(
      id: (row['id'] ?? '').toString(),
      level: (row['level'] ?? '').toString().trim(),
      programme: (row['programme'] ?? '').toString().trim(),
      groupName: (row['group_name'] ?? '').toString().trim(),
      title: (row['title'] ?? '').toString().trim(),
      url: (row['url'] ?? '').toString().trim(),
    );
  }
}
