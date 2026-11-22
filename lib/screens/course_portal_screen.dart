import 'package:flutter/material.dart';

import 'grade_appeal_screen.dart';
import 'lesson_player_screen.dart';
import 'live_broadcast_screen.dart';
import 'lms_quiz_lockdown_screen.dart';

class CoursePortalScreen extends StatelessWidget {
  const CoursePortalScreen({super.key, required this.courseName});

  final String courseName;

  @override
  Widget build(BuildContext context) {
    final config =
        _coursePortalConfigs[courseName] ??
        _CoursePortalConfig.fallback(courseName);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F9FD),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF07172F),
          title: Text(
            courseName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Color(0xFF07172F),
            unselectedLabelColor: Color(0xFF2457F5),
            indicatorColor: Color(0xFF2457F5),
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'Modules'),
              Tab(text: 'Assessments'),
              Tab(text: 'Grades'),
              Tab(text: 'Announcements'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ModulesTab(config: config),
            _AssessmentsTab(config: config),
            _GradesTab(config: config),
            _AnnouncementsTab(config: config),
          ],
        ),
      ),
    );
  }
}

class _ModulesTab extends StatelessWidget {
  const _ModulesTab({required this.config});

  final _CoursePortalConfig config;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (config.hasLiveBroadcast)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF07172F), Color(0xFF0D47A1)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              leading: const CircleAvatar(
                backgroundColor: Color(0x33FFFFFF),
                child: Icon(Icons.live_tv_rounded, color: Colors.white),
              ),
              title: Text(
                config.liveBannerTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                config.liveBannerSubtitle,
                style: const TextStyle(
                  color: Color(0xFFE8F0FF),
                  fontWeight: FontWeight.w500,
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LiveBroadcastScreen(),
                  ),
                );
              },
            ),
          ),
        Text(
          'Syllabus',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: const Color(0xFF07172F),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        ...config.modules.map(
          (module) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ModuleCard(config: config, module: module),
          ),
        ),
      ],
    );
  }
}

class _AssessmentsTab extends StatelessWidget {
  const _AssessmentsTab({required this.config});

