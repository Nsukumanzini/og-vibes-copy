// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> showWebIncomingCallNotification({
  required String callId,
  required String callerName,
  required bool isVideo,
  bool isGroupCall = false,
}) async {
  if (!html.Notification.supported ||
      html.Notification.permission != 'granted') {
    return;
  }

  final notification = html.Notification(
    isGroupCall
        ? (isVideo ? 'Incoming group video call' : 'Incoming group voice call')
        : (isVideo ? 'Incoming video call' : 'Incoming voice call'),
    body: callerName,
    icon: '/icons/Icon-192.png',
    tag: 'og-vibes-call-$callId',
  );
  notification.onClick.first.then((_) {
    notification.close();
    final parameter = isGroupCall ? 'groupCallId' : 'callId';
    html.window.location.href =
        '/?$parameter=${Uri.encodeQueryComponent(callId)}&callAction=open';
  });
}

Future<void> showWebStudentNotification({
  required String title,
  required String body,
  required String route,
  String? entityId,
  String? notificationId,
}) async {
  if (!html.Notification.supported ||
      html.Notification.permission != 'granted') {
    return;
  }
  final notification = html.Notification(
    title,
    body: body,
    icon: '/icons/Icon-192.png',
    tag: 'og-vibes-${notificationId ?? route}',
  );
  notification.onClick.first.then((_) {
    notification.close();
    final parameters = <String, String>{'notificationRoute': route};
    if (entityId?.isNotEmpty == true) {
      parameters['notificationEntity'] = entityId!;
    }
    html.window.location.href = '/?${Uri(queryParameters: parameters).query}';
  });
}
