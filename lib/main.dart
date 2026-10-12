import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';

import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/incoming_call_screen.dart';
import 'screens/active_call_screen.dart';
import 'screens/group_call_screen.dart';
import 'screens/my_modules_screen.dart';
import 'screens/email_confirmed_landing_screen.dart';
import 'screens/signup_confirmation_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/chat_detail_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/group_chats_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/assessments_calendar_screen.dart';
import 'screens/online_classes_screen.dart';
import 'screens/announcements_screen.dart';
import 'screens/events_screen.dart';
import 'screens/friend_requests_screen.dart';
import 'screens/market_screen.dart';
import 'screens/lost_and_found_screen.dart';
import 'screens/icass_checker_screen.dart';
import 'screens/career_screen.dart';
import 'screens/past_question_papers_screen.dart';
import 'screens/slides_screen.dart';
import 'services/call_service.dart';
import 'services/accessibility_preferences.dart';
import 'services/group_call_service.dart';
import 'services/diagnostics_service.dart';
import 'services/push_notification_service.dart';
import 'services/presence_service.dart';
import 'services/theme_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'utils/app_theme.dart';
import 'widgets/app_notice_gate.dart';
import 'widgets/notification_enrollment_gate.dart';
import 'widgets/onboarding_checklist_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    ThemePreferences.initialise(),
    AccessibilityPreferences.initialise(),
  ]);

  try {
    final supported = kIsWeb || defaultTargetPlatform == TargetPlatform.android;
    if (supported && (!kIsWeb || DefaultFirebaseOptions.webIsConfigured)) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (error, stackTrace) {
    debugPrint('Firebase initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final supabaseConfigured =
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // ignore: avoid_print
  print(
    'Loaded web configuration: SUPABASE_URL=${supabaseUrl.isEmpty ? "NOT SET" : "set"}, SUPABASE_ANON_KEY=${supabaseAnonKey.isEmpty ? "NOT SET" : "set"}',
  );

  // Initialize Supabase early so screens and services can safely use it.
  try {
    if (supabaseConfigured) {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      // ignore: avoid_print
      print('✓ Supabase initialized successfully.');
    } else {
      // ignore: avoid_print
      print(
        '⚠ Supabase keys not provided. For web, build with: flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
      );
    }
  } catch (e, st) {
    // ignore: avoid_print
    print('Supabase initialization failed in main: $e');
    // ignore: avoid_print
    print(st);
  }

  // Keep client failures observable during the pilot without storing message
  // contents, access tokens or stack traces in the database.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(DiagnosticsService.recordFlutterError(details));
  };

  runApp(MyApp(supabaseConfigured: supabaseConfigured));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.supabaseConfigured});

  final bool supabaseConfigured;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final CallService _callService = CallService();
  final GroupCallService _groupCallService = GroupCallService.instance;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<CallNotificationAction>? _callActionSubscription;
  StreamSubscription<String>? _moduleInvitationSubscription;
  StreamSubscription<StudentNotificationAction>?
  _studentNotificationSubscription;
  StreamSubscription<Uri>? _appLinkSubscription;
  final AppLinks _appLinks = AppLinks();
  String? _pendingModuleToken;
  String? _pendingModuleInvitationId;
  String? _lastModuleLinkSignature;
  bool _isShowingIncomingCall = false;
  bool _isShowingPasswordRecovery = false;
  final Set<String> _handledConfirmationTokens = <String>{};
  String? _lastStudentNotificationSignature;
  String? _incomingUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _callActionSubscription = PushNotificationService.actions.listen(
      (action) => unawaited(_handleCallNotificationAction(action)),
    );
    _moduleInvitationSubscription = PushNotificationService.moduleInvitations
        .listen((invitationId) {
          _openModuleInvitation(invitationId: invitationId);
        });
    _studentNotificationSubscription = PushNotificationService
        .studentNotifications
        .listen(_openStudentNotification);
    unawaited(_configureModuleInvitationLinks());
    if (Firebase.apps.isNotEmpty) {
      unawaited(PushNotificationService.initialise());
    }
    if (widget.supabaseConfigured) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            if (state.event == AuthChangeEvent.passwordRecovery) {
              _openPasswordRecovery();
            }
            if (state.session?.user.id == null) {
              _incomingUserId = null;
              _callService.dispose();
              _groupCallService.dispose();
              unawaited(PresenceService.instance.stop());
            } else {
              unawaited(PresenceService.instance.start());
              _listenForIncomingCalls();
              if (Firebase.apps.isNotEmpty) {
                unawaited(PushNotificationService.registerCurrentDevice());
              }
              _openPendingModuleInvitation();
            }
          });
      if (Supabase.instance.client.auth.currentUser != null) {
        unawaited(PresenceService.instance.start());
        _listenForIncomingCalls();
        if (Firebase.apps.isNotEmpty) {
          unawaited(PushNotificationService.registerCurrentDevice());
        }
      }
    }
  }

  Future<void> _configureModuleInvitationLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleModuleInvitationUri(initial);
      _appLinkSubscription = _appLinks.uriLinkStream.listen(
        _handleModuleInvitationUri,
        onError: (Object error) =>
            debugPrint('Unable to process module invitation link: $error'),
      );
      if (kIsWeb) _handleModuleInvitationUri(Uri.base);
    } catch (error) {
      debugPrint('Module invitation links are unavailable: $error');
    }
  }

  void _handleModuleInvitationUri(Uri uri) {
    final confirmationToken = uri.queryParameters['token_hash'];
    if (uri.host == 'student.ogvibes.co.za' &&
        uri.queryParameters['type'] == 'email' &&
        confirmationToken?.isNotEmpty == true) {
      if (!_handledConfirmationTokens.add(confirmationToken!)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) =>
                SignupConfirmationScreen(tokenHash: confirmationToken),
          ),
          (_) => false,
        );
      });
      return;
    }
    if (uri.queryParameters['passwordRecovery'] == '1') {
      _openPasswordRecovery();
      return;
    }
    if (uri.queryParameters['emailConfirmed'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => const EmailConfirmedLandingScreen(),
          ),
          (_) => false,
        );
      });
      return;
    }
    final token = uri.queryParameters['moduleToken'];
    final invitationId = uri.queryParameters['moduleInvite'];
    if (token?.isNotEmpty == true) {
      _openModuleInvitation(token: token);
    } else if (invitationId?.isNotEmpty == true) {
      _openModuleInvitation(invitationId: invitationId);
    }
  }

  void _openPasswordRecovery() {
    if (_isShowingPasswordRecovery) return;
    _isShowingPasswordRecovery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        _isShowingPasswordRecovery = false;
        return;
      }
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const ResetPasswordScreen(),
            ),
          )
          .whenComplete(() => _isShowingPasswordRecovery = false);
    });
  }

  void _openModuleInvitation({String? token, String? invitationId}) {
    if (token == null && invitationId == null) return;
    if (!widget.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      _pendingModuleToken = token;
      _pendingModuleInvitationId = invitationId;
      return;
    }
    final signature = token != null ? 'token:$token' : 'id:$invitationId';
    if (_lastModuleLinkSignature == signature) return;
    _lastModuleLinkSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        _pendingModuleToken = token;
        _pendingModuleInvitationId = invitationId;
        _lastModuleLinkSignature = null;
        return;
      }
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => MyModulesScreen(
            initialToken: token,
            highlightInvitationId: invitationId,
          ),
        ),
      );
    });
  }

  void _openPendingModuleInvitation() {
    final token = _pendingModuleToken;
    final invitationId = _pendingModuleInvitationId;
    if (token == null && invitationId == null) return;
    _pendingModuleToken = null;
    _pendingModuleInvitationId = null;
    _openModuleInvitation(token: token, invitationId: invitationId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(PresenceService.instance.resume());
      _listenForIncomingCalls();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(PresenceService.instance.pause());
    }
  }

  void _listenForIncomingCalls() {
    if (!widget.supabaseConfigured) return;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;
    if (_incomingUserId == currentUserId) return;
    _incomingUserId = currentUserId;

    _callService.listenForIncomingCalls(
      currentUserId: currentUserId,
      onIncoming: (call) => unawaited(_showIncomingCall(call)),
    );
    _groupCallService.listenForInvites(
      currentUserId: currentUserId,
      onIncoming: (invite) => unawaited(_showIncomingGroupCall(invite)),
    );
    unawaited(_restorePendingCall());
  }

  Future<void> _restorePendingCall() async {
    final pending = await _callService.pendingIncomingCalls();
    if (pending.isNotEmpty) {
      await _showIncomingCall(pending.first);
      return;
    }
    final groupInvites = await _groupCallService.pendingInvites();
    if (groupInvites.isNotEmpty) {
      await _showIncomingGroupCall(groupInvites.first);
    }
  }

  Future<void> _handleCallNotificationAction(
    CallNotificationAction action,
  ) async {
    if (!widget.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      return;
    }
    try {
      if (action.isGroupCall) {
        final invite = await _groupCallService.inviteById(action.callId);
        if (invite == null ||
            !const {'ringing', 'active'}.contains(invite.call['status'])) {
          return;
        }
        if (action.action == 'decline') {
          await _groupCallService.decline(action.callId);
          return;
        }
        await _showIncomingGroupCall(
          invite,
          autoAccept: action.action == 'accept',
        );
        return;
      }
      final call = await Supabase.instance.client
          .from('calls')
          .select()
          .eq('id', action.callId)
          .maybeSingle();
      if (call == null || call['status'] != 'ringing') return;
      if (action.action == 'decline') {
        await _callService.declineCall(action.callId);
        return;
      }
      await _showIncomingCall(
        Map<String, dynamic>.from(call),
        autoAccept: action.action == 'accept',
      );
    } catch (error) {
      debugPrint('Unable to process call notification action: $error');
    }
  }

  void _openStudentNotification(StudentNotificationAction notification) {
    if (!widget.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      return;
    }
    final signature = '${notification.route}:${notification.entityId ?? ''}';
    if (_lastStudentNotificationSignature == signature) return;
    _lastStudentNotificationSignature = signature;

    final Widget destination = switch (notification.route) {
      'chat' when notification.entityId?.isNotEmpty == true => ChatDetailScreen(
        chatId: notification.entityId!,
        chatTitle: notification.title,
      ),
      'messages' => const MessagesScreen(),
      'group_chats' => GroupChatsScreen(initialGroupId: notification.entityId),
      'quiz' || 'quizzes' => const QuizScreen(),
      'assessments' => const AssessmentsCalendarScreen(),
      'online_classes' => const OnlineClassesScreen(),
      'alerts' => const AnnouncementsScreen(),
      'events' => const EventsScreen(),
      'friends' => const FriendRequestsScreen(),
      'marketplace' => const MarketScreen(),
      'lost_found' => const LostAndFoundScreen(),
      'icass' => const IcassCheckerScreen(),
      'career' => const CareerScreen(),
      'past_papers' => const PastQuestionPapersScreen(),
      'lecture_slides' => const SlidesScreen(),
      'home' || 'feed' || 'social' => const HomeScreen(),
      _ => const HomeScreen(),
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        _lastStudentNotificationSignature = null;
        return;
      }
      navigator
          .push(MaterialPageRoute<void>(builder: (_) => destination))
          .whenComplete(() => _lastStudentNotificationSignature = null);
    });
  }

  Future<void> _showIncomingCall(
    Map<String, dynamic> call, {
    bool autoAccept = false,
  }) async {
    if (_isShowingIncomingCall || call['status'] != 'ringing') return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _isShowingIncomingCall = true;
    var name = 'OG Vibes student';
    String? photoUrl;
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('nickname,photo_url')
          .eq('id', call['caller_id'])
          .maybeSingle();
      final nickname = profile?['nickname']?.toString().trim() ?? '';
      name = nickname.isNotEmpty ? nickname : name;
      photoUrl = profile?['photo_url']?.toString();
    } catch (_) {}
    if (!mounted) {
      _isShowingIncomingCall = false;
      return;
    }
    await PushNotificationService.cancelIncomingCallNotification(
      call['id']?.toString() ?? '',
    );
    if (autoAccept) {
      try {
        final session = await _callService.acceptIncomingCall(call);
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => ActiveCallScreen(
              session: session,
              contactName: name,
              contactPhotoUrl: photoUrl,
            ),
          ),
        );
      } catch (_) {
        final context = _navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to connect this call. Please try again.'),
            ),
          );
        }
      } finally {
        _isShowingIncomingCall = false;
      }
      return;
    }
    navigator.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          contactName: name,
          contactPhotoUrl: photoUrl,
          callType: call['type']?.toString() ?? 'audio',
          onAccept: () async {
            navigator.pop();
            try {
              final session = await _callService.acceptIncomingCall(call);
              await navigator.push(
                MaterialPageRoute(
                  builder: (_) => ActiveCallScreen(
                    session: session,
                    contactName: name,
                    contactPhotoUrl: photoUrl,
                  ),
                ),
              );
            } catch (_) {
              final context = _navigatorKey.currentContext;
              if (context != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Unable to connect this call. Please try again.',
                    ),
                  ),
                );
              }
            } finally {
              _isShowingIncomingCall = false;
            }
          },
          onDecline: () async {
            navigator.pop();
            await _callService.declineCall(call['id'].toString());
            _isShowingIncomingCall = false;
          },
        ),
      ),
    );
  }

  Future<void> _showIncomingGroupCall(
    GroupCallInvite invite, {
    bool autoAccept = false,
  }) async {
    if (_isShowingIncomingCall ||
        !const {'ringing', 'active'}.contains(invite.call['status'])) {
      return;
    }
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _isShowingIncomingCall = true;
    await PushNotificationService.cancelIncomingCallNotification(invite.callId);

    Future<void> accept() async {
      try {
        final session = await _groupCallService.accept(invite);
        await navigator.push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => GroupCallScreen(session: session),
          ),
        );
      } catch (error) {
        final context = _navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to join this group call. It may be full or finished.',
              ),
            ),
          );
        }
      } finally {
        _isShowingIncomingCall = false;
      }
    }

    if (autoAccept) {
      await accept();
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          contactName: '${invite.callerName} • ${invite.groupName}',
          contactPhotoUrl: invite.callerPhotoUrl,
          callType: invite.callType,
          onAccept: () async {
            navigator.pop();
            await accept();
          },
          onDecline: () async {
            navigator.pop();
            await _groupCallService.decline(invite.callId);
            _isShowingIncomingCall = false;
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _callActionSubscription?.cancel();
    _moduleInvitationSubscription?.cancel();
    _studentNotificationSubscription?.cancel();
    _appLinkSubscription?.cancel();
    _callService.dispose();
    _groupCallService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemePreferences.mode,
      builder: (context, themeMode, _) => ValueListenableBuilder<bool>(
        valueListenable: AccessibilityPreferences.reduceMotion,
        builder: (context, reduceMotion, _) => MaterialApp(
          title: 'OG Vibes',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          home: SplashScreen(supabaseConfigured: widget.supabaseConfigured),
          builder: (context, child) {
            final platformMedia = MediaQuery.of(context);
            return MediaQuery(
              data: platformMedia.copyWith(
                disableAnimations:
                    platformMedia.disableAnimations || reduceMotion,
              ),
              child: OnboardingChecklistGate(
                enabled: widget.supabaseConfigured,
                child: NotificationEnrollmentGate(
                  enabled: widget.supabaseConfigured,
                  child: AppNoticeGate(
                    enabled: widget.supabaseConfigured,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
