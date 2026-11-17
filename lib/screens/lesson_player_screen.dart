import 'package:flutter/material.dart';

class LessonPlayerScreen extends StatefulWidget {
  const LessonPlayerScreen({
    super.key,
    required this.courseName,
    required this.lessonTitle,
    required this.lessonDescription,
  });

  final String courseName;
  final String lessonTitle;
  final String lessonDescription;

  @override
  State<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends State<LessonPlayerScreen> {
  bool _isCompleted = false;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          title: Text(
            widget.courseName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: Column(
          children: [
            _VideoPreview(lessonTitle: widget.lessonTitle),
            Container(
              color: Colors.white,
              child: const TabBar(
                labelColor: Color(0xFF0F172A),
                unselectedLabelColor: Color(0xFF64748B),
                indicatorColor: Color(0xFF2563EB),
                indicatorWeight: 3,
                tabs: [
                  Tab(text: 'Overview'),
                  Tab(text: 'Resources'),
                  Tab(text: 'Discussion'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _OverviewTab(
                    lessonTitle: widget.lessonTitle,
                    lessonDescription: widget.lessonDescription,
                    isCompleted: _isCompleted,
                    onMarkComplete: () {
                      setState(() {
                        _isCompleted = !_isCompleted;
                      });
                    },
                  ),
                  const _ResourcesTab(),
                  const _DiscussionTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({required this.lessonTitle});

  final String lessonTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x290F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF0B1020).withOpacity(0.2),
                          const Color(0xFF0B1020).withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                ),
                const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white,
                    size: 74,
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Text(
                    lessonTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: 14.0 / 45.0,
                          minHeight: 5,
                          backgroundColor: const Color(0x4DFFFFFF),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF3B82F6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '14:20 / 45:00',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.lessonTitle,
    required this.lessonDescription,
    required this.isCompleted,
    required this.onMarkComplete,
  });

  final String lessonTitle;
  final String lessonDescription;

  final bool isCompleted;
  final VoidCallback onMarkComplete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lessonTitle,
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                lessonDescription,
                style: TextStyle(
                  color: Color(0xFF475569),
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onMarkComplete,
                  icon: Icon(
                    isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.done_rounded,
                  ),
                  label: Text(
                    isCompleted ? 'Completed' : 'Mark as Completed',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    backgroundColor: isCompleted
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResourcesTab extends StatelessWidget {
  const _ResourcesTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: const [
        _ResourceCard(
          title: 'Limits_Slides.pdf',
          subtitle: 'Lecture slides • 2.3 MB',
        ),
      ],
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: const CircleAvatar(
          radius: 19,
          backgroundColor: Color(0xFFEFF6FF),
          child: Icon(Icons.description_rounded, color: Color(0xFF1D4ED8)),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: IconButton(
          onPressed: () {},
          icon: const Icon(Icons.download_rounded, color: Color(0xFF0F172A)),
          tooltip: 'Download',
        ),
      ),
    );
  }
}

class _DiscussionTab extends StatelessWidget {
  const _DiscussionTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: const [
        _DiscussionBubble(
          author: 'Sipho',
          role: 'Student',
          message: 'At 12:45, why did the sign change?',
          tint: Color(0xFFEFF6FF),
          accent: Color(0xFF1D4ED8),
        ),
        SizedBox(height: 10),
        _DiscussionBubble(
          author: 'Mr. Nkosi',
          role: 'Lecturer',
          message:
              'Great question. The sign flips after factoring out a negative term from the denominator.',
          tint: Color(0xFFF0FDF4),
          accent: Color(0xFF166534),
        ),
      ],
    );
  }
}

class _DiscussionBubble extends StatelessWidget {
  const _DiscussionBubble({
    required this.author,
    required this.role,
    required this.message,
    required this.tint,
    required this.accent,
  });

  final String author;
  final String role;
  final String message;
  final Color tint;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                author,
                style: TextStyle(color: accent, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Text(
                role,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
