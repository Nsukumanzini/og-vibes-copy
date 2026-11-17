import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class StudyResourcesScreen extends StatefulWidget {
  const StudyResourcesScreen({super.key});

  @override
  State<StudyResourcesScreen> createState() => _StudyResourcesScreenState();
}

class _StudyResourcesScreenState extends State<StudyResourcesScreen>
    with SingleTickerProviderStateMixin {
  static const _levelOptions = ['Level 2', 'Level 3', 'Level 4'];

  late final TabController _tabController;
  late Future<Map<String, Map<String, List<Map<String, String>>>>>
  _resourcesFuture;
  String _selectedLevel = _levelOptions.first;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _resourcesFuture = _loadResources();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<Map<String, Map<String, List<Map<String, String>>>>>
  _loadResources() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));

    return {
      'Level 2': {
        'Subjects': [
          {
            'title': 'English',
            'subtitle': 'Communication skills and academic writing',
          },
          {
            'title': 'Life Skills',
            'subtitle': 'Personal development and study habits',
          },
          {
            'title': 'ICT',
            'subtitle': 'Basic computer literacy and applications',
          },
          {
            'title': 'Introduction to Information Systems (IIS)',
            'subtitle': 'Overview of information systems',
          },
          {
            'title': 'Introduction to System Development (ISD)',
            'subtitle': 'Basic system development concepts',
          },
          {
            'title': 'Electronics',
            'subtitle': 'Fundamentals of electronic components and circuits',
          },
          {
            'title': 'Multimedia Basics (MB)',
            'subtitle': 'Intro to multimedia authoring and assets',
          },
          {
            'title': 'Mathematics',
            'subtitle': 'Core numeracy for IT applications',
          },
        ],
        'Past Question Papers': [
          {
            'title': 'Level 2 IT June 2025 Past Paper',
            'subtitle': 'Solved paper + memo for Computer Practice',
          },
          {
            'title': 'Level 2 IT November 2024 Past Paper',
            'subtitle': 'Engineering Science exam ready review',
          },
          {
            'title': 'Level 2 IT Trial Paper Pack',
            'subtitle': '3 papers with model answers for final exam prep',
          },
        ],
        'Study Guides': [
          {
            'title': 'Level 2 IT Study Roadmap',
            'subtitle': 'Weekly plan, key outcomes, and exam checkpoints',
          },
          {
            'title': 'Level 2 Practical Checklist',
            'subtitle': 'What examiners look for in your practical work',
          },
          {
            'title': 'IT Theory Mastery Guide',
            'subtitle': 'Concept summaries and memory aids for theory tests',
          },
        ],
      },
      'Level 3': {
        'Subjects': [
          {
            'title': 'English',
            'subtitle': 'Communication and technical reporting',
          },
          {
            'title': 'Life Skills',
            'subtitle': 'Study habits and career readiness',
          },
          {
            'title': 'ICT',
            'subtitle': 'Intermediate computer skills and tools',
          },
          {
            'title': 'System Analysis and Design (SAD)',
            'subtitle': 'Requirements, modelling and UML basics',
          },
          {
            'title': 'Principles of Computer Programming (PCP)',
            'subtitle': 'Intro to programming concepts',
          },
          {
            'title': 'Multimedia Content (MC)',
            'subtitle': 'Creating multimedia assets and workflows',
          },
          {
            'title': 'Computer Hardware and Software (CHS)',
            'subtitle': 'Hardware components and OS fundamentals',
          },
          {
            'title': 'Mathematics',
            'subtitle': 'Applied maths for computing problems',
          },
        ],
        'Past Question Papers': [
          {
            'title': 'Level 3 IT June 2025 Past Paper',
            'subtitle': 'Computer Practice memo and exam highlights',
          },
          {
            'title': 'Level 3 IT Trial Questions',
            'subtitle': 'Top questions to revise before exams',
          },
        ],
        'Study Guides': [
          {
            'title': 'Level 3 IT Exam Success Guide',
            'subtitle': 'Best practices for scoring in theory and practicals',
          },
          {
            'title': 'Level 3 Project Planning Guide',
            'subtitle': 'How to deliver strong practical project evidence',
          },
        ],
      },
      'Level 4': {
        'Subjects': [
          {
            'title': 'English',
            'subtitle': 'Advanced communication and technical writing',
          },
          {
            'title': 'Life Skills',
            'subtitle': 'Professional development and employability',
          },
          {
            'title': 'ICT',
            'subtitle': 'Advanced ICT skills and productivity tools',
          },
          {
            'title': 'System Analysis and Design (SAD)',
            'subtitle': 'Design patterns, modelling and validation',
          },
          {
            'title': 'Computer Programming (CP)',
            'subtitle': 'Structured programming and problem solving',
          },
          {
            'title': 'Multimedia Services (MS)',
            'subtitle': 'Deploying and managing multimedia solutions',
          },
          {
            'title': 'Data Communication and Network (DCN)',
            'subtitle': 'Networking fundamentals and protocols',
          },
          {
            'title': 'Mathematics',
            'subtitle': 'Technical maths for diagnostics and algorithms',
          },
        ],
        'Past Question Papers': [
          {
            'title': 'Level 4 IT Final Exam Pack',
            'subtitle': 'Latest papers with examiner commentary',
          },
          {
            'title': 'Level 4 IT Practical Exam Guide',
            'subtitle': 'Recorded sample answers and marking notes',
          },
        ],
        'Study Guides': [
          {
            'title': 'Level 4 Graduation Preparation Guide',
            'subtitle': 'Project, portfolio, and exam readiness toolkit',
          },
          {
            'title': 'Advanced IT Revision Guide',
            'subtitle': 'Key theory, practical resources, and exam tips',
          },
        ],
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('NCV IT Study Resources'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Subjects'),
            Tab(text: 'Past Papers'),
            Tab(text: 'Study Guides'),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B3D91), Color(0xFF2196F3), Color(0xFF6A1B9A)],
          ),
        ),
        child: FutureBuilder<Map<String, Map<String, List<Map<String, String>>>>>(
          future: _resourcesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _buildLoading();
            }

            if (!snapshot.hasData || snapshot.hasError) {
              return Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _resourcesFuture = _loadResources();
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload resources'),
                ),
              );
            }

            final resources = snapshot.data!;
            final levelData = resources[_selectedLevel]!;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NCV IT student resources tailored to your level',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 14),
                      _buildLevelSelector(context),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedLevel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Your selected NCV IT level. Swipe the tabs to find subjects, past papers, and study guides designed for this level.',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.school_outlined,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildResourceList(levelData['Subjects']!),
                        _buildResourceList(levelData['Past Question Papers']!),
                        _buildResourceList(levelData['Study Guides']!),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLevelSelector(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _levelOptions.map((level) {
        final selected = level == _selectedLevel;
        return ChoiceChip(
          label: Text(level),
          selected: selected,
          selectedColor: Colors.white,
          backgroundColor: Colors.white.withOpacity(0.18),
          labelStyle: TextStyle(
            color: selected ? Colors.black87 : Colors.white,
            fontWeight: FontWeight.w700,
          ),
          side: BorderSide(color: selected ? Colors.white : Colors.white54),
          onSelected: (_) {
            setState(() {
              _selectedLevel = level;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildResourceList(List<Map<String, String>> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return Material(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Opening ${item['title']}...')),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF42A5F5), Color(0xFF7E57C2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(
                      Icons.folder_open,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item['subtitle']!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.78),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Opening ${item['title']}...')),
                      );
                    },
                    child: const Text('View'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Shimmer.fromColors(
        baseColor: Colors.white24,
        highlightColor: Colors.white38,
        child: Column(
          children: List.generate(
            4,
            (index) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              height: 84,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
