import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class TutorDirectoryScreen extends StatefulWidget {
  const TutorDirectoryScreen({super.key});

  @override
  State<TutorDirectoryScreen> createState() => _TutorDirectoryScreenState();
}

class _TutorDirectoryScreenState extends State<TutorDirectoryScreen> {
  static const List<String> _categories = <String>[
    'All',
    'NATED Engineering',
    'NATED Business',
    'NC(V)',
  ];

  final TextEditingController _searchController = TextEditingController();
  late Future<List<_TutorProfile>> _tutorsFuture;
  String _selectedCategory = _categories.first;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tutorsFuture = _loadTutors();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_TutorProfile>> _loadTutors() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));

    return const <_TutorProfile>[
      _TutorProfile(
        name: 'Sipho Ndlovu (N6)',
        subjects: 'Mathematics N4, Engineering Science N4',
        rating: '4.9 (12 reviews)',
        availability: 'Tuesdays and Thursdays, Library',
        category: 'NATED Engineering',
        accent: Color(0xFF1565C0),
      ),
      _TutorProfile(
        name: 'Lerato M. (L4)',
        subjects: 'Office Data Processing NC(V) L4',
        rating: '4.8 (8 reviews)',
        availability: 'Online via Zoom or WhatsApp',
        category: 'NC(V)',
        accent: Color(0xFF00897B),
      ),
      _TutorProfile(
        name: 'David K. (N5)',
        subjects: 'Financial Accounting N4 and N5',
        rating: '4.7 (15 reviews)',
        availability: 'Weekends only',
        category: 'NATED Business',
        accent: Color(0xFF6A1B9A),
      ),
      _TutorProfile(
        name: 'Thandiwe S. (L4)',
        subjects: 'Life Orientation and Computer Practice',
        rating: '5.0 (3 reviews)',
        availability: 'Campus Cafeteria, 13:00 - 14:00',
        category: 'NC(V)',
        accent: Color(0xFFC62828),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Peer Tutor Directory')),
      body: FutureBuilder<List<_TutorProfile>>(
        future: _tutorsFuture,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<List<_TutorProfile>> snapshot,
            ) {
              if (snapshot.connectionState != ConnectionState.done) {
                return _buildLoadingState();
              }

              if (snapshot.hasError || !snapshot.hasData) {
                return Center(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _tutorsFuture = _loadTutors();
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry tutor load'),
                  ),
                );
              }

              final List<_TutorProfile> tutors = _applyFilters(snapshot.data!);

              return Column(
                children: <Widget>[
                  _buildSearchField(),
                  _buildCategoryBar(),
                  const SizedBox(height: 10),
                  Expanded(
                    child: tutors.isEmpty
                        ? const Center(
                            child: Text(
                              'No tutors match this search right now.',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: tutors.length,
                            itemBuilder: (BuildContext context, int index) {
                              final _TutorProfile tutor = tutors[index];
                              return _TutorCard(
                                tutor: tutor,
                                onRequest: () {
                                  final String shortName = tutor.name
                                      .split('(')
                                      .first
                                      .trim();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Tutor request sent to $shortName. They will contact you shortly.',
                                      ),
                                    ),
                                  );
                                },
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

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (String value) {
          setState(() => _searchQuery = value.trim().toLowerCase());
        },
        decoration: InputDecoration(
          hintText: 'Search by subject or tutor name...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBar() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (BuildContext context, int index) {
          return const SizedBox(width: 8);
        },
        itemBuilder: (BuildContext context, int index) {
          final String category = _categories[index];
          final bool selected = category == _selectedCategory;
          return ChoiceChip(
            label: Text(category),
            selected: selected,
            onSelected: (bool _) {
              setState(() => _selectedCategory = category);
            },
            showCheckmark: false,
            selectedColor: const Color(0xFF2962FF),
            backgroundColor: Colors.white,
            labelStyle: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
    );
  }

  List<_TutorProfile> _applyFilters(List<_TutorProfile> source) {
    return source.where((_TutorProfile tutor) {
      final bool categoryMatch =
          _selectedCategory == 'All' || _selectedCategory == tutor.category;
      final String query = _searchQuery;
      final bool queryMatch =
          query.isEmpty ||
          tutor.subjects.toLowerCase().contains(query) ||
          tutor.name.toLowerCase().contains(query);
      return categoryMatch && queryMatch;
    }).toList();
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: <Widget>[
            Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: List<Widget>.generate(
                4,
                (int index) => Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: 4,
                separatorBuilder: (BuildContext context, int index) {
                  return const SizedBox(height: 10);
                },
                itemBuilder: (BuildContext context, int index) {
                  return Container(
                    height: 142,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorProfile {
  const _TutorProfile({
    required this.name,
    required this.subjects,
    required this.rating,
    required this.availability,
    required this.category,
    required this.accent,
  });

  final String name;
  final String subjects;
  final String rating;
  final String availability;
  final String category;
  final Color accent;
}

class _TutorCard extends StatelessWidget {
  const _TutorCard({required this.tutor, required this.onRequest});

  final _TutorProfile tutor;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final Color accent = tutor.accent;
    final String initials = _getInitials(tutor.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 24,
                backgroundColor: accent.withValues(alpha: 0.14),
                child: Text(
                  initials,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tutor.name,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _line(Icons.menu_book_rounded, tutor.subjects),
          const SizedBox(height: 6),
          _line(Icons.star_rounded, tutor.rating),
          const SizedBox(height: 6),
          _line(Icons.schedule, tutor.availability),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Request Tutor'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 17, color: Colors.black54),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  String _getInitials(String name) {
    final String cleaned = name.split('(').first.trim();
    final List<String> parts = cleaned
        .split(' ')
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'PT';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}
