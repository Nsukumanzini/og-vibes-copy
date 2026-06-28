import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class IcassCheckerScreen extends StatefulWidget {
  const IcassCheckerScreen({super.key});

  @override
  State<IcassCheckerScreen> createState() => _IcassCheckerScreenState();
}

class _IcassCheckerScreenState extends State<IcassCheckerScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  final List<IcassItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadIcass();
  }

  Future<void> _loadIcass() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Please sign in to view your ICASS marks.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await Supabase.instance.client
          .from('icass_marks')
          .select('id, subject_name, lecturer_name, component_name, component_score, student_id, created_at')
          .eq('student_id', user.id)
          .order('created_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(response as List<dynamic>? ?? []);
      final grouped = <String, List<IcassItem>>{};
      for (final row in rows) {
        final item = IcassItem.fromSupabaseRow(row);
        grouped.putIfAbsent(item.subjectName, () => []).add(item);
      }

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(grouped.entries.expand((entry) => entry.value).toList());
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

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('My ICASS Marks')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBanner(),
            const SizedBox(height: 12),
            Expanded(child: _buildSubjectsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0D47A1), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.08),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'My ICASS Overview',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Your marks are loaded from the college system and grouped by subject.',
            style: TextStyle(
              color: Color(0xFFE3F2FD),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(_errorMessage!),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadIcass, child: const Text('Retry')),
          ],
        ),
      );
    }

    final grouped = <String, List<IcassItem>>{};
    for (final item in _items) {
      grouped.putIfAbsent(item.subjectName, () => []).add(item);
    }

    final subjects = grouped.entries.toList();
    if (subjects.isEmpty) {
      return const Center(child: Text('No ICASS records available yet.'));
    }

    return ListView.separated(
      itemCount: subjects.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = subjects[index];
        final subjectName = entry.key;
        final items = entry.value;
        final marks = <String, double?>{};
        for (final item in items) {
          marks[item.componentName] = item.componentScore;
        }
        final icassPercent = _computeIcassPercentage(marks);
        final lecturerName = items.first.lecturerName;

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subjectName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text('Lecturer: $lecturerName', style: const TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${icassPercent.toStringAsFixed(1)}%',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1565C0)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _openSubjectDetails(context, subjectName, lecturerName, marks),
                    child: const Text('View details'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _computeIcassPercentage(Map<String, double?> marks) {
    final values = marks.values.where((v) => v != null).map((v) => v!).toList();
    if (values.isEmpty) return 0.0;
    final sum = values.reduce((a, b) => a + b);
    return sum / values.length;
  }

  void _openSubjectDetails(BuildContext context, String subjectName, String lecturerName, Map<String, double?> marks) {
    final icassPercent = _computeIcassPercentage(marks);
    final requiredExam = ((40 - (0.4 * icassPercent)) / 0.6).clamp(0, 100);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) {
      return Scaffold(
        appBar: AppBar(title: Text(subjectName)),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lecturer: $lecturerName', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text('ICASS Percentage: ${icassPercent.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text('To qualify to sit the final exam you must have 40% overall. Based on current ICASS you would need at least ${requiredExam.toStringAsFixed(1)}% in the exam.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: marks.keys.map((component) {
                    final val = marks[component];
                    return ListTile(
                      title: Text(component),
                      subtitle: Text(val == null ? 'No marks yet' : '${val.toStringAsFixed(1)}%'),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      );
    }));
  }
}

class IcassItem {
  IcassItem({
    required this.id,
    required this.studentId,
    required this.subjectName,
    required this.lecturerName,
    required this.componentName,
    required this.componentScore,
  });

  final String id;
  final String studentId;
  final String subjectName;
  final String lecturerName;
  final String componentName;
  final double? componentScore;

  factory IcassItem.fromSupabaseRow(Map<String, dynamic> row) {
    return IcassItem(
      id: (row['id'] ?? '').toString(),
      studentId: (row['student_id'] ?? '').toString(),
      subjectName: (row['subject_name'] ?? 'Subject').toString(),
      lecturerName: (row['lecturer_name'] ?? 'Lecturer').toString(),
      componentName: (row['component_name'] ?? 'Component').toString(),
      componentScore: row['component_score'] is num ? (row['component_score'] as num).toDouble() : null,
    );
  }
}

