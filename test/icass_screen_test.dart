import 'package:flutter_test/flutter_test.dart';
import 'package:og_vibes_student/screens/icass_checker_screen.dart';

void main() {
  group('ICASS models', () {
    test('maps Supabase ICASS rows into view models', () {
      final item = IcassItem.fromSupabaseRow({
        'id': '1',
        'subject_name': 'Mathematics N4',
        'lecturer_name': 'Dr. Smith',
        'component_name': 'Test 1',
        'component_score': 72.0,
      });

      expect(item.subjectName, 'Mathematics N4');
      expect(item.lecturerName, 'Dr. Smith');
      expect(item.componentName, 'Test 1');
      expect(item.componentScore, 72.0);
    });
  });
}
