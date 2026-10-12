import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's visual theme locally without changing account data.
class ThemePreferences {
  ThemePreferences._();

  static const _storageKey = 'og_vibes_theme_mode';
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> initialise() async {
    final preferences = await SharedPreferences.getInstance();
    mode.value = _fromName(preferences.getString(_storageKey));
  }

  static Future<void> setMode(ThemeMode nextMode) async {
    if (mode.value == nextMode) return;
    mode.value = nextMode;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, nextMode.name);
  }

  static ThemeMode _fromName(String? name) {
    return ThemeMode.values.firstWhere(
      (value) => value.name == name,
      orElse: () => ThemeMode.system,
    );
  }
}
