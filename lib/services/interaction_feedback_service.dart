import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shared, lightweight tactile and sound feedback for meaningful app events.
class InteractionFeedbackService {
  InteractionFeedbackService._();

  static final AudioPlayer _player = AudioPlayer();
  static DateTime? _lastNotificationFeedback;

  static void selection() {
    unawaited(HapticFeedback.selectionClick());
  }

  static void taskSucceeded() {
    unawaited(HapticFeedback.mediumImpact());
  }

  static void taskFailed() {
    unawaited(HapticFeedback.heavyImpact());
  }

  static Future<void> callEnded() async {
    await HapticFeedback.mediumImpact();
    await _play('audio/call_end.wav');
  }

  static Future<void> notificationReceived() async {
    final now = DateTime.now();
    if (_lastNotificationFeedback != null &&
        now.difference(_lastNotificationFeedback!) <
            const Duration(milliseconds: 1500)) {
      return;
    }
    _lastNotificationFeedback = now;
    await HapticFeedback.lightImpact();
    await _play('audio/notification.wav');
  }

  static Future<void> _play(String assetPath) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(assetPath), volume: .55);
    } catch (error) {
      // Audio may be unavailable, muted, or blocked by the browser. Haptics
      // and the underlying app action still proceed normally.
      debugPrint('Unable to play interaction sound: $error');
    }
  }
}
