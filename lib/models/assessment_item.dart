import 'package:flutter/material.dart';

class AssessmentItem {
  AssessmentItem({
    required this.title,
    required this.date,
    required this.venue,
    required this.type,
    required this.color,
    required this.icon,
  });

  final String title;
  final String date;
  final String venue;
  final String type;
  final Color color;
  final IconData icon;

  factory AssessmentItem.fromQuizRow(Map<String, dynamic> row) {
    final title = (row['title'] ?? 'Untitled quiz').toString();
    final quizDate = row['quiz_date']?.toString();
    final formattedDate = _formatDate(quizDate);

    return AssessmentItem(
      title: title,
      date: formattedDate ?? 'Date to be announced',
      venue: 'Online / Campus',
      type: 'Quiz',
      color: const Color(0xFF1565C0),
      icon: Icons.quiz_rounded,
    );
  }

  factory AssessmentItem.fromSubmissionRow(Map<String, dynamic> row) {
    final subject = (row['subject'] ?? 'Assessment').toString();
    final title = (row['title'] ?? 'Assessment').toString();
    final dueDate = row['due_date']?.toString();
    final formattedDate = _formatDate(dueDate);

    return AssessmentItem(
      title: '$subject — $title',
      date: formattedDate ?? 'Due date not set',
      venue: 'Submitted in-app',
      type: 'Assignment',
      color: const Color(0xFF8E24AA),
      icon: Icons.assignment_rounded,
    );
  }

  static String? _formatDate(String? rawDate) {
    if (rawDate == null || rawDate.trim().isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) {
      return rawDate;
    }

    return '${_monthName(parsed.month)} ${parsed.day}, ${parsed.year} • ${_formatTime(parsed)}';
  }

  static String _monthName(int month) {
    const months = <int, String>{
      1: 'Jan',
      2: 'Feb',
      3: 'Mar',
      4: 'Apr',
      5: 'May',
      6: 'Jun',
      7: 'Jul',
      8: 'Aug',
      9: 'Sep',
      10: 'Oct',
      11: 'Nov',
      12: 'Dec',
    };
    return months[month] ?? 'Month';
  }

  static String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final suffix = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }
}
