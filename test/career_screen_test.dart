import 'package:flutter_test/flutter_test.dart';
import 'package:og_vibes_student/screens/career_screen.dart';

void main() {
  group('career mapping', () {
    test('maps a Supabase opportunity row into a career card item', () {
      final row = {
        'title': 'Software Development Intern',
        'description': 'Join the engineering team',
        'category': 'internship',
        'company': 'Tech Corp',
        'duration': '6 months',
        'type': 'Full-time',
        'salary': 'R15,000',
        'created_at': '2026-06-28T10:00:00.000Z',
      };

      final item = mapCareerRowToItem(row);

      expect(item['title'], 'Software Development Intern');
      expect(item['category'], 'internship');
      expect(item['company'], 'Tech Corp');
    });
  });
}
