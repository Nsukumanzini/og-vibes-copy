import 'package:flutter/material.dart';

import '../screens/call_history_screen.dart';
import '../screens/download_history_screen.dart';
import '../screens/helpful_contacts_screen.dart';
import '../screens/landing_screen.dart';
import '../screens/my_modules_screen.dart';
import '../screens/my_posts_screen.dart';
import '../screens/og_assistant_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/safety_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/suggestion_box_screen.dart';
import '../screens/whats_new_screen.dart';
import '../screens/whistleblower_screen.dart';
import '../utils/theme_constants.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final String _userName = 'OG Vibester';
  final String _userCampus = 'Campus Unknown';
  final String _userCourse = 'General Studies';
  String? _photoUrl;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.auroraCanvas,
      child: SafeArea(
        child: Column(
          children: [
            _buildProfileHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
                children: [
                  _buildSection('MY SPACE', [
                    _buildItem(
                      icon: Icons.person_rounded,
                      title: 'My profile',
                      onTap: () => _openScreen(context, const ProfileScreen()),
                    ),
                    _buildItem(
                      icon: Icons.dynamic_feed_rounded,
                      title: 'My posts',
                      subtitle: 'View and manage your posts',
                      onTap: () => _openScreen(context, const MyPostsScreen()),
                    ),
                    _buildItem(
                      icon: Icons.menu_book_rounded,
                      title: 'My modules',
                      subtitle: 'Modules and invitations',
                      onTap: () =>
                          _openScreen(context, const MyModulesScreen()),
                    ),
                  ]),
                  _buildSection('LEARNING', [
                    _buildItem(
                      icon: Icons.auto_awesome_rounded,
                      title: 'OG Assistant',
                      subtitle: 'Search academic study material',
                      onTap: () => _openScreen(context, const OgAssistantScreen()),
                    ),
                  ]),
                  _buildSection('CAMPUS SUPPORT', [
                    _buildItem(
                      icon: Icons.support_agent_rounded,
                      title: 'Helpful contacts',
                      onTap: () =>
                          _openScreen(context, const HelpfulContactsScreen()),
                    ),
                    _buildItem(
                      icon: Icons.shield_rounded,
                      title: 'Safety setup',
                      subtitle: 'Emergency contacts and details',
                      goldAccent: true,
                      onTap: () => _openScreen(context, const SafetyScreen()),
                    ),
                    _buildItem(
                      icon: Icons.history_rounded,
                      title: 'Call history',
                      onTap: () =>
                          _openScreen(context, const CallHistoryScreen()),
                    ),
                  ]),
                  _buildSection('HELP & FEEDBACK', [
                    _buildItem(
                      icon: Icons.bug_report_rounded,
                      title: 'Report a problem',
                      onTap: () =>
                          _openScreen(context, const WhistleblowerScreen()),
                    ),
                    _buildItem(
                      icon: Icons.lightbulb_rounded,
                      title: 'Suggest an idea',
                      onTap: () =>
                          _openScreen(context, const SuggestionBoxScreen()),
                    ),
                  ]),
                  _buildSection('YOUR APP', [
                    _buildItem(
                      icon: Icons.download_rounded,
                      title: 'Downloads',
                      onTap: () =>
                          _openScreen(context, const DownloadHistoryScreen()),
                    ),
                    _buildItem(
                      icon: Icons.tune_rounded,
                      title: 'Settings',
                      onTap: () => _openScreen(context, const SettingsScreen()),
                    ),
                    _buildItem(
                      icon: Icons.new_releases_rounded,
                      title: 'Version updates',
                      onTap: () => _openScreen(context, const WhatsNewScreen()),
                    ),
                  ]),
                ],
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.midnightInk,
            AppColors.deepBlue,
            AppColors.vibeBlue,
          ],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .18),
                  ),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  size: 19,
                  color: Color(0xFFFFD46A),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'OG VIBES',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .16),
                  ),
                ),
                child: const Text(
                  'STUDENT',
                  style: TextStyle(
                    color: Color(0xFFFFE7A3),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _openScreen(context, const ProfileScreen()),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFE7A3), Color(0xFFFFC943)],
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 27,
                        backgroundColor: const Color(0xFFE8F0FF),
                        backgroundImage: _photoUrl != null
                            ? NetworkImage(_photoUrl!)
                            : null,
                        child: _photoUrl == null
                            ? const Icon(
                                Icons.person_rounded,
                                color: AppColors.deepBlue,
                                size: 30,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_userCourse · $_userCampus',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .72),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            'View your profile',
                            style: TextStyle(
                              color: Color(0xFFFFE7A3),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white.withValues(alpha: .82),
                      size: 15,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 0, 7, 8),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.15,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: AppColors.deepBlue.withValues(alpha: .045),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    items[index],
                    if (index != items.length - 1)
                      const Padding(
                        padding: EdgeInsets.only(left: 65),
                        child: Divider(height: 1, thickness: 1, indent: 0),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool goldAccent = false,
  }) {
    final iconColor = goldAccent ? const Color(0xFF8A6500) : AppColors.deepBlue;
    final iconBackground = goldAccent ? AppColors.goldTint : AppColors.blueTint;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.midnightInk,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9AA9BF),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2F1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF4D5D2)),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _logOut(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      Icon(
                        Icons.logout_rounded,
                        color: Color(0xFFC64343),
                        size: 19,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Log out',
                          style: TextStyle(
                            color: Color(0xFFAF3030),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFD47B76),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: AppColors.ogGold,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'Powered by OG Technologies',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                '·  © 2026',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  void _openScreen(BuildContext context, Widget screen) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _logOut(BuildContext context) async {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LandingScreen()),
      (route) => false,
    );
  }
}
