import 'package:flutter_test/flutter_test.dart';
import 'package:og_vibes_student/screens/market_screen.dart';

void main() {
  group('market item mapping', () {
    test('maps a Supabase product row into a marketplace card item', () {
      final row = {
        'id': 'abc-123',
        'title': 'N4 Mathematics Textbook',
        'price': 200.0,
        'category': 'Textbooks',
        'description': 'Good condition',
        'created_at': '2026-06-28T10:00:00.000Z',
        'profiles': {
          'name': 'Thandi',
          'surname': 'Molefe',
        },
      };

      final item = mapProductRowToMarketItem(row);

      expect(item['title'], 'N4 Mathematics Textbook');
      expect(item['price'], 'R 200.00');
      expect(item['seller'], 'Thandi Molefe');
      expect(item['category'], 'Textbooks');
      expect(item['time'], isA<String>());
    });
  });
}
