import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/offline_data_adapter.dart';

import '../screens/profile_screen.dart';
import '../services/push_notification_service.dart';
import '../utils/theme_constants.dart';

/// A short, non-blocking setup checklist for newly created accounts.
class OnboardingChecklistGate extends StatefulWidget {
  const OnboardingChecklistGate({
    super.key,
    required this.child,
    required this.enabled,
  });

  final Widget child;
  final bool enabled;

  @override
  State<OnboardingChecklistGate> createState() =>
      _OnboardingChecklistGateState();
}

class _OnboardingChecklistGateState extends State<OnboardingChecklistGate> {
  StreamSubscription<OfflineAuthState>? _authSubscription;
  bool _checking = false;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    _authSubscription = OfflineData.instance.client.auth.onAuthStateChange.listen(
      (_) => _scheduleCheck(),
    );
    _scheduleCheck();
  }

  void _scheduleCheck() {
    Future<void>.delayed(const Duration(seconds: 2), _check);
  }

  Future<void> _check() async {
    if (!mounted || _checking || _showing || !widget.enabled) return;
    final user = OfflineData.instance.client.auth.currentUser;
    if (user == null) return;
    final createdAt = DateTime.tryParse(user.createdAt)?.toLocal();
    if (createdAt == null ||
        DateTime.now().difference(createdAt) > const Duration(days: 7)) {
      return;
    }

    _checking = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final key = 'og_setup_checklist_${user.id}';
      if (preferences.getBool(key) ?? false) return;
      final profile = await OfflineData.instance.client
          .from('profiles')
          .select('photo_url')
          .eq('id', user.id)
          .maybeSingle();
      final hasPicture =
          (profile?['photo_url']?.toString().trim().isNotEmpty ?? false);
      final notificationStatus =
          await PushNotificationService.enrollmentStatus();
      final notificationsEnabled =
          notificationStatus == PushEnrollmentStatus.enabled;
      if (hasPicture && notificationsEnabled) {
        await preferences.setBool(key, true);
        return;
      }
      if (!mounted) return;
      _showing = true;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => _SetupChecklistSheet(
          hasPicture: hasPicture,
          notificationsEnabled: notificationsEnabled,
          onPicture: () async {
            Navigator.of(sheetContext).pop();
            await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
            );
          },
          onNotifications: () async {
            final enabled =
                await PushNotificationService.requestAndRegisterCurrentDevice();
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                content: Text(
                  enabled
                      ? 'Notifications are ready.'
                      : 'Notifications were not enabled.',
                ),
              ),
            );
          },
          onLater: () async {
            await preferences.setBool(key, true);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          },
        ),
      );
    } catch (_) {
      // Setup assistance must never prevent the app from opening.
    } finally {
      _checking = false;
      _showing = false;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SetupChecklistSheet extends StatelessWidget {
  const _SetupChecklistSheet({
    required this.hasPicture,
    required this.notificationsEnabled,
    required this.onPicture,
    required this.onNotifications,
    required this.onLater,
  });

  final bool hasPicture;
  final bool notificationsEnabled;
  final VoidCallback onPicture;
  final VoidCallback onNotifications;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Finish setting up OG Vibes',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Two quick steps help classmates recognise you and keep you up to date.',
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 18),
            _ChecklistTile(
              complete: hasPicture,
              icon: Icons.add_a_photo_rounded,
              title: 'Upload a profile picture',
              actionLabel: hasPicture ? 'Done' : 'Add picture',
              onTap: hasPicture ? null : onPicture,
            ),
            const SizedBox(height: 10),
            _ChecklistTile(
              complete: notificationsEnabled,
              icon: Icons.notifications_active_rounded,
              title: 'Enable notifications',
              actionLabel: notificationsEnabled ? 'Done' : 'Enable',
              onTap: notificationsEnabled ? null : onNotifications,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onLater, child: const Text('Later')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({
    required this.complete,
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onTap,
  });

  final bool complete;
  final IconData icon;
  final String title;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      checked: complete,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: complete
              ? AppColors.success.withValues(alpha: .08)
              : AppColors.blueTint,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: complete ? AppColors.success : AppColors.glassBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              complete ? Icons.check_circle_rounded : icon,
              color: complete ? AppColors.success : AppColors.vibeBlue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(onPressed: onTap, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
