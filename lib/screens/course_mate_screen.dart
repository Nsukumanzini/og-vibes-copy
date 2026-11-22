import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class CourseMateScreen extends StatefulWidget {
  const CourseMateScreen({super.key});

  @override
  State<CourseMateScreen> createState() => _CourseMateScreenState();
}

class _CourseMateScreenState extends State<CourseMateScreen> {
  late Future<List<_StudyGroup>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _loadGroups();
  }

  Future<List<_StudyGroup>> _loadGroups() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    return const [
      _StudyGroup(
        name: 'N4 Maths Night Owls',
        members: '4/6',
        focus: 'Past Papers',
        meeting: 'Library / WhatsApp',
        accent: Color(0xFF2457F5),
      ),
      _StudyGroup(
        name: 'Mech Draughting Distinction Seekers',
        members: '2/5',
        focus: 'Assignments & PoE',
        meeting: 'IT Lab',
        accent: Color(0xFF2E7D32),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Course Mate')),
      body: FutureBuilder<List<_StudyGroup>>(
        future: _groupsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingState();
          }

          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _groupsFuture = _loadGroups();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry loading groups'),
              ),
            );
          }

          final groups = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              _buildTopBanner(),
              const SizedBox(height: 14),
              ...groups.map(
                (group) => _CourseGroupCard(
                  group: group,
                  onJoin: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Join request sent to Group Admin! 📚'),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2457F5), Color(0xFF2457F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2457F5).withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: const [
          Icon(Icons.groups_2_rounded, color: Colors.white, size: 30),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Find Your Study Squad for N4 Engineering',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: [
            Container(
              height: 122,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 168,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 168,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseGroupCard extends StatelessWidget {
  const _CourseGroupCard({required this.group, required this.onJoin});

  final _StudyGroup group;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: group.accent.withValues(alpha: 0.24),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.name,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF07172F),
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.people_alt_outlined,
            label: 'Members',
            value: group.members,
          ),
          const SizedBox(height: 6),
          _InfoRow(
            icon: Icons.track_changes_outlined,
            label: 'Focus',
            value: group.focus,
          ),
          const SizedBox(height: 6),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: 'Meeting',
            value: group.meeting,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: group.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text(
                'Request to Join',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2457F5)),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Color(0xFF0D47A1),
                fontSize: 13,
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StudyGroup {
  const _StudyGroup({
    required this.name,
    required this.members,
    required this.focus,
    required this.meeting,
    required this.accent,
  });

  final String name;
  final String members;
  final String focus;
  final String meeting;
  final Color accent;
}
