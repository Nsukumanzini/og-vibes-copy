import 'package:flutter/material.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class StudyGroupFinderScreen extends StatefulWidget {
  const StudyGroupFinderScreen({super.key});

  @override
  State<StudyGroupFinderScreen> createState() => _StudyGroupFinderScreenState();
}

class _StudyGroupFinderScreenState extends State<StudyGroupFinderScreen> {
  static const _departments = [
    'All',
    'Civil',
    'Electrical',
    'Finance',
    'Education',
    'Office Admin',
    'Tourism',
  ];

  final List<_CollabGroup> _groups = [
    _CollabGroup(
      title: 'Math N4 Wizards',
      department: 'Civil',
      tags: ['#Calculus', '#ExamPrep'],
      isPrivate: true,
      members: 3,
      capacity: 5,
      avatars: ['M', 'A', 'S'],
    ),
    _CollabGroup(
      title: 'Electrical Systems Lab',
      department: 'Electrical',
      tags: ['#Circuits', '#LabPrep'],
      isPrivate: false,
      members: 4,
      capacity: 6,
      avatars: ['E', 'Q', 'T', 'J'],
    ),
    _CollabGroup(
      title: 'Tourism Pitch Squad',
      department: 'Tourism',
      tags: ['#Presentation', '#Marketing'],
      isPrivate: false,
      members: 2,
      capacity: 5,
      avatars: ['L', 'H'],
    ),
    _CollabGroup(
      title: 'Finance Ledger Lab',
      department: 'Finance',
      tags: ['#Accounting', '#StudyJam'],
      isPrivate: true,
      members: 1,
      capacity: 4,
      avatars: ['F'],
    ),
  ];

  String _selectedDept = 'All';
  static const _levelOptions = ['Level 2', 'Level 3', 'Level 4'];
  String _selectedLevel = _levelOptions.first;

  @override
  Widget build(BuildContext context) {
    final filteredGroups = _selectedDept == 'All'
        ? _groups
        : _groups.where((group) => group.department == _selectedDept).toList();

    return VibeScaffold(
      appBar: AppBar(
        title: Text(
          'Collaboration Lobby — $_selectedLevel',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D47A1), Color(0xFF2962FF), Color(0xFF6200EA)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Column(
            children: [
              _SkillMatcherCTA(onTap: _showSkillMatcherDialog),
              const SizedBox(height: 12),
              _buildLevelSelector(),
              const SizedBox(height: 12),
              _DepartmentFilter(
                departments: _departments,
                selectedDept: _selectedDept,
                onSelected: (value) => setState(() => _selectedDept = value),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: filteredGroups.isEmpty
                    ? const _EmptyLobbyState()
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: filteredGroups.length,
                        itemBuilder: (context, index) => Padding(
                          padding: EdgeInsets.only(
                            bottom: index == filteredGroups.length - 1 ? 0 : 16,
                          ),
                          child: _GroupCard(group: filteredGroups[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSkillMatcherDialog() async {
    final subjects = _selectedLevel == 'Level 2'
        ? [
            'English',
            'Life Skills',
            'ICT',
            'Introduction to Information Systems (IIS)',
            'Introduction to System Development (ISD)',
          ]
        : _selectedLevel == 'Level 3'
        ? [
            'English',
            'Life Skills',
            'ICT',
            'System Analysis and Design (SAD)',
            'Principles of Computer Programming (PCP)',
          ]
        : [
            'English',
            'Life Skills',
            'ICT',
            'System Analysis and Design (SAD)',
            'Computer Programming (CP)',
          ];

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('I need help with...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: subjects
                .map(
                  (subject) => ListTile(
                    title: Text(subject),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildLevelSelector() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _levelOptions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final level = _levelOptions[index];
          final selected = level == _selectedLevel;
          return ChoiceChip(
            label: Text(level),
            selected: selected,
            onSelected: (_) => setState(() => _selectedLevel = level),
            selectedColor: Colors.white,
            backgroundColor: Colors.white10,
            labelStyle: TextStyle(
              color: selected ? Colors.black87 : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
    );
  }
}

class _SkillMatcherCTA extends StatelessWidget {
  const _SkillMatcherCTA({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: const [
            Icon(Icons.auto_awesome, color: Color(0xFFFFD54F)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'I need help with... Tap to match skills',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _DepartmentFilter extends StatelessWidget {
  const _DepartmentFilter({
    required this.departments,
    required this.selectedDept,
    required this.onSelected,
  });

  final List<String> departments;
  final String selectedDept;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: departments.length,
        separatorBuilder: (_, spacing) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final dept = departments[index];
          final selected = dept == selectedDept;
          return ChoiceChip(
            label: Text(dept),
            selected: selected,
            onSelected: (_) => onSelected(dept),
            selectedColor: Colors.white24,
            backgroundColor: Colors.white10,
            side: BorderSide(color: selected ? Colors.white : Colors.white24),
            labelStyle: TextStyle(
              color: Colors.white.withOpacity(selected ? 1 : 0.7),
              fontWeight: FontWeight.w600,
            ),
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final _CollabGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (group.isPrivate)
                const Icon(Icons.lock_outline, color: Colors.white70),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: group.tags
                .map(
                  (tag) => Chip(
                    label: Text(tag),
                    backgroundColor: Colors.white24,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _FacePile(avatars: group.avatars),
              const Spacer(),
              Text(
                '${group.members}/${group.capacity} Filled',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amberAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Join Group'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FacePile extends StatelessWidget {
  const _FacePile({required this.avatars});

  final List<String> avatars;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: 50,
      child: Stack(
        clipBehavior: Clip.none,
        children: avatars.take(3).toList().asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;
          return Positioned(
            left: index * 28,
            child: CircleAvatar(
              radius: 22,
              backgroundColor: _avatarColor(index),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _avatarColor(int index) {
    const palette = [Color(0xFF2962FF), Color(0xFF00BFA5), Color(0xFFFF6D00)];
    return palette[index % palette.length];
  }
}

class _EmptyLobbyState extends StatelessWidget {
  const _EmptyLobbyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.menu_book_outlined, size: 64, color: Colors.white70),
        SizedBox(height: 12),
        Text(
          'No groups match this department yet.',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 4),
        Text(
          'Tap "I need help with..." to summon collaborators.',
          style: TextStyle(color: Colors.white54),
        ),
      ],
    );
  }
}

class _CollabGroup {
  const _CollabGroup({
    required this.title,
    required this.department,
    required this.tags,
    required this.isPrivate,
    required this.members,
    required this.capacity,
    required this.avatars,
  });

  final String title;
  final String department;
  final List<String> tags;
  final bool isPrivate;
  final int members;
  final int capacity;
  final List<String> avatars;
}
