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

const _channelId = 'og_vibes_calls';
const _pendingActionKey = 'pending_call_notification_action';
const _deviceIdKey = 'og_vibes_push_device_id';
const _acceptAction = 'accept_call';
const _declineAction = 'decline_call';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  await PushNotificationService.showIncomingCall(message.data);
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
  });

  final String callId;
  final String action;
  final String? callerName;
  final String? callType;

  factory CallNotificationAction.fromMap(Map<String, dynamic> data) {
    return CallNotificationAction(
      callId: (data['call_id'] ?? data['callId'] ?? '').toString(),
      action: (data['action'] ?? 'open').toString(),
      callerName: data['caller_name']?.toString(),
      callType: data['call_type']?.toString(),
    );
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final StreamController<CallNotificationAction> _actions =
      StreamController<CallNotificationAction>.broadcast();
  static StreamSubscription<String>? _tokenRefresh;
  static StreamSubscription<RemoteMessage>? _foregroundMessages;
  static StreamSubscription<RemoteMessage>? _openedMessages;
  static bool _initialised = false;

  static Stream<CallNotificationAction> get actions => _actions.stream;

  static Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    if (!kIsWeb) {
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
      );
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    _foregroundMessages = FirebaseMessaging.onMessage.listen((message) {
      if (message.data['event'] == 'incoming_call') {
        unawaited(showIncomingCall(message.data));
      }
    });
    _openedMessages = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _emit(message.data, 'open');
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial?.data['event'] == 'incoming_call') {
      _emit(initial!.data, 'open');
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
        _emit(
          {'call_id': callId},
          parameters['callAction'] ?? 'open',
        );
      }
    }
  }

  static Future<void> registerCurrentDevice() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || Firebase.apps.isEmpty) return;
    const vapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');
    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb && vapidKey.isNotEmpty ? vapidKey : null,
    );
    if (token == null || token.isEmpty) return;
    await _registerToken(token);
    await _tokenRefresh?.cancel();
    _tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen((value) {
      unawaited(_registerToken(value));
    });
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

  static Future<void> sendIncomingCall(String callId) async {
    await Supabase.instance.client.functions.invoke(
      'call-push',
      body: {'action': 'send', 'callId': callId},
    );
  }

  static Future<void> showIncomingCall(Map<String, dynamic> data) async {
    if (data['event'] != 'incoming_call' || kIsWeb) return;
    final callId = data['call_id']?.toString() ?? '';
    if (callId.isEmpty) return;
    final name = data['caller_name']?.toString() ?? 'OG Vibes student';
    final video = data['call_type'] == 'video';
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
      timeoutAfter: 60000,
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
      title: video ? 'Incoming video call' : 'Incoming voice call',
      body: name,
      notificationDetails: NotificationDetails(android: details),
      payload: payload,
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
    final event = CallNotificationAction.fromMap(data);
    if (event.callId.isNotEmpty) _actions.add(event);
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
