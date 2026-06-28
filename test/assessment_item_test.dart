import 'package:flutter_test/flutter_test.dart';
import 'package:og_vibes_student/models/assessment_item.dart';

void main() {
  group('AssessmentItem mapping', () {
    test('creates a quiz item from a Supabase quiz row', () {
      final item = AssessmentItem.fromQuizRow({
        'id': 'quiz-1',
        'title': 'Mathematics N4 Quiz',
        'description': 'Covers algebra and equations',
        'lecturer_name': 'Dr. Mokoena',
        'quiz_date': '2026-04-18T09:00:00.000Z',
        'duration_minutes': 30,
      });

      expect(item.title, 'Mathematics N4 Quiz');
      expect(item.type, 'Quiz');
      expect(item.venue, 'Online / Campus');
      expect(item.color.value, 0xFF1565C0);
    });

    test('creates an assignment item from a Supabase submission row', () {
      final item = AssessmentItem.fromSubmissionRow({
        'id': 'sub-1',
        'title': 'Assignment 2',
        'subject': 'Entrepreneurship N4',
        'due_date': '2026-04-25T23:59:00.000Z',
        'status': 'submitted',
      });

      expect(item.title, 'Entrepreneurship N4 — Assignment 2');
      expect(item.type, 'Assignment');
      expect(item.venue, 'Submitted in-app');
      expect(item.color.value, 0xFF8E24AA);
    });
  });
}
