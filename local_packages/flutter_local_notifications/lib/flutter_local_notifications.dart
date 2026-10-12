library flutter_local_notifications;

import 'dart:async';

class FlutterLocalNotificationsPlugin {
  Future<bool?> initialize(InitializationSettings settings, {Function(NotificationResponse)? onDidReceiveNotificationResponse, Function(NotificationResponse)? onDidReceiveBackgroundNotificationResponse}) async => true;
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async => null;
  Future<void> show(int id, String? title, String? body, NotificationDetails? details, {String? payload}) async {}
  Future<void> cancel(int id) async {}
}

class InitializationSettings {
  const InitializationSettings({required AndroidInitializationSettings android});
}

class AndroidInitializationSettings {
  final String defaultIcon;
  const AndroidInitializationSettings(this.defaultIcon);
}

class NotificationResponse {
  final String? payload;
  final String actionId;
  NotificationResponse({this.payload, this.actionId = ''});
}

class NotificationAppLaunchDetails {
  final bool didNotificationLaunchApp;
  final NotificationResponse? notificationResponse;
  NotificationAppLaunchDetails({required this.didNotificationLaunchApp, this.notificationResponse});
}

class AndroidNotificationChannel {
  final String id;
  final String name;
  final String? description;
  final Importance importance;
  final bool playSound;
  final bool enableVibration;
  const AndroidNotificationChannel(this.id, this.name, {this.description, this.importance = Importance.defaultImportance, this.playSound = false, this.enableVibration = false});
}

enum Importance {
  defaultImportance,
  max,
}

class AndroidFlutterLocalNotificationsPlugin {}

class NotificationDetails {
  final AndroidNotificationDetails? android;
  const NotificationDetails({this.android});
}

class AndroidNotificationDetails {
  final String channelId;
  final String channelName;
  final String channelDescription;
  final Importance importance;
  final Priority priority;
  final AndroidNotificationCategory category;
  final NotificationVisibility visibility;
  final bool playSound;
  final bool enableVibration;
  final bool ongoing;
  final bool autoCancel;
  final int timeoutAfter;
  final List<AndroidNotificationAction>? actions;
  const AndroidNotificationDetails(
    this.channelId,
    this.channelName, {
    required this.channelDescription,
    required this.importance,
    required this.priority,
    required this.category,
    required this.visibility,
    required this.playSound,
    required this.enableVibration,
    required this.ongoing,
    required this.autoCancel,
    required this.timeoutAfter,
    this.actions,
  });
}

enum Priority { max }

enum AndroidNotificationCategory { call }

enum NotificationVisibility { public }

class AndroidNotificationAction {
  final String actionId;
  final String title;
  const AndroidNotificationAction(this.actionId, this.title);
}
