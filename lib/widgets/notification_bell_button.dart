import 'package:flutter/material.dart';

import '../screens/notification_center_screen.dart';
import '../services/notification_badge_service.dart';

class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key, this.onDarkSurface = false});

  final bool onDarkSurface;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<NotificationBadgeCounts>(
      stream: NotificationBadgeService.instance.stream,
      builder: (context, snapshot) {
        final unread = snapshot.data?.notifications ?? 0;
        return Semantics(
          button: true,
          label: unread == 0
              ? 'Open notifications'
              : 'Open notifications. $unread unread',
          child: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            backgroundColor: Theme.of(context).colorScheme.error,
            child: IconButton(
              tooltip: 'Notifications',
              style: IconButton.styleFrom(
                minimumSize: const Size.square(48),
                backgroundColor: onDarkSurface
                    ? Colors.white.withValues(alpha: .13)
                    : Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: onDarkSurface
                    ? Colors.white
                    : Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationCenterScreen(),
                ),
              ),
              icon: const Icon(Icons.notifications_rounded),
            ),
          ),
        );
      },
    );
  }
}
