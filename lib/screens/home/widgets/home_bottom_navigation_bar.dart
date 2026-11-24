import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../utils/theme_constants.dart';
import '../../../services/notification_badge_service.dart';

class HomeBottomNavigationBar extends StatelessWidget {
  const HomeBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = <({IconData icon, IconData active, String label})>[
    (
      icon: Icons.dynamic_feed_outlined,
      active: Icons.dynamic_feed_rounded,
      label: 'Feed',
    ),
    (
      icon: Icons.dashboard_customize_outlined,
      active: Icons.dashboard_customize_rounded,
      label: 'Academic',
    ),
    (
      icon: Icons.notifications_none_rounded,
      active: Icons.notifications_rounded,
      label: 'Alerts',
    ),
    (
      icon: Icons.school_outlined,
      active: Icons.school_rounded,
      label: 'Campus',
    ),
    (
      icon: Icons.chat_bubble_outline_rounded,
      active: Icons.chat_bubble_rounded,
      label: 'Chats',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return StreamBuilder<NotificationBadgeCounts>(
      stream: NotificationBadgeService.instance.stream,
      builder: (context, snapshot) {
        final counts = snapshot.data ?? const NotificationBadgeCounts();
        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 72,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                decoration: BoxDecoration(
                  color: (dark ? const Color(0xFF07172F) : Colors.white)
                      .withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: dark ? Colors.white12 : const Color(0xFFE8F0FF),
                  ),
                  boxShadow: AppStyles.glassShadow,
                ),
                child: Row(
                  children: List.generate(_items.length, (index) {
                    final item = _items[index];
                    final selected = index == currentIndex;
                    final alerts = index == 2;
                    final hasUnreadAlerts = alerts && counts.alerts > 0;
                    final iconSize = alerts ? 28.0 : 23.0;
                    return Expanded(
                      child: Semantics(
                        selected: selected,
                        button: true,
                        label: item.label,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => onTap(index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.vibeBlue.withValues(alpha: .11)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedScale(
                                  scale: selected ? (alerts ? 1.12 : 1.08) : 1,
                                  duration: const Duration(milliseconds: 220),
                                  child: Badge(
                                    isLabelVisible:
                                        (index == 2
                                            ? counts.alerts
                                            : index == 4
                                            ? counts.chats
                                            : 0) >
                                        0,
                                    label: Text(
                                      '${index == 2 ? counts.alerts : counts.chats}',
                                    ),
                                    backgroundColor: index == 2
                                        ? AppColors.danger
                                        : const Color(0xFF00A67E),
                                    child: Icon(
                                      selected ? item.active : item.icon,
                                      size: iconSize,
                                      color: alerts
                                          ? hasUnreadAlerts
                                                ? AppColors.danger
                                                : selected
                                                ? AppColors.vibeBlue
                                                : AppColors.textMuted
                                          : selected
                                          ? AppColors.vibeBlue
                                          : AppColors.textMuted,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.label,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: selected
                                        ? FontWeight.w900
                                        : FontWeight.w600,
                                    color: selected
                                        ? AppColors.vibeBlue
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
