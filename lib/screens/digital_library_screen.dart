import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class DigitalLibraryScreen extends StatefulWidget {
  const DigitalLibraryScreen({super.key});

  @override
  State<DigitalLibraryScreen> createState() => _DigitalLibraryScreenState();
}

class _DigitalLibraryScreenState extends State<DigitalLibraryScreen> {
  static const List<String> _categories = <String>[
    'All',
    'N4 Engineering',
    'N4 Business',
    'Past Memos',
  ];

  static const List<_LibraryBook> _books = <_LibraryBook>[
    _LibraryBook(
      title: 'Mathematics N4 Textbook',
      author: 'M. van Rensburg',
      size: '14 MB',
      category: 'N4 Engineering',
      color: Color(0xFF1565C0),
      icon: Icons.menu_book,
    ),
    _LibraryBook(
      title: 'Computer Practice N4 Study Guide',
      author: 'TVET First',
      size: '8 MB',
      category: 'N4 Business',
      color: Color(0xFF00897B),
      icon: Icons.menu_book,
    ),
    _LibraryBook(
      title: 'Entrepreneurship Slides - Mod 1-3',
      author: 'Mrs. Venter',
      size: '2.4 MB',
      category: 'N4 Business',
      color: Color(0xFFEF6C00),
      icon: Icons.picture_as_pdf,
    ),
  ];

  late Future<void> _initialLoad;
  String _selectedCategory = _categories.first;

  @override
  void initState() {
    super.initState();
    _initialLoad = Future<void>.delayed(const Duration(milliseconds: 800));
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Digital Library')),
      body: FutureBuilder<void>(
        future: _initialLoad,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingState();
          }

          final List<_LibraryBook> filteredBooks = _selectedCategory == 'All'
              ? _books
              : _books
                    .where((book) => book.category == _selectedCategory)
                    .toList();

          return Column(
            children: <Widget>[
              _buildCategoryChips(),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: filteredBooks.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.74,
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final _LibraryBook book = filteredBooks[index];
                    return _BookCard(
                      book: book,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Opening encrypted PDF reader (Zero Data Mode)...',
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

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
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
            showCheckmark: false,
            onSelected: (bool _) {
              setState(() {
                _selectedCategory = category;
              });
            },
            selectedColor: const Color(0xFF1565C0),
            backgroundColor: Colors.white,
            side: BorderSide(
              color: selected ? Colors.transparent : const Color(0xFFD6DEE8),
            ),
            labelStyle: TextStyle(
              color: selected ? Colors.white : const Color(0xFF1F2A37),
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 40,
              child: Row(
                children: List<Widget>.generate(
                  4,
                  (int index) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: GridView.builder(
                itemCount: 4,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.74,
                ),
                itemBuilder: (BuildContext context, int index) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
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

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book, required this.onTap});

  final _LibraryBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE3EAF2)),
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
            Container(
              height: 112,
              width: double.infinity,
              decoration: BoxDecoration(
                color: book.color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(book.icon, size: 54, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Available Offline',
                style: TextStyle(
                  color: Color(0xFF2E7D32),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF102027),
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Author: ${book.author}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF607D8B),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.sd_storage_rounded,
                  size: 14,
                  color: Color(0xFF607D8B),
                ),
                const SizedBox(width: 4),
                Text(
                  book.size,
                  style: const TextStyle(
                    color: Color(0xFF607D8B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryBook {
  const _LibraryBook({
    required this.title,
    required this.author,
    required this.size,
    required this.category,
    required this.color,
    required this.icon,
  });

  final String title;
  final String author;
  final String size;
  final String category;
  final Color color;
  final IconData icon;
}
