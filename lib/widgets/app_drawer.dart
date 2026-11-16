import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/push_notification_service.dart';
import '../services/auth_persistence_service.dart';

import '../screens/call_history_screen.dart';
import '../screens/helpful_contacts_screen.dart';
import '../screens/download_history_screen.dart';
import '../screens/login_screen.dart';
import '../screens/my_modules_screen.dart';
import '../screens/my_posts_screen.dart';
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
            : 'OG Vibester';
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
        _userName =
            user.userMetadata?['nickname']?.toString().trim().isNotEmpty == true
            ? user.userMetadata!['nickname'].toString().trim()
            : 'OG Vibester';
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white24,
                        backgroundImage: _photoUrl != null
                            ? NetworkImage(_photoUrl!)
                            : null,
                        child: _photoUrl == null
                            ? const Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                                size: 30,
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
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white70,
                        size: 18,
                      ),
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
                    'My profile',
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
                    Icons.dynamic_feed_rounded,
                    color: Colors.cyanAccent,
                  ),
                  title: const Text(
                    'My posts',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'View, edit or delete your posts',
                    style: TextStyle(color: Colors.white60),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MyPostsScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.menu_book_rounded,
                    color: Colors.cyanAccent,
                  ),
                  title: const Text(
                    'My modules',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Invitations and modules you joined',
                    style: TextStyle(color: Colors.white60),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyModulesScreen(),
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
                    'Helpful contacts',
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
                    Icons.history_rounded,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Call history',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CallHistoryScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.bug_report_outlined,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Report a problem',
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
                    'Suggest an idea',
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
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.white70),
                  title: const Text(
                    'Downloads',
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
                    'Version updates',
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
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Log out',
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
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Column(
              children: [
                Text(
                  'Powered by OG Technologies',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '© 2026 OG Technologies',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
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
      await PushNotificationService.unregisterCurrentDevice();
      await AuthPersistenceService.clear();
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
}
