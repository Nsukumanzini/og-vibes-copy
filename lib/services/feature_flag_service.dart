import 'package:supabase_flutter/supabase_flutter.dart';

class FeatureAvailability {
  const FeatureAvailability({
    required this.enabled,
    required this.message,
  });

  final bool enabled;
  final String message;
}

class FeatureFlagService {
  FeatureFlagService._();

  static final Map<String, ({FeatureAvailability value, DateTime fetchedAt})>
  _cache = {};
  static const _cacheLifetime = Duration(seconds: 30);

  static Future<FeatureAvailability> availability(
    String featureKey, {
    SupabaseClient? client,
    bool forceRefresh = false,
  }) async {
    final cached = _cache[featureKey];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheLifetime) {
      return cached.value;
    }

    try {
      final row = await (client ?? Supabase.instance.client)
          .from('app_feature_flags')
          .select('enabled,disabled_message')
          .eq('feature_key', featureKey)
          .maybeSingle();
      final value = FeatureAvailability(
        enabled: row?['enabled'] != false,
        message:
            row?['disabled_message']?.toString().trim().isNotEmpty == true
            ? row!['disabled_message'].toString().trim()
            : 'This feature is temporarily unavailable.',
      );
      _cache[featureKey] = (value: value, fetchedAt: DateTime.now());
      return value;
    } catch (_) {
      // Keep existing functionality available if the control plane itself is
      // temporarily unreachable. Server-side checks still protect calls.
      return const FeatureAvailability(
        enabled: true,
        message: 'This feature is temporarily unavailable.',
      );
    }
  }

  static void clearCache() => _cache.clear();
}
