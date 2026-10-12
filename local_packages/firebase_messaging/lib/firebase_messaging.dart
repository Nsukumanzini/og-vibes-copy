library firebase_messaging;

import 'dart:async';

class RemoteMessage {
  final Map<String, dynamic> data;
  RemoteMessage({required this.data});
}

class FirebaseMessaging {
  FirebaseMessaging._();
  static final FirebaseMessaging instance = FirebaseMessaging._();

  static Future<void> onBackgroundMessage(Future<void> Function(RemoteMessage) handler) async {}

  Stream<RemoteMessage> get onMessage => const Stream<RemoteMessage>.empty();
  Stream<RemoteMessage> get onMessageOpenedApp => const Stream<RemoteMessage>.empty();
  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  Future<String?> getToken({String? vapidKey}) async => null;
  Future<NotificationSettings> requestPermission({
    bool alert = false,
    bool badge = false,
    bool sound = false,
    bool provisional = false,
  }) async => NotificationSettings();
  Future<RemoteMessage?> getInitialMessage() async => null;
}

class NotificationSettings {
  final AuthorizationStatus authorizationStatus = AuthorizationStatus.notDetermined;
}

enum AuthorizationStatus {
  notDetermined,
  authorized,
  denied,
}
