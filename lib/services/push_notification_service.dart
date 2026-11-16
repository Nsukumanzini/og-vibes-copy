import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../firebase_options.dart';
import 'web_call_notification.dart';

// Android notification-channel sound settings are immutable after creation.
// A versioned ID upgrades existing installs from a short alert to ringtone use.
const _channelId = 'og_vibes_calls_v2';
const _sosChannelId = 'og_vibes_sos';
const _academicChannelId = 'og_vibes_academic';
const _messagesChannelId = 'og_vibes_messages';
const _campusChannelId = 'og_vibes_campus';
const _activityChannelId = 'og_vibes_activity';
const _pendingActionKey = 'pending_call_notification_action';
const _deviceIdKey = 'og_vibes_push_device_id';
const _acceptAction = 'accept_call';
const _declineAction = 'decline_call';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  if (message.data['event'] == 'sos_alert') {
    await PushNotificationService.showSosAlert(message.data);
  } else if (message.data['event'] == 'module_invitation') {
    await PushNotificationService.showModuleInvitation(message.data);
  } else if (message.data['event'] == 'student_notification') {
    await PushNotificationService.showStudentNotification(message.data);
  } else {
    await PushNotificationService.showIncomingCall(message.data);
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_persistNotificationResponse(response));
}

Future<void> _persistNotificationResponse(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  final decoded = Map<String, dynamic>.from(jsonDecode(payload) as Map);
  decoded['action'] = response.actionId == _declineAction
      ? 'decline'
      : response.actionId == _acceptAction
      ? 'accept'
      : 'open';
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_pendingActionKey, jsonEncode(decoded));
}

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

  factory CallNotificationAction.fromMap(Map<String, dynamic> data) {
    return CallNotificationAction(
      callId: (data['call_id'] ?? data['callId'] ?? '').toString(),
      action: (data['action'] ?? 'open').toString(),
      callerName: data['caller_name']?.toString(),
      callType: data['call_type']?.toString(),
      isGroupCall: data['group_call'] == true || data['group_call'] == 'true',
    );
  }
}

class StudentNotificationAction {
  const StudentNotificationAction({
    required this.route,
    this.entityId,
    this.title,
  });

  final String route;
  final String? entityId;
  final String? title;

  factory StudentNotificationAction.fromMap(Map<String, dynamic> data) {
    return StudentNotificationAction(
      route: data['route']?.toString() ?? '',
      entityId: data['entity_id']?.toString(),
      title: data['title']?.toString(),
    );
  }
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

  factory PushDeviceRegistration.fromMap(Map<String, dynamic> row) {
    return PushDeviceRegistration(
      id: row['id']?.toString() ?? '',
      platform: row['platform']?.toString() ?? 'device',
      lastSeenAt: DateTime.tryParse(row['last_seen_at']?.toString() ?? ''),
      current: row['current'] == true,
    );
  }
}

enum PushEnrollmentStatus {
  signedOut,
  unsupported,
  needsPermission,
  blocked,
  enabled,
  error,
}

class PushNotificationService {
  PushNotificationService._();

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final StreamController<CallNotificationAction> _actions =
      StreamController<CallNotificationAction>.broadcast();
  static final StreamController<String> _moduleInvitations =
      StreamController<String>.broadcast();
  static final StreamController<StudentNotificationAction>
  _studentNotifications =
      StreamController<StudentNotificationAction>.broadcast();
  static StreamSubscription<String>? _tokenRefresh;
  static StreamSubscription<RemoteMessage>? _foregroundMessages;
  static StreamSubscription<RemoteMessage>? _openedMessages;
  static bool _initialised = false;
  static bool _localNotificationsReady = false;

  static Stream<CallNotificationAction> get actions => _actions.stream;
  static Stream<String> get moduleInvitations => _moduleInvitations.stream;
  static Stream<StudentNotificationAction> get studentNotifications =>
      _studentNotifications.stream;

