Future<void> showWebIncomingCallNotification({
  required String callId,
  required String callerName,
  required bool isVideo,
  bool isGroupCall = false,
}) async {}

Future<void> showWebStudentNotification({
  required String title,
  required String body,
  required String route,
  String? entityId,
  String? notificationId,
}) async {}
