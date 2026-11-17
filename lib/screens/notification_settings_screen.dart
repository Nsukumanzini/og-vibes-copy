import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  static const String _examKey = 'pref_exam_alerts';
  static const String _socialKey = 'pref_social_chat';
  static const String _marketplaceKey = 'pref_marketplace_updates';

  bool _examAlerts = true;
  bool _socialChat = true;
  bool _marketplaceUpdates = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _examAlerts = prefs.getBool(_examKey) ?? true;
      _socialChat = prefs.getBool(_socialKey) ?? true;
      _marketplaceUpdates = prefs.getBool(_marketplaceKey) ?? false;
      _isLoading = false;
    });
  }

  Future<void> _updatePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notification Manager',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D47A1), Color(0xFF2962FF), Color(0xFF6200EA)],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSwitch(
                    title: 'Exam Alerts 🔔',
                    subtitle: 'Stay in the loop for timetable changes.',
                    value: _examAlerts,
                    onChanged: (value) {
                      setState(() => _examAlerts = value);
                      _updatePreference(_examKey, value);
                    },
                  ),
                  _buildSwitch(
                    title: 'Social & Chat 💬',
                    subtitle: 'Messages, clubs, and campus buzz.',
                    value: _socialChat,
                    onChanged: (value) {
                      setState(() => _socialChat = value);
                      _updatePreference(_socialKey, value);
                    },
                  ),
                  _buildSwitch(
                    title: 'Marketplace Updates 🛒',
                    subtitle: 'Listings, offers, and verified trades.',
                    value: _marketplaceUpdates,
                    onChanged: (value) {
                      setState(() => _marketplaceUpdates = value);
                      _updatePreference(_marketplaceKey, value);
                    },
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      color: Colors.white.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.only(bottom: 16),
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        activeThumbColor: Colors.amber,
        inactiveThumbColor: Colors.white54,
        inactiveTrackColor: Colors.white24,
      ),
    );
  }
}
