import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local accessibility choices. The operating-system preference is
/// still honoured; this switch lets a student reduce motion independently.
class AccessibilityPreferences {
  AccessibilityPreferences._();

  static const _reduceMotionKey = 'og_vibes_reduce_motion';
  static final ValueNotifier<bool> reduceMotion = ValueNotifier<bool>(false);

  static Future<void> initialise() async {
    final preferences = await SharedPreferences.getInstance();
    reduceMotion.value = preferences.getBool(_reduceMotionKey) ?? false;
  }

  static Future<void> setReduceMotion(bool value) async {
    if (reduceMotion.value == value) return;
    reduceMotion.value = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_reduceMotionKey, value);
  }
}
