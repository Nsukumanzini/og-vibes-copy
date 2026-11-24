import 'dart:async';

import 'package:flutter/material.dart';

import '../services/interaction_feedback_service.dart';
import '../services/notification_badge_service.dart';

/// Plays a subtle cue only for notification counts that increase while the
/// app is actively in the foreground.
class ForegroundNotificationFeedback extends StatefulWidget {
  const ForegroundNotificationFeedback({super.key, required this.child});

  final Widget child;

  @override
  State<ForegroundNotificationFeedback> createState() =>
      _ForegroundNotificationFeedbackState();
}

class _ForegroundNotificationFeedbackState
    extends State<ForegroundNotificationFeedback>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _subscription;
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isForeground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _subscription = NotificationBadgeService.instance.incomingNotifications
        .listen(_onNotification);
  }

  void _onNotification(void _) {
    if (_isForeground) {
      unawaited(InteractionFeedbackService.notificationReceived());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
