import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_persistence_service.dart';
import 'push_notification_service.dart';

class AuthService {
  AuthService();

  Future<void> signOut() async {
    await AuthPersistenceService.clear();
    try {
      await PushNotificationService.unregisterCurrentDevice();
      await Supabase.instance.client.auth.signOut();
    } on AssertionError catch (_) {
      // If Supabase isn't initialized, treat signOut as a no-op.
      return;
    }
  }
}
