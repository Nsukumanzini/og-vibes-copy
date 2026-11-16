import 'offline_data_adapter.dart';

import 'auth_persistence_service.dart';
import 'push_notification_service.dart';

class AuthService {
  AuthService();

  Future<void> signOut() async {
    await AuthPersistenceService.clear();
    try {
      await PushNotificationService.unregisterCurrentDevice();
      await OfflineData.instance.client.auth.signOut();
    } on AssertionError catch (_) {
      // If No local session is active, treat signOut as a no-op.
      return;
    }
  }
}
