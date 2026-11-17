import 'package:flutter/material.dart';

import 'academic_escalation_screen.dart';
import 'bursary_screen.dart';
import 'campus_events_screen.dart';
import 'campus_map_screen.dart';
import 'checklist_screen.dart';
import 'course_mate_screen.dart';
import 'course_portal_screen.dart';
import 'digital_library_screen.dart';
import 'exam_readiness_screen.dart';
import 'exam_timetable_screen.dart';
import 'flashcards_screen.dart';
import 'grade_appeal_screen.dart';
import 'lesson_player_screen.dart';
import 'lift_club_screen.dart';
import 'lms_dashboard_screen.dart';
import 'mark_simulator_screen.dart';
import 'miss_mr_vibes_screen.dart';
import 'my_campus_friends_screen.dart';
import 'no_connection_screen.dart';
import 'notification_settings_screen.dart';
import 'nsfas_check_screen.dart';
import 'offline_downloader_screen.dart';
import 'privacy_screen.dart';
import 'product_details_screen.dart';
import 'rewards_screen.dart';
import 'src_help_desk_screen.dart';
import 'student_analytics_dashboard.dart';
import 'study_group_finder_screen.dart';
import 'study_resources_screen.dart';
import 'trivia_game_screen.dart';
import 'tutor_application_screen.dart';
import 'tutor_directory_screen.dart';
import 'video_tutorials_screen.dart';

class AllToolsScreen extends StatelessWidget {
  const AllToolsScreen({super.key});

  static final List<_ToolLink> _tools = [
    _ToolLink(
      'Academic escalation',
      Icons.support_agent,
      const AcademicEscalationScreen(),
    ),
    _ToolLink('Bursaries', Icons.account_balance, const BursaryScreen()),
    _ToolLink('Campus events', Icons.event, const CampusEventsScreen()),
    _ToolLink('Campus map', Icons.map, const CampusMapScreen()),
    _ToolLink('Student checklist', Icons.checklist, const ChecklistScreen()),
    _ToolLink('Find a course mate', Icons.people_alt, const CourseMateScreen()),
    _ToolLink(
      'Course portal',
      Icons.school,
      const CoursePortalScreen(courseName: 'General Studies'),
    ),
    _ToolLink(
      'Digital library',
      Icons.local_library,
      const DigitalLibraryScreen(),
    ),
    _ToolLink('Exam readiness', Icons.fact_check, const ExamReadinessScreen()),
    _ToolLink(
      'Exam seat plan',
      Icons.event_seat,
      const ExamTimetableSeatPlanScreen(),
    ),
    _ToolLink('Flashcards', Icons.style, const FlashcardsScreen()),
    _ToolLink('Grade appeal', Icons.edit_note, const GradeAppealScreen()),
    _ToolLink(
      'Lesson player',
      Icons.play_lesson,
      const LessonPlayerScreen(
        courseName: 'General Studies',
        lessonTitle: 'Course lessons',
        lessonDescription: 'Browse lessons and study material.',
      ),
    ),
    _ToolLink('Lift club', Icons.directions_car, const LiftClubScreen()),
    _ToolLink(
      'Learning dashboard',
      Icons.dashboard,
      const LmsDashboardScreen(),
    ),
    _ToolLink('Mark simulator', Icons.calculate, const MarkSimulatorScreen()),
    _ToolLink('Miss & Mr Vibes', Icons.emoji_events, const MissMrVibesScreen()),
    _ToolLink('Campus friends', Icons.group, const MyCampusFriendsScreen()),
    _ToolLink('Connection help', Icons.wifi_off, const NoConnectionScreen()),
    _ToolLink(
      'Notification settings',
      Icons.notifications,
      const NotificationSettingsScreen(),
    ),
    _ToolLink('NSFAS checker', Icons.payments, const NsfasCheckScreen()),
    _ToolLink(
      'Offline downloads',
      Icons.download,
      const OfflineDownloaderScreen(),
    ),
    _ToolLink('Privacy', Icons.privacy_tip, const PrivacyScreen()),
    _ToolLink(
      'Product details',
      Icons.shopping_bag,
      const ProductDetailsScreen(),
    ),
    _ToolLink('Campus rewards', Icons.card_giftcard, const RewardsScreen()),
    _ToolLink('SRC help desk', Icons.forum, const SrcHelpDeskScreen()),
    _ToolLink(
      'Student analytics',
      Icons.insights,
      const StudentAnalyticsDashboard(),
    ),
    _ToolLink('Study groups', Icons.groups, const StudyGroupFinderScreen()),
    _ToolLink('Study resources', Icons.menu_book, const StudyResourcesScreen()),
    _ToolLink('Trivia game', Icons.quiz, const TriviaGameScreen()),
    _ToolLink(
      'Tutor application',
      Icons.assignment_ind,
      const TutorApplicationScreen(),
    ),
    _ToolLink(
      'Find a tutor',
      Icons.person_search,
      const TutorDirectoryScreen(),
    ),
    _ToolLink(
      'Video tutorials',
      Icons.video_library,
      const VideoTutorialsScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Campus features')),
    body: GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        mainAxisExtent: 106,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _tools.length,
      itemBuilder: (context, index) {
        final tool = _tools[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(
              context,
            ).push<void>(MaterialPageRoute<void>(builder: (_) => tool.screen)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(tool.icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tool.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _ToolLink {
  const _ToolLink(this.title, this.icon, this.screen);

  final String title;
  final IconData icon;
  final Widget screen;
}
