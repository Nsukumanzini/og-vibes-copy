import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/services/content_service.dart';
import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class AccreditedAccommodationScreen extends StatefulWidget {
  const AccreditedAccommodationScreen({super.key});

  @override
  State<AccreditedAccommodationScreen> createState() =>
      _AccreditedAccommodationScreenState();
}

class _AccreditedAccommodationScreenState
    extends State<AccreditedAccommodationScreen> {
  static const List<String> _filters = <String>[
    'All',
    'NSFAS Accredited Only',
    '< 1km from Campus',
  ];

  final TextEditingController _searchController = TextEditingController();
  late Future<List<_AccommodationProperty>> _propertiesFuture;
  String _selectedFilter = _filters.first;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _propertiesFuture = _loadProperties();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_AccommodationProperty>> _loadProperties() async {
    final rows = await ContentService.loadSection(
      'accommodations',
      fallback: const [
        {
          'title': 'The Block Student Res',
          'distanceKm': 0.5,
          'distanceLabel': '500m from Campus',
          'priceLabel': 'R 2,500/m (NSFAS Covered)',
          'roomType': 'Sharing Room',
          'badges': ['NSFAS Accredited', 'Free Wi-Fi', 'Verified Landlord'],
          'accent': 'blue',
        },
        {
          'title': 'Ermelo Varsity Lodge',
          'distanceKm': 1.2,
          'distanceLabel': '1.2km from Campus',
          'priceLabel': 'R 3,200/m',
          'roomType': 'Single Room',
          'badges': ['NSFAS Accredited', '24/7 Security'],
          'accent': 'green',
        },
        {
          'title': "Mama Joy's Commune",
          'distanceKm': 2.0,
          'distanceLabel': '2km from Campus',
          'priceLabel': 'R 1,800/m',
          'roomType': 'Sharing Room',
          'badges': ['Pending Accreditation', 'Female Only'],
          'accent': 'amber',
        },
      ],
    );

    return rows.map((row) {
      final Color accent = switch (row['accent']) {
        'green' => AppColors.success,
        'amber' => AppColors.warning,
        _ => AppColors.vibeBlue,
      };
      return _AccommodationProperty(
        name: row['title'] as String? ?? 'Student accommodation',
        distanceKm: (row['distanceKm'] as num?)?.toDouble() ?? 0,
        distanceLabel: row['distanceLabel'] as String? ?? '',
        priceLabel: row['priceLabel'] as String? ?? '',
        roomType: row['roomType'] as String? ?? '',
        badges: List<String>.from(row['badges'] as List? ?? const []),
        accent: accent,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Verified stays')),
      body: FutureBuilder<List<_AccommodationProperty>>(
        future: _propertiesFuture,
        builder: (BuildContext context, AsyncSnapshot<List<_AccommodationProperty>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingState();
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _propertiesFuture = _loadProperties();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry accommodation load'),
              ),
            );
          }

          final List<_AccommodationProperty> filtered = _applyFilters(snapshot.data!);

          return Column(
            children: <Widget>[
              _buildDiscoveryHeader(filtered.length),
              _buildSearchField(),
              _buildFilterBar(),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No properties match this filter right now.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: filtered.length,
                        itemBuilder: (BuildContext context, int index) {
                          final _AccommodationProperty item = filtered[index];
                          return _PropertyCard(
                            property: item,
                            onContact: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Opening secure WhatsApp chat with verified landlord...',
                                  ),
                                ),
                              );
                            },
                          )
                              .animate(delay: (70 * index).ms)
                              .fadeIn(duration: 320.ms)
                              .slideY(begin: .05, end: 0);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDiscoveryHeader(int resultCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: AppStyles.brandGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.apartment_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Find a place you can trust',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                Text(
                  '$resultCount verified options match your search',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.verified_rounded, color: AppColors.success),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: TextField(
        controller: _searchController,
        onChanged: (String value) {
          setState(() => _searchQuery = value.trim().toLowerCase());
        },
        decoration: InputDecoration(
          hintText: 'Search by price, distance, or room type...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final String filter = _filters[index];
          final bool selected = filter == _selectedFilter;
          return ChoiceChip(
            label: Text(filter),
            selected: selected,
            onSelected: (bool _) {
              setState(() => _selectedFilter = filter);
            },
            showCheckmark: false,
            selectedColor: AppColors.vibeBlue,
            backgroundColor: Colors.white.withValues(alpha: .7),
            labelStyle: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
    );
  }

  List<_AccommodationProperty> _applyFilters(List<_AccommodationProperty> source) {
    return source.where((_AccommodationProperty item) {
      final String query = _searchQuery;
      final bool queryMatch = query.isEmpty ||
          item.priceLabel.toLowerCase().contains(query) ||
          item.distanceLabel.toLowerCase().contains(query) ||
          item.roomType.toLowerCase().contains(query) ||
          item.name.toLowerCase().contains(query);

      final bool filterMatch = switch (_selectedFilter) {
        'NSFAS Accredited Only' => item.badges.contains('NSFAS Accredited'),
        '< 1km from Campus' => item.distanceKm < 1.0,
        _ => true,
      };

      return queryMatch && filterMatch;
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
                3,
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
                itemCount: 3,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) => Container(
                  height: 160,
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

class _AccommodationProperty {
  const _AccommodationProperty({
    required this.name,
    required this.distanceKm,
    required this.distanceLabel,
    required this.priceLabel,
    required this.roomType,
    required this.badges,
    required this.accent,
  });

  final String name;
  final double distanceKm;
  final String distanceLabel;
  final String priceLabel;
  final String roomType;
  final List<String> badges;
  final Color accent;
}

class _PropertyCard extends StatelessWidget {
  const _PropertyCard({required this.property, required this.onContact});

  final _AccommodationProperty property;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final Color accent = property.accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .82),
        borderRadius: AppStyles.bentoRadius,
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.deepBlue.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.home_work_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  property.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.midnightInk,
                  ),
                ),
              ),
              const Icon(Icons.verified_rounded,
                  color: AppColors.success, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          _line(Icons.location_on_outlined, property.distanceLabel),
          const SizedBox(height: 6),
          _line(Icons.payments_outlined, property.priceLabel),
          const SizedBox(height: 6),
          _line(Icons.bed_outlined, property.roomType),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: property.badges
                .map(
                  (String badge) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onContact,
              style: ElevatedButton.styleFrom(backgroundColor: accent),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Contact Landlord'),
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
}
