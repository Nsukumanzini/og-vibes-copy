import 'package:flutter/material.dart';

import 'package:og_vibes_student/utils/custom_ui_components.dart';
import 'package:og_vibes_student/utils/theme_constants.dart';

class LmsDashboardScreen extends StatelessWidget {
  const LmsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color pageBackground = isDark
        ? AppColors.backgroundDark
        : AppColors.backgroundLight;
    final Color primaryText = isDark
        ? AppColors.crispWhite
        : AppColors.navyBlue;
    final Color secondaryText = isDark
        ? AppColors.slateGrey
        : AppColors.slateGrey.withValues(alpha: 0.9);

    return Scaffold(
      backgroundColor: pageBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: pageBackground.withValues(alpha: 0.92),
            surfaceTintColor: Colors.transparent,
            titleSpacing: 8,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).pop(),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: AppColors.crispWhite.withValues(
                        alpha: isDark ? 0.08 : 0.95,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.slateGrey.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: primaryText,
                    ),
                  ),
                ),
              ),
            ),
            title: Text(
              'OG Scholar Enterprise',
              style: TextStyle(
                color: primaryText,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.deepBlue.withValues(alpha: 0.14),
                  child: Icon(Icons.person_outline_rounded, color: primaryText),
                ),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            sliver: SliverToBoxAdapter(
              child: Text(
                'My Enrolled Modules',
                style: TextStyle(
                  color: primaryText,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 228,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: const <Widget>[
                  _ModuleCard(
                    title: 'Mathematics N4',
                    subtitle: 'Next: Calculus Task',
                    progress: 0.45,
                    backgroundColor: AppColors.deepBlue,
                    progressColor: AppColors.ogGold,
                  ),
                  SizedBox(width: 14),
                  _ModuleCard(
                    title: 'Computer Practice N4',
                    subtitle: 'Next: ISAT Prep',
                    progress: 0.80,
                    backgroundColor: AppColors.slateGrey,
                    progressColor: AppColors.ogGold,
                  ),
                  SizedBox(width: 4),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Urgent Deadlines & Updates',
                style: TextStyle(
                  color: primaryText,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
            sliver: SliverList.list(
              children: <Widget>[
                _ActivityItem(
                  color: AppColors.deepBlue,
                  iconText: '??',
                  message: 'Urgent: ICASS Task 2 Due Tomorrow at 23:59',
                  textColor: primaryText,
                  subtitleColor: secondaryText,
                  trailing: Align(
                    alignment: Alignment.centerLeft,
                    child: PrimaryHapticButton(
                      label: 'Go to Assignment',
                      icon: Icons.assignment_turned_in_outlined,
                      onPressed: () {},
                      color: AppColors.deepBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _ActivityItem(
                  color: Color(0xFF22C55E),
                  iconText: '??',
                  message: 'Grade Posted: Entrepreneurship Quiz 1 - 85%',
                  textColor: primaryText,
                  subtitleColor: secondaryText,
                ),
                const SizedBox(height: 12),
                _ActivityItem(
                  color: Color(0xFF3B82F6),
                  iconText: '??',
                  message:
                      'Announcement: Mr. Nkosi posted a new Calculus video.',
                  textColor: primaryText,
                  subtitleColor: secondaryText,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
  });

  final String title;
  final String subtitle;
  final double progress;
  final Color backgroundColor;
  final Color progressColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: BentoCard(
        color: backgroundColor,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                color: AppColors.crispWhite,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.26),
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${(progress * 100).toStringAsFixed(0)}% complete',
              style: TextStyle(
                color: AppColors.crispWhite.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: AppColors.crispWhite.withValues(alpha: 0.88),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  const _ActivityItem({
    required this.color,
    required this.iconText,
    required this.message,
    required this.textColor,
    required this.subtitleColor,
    this.trailing,
  });

  final Color color;
  final String iconText;
  final String message;
  final Color textColor;
  final Color subtitleColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return BentoCard(
      color: isDark
          ? AppColors.navyBlue.withValues(alpha: 0.88)
          : AppColors.crispWhite,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(iconText, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 4,
            width: 92,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Stay in sync with your course timeline.',
            style: TextStyle(
              color: subtitleColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(height: 14),
            trailing!,
          ],
        ],
      ),
    );
  }
}
