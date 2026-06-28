import 'package:flutter_test/flutter_test.dart';
import 'package:og_vibes_student/screens/quiz_screen.dart';

void main() {
  group('quiz data mapping', () {
    test('maps Supabase quiz rows into quiz items', () {
      final quiz = QuizItem.fromSupabaseRow({
        'id': 'quiz-1',
        'title': 'Revision Quiz',
        'description': 'A short quiz',
        'lecturer_name': 'Dr. Smith',
        'reward': 'R50 airtime',
        'duration_minutes': 10,
        'passing_score': 50,
        'quiz_date': '2026-06-27T10:00:00+00:00',
      });

      expect(quiz.id, 'quiz-1');
      expect(quiz.title, 'Revision Quiz');
      expect(quiz.lecturerName, 'Dr. Smith');
      expect(quiz.reward, 'R50 airtime');
      expect(quiz.durationMinutes, 10);
      expect(quiz.passingScore, 50);
    });

    test('builds question options from Supabase fields', () {
      final question = QuizQuestion.fromSupabaseRow({
        'id': 'q1',
        'question_text': 'What is 2 + 2?',
        'option_a': '3',
        'option_b': '4',
        'option_c': '5',
        'option_d': '6',
        'correct_option': 1,
        'points': 2,
        'position': 1,
      });

      expect(question.text, 'What is 2 + 2?');
      expect(question.options, ['3', '4', '5', '6']);
      expect(question.correctOption, 1);
      expect(question.points, 2);
    });
  });
}
