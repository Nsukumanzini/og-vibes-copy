import 'package:shared_preferences/shared_preferences.dart';

/// Stores only the local routing decision needed for offline startup.
/// Supabase remains the source of truth for authentication and permissions.
class AuthPersistenceService {
  static const _signedInBeforeKey = 'og_vibes_signed_in_before';

  static Future<bool> hasSignedInBefore() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_signedInBeforeKey) ?? false;
  }

  static Future<void> rememberSignedInUser() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_signedInBeforeKey, true);
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_signedInBeforeKey);
  }
}
