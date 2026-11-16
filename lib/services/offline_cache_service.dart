import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'offline_data_adapter.dart';

/// Small, user-scoped JSON cache for read-only screen data.
///
/// It is intentionally bounded and keeps record metadata available offline.
class OfflineCacheService {
  OfflineCacheService._();

  static String userKey(String namespace) {
    final userId = OfflineData.instance.client.auth.currentUser?.id ?? 'guest';
    return 'og_vibes_cache_v3_${namespace}_$userId';
  }

  static Future<List<Map<String, dynamic>>> readList(String namespace) async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(
        userKey(namespace),
      );
      if (value == null || value.isEmpty) return const [];
      final decoded = jsonDecode(value);
      final records = decoded is Map ? decoded['records'] : decoded;
      if (records is! List) return const [];
      return records
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> writeList(
    String namespace,
    Iterable<Map<String, dynamic>> records, {
    int maxRecords = 120,
  }) async {
    try {
      final bounded = records.take(maxRecords).toList(growable: false);
      await (await SharedPreferences.getInstance()).setString(
        userKey(namespace),
        jsonEncode(<String, dynamic>{
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'records': bounded,
        }),
      );
    } catch (_) {
      // A cache failure must never block the live feature.
    }
  }
}
