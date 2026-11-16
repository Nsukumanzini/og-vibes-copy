import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../services/offline_data_adapter.dart';

import '../services/auth_persistence_service.dart';

import '../services/auth_service.dart';
import '../services/accessibility_preferences.dart';
import '../services/push_notification_service.dart';
import '../services/theme_preferences.dart';
import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';
import 'blocked_users_screen.dart';
import 'login_screen.dart';
import 'legal_document_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  late Future<_SettingsProfile> _profile;

  User? get _user => OfflineData.instance.client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _profile = _loadProfile();
  }

  Future<_SettingsProfile> _loadProfile() async {
    final user = _user;
    if (user == null) return const _SettingsProfile.guest();
    try {
      final row = await OfflineData.instance.client
          .from('profiles')
          .select('nickname,student_number,campus,department,level,photo_url')
          .eq('id', user.id)
          .maybeSingle();
      return _SettingsProfile.from(row, user);
    } catch (_) {
      return _SettingsProfile.from(null, user);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: VibeScaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          leading: Navigator.canPop(context) ? const BackButton() : null,
          actions: [
            Semantics(
              button: true,
              label: 'Reload profile',
              child: IconButton(
                tooltip: 'Refresh',
                onPressed: () => setState(() => _profile = _loadProfile()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth >= 900 ? 28.0 : 16.0;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padding, 8, padding, 0),
                  child: NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      SliverToBoxAdapter(
                        child: FutureBuilder<_SettingsProfile>(
                          future: _profile,
                          builder: (context, snapshot) => _ProfileHero(
                            profile: snapshot.data,
                            loading:
                                snapshot.connectionState !=
                                ConnectionState.done,
                            onEdit: _openProfile,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                      const SliverToBoxAdapter(child: _SettingsTabs()),
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    ],
                    body: TabBarView(
                      children: [
                        _SettingsList(children: _accountItems()),
                        const _PreferencesTab(),
                        _SettingsList(children: _privacyItems()),
                        _SettingsList(children: _securityItems()),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _accountItems() => [
    const _SectionIntro(
      eyebrow: 'YOUR OG VIBES',
      title: 'Your account and app',
      description:
          'Keep your student identity current and find the important product information in one place.',
    ),
    _SettingsAction(
      icon: Icons.manage_accounts_outlined,
      title: 'Edit profile',
      subtitle: 'Update your photo and student information.',
      badge: 'PROFILE',
      onTap: _openProfile,
    ),
    _SettingsAction(
      icon: Icons.bug_report_outlined,
      title: 'Report a bug',
      subtitle: 'Tell the OG Vibes team when something is not working.',
      onTap: _showBugReportDialog,
    ),
    const _SectionLabel('LEGAL & ABOUT'),
    _SettingsAction(
      icon: Icons.privacy_tip_outlined,
      title: 'Privacy policy',
      subtitle: 'Understand how your information is handled.',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              const LegalDocumentScreen(type: LegalDocumentType.privacy),
        ),
      ),
    ),
    _SettingsAction(
      icon: Icons.gavel_rounded,
      title: 'Terms of use',
      subtitle: 'The rules that apply when using OG Vibes.',
      onTap: () => _showInformationSheet(
        title: 'Terms of use',
        icon: Icons.gavel_rounded,
        body:
            'Use OG Vibes responsibly, respect other students, and only upload content you are permitted to share. Campus and institutional rules still apply while using the platform.',
      ),
    ),
    _SettingsAction(
      icon: Icons.groups_2_outlined,
      title: 'Community guidelines',
      subtitle: 'How we keep the student community respectful and safe.',
      onTap: () => _showInformationSheet(
        title: 'Community guidelines',
        icon: Icons.groups_2_outlined,
        body:
            'Be respectful, protect private information, avoid harassment or impersonation, report unsafe content, and keep academic collaboration honest.',
      ),
    ),
    _SettingsAction(
      icon: Icons.info_outline_rounded,
      title: 'About OG Vibes',
      subtitle: 'Version 1.0.0 · Built for students.',
      badge: 'v1.0.0',
      onTap: _showAbout,
    ),
    _SettingsAction(
      icon: Icons.code_rounded,
      title: 'Open-source licences',
      subtitle: 'View licences for packages used by this app.',
      onTap: () => showLicensePage(
        context: context,
        applicationName: 'OG Vibes',
        applicationVersion: '1.0.0',
        applicationLegalese: 'Built for Students.',
      ),
    ),
  ];

  List<Widget> _privacyItems() => [
    const _SectionIntro(
      eyebrow: 'PRIVACY CENTRE',
      title: 'Manage your privacy',
      description:
          'Review the people you have blocked and learn how your information is protected.',
    ),
    _SettingsAction(
      icon: Icons.block_rounded,
      title: 'Blocked users',
      subtitle: 'Manage people who cannot message or interact with you.',
      badge: 'MANAGE',
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const BlockedUsersScreen())),
    ),
    _SettingsAction(
      icon: Icons.shield_outlined,
      title: 'Privacy policy',
      subtitle: 'Review collection, storage, and protection of your data.',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              const LegalDocumentScreen(type: LegalDocumentType.privacy),
        ),
      ),
    ),
    const _PrivacyPromise(),
  ];

  List<Widget> _securityItems() => [
    const _SectionIntro(
      eyebrow: 'ACCOUNT SECURITY',
      title: 'Keep your account safe',
      description:
          'Keep your sign-in secure and review sensitive account actions carefully.',
    ),
    _SettingsAction(
      icon: Icons.password_rounded,
      title: 'Change password',
      subtitle: 'Choose a new password for your account.',
      onTap: _showChangePasswordDialog,
    ),
    const _ActiveDevicesCard(),
    _SettingsAction(
      icon: Icons.logout_rounded,
      title: 'Sign out',
      subtitle: 'End your OG Vibes session on this device.',
      onTap: _signOut,
    ),
    const _SectionLabel('DANGER ZONE', danger: true),
    _SettingsAction(
      icon: Icons.delete_forever_rounded,
      title: 'Delete account',
      subtitle: 'Permanently remove your profile and sign out.',
      danger: true,
      onTap: _confirmDeleteAccount,
    ),
  ];

  Future<void> _openProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
    if (mounted) setState(() => _profile = _loadProfile());
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.password_rounded),
        title: const Text('Change password'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New password',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
            validator: (value) => value == null || value.length < 6
                ? 'Use at least 6 characters.'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              try {
                await OfflineData.instance.client.auth.reauthenticate();
                await OfflineData.instance.client.auth.updateUser(
                  OfflineUserAttributes(password: controller.text.trim()),
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _showSnack('Password updated.');
              } catch (error) {
                _showSnack('Could not update password: $error');
              }
            },
            child: const Text('Update password'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _showBugReportDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.bug_report_outlined),
        title: const Text('Report a bug'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'What happened, and what did you expect?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send report'),
            onPressed: () async {
              final description = controller.text.trim();
              if (description.isEmpty) {
                _showSnack('Please describe the issue.');
                return;
              }
              try {
                await OfflineData.instance.client.from('bug_reports').insert({
                  'user_id': _user?.id,
                  'description': description,
                });
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _showSnack('Bug report sent. Thank you!');
              } catch (error) {
                _showSnack('Failed to send report: $error');
              }
            },
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _confirmDeleteAccount() async {
    final controller = TextEditingController();
    final confirmationController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
        title: const Text('Delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This action is permanent. Enter your password, then type DELETE to continue.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmationController,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Type DELETE',
                prefixIcon: const Icon(Icons.delete_forever_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep account'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    final password = controller.text;
    final confirmationPhrase = confirmationController.text.trim();
    controller.dispose();
    confirmationController.dispose();
    if (confirm != true) return;

    final user = _user;
    if (user == null || user.email == null) {
      _showSnack('No authenticated user.');
      return;
    }
    try {
      if (password.isEmpty) {
        _showSnack('Enter your password to confirm deletion.');
        return;
      }
      if (confirmationPhrase != 'DELETE') {
        _showSnack('Type DELETE exactly to confirm.');
        return;
      }
      await OfflineData.instance.client.auth.signInWithPassword(
        email: user.email!,
        password: password,
      );
      final response = await OfflineData.instance.client.functions.invoke(
        'delete-account',
        body: const <String, String>{'confirmation': 'DELETE'},
      );
      if (response.status < 200 || response.status >= 300) {
        final message = response.data is Map
            ? '${(response.data as Map)['error'] ?? 'Account could not be deleted.'}'
            : 'Account could not be deleted.';
        throw Exception(message);
      }
      await OfflineData.instance.client.auth.signOut();
      await AuthPersistenceService.clear();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      _showSnack('Account deleted.');
    } catch (error) {
      _showSnack('Failed to delete account: $error');
    }
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationIcon: const _BrandMark(size: 54),
      applicationName: 'OG Vibes',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2026 OG Technologies',
      children: const [
        SizedBox(height: 8),
        Text(
          'A connected student experience for academics, opportunities, community, and campus life.',
        ),
        SizedBox(height: 10),
        Text(
          'Powered by OG Technologies',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  void _showInformationSheet({
    required String title,
    required IconData icon,
    required String body,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: AppColors.vibeBlue),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(body, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _GlassSurface(
      radius: 20,
      padding: const EdgeInsets.all(5),
      child: Semantics(
        label: 'Settings categories',
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: AppStyles.brandGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.vibeBlue.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          labelColor: Colors.white,
          unselectedLabelColor: isDark
              ? const Color(0xFFB8C5D9)
              : AppColors.textMuted,
          tabs: const [
            Tab(icon: Icon(Icons.person_outline_rounded), text: 'Account'),
            Tab(icon: Icon(Icons.tune_rounded), text: 'Preferences'),
            Tab(icon: Icon(Icons.visibility_outlined), text: 'Privacy'),
            Tab(icon: Icon(Icons.security_rounded), text: 'Security'),
          ],
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.profile,
    required this.loading,
    required this.onEdit,
  });

  final _SettingsProfile? profile;
  final bool loading;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final data = profile ?? const _SettingsProfile.guest();
    return Semantics(
      container: true,
      label: loading
          ? 'Loading student profile'
          : '${data.name}, ${data.summary}',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: AppStyles.bentoRadius,
            gradient: AppStyles.brandGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.vibeBlue.withValues(alpha: 0.24),
                blurRadius: 34,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Wrap(
            spacing: 18,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Hero(
                tag: 'settings-profile-avatar',
                child: _ProfileAvatar(profile: data, loading: loading),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 190, maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const _BrandMark(size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'Your profile',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: AppColors.electricCyan,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.3,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      child: Text(
                        loading ? 'Loading your profile…' : data.name,
                        key: ValueKey('${data.name}$loading'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        const _HeroStatusPill(
                          icon: Icons.verified_rounded,
                          label: 'Signed in',
                        ),
                        if (data.email.isNotEmpty)
                          _HeroStatusPill(
                            icon: Icons.mail_outline_rounded,
                            label: data.email,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: onEdit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.38)),
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreferencesTab extends StatelessWidget {
  const _PreferencesTab();

  @override
  Widget build(BuildContext context) {
    return _SettingsList(
      children: [
        const _SectionIntro(
          eyebrow: 'APP LOOK',
          title: 'Choose how the app looks',
          description:
              'Choose light mode, dark mode or use your phone setting.',
        ),
        _GlassSurface(
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemePreferences.mode,
            builder: (context, selected, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _IconBadge(icon: Icons.palette_outlined),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'App theme',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Saved automatically on this device.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Dark'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.devices_rounded),
                        label: Text('System'),
                      ),
                    ],
                    selected: {selected},
                    onSelectionChanged: (selection) {
                      ThemePreferences.setMode(selection.first);
                      SemanticsService.announce(
                        '${selection.first.name} theme selected',
                        Directionality.of(context),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const _ThemePreview(),
        const _NotificationReadinessCard(),
        const _MotionNotice(),
      ],
    );
  }
}

class _NotificationReadinessCard extends StatefulWidget {
  const _NotificationReadinessCard();

  @override
  State<_NotificationReadinessCard> createState() =>
      _NotificationReadinessCardState();
}

class _NotificationReadinessCardState
    extends State<_NotificationReadinessCard> {
  late Future<PushEnrollmentStatus> _status;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _status = PushNotificationService.enrollmentStatus();
  }

  Future<void> _enable() async {
    if (_working) return;
    setState(() => _working = true);
    final enabled =
        await PushNotificationService.requestAndRegisterCurrentDevice();
    if (!mounted) return;
    setState(() {
      _working = false;
      _status = PushNotificationService.enrollmentStatus();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Notifications and incoming call alerts are ready on this device.'
              : 'Notifications were not enabled. OG Vibes will continue without them.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PushEnrollmentStatus>(
      future: _status,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final enabled = status == PushEnrollmentStatus.enabled;
        final unsupported = status == PushEnrollmentStatus.unsupported;
        final title = enabled
            ? 'Notifications are ready'
            : unsupported
            ? 'Notifications are unavailable'
            : 'Turn on notifications';
        final subtitle = enabled
            ? 'Messages, alerts, assessments and incoming calls can reach this device.'
            : unsupported
            ? 'This browser or device does not support push notifications.'
            : 'Allow alerts so important messages and incoming calls are easier to notice.';
        return Semantics(
          container: true,
          label: '$title. $subtitle',
          child: _GlassSurface(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconBadge(
                  icon: enabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  color: enabled ? AppColors.success : AppColors.vibeBlue,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle),
                      if (!enabled && !unsupported) ...[
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _working ? null : _enable,
                          icon: _working
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.notifications_active_outlined),
                          label: Text(_working ? 'Checking…' : 'Enable alerts'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActiveDevicesCard extends StatefulWidget {
  const _ActiveDevicesCard();

  @override
  State<_ActiveDevicesCard> createState() => _ActiveDevicesCardState();
}

class _ActiveDevicesCardState extends State<_ActiveDevicesCard> {
  late Future<List<PushDeviceRegistration>> _devices;
  String? _removingId;

  @override
  void initState() {
    super.initState();
    _devices = PushNotificationService.activeDevices();
  }

  void _refresh() {
    setState(() => _devices = PushNotificationService.activeDevices());
  }

  Future<void> _remove(PushDeviceRegistration device) async {
    if (_removingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this device?'),
        content: Text(
          device.current
              ? 'This device will stop receiving OG Vibes notifications until notifications are enabled again.'
              : 'This device will stop receiving OG Vibes notifications and incoming call alerts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep device'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removingId = device.id);
    try {
      await PushNotificationService.removeDevice(device.id);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device removed from notifications.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove this device. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconBadge(icon: Icons.devices_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active devices',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Devices currently registered for your alerts and incoming calls.',
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh devices',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<PushDeviceRegistration>>(
            future: _devices,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              if (snapshot.hasError) {
                return const Text(
                  'Active devices could not be loaded. Pull to refresh or try again later.',
                );
              }
              final devices = snapshot.data ?? const [];
              if (devices.isEmpty) {
                return const Text(
                  'No notification-enabled devices are registered yet.',
                );
              }
              return Column(
                children: [
                  for (var index = 0; index < devices.length; index++) ...[
                    _DeviceRow(
                      device: devices[index],
                      removing: _removingId == devices[index].id,
                      onRemove: () => _remove(devices[index]),
                    ),
                    if (index != devices.length - 1) const Divider(height: 22),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.removing,
    required this.onRemove,
  });

  final PushDeviceRegistration device;
  final bool removing;
  final VoidCallback onRemove;

  String get _lastSeen {
    final value = device.lastSeenAt?.toLocal();
    if (value == null) return 'Recently active';
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inMinutes < 2) return 'Active now';
    if (difference.inHours < 1) return 'Active ${difference.inMinutes} min ago';
    if (difference.inDays < 1) return 'Active ${difference.inHours} hr ago';
    return 'Active ${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context) {
    final web = device.platform == 'web';
    return Row(
      children: [
        Icon(
          web ? Icons.language_rounded : Icons.phone_android_rounded,
          color: AppColors.vibeBlue,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                web ? 'Web or installed PWA' : 'Android app',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                device.current ? 'This device · $_lastSeen' : _lastSeen,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Remove device',
          onPressed: removing ? null : onRemove,
          icon: removing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 11),
      itemBuilder: (_, index) => children[index],
    );
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.vibeBlue;
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: _GlassSurface(
        padding: EdgeInsets.zero,
        child: ListTile(
          minVerticalPadding: 15,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 5,
          ),
          leading: _IconBadge(icon: icon, color: color),
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: danger ? AppColors.danger : null,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null) ...[
                _Pill(label: badge!, danger: danger),
                const SizedBox(width: 8),
              ],
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({
    required this.eyebrow,
    required this.title,
    required this.description,
  });
  final String eyebrow;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: AppColors.vibeBlue,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 5),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(description, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.danger = false});
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
    child: Text(
      label,
      style: TextStyle(
        color: danger ? AppColors.danger : AppColors.textMuted,
        fontWeight: FontWeight.w800,
        fontSize: 11,
        letterSpacing: 1.15,
      ),
    ),
  );
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 22,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.outline,
        ),
        boxShadow: AppStyles.softShadow,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, this.color = AppColors.vibeBlue});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, color: color),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.danger = false});
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.vibeBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) => _GlassSurface(
    child: Row(
      children: [
        Expanded(
          child: Container(
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: const Center(
              child: _PreviewMark(label: 'LIGHT', dark: false),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 88,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.canvasDark, AppColors.surfaceDark],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Center(child: _PreviewMark(label: 'DARK', dark: true)),
          ),
        ),
      ],
    ),
  );
}

class _PreviewMark extends StatelessWidget {
  const _PreviewMark({required this.label, required this.dark});
  final String label;
  final bool dark;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const _BrandMark(size: 28),
      const SizedBox(height: 6),
      Text(
        label,
        style: TextStyle(
          color: dark ? Colors.white : AppColors.midnightInk,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 1,
        ),
      ),
    ],
  );
}

class _MotionNotice extends StatelessWidget {
  const _MotionNotice();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AccessibilityPreferences.reduceMotion,
      builder: (context, reduced, _) => _GlassSurface(
        child: Row(
          children: [
            _IconBadge(
              icon: reduced ? Icons.motion_photos_off : Icons.animation_rounded,
              color: AppColors.success,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reduce motion',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    reduced
                        ? 'Extra movement and transitions are minimised.'
                        : 'Turn this on for calmer transitions across OG Vibes.',
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: reduced,
              onChanged: AccessibilityPreferences.setReduceMotion,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyPromise extends StatelessWidget {
  const _PrivacyPromise();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: AppStyles.bentoRadius,
      gradient: LinearGradient(
        colors: [
          AppColors.vibeBlue.withValues(alpha: 0.13),
          AppColors.electricCyan.withValues(alpha: 0.10),
        ],
      ),
      border: Border.all(color: AppColors.vibeBlue.withValues(alpha: 0.18)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined, color: AppColors.vibeBlue),
        SizedBox(width: 14),
        Expanded(
          child: Text(
            'Your private conversations and account controls remain protected by authenticated database policies.',
          ),
        ),
      ],
    ),
  );
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile, required this.loading});
  final _SettingsProfile profile;
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
    width: 78,
    height: 78,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.electricCyan, width: 2),
      color: Colors.white.withValues(alpha: 0.12),
    ),
    child: ClipOval(
      child: loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : profile.photoUrl.isNotEmpty
          ? Image.network(
              profile.photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _Initials(),
            )
          : const _Initials(),
    ),
  );
}

class _Initials extends StatelessWidget {
  const _Initials();
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white.withValues(alpha: 0.12),
    alignment: Alignment.center,
    child: const Icon(Icons.person_rounded, color: Colors.white, size: 34),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        colors: [AppColors.electricCyan, AppColors.vibeBlue],
      ),
    ),
    child: Icon(Icons.bolt_rounded, size: size * 0.62, color: Colors.white),
  );
}

class _HeroStatusPill extends StatelessWidget {
  const _HeroStatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 290),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.electricCyan),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SettingsProfile {
  const _SettingsProfile({
    required this.name,
    required this.studentNumber,
    required this.campus,
    required this.department,
    required this.level,
    required this.photoUrl,
    required this.email,
  });

  const _SettingsProfile.guest()
    : name = 'OG Vibes Student',
      studentNumber = '',
      campus = 'Student community',
      department = '',
      level = '',
      photoUrl = '',
      email = '';

  factory _SettingsProfile.from(Map<String, dynamic>? row, User user) {
    String value(String key) => row?[key]?.toString().trim() ?? '';
    final nickname = value('nickname');
    final metadataNickname =
        user.userMetadata?['nickname']?.toString().trim() ?? '';
    return _SettingsProfile(
      name: nickname.isNotEmpty
          ? nickname
          : metadataNickname.isNotEmpty
          ? metadataNickname
          : 'OG Vibester',
      studentNumber: value('student_number'),
      campus: value('campus'),
      department: value('department'),
      level: value('level'),
      photoUrl: value('photo_url'),
      email: user.email?.trim() ?? '',
    );
  }

  final String name;
  final String studentNumber;
  final String campus;
  final String department;
  final String level;
  final String photoUrl;
  final String email;

  String get initials {
    final parts = name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }

  String get summary {
    final details = [
      if (studentNumber.isNotEmpty) studentNumber,
      if (campus.isNotEmpty) campus,
      if (department.isNotEmpty) department,
      if (level.isNotEmpty) 'Level $level',
    ];
    return details.isEmpty ? 'Your student account' : details.join(' · ');
  }
}
