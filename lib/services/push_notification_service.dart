import 'dart:async';

class CallNotificationAction {
  const CallNotificationAction({
    required this.callId,
    required this.action,
    this.callerName,
    this.callType,
    this.isGroupCall = false,
  });

  final String callId;
  final String action;
  final String? callerName;
  final String? callType;
  final bool isGroupCall;
}

class StudentNotificationAction {
  const StudentNotificationAction({required this.route, this.entityId, this.title});
  final String route;
  final String? entityId;
  final String? title;
}

class PushDeviceRegistration {
  const PushDeviceRegistration({
    required this.id,
    required this.platform,
    required this.lastSeenAt,
    required this.current,
  });

  final String id;
  final String platform;
  final DateTime? lastSeenAt;
  final bool current;
}

enum PushEnrollmentStatus { signedOut, unsupported, needsPermission, blocked, enabled, error }

/// Push is disabled in the offline build. These no-op methods keep the
/// existing settings and notification widgets available without a service.
class PushNotificationService {
  PushNotificationService._();

  static final StreamController<CallNotificationAction> _actions =
      StreamController<CallNotificationAction>.broadcast();
  static final StreamController<String> _moduleInvitations =
      StreamController<String>.broadcast();
  static final StreamController<StudentNotificationAction> _studentNotifications =
      StreamController<StudentNotificationAction>.broadcast();

  static Stream<CallNotificationAction> get actions => _actions.stream;
  static Stream<String> get moduleInvitations => _moduleInvitations.stream;
  static Stream<StudentNotificationAction> get studentNotifications =>
      _studentNotifications.stream;

  static Future<void> initialise() async {}
  static Future<PushEnrollmentStatus> enrollmentStatus() async =>
      PushEnrollmentStatus.unsupported;
  static Future<bool> requestAndRegisterCurrentDevice() async => false;
  static Future<bool> registerCurrentDevice() async => false;
  static Future<void> unregisterCurrentDevice() async {}
  static Future<List<PushDeviceRegistration>> activeDevices() async => const [];
  static Future<void> removeDevice(String id) async {}
  static Future<void> sendIncomingCall(String callId) async {}
  static Future<void> sendIncomingGroupCall(String callId) async {}
  static Future<void> cancelIncomingCallNotification(String callId) async {}
  static Future<void> showIncomingCall(Map<String, dynamic> data) async {}
  static Future<void> showModuleInvitation(Map<String, dynamic> data) async {}
  static Future<void> showStudentNotification(Map<String, dynamic> data) async {}
  static Future<void> showSosAlert(Map<String, dynamic> data) async {}
}
