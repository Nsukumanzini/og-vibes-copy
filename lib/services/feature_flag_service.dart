class FeatureAvailability {
  const FeatureAvailability({required this.enabled, required this.message});
  final bool enabled;
  final String message;
}

/// Features remain visible in the offline build; no remote flag is queried.
class FeatureFlagService {
  FeatureFlagService._();

  static Future<FeatureAvailability> availability(
    String featureKey, {
    Object? client,
    bool forceRefresh = false,
  }) async =>
      const FeatureAvailability(
        enabled: true,
        message: 'This feature is temporarily unavailable.',
      );

  static void clearCache() {}
}
