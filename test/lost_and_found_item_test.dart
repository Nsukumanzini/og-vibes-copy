import 'package:flutter_test/flutter_test.dart';
import 'package:og_vibes_student/models/lost_and_found_item.dart';

void main() {
  group('Lost and found item mapping', () {
    test('maps a Supabase row into a UI item', () {
      final item = LostAndFoundItem.fromRow({
        'id': 'item-1',
        'title': 'Student ID Card',
        'found_at': 'Library',
        'collect_at': 'Admin Desk',
        'requirements': 'Bring ID copy',
        'image_url': 'https://example.com/id.jpg',
        'status': 'active',
      });

      expect(item.title, 'Student ID Card');
      expect(item.foundAt, 'Library');
      expect(item.collectAt, 'Admin Desk');
      expect(item.imageUrl, 'https://example.com/id.jpg');
    });
  });
}