  static Future<void> initialise() async {
    if (_initialised) return;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _ensureLocalNotificationsReady();

    _foregroundMessages = FirebaseMessaging.onMessage.listen((message) {
      if (message.data['event'] == 'incoming_call') {
        unawaited(showIncomingCall(message.data));
      } else if (message.data['event'] == 'sos_alert') {
        unawaited(showSosAlert(message.data));
      } else if (message.data['event'] == 'module_invitation') {
        unawaited(showModuleInvitation(message.data));
      } else if (message.data['event'] == 'student_notification') {
        unawaited(showStudentNotification(message.data));
      }
    });
    _openedMessages = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _emitNotification(message.data, 'open');
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _emitNotification(initial.data, 'open');
    }
    if (!kIsWeb) {
      final launch = await _notifications.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        _handleNotificationResponse(response);
      }
    }
    await _consumePendingAction();
    if (kIsWeb) {
      final parameters = Uri.base.queryParameters;
      final callId = parameters['callId'];
      if (callId != null && callId.isNotEmpty) {
        _emit({'call_id': callId}, parameters['callAction'] ?? 'open');
      }
      final groupCallId = parameters['groupCallId'];
      if (groupCallId != null && groupCallId.isNotEmpty) {
        _emit({
          'call_id': groupCallId,
          'group_call': 'true',
        }, parameters['callAction'] ?? 'open');
      }
      final invitationId = parameters['moduleInvite'];
      if (invitationId != null && invitationId.isNotEmpty) {
        _moduleInvitations.add(invitationId);
      }
      final notificationRoute = parameters['notificationRoute'];
      if (notificationRoute?.isNotEmpty == true) {
        _studentNotifications.add(
          StudentNotificationAction(
            route: notificationRoute!,
            entityId: parameters['notificationEntity'],
          ),
        );
      }
    }
    _initialised = true;
  }

  static Future<void> _ensureLocalNotificationsReady() async {
    if (kIsWeb || _localNotificationsReady) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    const channel = AndroidNotificationChannel(
      _channelId,
      'Incoming calls',
      description: 'Voice and video call alerts from OG Vibes',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    const sosChannel = AndroidNotificationChannel(
      _sosChannelId,
      'Emergency SOS alerts',
      description:
          'High-priority student safety alerts for trusted people and responders',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(sosChannel);
    const academicChannel = AndroidNotificationChannel(
      _academicChannelId,
      'Academic invitations',
      description: 'Module invitations and academic enrollment updates',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(academicChannel);
    const messagesChannel = AndroidNotificationChannel(
      _messagesChannelId,
      'Messages',
      description: 'Private and group chat messages',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(messagesChannel);
    const campusChannel = AndroidNotificationChannel(
      _campusChannelId,
      'Campus alerts and events',
      description: 'Important campus alerts, invitations and event updates',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(campusChannel);
    const activityChannel = AndroidNotificationChannel(
      _activityChannelId,
      'Student activity',
      description: 'Friend, marketplace, lost-and-found and feed activity',
      importance: Importance.defaultImportance,
      playSound: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(activityChannel);
    _localNotificationsReady = true;
  }

  static Future<PushEnrollmentStatus> enrollmentStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return PushEnrollmentStatus.signedOut;
    if (Firebase.apps.isEmpty) return PushEnrollmentStatus.unsupported;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushEnrollmentStatus.enabled,
        AuthorizationStatus.denied => PushEnrollmentStatus.blocked,
        AuthorizationStatus.notDetermined =>
          PushEnrollmentStatus.needsPermission,
      };
    } catch (error) {
      debugPrint('Unable to read notification permission: $error');
      return PushEnrollmentStatus.error;
    }
  }

  static Future<bool> requestAndRegisterCurrentDevice() async {
    if (Supabase.instance.client.auth.currentUser == null ||
        Firebase.apps.isEmpty) {
      return false;
    }
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return false;
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _ensureLocalNotificationsReady();
        final android = _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.requestNotificationsPermission();
        // Android 14+ treats ringing call screens as special access. This is
        // requested only after the student taps the enrollment button.
        await android?.requestFullScreenIntentPermission();
      }
      return registerCurrentDevice();
    } catch (error) {
      debugPrint('Notification permission request failed: $error');
      return false;
    }
  }

  static Future<bool> registerCurrentDevice() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || Firebase.apps.isEmpty) return false;
    try {
      final status = await enrollmentStatus();
      if (status != PushEnrollmentStatus.enabled) return false;
      const vapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');
      if (kIsWeb && vapidKey.isEmpty) {
        debugPrint(
          'Web notification registration needs FIREBASE_WEB_VAPID_KEY.',
        );
        return false;
      }
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? vapidKey : null,
      );
      if (token == null || token.isEmpty) return false;
      await _registerToken(token);
      await _tokenRefresh?.cancel();
      _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen(
        (value) => unawaited(_registerToken(value)),
        onError: (Object error) {
          debugPrint('Notification token refresh failed: $error');
        },
      );
      return true;
    } catch (error) {
      debugPrint('Unable to register this device for notifications: $error');
      return false;
    }
  }

  static Future<void> _registerToken(String token) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    await Supabase.instance.client.functions.invoke(
      'call-push',
      body: {
        'action': 'register',
        'token': token,
        'deviceId': await _deviceId(),
        'platform': kIsWeb ? 'web' : 'android',
      },
    );
  }

  static Future<void> unregisterCurrentDevice() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    await Supabase.instance.client.functions.invoke(
      'call-push',
      body: {'action': 'unregister', 'deviceId': await _deviceId()},
    );
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
  }

  static Future<List<PushDeviceRegistration>> activeDevices() async {
    if (Supabase.instance.client.auth.currentUser == null) return const [];
    final response = await Supabase.instance.client.functions.invoke(
      'call-push',
      body: {'action': 'list_devices', 'deviceId': await _deviceId()},
    );
    final payload = Map<String, dynamic>.from(response.data as Map);
    final rows = (payload['devices'] as List? ?? const []);
    return rows
        .whereType<Map>()
        .map((row) => PushDeviceRegistration.fromMap(
              Map<String, dynamic>.from(row),
            ))
        .where((device) => device.id.isNotEmpty)
        .toList(growable: false);
  }

  static Future<void> removeDevice(String registrationId) async {
    if (Supabase.instance.client.auth.currentUser == null ||
        registrationId.isEmpty) {
      return;
    }
    await Supabase.instance.client.functions.invoke(
      'call-push',
      body: {'action': 'remove_device', 'registrationId': registrationId},
    );
  }

  static Future<void> sendIncomingCall(String callId) async {
    await Supabase.instance.client.functions.invoke(
      'call-push',
      body: {'action': 'send', 'callId': callId},
    );
  }

  static Future<void> sendIncomingGroupCall(String callId) async {
    await Supabase.instance.client.functions.invoke(
      'call-push',
      body: {'action': 'send_group', 'callId': callId},
    );
  }

  static Future<void> showIncomingCall(Map<String, dynamic> data) async {
    if (data['event'] != 'incoming_call') return;
    final callId = data['call_id']?.toString() ?? '';
    if (callId.isEmpty) return;
    final name = data['caller_name']?.toString() ?? 'OG Vibes student';
    final video = data['call_type'] == 'video';
    if (kIsWeb) {
      await showWebIncomingCallNotification(
        callId: callId,
        callerName: name,
        isVideo: video,
        isGroupCall: data['group_call'] == true || data['group_call'] == 'true',
      );
      return;
    }
    await _ensureLocalNotificationsReady();
    final payload = jsonEncode(data);
    final details = AndroidNotificationDetails(
      _channelId,
      'Incoming calls',
      channelDescription: 'Voice and video call alerts from OG Vibes',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      ongoing: true,
      autoCancel: false,
      fullScreenIntent: true,
      timeoutAfter: 60000,
      // Android Notification.FLAG_INSISTENT repeats the ringtone until the
      // student answers, declines, or the 60-second call timeout is reached.
      additionalFlags: Int32List.fromList(<int>[4]),
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      actions: const [
        AndroidNotificationAction(
          _declineAction,
          'Decline',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          _acceptAction,
          'Accept',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );
    await _notifications.show(
      id: callId.hashCode & 0x7fffffff,
      title: data['group_call'] == 'true'
          ? (video ? 'Incoming group video call' : 'Incoming group voice call')
          : (video ? 'Incoming video call' : 'Incoming voice call'),
      body: name,
      notificationDetails: NotificationDetails(android: details),
      payload: payload,
    );
  }

  static Future<void> cancelIncomingCallNotification(String callId) async {
    if (kIsWeb || callId.isEmpty) return;
    await _ensureLocalNotificationsReady();
    await _notifications.cancel(id: callId.hashCode & 0x7fffffff);
  }

  static Future<void> showSosAlert(Map<String, dynamic> data) async {
    if (data['event'] != 'sos_alert' || kIsWeb) return;
    await _ensureLocalNotificationsReady();
    final incidentId = data['incident_id']?.toString() ?? '';
    if (incidentId.isEmpty) return;
    final name = data['student_name']?.toString() ?? 'A student';
    final type = data['emergency_type']?.toString() ?? 'emergency';
    final campus = data['campus']?.toString() ?? '';
    final details = AndroidNotificationDetails(
      _sosChannelId,
      'Emergency SOS alerts',
      channelDescription: 'High-priority student safety alerts',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );
    await _notifications.show(
      id: incidentId.hashCode & 0x7fffffff,
      title: 'Emergency SOS • ${type.toUpperCase()}',
      body: '$name needs help${campus.isEmpty ? '' : ' at $campus'}.',
      notificationDetails: NotificationDetails(android: details),
      payload: jsonEncode(data),
    );
  }

  static Future<void> showModuleInvitation(Map<String, dynamic> data) async {
    if (data['event'] != 'module_invitation' || kIsWeb) return;
    await _ensureLocalNotificationsReady();
    final invitationId = data['invitation_id']?.toString() ?? '';
    if (invitationId.isEmpty) return;
    final moduleName = data['module_name']?.toString() ?? 'a module';
    final moduleCode = data['module_code']?.toString() ?? '';
    final lecturer = data['lecturer_name']?.toString() ?? 'Your lecturer';
    const details = AndroidNotificationDetails(
      _academicChannelId,
      'Academic invitations',
      channelDescription: 'Module invitations and academic enrollment updates',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.private,
      playSound: true,
      enableVibration: true,
    );
    await _notifications.show(
      id: invitationId.hashCode & 0x7fffffff,
      title: 'New module invitation',
      body:
          '$lecturer invited you to ${moduleCode.isEmpty ? '' : '$moduleCode · '}$moduleName.',
      notificationDetails: const NotificationDetails(android: details),
      payload: jsonEncode(data),
    );
  }

  static Future<void> showStudentNotification(Map<String, dynamic> data) async {
    if (data['event'] != 'student_notification') return;
    final route = data['route']?.toString() ?? '';
    final title = data['title']?.toString() ?? 'OG Vibes update';
    final body = data['body']?.toString() ?? 'You have a new update.';
    if (route.isEmpty) return;
    if (kIsWeb) {
      await showWebStudentNotification(
        title: title,
        body: body,
        route: route,
        entityId: data['entity_id']?.toString(),
        notificationId: data['notification_id']?.toString(),
      );
      return;
    }
    await _ensureLocalNotificationsReady();
    final category = data['category']?.toString() ?? 'social';
    final channel = switch (category) {
      'messages' => (_messagesChannelId, 'Messages'),
      'academics' => (_academicChannelId, 'Academic updates'),
      'campus' => (_campusChannelId, 'Campus alerts and events'),
      _ => (_activityChannelId, 'Student activity'),
    };
    final details = AndroidNotificationDetails(
      channel.$1,
      channel.$2,
      importance: category == 'social' || category == 'marketplace'
          ? Importance.defaultImportance
          : Importance.high,
      priority: category == 'social' || category == 'marketplace'
          ? Priority.defaultPriority
          : Priority.high,
      category: category == 'messages'
          ? AndroidNotificationCategory.message
          : AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.private,
      playSound: true,
      enableVibration: true,
    );
    final notificationId = data['notification_id']?.toString() ?? route;
    await _notifications.show(
      id: notificationId.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: details),
      payload: jsonEncode(data),
    );
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    final action = response.actionId == _declineAction
        ? 'decline'
        : response.actionId == _acceptAction
        ? 'accept'
        : 'open';
    _emitNotification(data, action);
  }

  static void _emitNotification(Map<String, dynamic> data, String action) {
    if (data['event'] == 'module_invitation') {
      final invitationId = data['invitation_id']?.toString() ?? '';
      if (invitationId.isNotEmpty) _moduleInvitations.add(invitationId);
      return;
    }
    if (data['event'] == 'student_notification') {
      final notification = StudentNotificationAction.fromMap(data);
      if (notification.route.isNotEmpty) {
        _studentNotifications.add(notification);
      }
      return;
    }
    _emit(data, action);
  }

  static void _emit(Map<String, dynamic> data, String action) {
    final enriched = Map<String, dynamic>.from(data)..['action'] = action;
    final event = CallNotificationAction.fromMap(enriched);
    if (event.callId.isNotEmpty) _actions.add(event);
  }

  static Future<void> _consumePendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingActionKey);
    if (raw == null) return;
    await prefs.remove(_pendingActionKey);
    final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    _emitNotification(data, data['action']?.toString() ?? 'open');
  }

  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_deviceIdKey);
    if (current != null && current.length >= 8) return current;
    final random = Random.secure();
    final value = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await prefs.setString(_deviceIdKey, value);
    return value;
  }

  static Future<void> dispose() async {
    await _tokenRefresh?.cancel();
    await _foregroundMessages?.cancel();
    await _openedMessages?.cancel();
  }
}
