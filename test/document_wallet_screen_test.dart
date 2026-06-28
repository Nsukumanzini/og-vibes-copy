import 'package:flutter_test/flutter_test.dart';
import 'package:og_vibes_student/screens/document_wallet_screen.dart';

void main() {
  group('document wallet mapping', () {
    test('maps a Supabase document row into a wallet document model', () {
      final row = {
        'id': 'doc-1',
        'title': 'Proof of registration',
        'description': 'My student proof',
        'file_name': 'proof.pdf',
        'file_url': 'https://example.com/proof.pdf',
        'file_type': 'pdf',
        'uploaded_at': '2026-06-28T10:00:00.000Z',
      };

      final document = mapDocumentRowToWalletDocument(row);

      expect(document.title, 'Proof of registration');
      expect(document.fileName, 'proof.pdf');
      expect(document.fileExtension, 'pdf');
    });
  });
}