  final _CoursePortalConfig config;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (config.hasSecureQuiz)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LmsQuizLockdownScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.lock_outline_rounded),
              label: Text(config.secureQuizLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF07172F),
                side: const BorderSide(color: Color(0xFFE8F0FF)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ...config.assessments.map(
          (assessment) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AssessmentCard(
              title: assessment.title,
              dueText: assessment.dueText,
              icon: assessment.icon,
            ),
          ),
        ),
      ],
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({
    required this.title,
    required this.dueText,
    required this.icon,
  });

  final String title;
  final String dueText;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8F0FF)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 19,
          backgroundColor: const Color(0xFFE8F0FF),
          child: Icon(icon, color: const Color(0xFF2457F5)),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF07172F),
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          dueText,
          style: const TextStyle(
            color: Color(0xFF2457F5),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _GradesTab extends StatelessWidget {
  const _GradesTab({required this.config});

  final _CoursePortalConfig config;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (config.hasGradeAppeal)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6D6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFC107)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      config.gradeAppealMessage,
                      style: const TextStyle(
                        color: Color(0xFF713F12),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const GradeAppealScreen(),
                        ),
                      );
                    },
                    child: const Text('Appeal'),
                  ),
                ],
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8F0FF)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < config.grades.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Color(0xFFE8F0FF)),
                _GradeListTile(row: config.grades[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AnnouncementsTab extends StatelessWidget {
  const _AnnouncementsTab({required this.config});

  final _CoursePortalConfig config;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: config.announcements
          .map(
            (announcement) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AnnouncementCard(
                title: announcement.title,
                body: announcement.body,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.config, required this.module});

  final _CoursePortalConfig config;
  final _CourseModule module;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8F0FF)),
      ),
      child: ExpansionTile(
        initiallyExpanded: module.initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Text(
          module.title,
          style: const TextStyle(
            color: Color(0xFF07172F),
            fontWeight: FontWeight.w700,
          ),
        ),
        children: module.items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ModuleItemCard(config: config, item: item),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ModuleItemCard extends StatelessWidget {
  const _ModuleItemCard({required this.config, required this.item});

  final _CoursePortalConfig config;
  final _ModuleItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: item.isVideo
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LessonPlayerScreen(
                    courseName: config.courseName,
                    lessonTitle: item.title,
                    lessonDescription: item.description,
                  ),
                ),
              );
            }
          : null,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FD),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8F0FF)),
        ),
        child: Row(
          children: [
            Icon(item.icon, color: item.iconColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                style: const TextStyle(
                  color: Color(0xFF0D47A1),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (item.isVideo)
              const Icon(
                Icons.open_in_new_rounded,
                color: Color(0xFF2457F5),
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

class _GradeListTile extends StatelessWidget {
  const _GradeListTile({required this.row});

  final _GradeRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.label,
              style: const TextStyle(
                color: Color(0xFF07172F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              row.value,
              style: const TextStyle(
                color: Color(0xFF166534),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8F0FF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF07172F),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(color: Color(0xFF2457F5), height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeRow {
  const _GradeRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _CoursePortalConfig {
  const _CoursePortalConfig({
    required this.courseName,
    required this.hasLiveBroadcast,
    required this.liveBannerTitle,
    required this.liveBannerSubtitle,
    required this.hasSecureQuiz,
    required this.secureQuizLabel,
    required this.hasGradeAppeal,
    required this.gradeAppealMessage,
    required this.modules,
    required this.assessments,
    required this.grades,
    required this.announcements,
  });

  factory _CoursePortalConfig.fallback(String courseName) {
    return _CoursePortalConfig(
      courseName: courseName,
      hasLiveBroadcast: false,
      liveBannerTitle: '',
      liveBannerSubtitle: '',
      hasSecureQuiz: false,
      secureQuizLabel: 'Open Secure Assessment Space',
      hasGradeAppeal: false,
      gradeAppealMessage: '',
      modules: const [
        _CourseModule(
          title: 'Week 1: Orientation',
          initiallyExpanded: true,
          items: [
            _ModuleItem.video(
              title: 'Lecture 1: Course Overview',
              description:
                  'This lesson introduces the module structure, grading model, and expected learning outcomes.',
            ),
            _ModuleItem.document(title: 'Course Outline.pdf'),
          ],
        ),
      ],
      assessments: const [
        _AssessmentInfo(
          title: 'Diagnostic Activity',
          dueText: 'Due next week',
          icon: Icons.assignment_rounded,
        ),
      ],
      grades: const [_GradeRow(label: 'Orientation Task', value: 'Pending')],
      announcements: const [
        _AnnouncementInfo(
          title: 'Course Opened',
          body: 'Your course workspace is active and ready for study.',
        ),
      ],
    );
  }

  final String courseName;
  final bool hasLiveBroadcast;
  final String liveBannerTitle;
  final String liveBannerSubtitle;
  final bool hasSecureQuiz;
  final String secureQuizLabel;
  final bool hasGradeAppeal;
  final String gradeAppealMessage;
  final List<_CourseModule> modules;
  final List<_AssessmentInfo> assessments;
  final List<_GradeRow> grades;
  final List<_AnnouncementInfo> announcements;
}

class _CourseModule {
  const _CourseModule({
    required this.title,
    required this.items,
    this.initiallyExpanded = false,
  });

  final String title;
  final bool initiallyExpanded;
  final List<_ModuleItem> items;
}

class _ModuleItem {
  const _ModuleItem._({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.isVideo,
  });

  const _ModuleItem.video({required String title, required String description})
    : this._(
        title: title,
        description: description,
        icon: Icons.videocam_rounded,
        iconColor: const Color(0xFF2457F5),
        isVideo: true,
      );

  const _ModuleItem.document({required String title})
    : this._(
        title: title,
        description: '',
        icon: Icons.picture_as_pdf_rounded,
        iconColor: const Color(0xFFDC2626),
        isVideo: false,
      );

  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final bool isVideo;
}

class _AssessmentInfo {
  const _AssessmentInfo({
    required this.title,
    required this.dueText,
    required this.icon,
  });

  final String title;
  final String dueText;
  final IconData icon;
}

class _AnnouncementInfo {
  const _AnnouncementInfo({required this.title, required this.body});

  final String title;
  final String body;
}

const Map<String, _CoursePortalConfig> _coursePortalConfigs = {
  'Mathematics N4': _CoursePortalConfig(
    courseName: 'Mathematics N4',
    hasLiveBroadcast: true,
    liveBannerTitle: 'Live calculus lecture in progress',
    liveBannerSubtitle: 'Join the broadcast and continue attendance tracking.',
    hasSecureQuiz: true,
    secureQuizLabel: 'Open Secure Quiz Environment',
    hasGradeAppeal: false,
    gradeAppealMessage: '',
    modules: [
      _CourseModule(
        title: 'Week 1: Introduction to Calculus',
        initiallyExpanded: true,
        items: [
          _ModuleItem.video(
            title: 'Lecture 1: Introduction to Limits',
            description:
                'In this lesson, we cover the foundational rules of calculus limits and how to apply them to basic algebraic functions.',
          ),
          _ModuleItem.document(title: 'Limits Cheat Sheet.pdf'),
        ],
      ),
      _CourseModule(
        title: 'Week 2: Derivatives',
        items: [
          _ModuleItem.video(
            title: 'Lecture 2: Derivative Basics',
            description:
                'This lesson introduces first derivatives, notation, and the basic rules used to differentiate algebraic expressions.',
          ),
        ],
      ),
    ],
    assessments: [
      _AssessmentInfo(
        title: 'ICASS Task 1',
        dueText: 'Due April 15',
        icon: Icons.assignment_rounded,
      ),
      _AssessmentInfo(
        title: 'Online Quiz 1',
        dueText: 'Closes Friday',
        icon: Icons.quiz_rounded,
      ),
    ],
    grades: [
      _GradeRow(label: 'Assignment 1', value: '85%'),
      _GradeRow(label: 'Quiz 1', value: '90%'),
      _GradeRow(label: 'Current DP Mark', value: '87.5%'),
    ],
    announcements: [
      _AnnouncementInfo(
        title: 'Welcome to the Course',
        body:
            'Please review Week 1 resources and complete the orientation checklist by Monday.',
      ),
      _AnnouncementInfo(
        title: 'Consultation Hours',
        body:
            'Lecturer consultation is available every Wednesday from 14:00 to 16:00.',
      ),
    ],
  ),
  'Computer Practice N4': _CoursePortalConfig(
    courseName: 'Computer Practice N4',
    hasLiveBroadcast: true,
    liveBannerTitle: 'Lab support session is live',
    liveBannerSubtitle:
        'Open the practical walkthrough and log your session attendance.',
    hasSecureQuiz: false,
    secureQuizLabel: 'Open Secure Assessment Space',
    hasGradeAppeal: false,
    gradeAppealMessage: '',
    modules: [
      _CourseModule(
        title: 'Week 1: Lab Orientation',
        initiallyExpanded: true,
        items: [
          _ModuleItem.video(
            title: 'Lecture 1: ISAT Workstation Setup',
            description:
                'This lesson covers workstation preparation, folder structures, and safe file handling for practical assessments.',
          ),
          _ModuleItem.document(title: 'Lab Rules and Checklist.pdf'),
        ],
      ),
      _CourseModule(
        title: 'Week 2: Productivity Tools',
        items: [
          _ModuleItem.video(
            title: 'Lecture 2: Spreadsheet Essentials',
            description:
                'This lesson introduces formulas, formatting workflows, and the spreadsheet operations required in timed practicals.',
          ),
        ],
      ),
    ],
    assessments: [
      _AssessmentInfo(
        title: 'ISAT Practical Draft',
        dueText: 'Due in 3 days',
        icon: Icons.computer_rounded,
      ),
      _AssessmentInfo(
        title: 'Keyboard Speed Check',
        dueText: 'Opens tomorrow',
        icon: Icons.keyboard_rounded,
      ),
    ],
    grades: [
      _GradeRow(label: 'Practical 1', value: '78%'),
      _GradeRow(label: 'Spreadsheet Drill', value: '84%'),
      _GradeRow(label: 'Current DP Mark', value: '81.0%'),
    ],
    announcements: [
      _AnnouncementInfo(
        title: 'Lab Booking Reminder',
        body:
            'Please confirm your computer lab slot before Friday practical sessions.',
      ),
      _AnnouncementInfo(
        title: 'USB Policy Update',
        body:
            'External storage devices must be scanned before use in the campus lab.',
      ),
    ],
  ),
  'Entrepreneurship N4': _CoursePortalConfig(
    courseName: 'Entrepreneurship N4',
    hasLiveBroadcast: false,
    liveBannerTitle: '',
    liveBannerSubtitle: '',
    hasSecureQuiz: false,
    secureQuizLabel: 'Open Secure Assessment Space',
    hasGradeAppeal: true,
    gradeAppealMessage:
        'Need a formal review of this result? Start the grade dispute workflow.',
    modules: [
      _CourseModule(
        title: 'Week 1: Opportunity Recognition',
        initiallyExpanded: true,
        items: [
          _ModuleItem.video(
            title: 'Lecture 1: Evaluating Business Ideas',
            description:
                'This lesson focuses on identifying viable opportunities, customer pain points, and sustainable value propositions.',
          ),
          _ModuleItem.document(title: 'Idea Validation Canvas.pdf'),
        ],
      ),
      _CourseModule(
        title: 'Week 2: Business Model Planning',
        items: [
          _ModuleItem.video(
            title: 'Lecture 2: Revenue Model Design',
            description:
                'This lesson explores revenue streams, cost structure planning, and pricing assumptions for startup proposals.',
          ),
        ],
      ),
    ],
    assessments: [
      _AssessmentInfo(
        title: 'Business Plan Draft',
        dueText: 'Feedback released',
        icon: Icons.description_rounded,
      ),
      _AssessmentInfo(
        title: 'Market Research Pitch',
        dueText: 'Due next Tuesday',
        icon: Icons.campaign_rounded,
      ),
    ],
    grades: [
      _GradeRow(label: 'Business Plan Draft', value: '45%'),
      _GradeRow(label: 'Pitch Outline', value: '71%'),
      _GradeRow(label: 'Current DP Mark', value: '58.0%'),
    ],
    announcements: [
      _AnnouncementInfo(
        title: 'Rubric Clarification Posted',
        body:
            'A revised marking memo for the business plan draft is now available under resources.',
      ),
      _AnnouncementInfo(
        title: 'Guest Founder Session',
        body:
            'An industry entrepreneur will join next week to review student venture concepts.',
      ),
    ],
  ),
};
