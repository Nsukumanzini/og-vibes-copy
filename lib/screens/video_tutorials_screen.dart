import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class VideoTutorialsScreen extends StatefulWidget {
  const VideoTutorialsScreen({super.key});

  @override
  State<VideoTutorialsScreen> createState() => _VideoTutorialsScreenState();
}

class _VideoTutorialsScreenState extends State<VideoTutorialsScreen> {
  static const List<String> _categories = [
    'Engineering',
    'Business Studies',
    'NC(V) IT',
  ];

  late Future<List<_VideoTutorial>> _videosFuture;
  String _selectedCategory = _categories.first;

  @override
  void initState() {
    super.initState();
    _videosFuture = _loadVideos();
  }

  Future<List<_VideoTutorial>> _loadVideos() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    return const [
      _VideoTutorial(
        title: 'Isometric Drawing Basics - N4 Engineering',
        channel: 'TVET Masterclass',
        duration: '14:20',
        views: '1.2k',
        category: 'Engineering',
        accent: Color(0xFF1565C0),
      ),
      _VideoTutorial(
        title: 'Bank Reconciliation Statements - Financial Accounting N4',
        channel: 'Accounting Hub',
        duration: '22:15',
        views: '3.4k',
        category: 'Business Studies',
        accent: Color(0xFF00695C),
      ),
      _VideoTutorial(
        title: 'Office Data Processing L4 - Excel VLOOKUP',
        channel: 'NC(V) Tutorials',
        duration: '10:05',
        views: '890',
        category: 'NC(V) IT',
        accent: Color(0xFF5E35B1),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Video Tutorials')),
      body: FutureBuilder<List<_VideoTutorial>>(
        future: _videosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingState();
          }

          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _videosFuture = _loadVideos();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry loading tutorials'),
              ),
            );
          }

          final videos = snapshot.data!;

          return Column(
            children: [
              _buildCategoryChips(),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                  itemCount: videos.length,
                  itemBuilder: (context, index) {
                    final video = videos[index];
                    return _VideoCard(
                      video: video,
                      onTap: () {
                        setState(() {
                          _selectedCategory = video.category;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Opening secure video player...'),
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

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final selected = category == _selectedCategory;

          return ChoiceChip(
            label: Text(category),
            selected: selected,
            onSelected: (_) {
              setState(() {
                _selectedCategory = category;
              });
            },
            showCheckmark: false,
            selectedColor: const Color(0xFF1A237E),
            backgroundColor: Colors.white,
            side: BorderSide(
              color: selected
                  ? const Color(0xFF1A237E)
                  : const Color(0xFFCFD8DC),
            ),
            labelStyle: TextStyle(
              color: selected ? Colors.white : const Color(0xFF37474F),
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: [
            Row(
              children: List.generate(
                3,
                (_) => Expanded(
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
                itemCount: 3,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, _) => Container(
                  height: 176,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video, required this.onTap});

  final _VideoTutorial video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: video.accent.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 34,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        video.duration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF102027),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    video.channel,
                    style: const TextStyle(
                      color: Color(0xFF546E7A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        size: 16,
                        color: Color(0xFF607D8B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${video.views} views',
                        style: const TextStyle(
                          color: Color(0xFF607D8B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoTutorial {
  const _VideoTutorial({
    required this.title,
    required this.channel,
    required this.duration,
    required this.views,
    required this.category,
    required this.accent,
  });

  final String title;
  final String channel;
  final String duration;
  final String views;
  final String category;
  final Color accent;
}
