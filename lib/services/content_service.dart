import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads CMS-style feature content from Supabase while retaining a local
/// fallback so the app remains useful during an outage or first-run setup.
class ContentService {
  ContentService._();

  static Future<List<Map<String, dynamic>>> loadSection(
    String section, {
    required List<Map<String, dynamic>> fallback,
  }) async {
    try {
      final response = await Supabase.instance.client
          .from('app_content')
          .select('id, slug, title, subtitle, data')
          .eq('section', section)
          .eq('is_active', true)
          .order('sort_order');

      final rows = List<Map<String, dynamic>>.from(response);
      if (rows.isEmpty) return fallback;

      return rows.map((row) {
        final payload = Map<String, dynamic>.from(
          row['data'] as Map<String, dynamic>? ?? const {},
        );
        return <String, dynamic>{
          'id': row['id'],
          'slug': row['slug'],
          'title': row['title'],
          'subtitle': row['subtitle'],
          ...payload,
        };
      }).toList();
    } catch (_) {
      return fallback;
    }
  }
}
