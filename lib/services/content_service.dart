import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_cache_service.dart';

/// Reads CMS-style feature content from Supabase while retaining a local
/// fallback so the app remains useful during an outage or first-run setup.
class ContentService {
  ContentService._();

  static Future<List<Map<String, dynamic>>> loadSection(
    String section, {
    required List<Map<String, dynamic>> fallback,
  }) async {
    final cacheKey = 'content_$section';
    final cached = await OfflineCacheService.readList(cacheKey);
    try {
      final response = await Supabase.instance.client
          .from('app_content')
          .select('id, slug, title, subtitle, data')
          .eq('section', section)
          .eq('is_active', true)
          .order('sort_order');

      final rows = List<Map<String, dynamic>>.from(response);
      if (rows.isEmpty) return cached.isNotEmpty ? cached : fallback;

      final content = rows.map((row) {
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
      await OfflineCacheService.writeList(cacheKey, content, maxRecords: 80);
      return content;
    } catch (_) {
      return cached.isNotEmpty ? cached : fallback;
    }
  }
}
