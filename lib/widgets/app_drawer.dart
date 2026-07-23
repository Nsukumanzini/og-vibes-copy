import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/call_feature_screen.dart';
import '../screens/helpful_contacts_screen.dart';
import '../screens/login_screen.dart';
import '../screens/notification_settings_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/suggestion_box_screen.dart';
import '../screens/whistleblower_screen.dart';
import '../screens/whats_new_screen.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  bool _isExamMode = false;
  String? _userNickname;
  String _userName = 'OG Vibester';
  String _userCampus = 'Campus Unknown';
  String _userCourse = 'General Studies';
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('nickname, name, campus, department, photo_url')
          .eq('id', user.id)
          .single();
      if (!mounted) return;
      final map = data as Map<String, dynamic>?;
      setState(() {
        _userNickname = (map?['nickname'] as String?)?.trim();
        _userName = (_userNickname?.isNotEmpty == true)
            ? _userNickname!
            : (map?['name'] as String?)?.trim().isNotEmpty == true
                ? map!['name'] as String
                : (user.email?.split('@').first ?? 'OG Vibester');
        _userCampus = (map?['campus'] as String?)?.trim().isNotEmpty == true
            ? map!['campus'] as String
            : 'Campus Unknown';
        final department = (map?['department'] as String?)?.trim();
        _userCourse = (department?.isNotEmpty == true)
            ? department!
            : 'General Studies';
        _photoUrl = (map?['photo_url'] as String?)?.trim().isNotEmpty == true
          ? map!['photo_url'] as String
          : user.userMetadata?['avatar_url'] as String?;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _userName = user.email?.split('@').first ?? 'OG Vibester';
        _userCampus = 'Campus Unknown';
        _userCourse = 'General Studies';
        _photoUrl = user.userMetadata?['avatar_url'] as String?;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0A0E21),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Material(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white24,
                        backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                        child: _photoUrl == null
                            ? Text(
                                _userName.isNotEmpty ? _userName[0].toUpperCase() : 'O',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _userName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _userCourse,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _userCampus,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.person_outline,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'My Profile',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.circle_notifications,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Notification Settings',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationSettingsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(color: Colors.white24),
                ListTile(
                  leading: const Icon(
                    Icons.phone_in_talk,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Helpful Contacts',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HelpfulContactsScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.video_call_rounded,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Call Feature',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CallFeatureScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.bug_report_outlined,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Report a Problem',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WhistleblowerScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.lightbulb_outline,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Suggest an Idea',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SuggestionBoxScreen(),
                      ),
                    );
                  },
                ),
                const Divider(color: Colors.white24),
                SwitchListTile.adaptive(
                  value: _isExamMode,
                  title: const Text(
                    'Exam Mode',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Silence notifications for 2 hrs',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onChanged: (value) {
                    setState(() => _isExamMode = value);
                    if (value) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Study hard! Notifications silenced.'),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.white70),
                  title: const Text(
                    'Download History',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DownloadHistoryScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings, color: Colors.white70),
                  title: const Text(
                    'Settings',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
                const Divider(color: Colors.white24),
                ListTile(
                  leading: const Icon(
                    Icons.new_releases,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    "What's New",
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WhatsNewScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip, color: Colors.white70),
                  title: const Text(
                    'Legal & Privacy',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _launchLegalPage();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Log Out',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () => _logOut(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: const Text(
              'v1.0.0 (Stable)',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to log out: $error')),
      );
    }
  }

  Future<void> _launchLegalPage() async {
    const url = 'https://www.nsfas.org.za';
    try {
      if (!await launchUrl(Uri.parse(url))) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open legal information.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open legal information.')),
      );
    }
  }
}

class DownloadHistoryScreen extends StatelessWidget {
  const DownloadHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> downloads = const [];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Download History',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D47A1), Color(0xFF2962FF), Color(0xFF6200EA)],
          ),
        ),
        child: SafeArea(
          child: downloads.isEmpty
              ? const Center(
                  child: Text(
                    'No downloads yet',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: downloads.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final entry = downloads[index];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: const BorderSide(color: Colors.white24),
                      ),
                      tileColor: Colors.white.withValues(alpha: 0.08),
                      leading: const Icon(Icons.picture_as_pdf),
                      title: Text(entry['title'] ?? 'Unknown file'),
                      subtitle: Text(
                        '${entry['size'] ?? '--'} • ${entry['date'] ?? ''}',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      textColor: Colors.white,
                      iconColor: Colors.white70,
                      onTap: () {},
                    );
                  },
                ),
        ),
      ),
    );
  }
}
