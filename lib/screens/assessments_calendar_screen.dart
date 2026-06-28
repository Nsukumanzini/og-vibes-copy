import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/models/assessment_item.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class AssessmentsCalendarScreen extends StatefulWidget {
  const AssessmentsCalendarScreen({super.key});

  @override
  State<AssessmentsCalendarScreen> createState() =>
      _AssessmentsCalendarScreenState();
}

class _AssessmentsCalendarScreenState extends State<AssessmentsCalendarScreen> {
  final List<AssessmentItem> _items = <AssessmentItem>[];
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription<List<Map<String, dynamic>>>? _assessmentSubscription;

  @override
  void initState() {
    super.initState();
    _loadAssessments();
    _listenForChanges();
  }

  @override
  void dispose() {
    _assessmentSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAssessments() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'You must be signed in to view your assessments.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final quizzes = await Supabase.instance.client
          .from('quizzes')
          .select('id, title, description, lecturer_name, quiz_date, duration_minutes')
          .eq('published', true)
          .order('quiz_date', ascending: true);

      final submissions = await Supabase.instance.client
          .from('assignment_submissions')
          .select('id, title, subject, due_date, status')
          .eq('user_id', user.id)
          .order('due_date', ascending: true);

      final quizItems = (quizzes as List<dynamic>? ?? [])
          .map((row) => AssessmentItem.fromQuizRow(Map<String, dynamic>.from(row as Map<String, dynamic>)))
          .toList();

      final submissionItems = (submissions as List<dynamic>? ?? [])
          .map((row) => AssessmentItem.fromSubmissionRow(Map<String, dynamic>.from(row as Map<String, dynamic>)))
          .toList();

      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll([...quizItems, ...submissionItems]);
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

  void _listenForChanges() {
    _assessmentSubscription = Supabase.instance.client
        .from('quizzes')
        .stream(primaryKey: ['id'])
        .listen((_) {
          if (!mounted) return;
          unawaited(_loadAssessments());
        }, onError: (error) {
          if (!mounted) return;
          setState(() {
            _errorMessage = error.toString();
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Assessments Calendar')),
      body: _isLoading && _items.isEmpty
          ? _buildLoadingState()
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text(
                'Unable to load your assessments right now.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadAssessments,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text('No assessments are available yet.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'My Upcoming Assessments',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: Color(0xFF102027),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
            itemCount: _items.length,
            itemBuilder: (BuildContext context, int index) {
              return _TimelineCard(
                item: _items[index],
                isLast: index == _items.length - 1,
                onReminderTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Calendar reminder saved!')),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 240,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: 3,
                separatorBuilder: (BuildContext context, int index) {
                  return const SizedBox(height: 10);
                },
                itemBuilder: (BuildContext context, int index) {
                  return Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.item,
    required this.onReminderTap,
    required this.isLast,
  });

  final AssessmentItem item;
  final VoidCallback onReminderTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 32,
          child: Column(
            children: <Widget>[
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 150,
                  color: const Color(0xFFD9E2EC),
                ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: item.color.withValues(alpha: 0.5),
                width: 1.4,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.icon, color: item.color, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          color: Color(0xFF102027),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onReminderTap,
                      icon: const Icon(Icons.notifications_none_rounded),
                      tooltip: 'Set Reminder',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.date,
                  style: const TextStyle(
                    color: Color(0xFF455A64),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Venue: ${item.venue}',
                  style: const TextStyle(
                    color: Color(0xFF607D8B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.type,
                    style: TextStyle(
                      color: item.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

