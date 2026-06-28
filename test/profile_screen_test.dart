import 'package:flutter_test/flutter_test.dart';
import 'package:og_vibes_student/screens/profile_screen.dart';

void main() {
  group('profile mapping', () {
    test('maps a Supabase profile row into the UI profile model', () {
      final row = {
        'id': 'user-1',
        'name': 'Thandi',
        'surname': 'Molefe',
        'department': 'Information Technology',
        'campus': 'Ermelo Campus',
        'level': 'Level 4',
        'photo_url': 'https://example.com/avatar.png',
      };

      final profile = mapProfileRowToUiProfile(row);

      expect(profile['fullName'], 'Thandi Molefe');
      expect(profile['department'], 'Information Technology');
      expect(profile['campus'], 'Ermelo Campus');
      expect(profile['level'], 'Level 4');
    });
  });
}
