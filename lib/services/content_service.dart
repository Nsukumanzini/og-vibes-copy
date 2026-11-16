import 'offline_cache_service.dart';

/// Loads content already saved on this device, with the supplied UI fallback.
class ContentService {
  ContentService._();

  static Future<List<Map<String, dynamic>>> loadSection(
    String section, {
    required List<Map<String, dynamic>> fallback,
  }) async {
    final cached = await OfflineCacheService.readList('content_$section');
    return cached.isNotEmpty ? cached : fallback;
  }
}
