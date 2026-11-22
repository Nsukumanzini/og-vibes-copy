import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import '../services/offline_data_adapter.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const _cacheKey = 'verified_accommodation_cache_v2';
  static const _tabs = <String>[
    'All',
    'NSFAS accredited',
    'Private paid',
  ];

  final TextEditingController _searchController = TextEditingController();
  late Future<List<_AccommodationProperty>> _propertiesFuture;
  OfflineRealtimeChannel? _channel;
  String _selectedTab = _tabs.first;
  String _searchQuery = '';
  String _roomFilter = 'All rooms';
  String _distanceFilter = 'Any distance';
  String _availabilityFilter = 'Any availability';

  @override
  void initState() {
    super.initState();
    _propertiesFuture = _loadProperties();
    _channel = OfflineData.instance.client.channel('student-accommodation')
      ..onPostgresChanges(
        event: OfflinePostgresChangeEvent.all,
        schema: 'public',
        table: 'accommodations',
        callback: (_) {
          if (mounted) {
            setState(() => _propertiesFuture = _loadProperties());
          }
        },
      )
      ..subscribe();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_channel != null) {
      unawaited(OfflineData.instance.client.removeChannel(_channel!));
    }
    super.dispose();
  }

  Future<List<_AccommodationProperty>> _loadProperties() async {
    List<Map<String, dynamic>> rows;
    try {
      rows = List<Map<String, dynamic>>.from(
        await OfflineData.instance.client
                .from('accommodations')
                .select()
                .eq('is_active', true)
                .order('verified_landlord', ascending: false)
                .order('title')
            as List<dynamic>,
      );
      await (await SharedPreferences.getInstance()).setString(
        _cacheKey,
        jsonEncode(rows),
      );
    } catch (_) {
      final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
      rows = raw == null
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              (jsonDecode(raw) as List<dynamic>).map(
                (value) => Map<String, dynamic>.from(value as Map),
              ),
            );
    }
    return rows.map(_AccommodationProperty.fromRow).toList();
  }

  List<_AccommodationProperty> _applyFilters(
    List<_AccommodationProperty> source,
  ) {
    return source.where((property) {
      final matchesTab = switch (_selectedTab) {
        'NSFAS accredited' => property.nsfasAccredited,
        'Private paid' => !property.nsfasAccredited,
        _ => true,
      };
      final room = property.roomType.toLowerCase();
      final matchesRoom = switch (_roomFilter) {
        'Single' => room.contains('single'),
        'Sharing' => room.contains('sharing') || room.contains('shared'),
        _ => true,
      };
      final matchesDistance = switch (_distanceFilter) {
        'Under 1 km' => (property.distanceKm ?? double.infinity) < 1,
        'Under 3 km' => (property.distanceKm ?? double.infinity) < 3,
        'Under 5 km' => (property.distanceKm ?? double.infinity) < 5,
        _ => true,
      };
      final matchesAvailability = switch (_availabilityFilter) {
        'Available now' => (property.availableSpaces ?? 0) >= 3,
        'Limited spaces' =>
          (property.availableSpaces ?? 0) > 0 &&
          (property.availableSpaces ?? 0) < 3,
        'Fully occupied' => property.availableSpaces == 0,
        _ => true,
      };
      final query = _searchQuery;
      final matchesSearch =
          query.isEmpty ||
          property.name.toLowerCase().contains(query) ||
          property.address.toLowerCase().contains(query) ||
          property.roomType.toLowerCase().contains(query) ||
          property.amenities.any(
            (amenity) => amenity.toLowerCase().contains(query),
          );
      return matchesTab &&
          matchesRoom &&
          matchesDistance &&
          matchesAvailability &&
          matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Accommodation')),
      body: FutureBuilder<List<_AccommodationProperty>>(
        future: _propertiesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _AccommodationLoading();
          }
          final properties = snapshot.data ?? <_AccommodationProperty>[];
          final filtered = _applyFilters(properties);
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _propertiesFuture = _loadProperties());
              await _propertiesFuture;
            },
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                SliverToBoxAdapter(child: _buildHero(properties)),
                SliverToBoxAdapter(child: _buildSearch()),
                SliverToBoxAdapter(child: _buildTabs()),
                SliverToBoxAdapter(child: _buildQuickFilters()),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyAccommodation(
                      tab: _selectedTab,
                      hasActiveFilters: _hasActiveFilters,
                      onClearFilters: _clearFilters,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                    sliver: SliverList.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final property = filtered[index];
                        return _PropertyCard(
                              property: property,
                              onOpen: () => _openDetails(property),
                            )
                            .animate(delay: (55 * index).ms)
                            .fadeIn(duration: 320.ms)
                            .slideY(begin: .04, end: 0);
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHero(List<_AccommodationProperty> properties) {
    final nsfasCount = properties.where((item) => item.nsfasAccredited).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: AppStyles.bentoRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.vibeBlue.withValues(alpha: .22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.apartment_rounded, color: Colors.white, size: 28),
              const Spacer(),
              TextButton.icon(
                onPressed: _showVerifiedInfo,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('Verified listings'),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const Text(
            'Find your place\nnear campus.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 27,
              height: 1.08,
              fontWeight: FontWeight.w900,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            properties.isEmpty
                ? 'Approved accommodation will appear here.'
                : '${properties.length} active ${properties.length == 1 ? 'listing' : 'listings'} · $nsfasCount NSFAS accredited',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .78),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showVerifiedInfo() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('About verified listings'),
        content: const Text(
          'A verified landlord has provided details that OG Vibes administrators have checked. Always visit the property and confirm the information before paying any money.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: TextField(
        controller: _searchController,
        onChanged: (value) =>
            setState(() => _searchQuery = value.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search property, room type or amenity',
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

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SegmentedButton<String>(
        segments: const <ButtonSegment<String>>[
          ButtonSegment(value: 'All', label: Text('All')),
          ButtonSegment(
            value: 'NSFAS accredited',
            label: Text('NSFAS accredited'),
          ),
          ButtonSegment(value: 'Private paid', label: Text('Private paid')),
        ],
        selected: <String>{_selectedTab},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          setState(() => _selectedTab = selection.first);
        },
      ),
    );
  }

  bool get _hasActiveFilters =>
      _roomFilter != 'All rooms' ||
      _distanceFilter != 'Any distance' ||
      _availabilityFilter != 'Any availability';

  void _clearFilters() {
    setState(() {
      _roomFilter = 'All rooms';
      _distanceFilter = 'Any distance';
      _availabilityFilter = 'Any availability';
    });
  }

  Widget _buildQuickFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          _AccommodationFilterMenu(
            icon: Icons.bed_outlined,
            label: _roomFilter,
            options: const <String>['All rooms', 'Single', 'Sharing'],
            onSelected: (value) => setState(() => _roomFilter = value),
          ),
          _AccommodationFilterMenu(
            icon: Icons.directions_walk_outlined,
            label: _distanceFilter,
            options: const <String>[
              'Any distance',
              'Under 1 km',
              'Under 3 km',
              'Under 5 km',
            ],
            onSelected: (value) => setState(() => _distanceFilter = value),
          ),
          _AccommodationFilterMenu(
            icon: Icons.event_available_outlined,
            label: _availabilityFilter,
            options: const <String>[
              'Any availability',
              'Available now',
              'Limited spaces',
              'Fully occupied',
            ],
            onSelected: (value) =>
                setState(() => _availabilityFilter = value),
          ),
          if (_hasActiveFilters)
            TextButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Clear'),
            ),
        ],
      ),
    );
  }

  Future<void> _openDetails(_AccommodationProperty property) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _AccommodationDetailsScreen(
          property: property,
          onWhatsApp: () => _openWhatsApp(property),
          onCall: () => _call(property),
          onDirections: () => _openDirections(property),
          onReport: () => _report(property),
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(_AccommodationProperty property) async {
    final digits = property.contactPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) {
      return _message('The landlord has not added a phone number.');
    }
    final uri = Uri.parse(
      'https://wa.me/${digits.replaceFirst('+', '')}?text=${Uri.encodeComponent('Hi, I found ${property.name} on OG Vibes and would like more information.')}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _message('WhatsApp could not be opened on this device.');
    }
  }

  Future<void> _call(_AccommodationProperty property) async {
    final phone = property.contactPhone.trim();
    if (phone.isEmpty) {
      return _message('The landlord has not added a phone number.');
    }
    if (!await launchUrl(Uri(scheme: 'tel', path: phone))) {
      _message('Calling is not available on this device.');
    }
  }

  Future<void> _openDirections(_AccommodationProperty property) async {
    final destination = <String>[property.address, 'Ermelo']
        .where((part) => part.trim().isNotEmpty)
        .join(', ');
    if (destination.isEmpty) {
      return _message('This listing does not have an address yet.');
    }
    final uri = Uri.https(
      'www.google.com',
      '/maps/search/',
      <String, String>{'api': '1', 'query': destination},
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _message('Maps could not be opened on this device.');
    }
  }

  Future<void> _report(_AccommodationProperty property) async {
    final draft = await showDialog<_AccommodationReportDraft>(
      context: context,
      builder: (_) => _AccommodationReportDialog(propertyName: property.name),
    );
    if (draft == null) return;
    final user = OfflineData.instance.client.auth.currentUser;
    if (user == null) return _message('Please sign in to report this listing.');
    try {
      await OfflineData.instance.client.from('accommodation_reports').insert({
        'accommodation_id': property.id,
        'reporter_id': user.id,
        'reason': draft.reason,
        'details': draft.details,
      });
      _message('Thanks. The administrator will review this listing.');
    } on OfflinePostgrestException catch (error) {
      _message(
        error.code == '23505'
            ? 'You already have an open report for this listing.'
            : 'The report could not be sent. Please try again.',
      );
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AccommodationProperty {
  const _AccommodationProperty({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    required this.campus,
    required this.distanceKm,
    required this.monthlyPrice,
    required this.roomType,
    required this.nsfasAccredited,
    required this.verifiedLandlord,
    required this.amenities,
    required this.images,
    required this.contactName,
    required this.contactPhone,
    required this.contactEmail,
    required this.availableSpaces,
    required this.updatedAt,
  });

  factory _AccommodationProperty.fromRow(Map<String, dynamic> row) {
    final validAccreditation = row['nsfas_accredited'] == true;
    final images = <String>[
      ...List<String>.from(row['image_urls'] as List? ?? const <String>[]),
      if ((row['image_url']?.toString().trim() ?? '').isNotEmpty)
        row['image_url'].toString(),
    ].where((value) => value.trim().isNotEmpty).toSet().toList();
    return _AccommodationProperty(
      id: row['id'].toString(),
      name: row['title']?.toString() ?? 'Student accommodation',
      description: row['description']?.toString() ?? '',
      address: row['address']?.toString() ?? '',
      campus: row['campus']?.toString() ?? 'Campus',
      distanceKm: (row['distance_km'] as num?)?.toDouble(),
      monthlyPrice: (row['monthly_price'] as num?)?.toDouble() ?? 0,
      roomType: row['room_type']?.toString() ?? 'Room',
      nsfasAccredited: validAccreditation,
      verifiedLandlord: row['verified_landlord'] == true,
      amenities: List<String>.from(
        row['amenities'] as List? ?? const <String>[],
      ),
      images: images,
      contactName: row['contact_name']?.toString() ?? 'Property contact',
      contactPhone: row['contact_phone']?.toString() ?? '',
      contactEmail: row['contact_email']?.toString() ?? '',
      availableSpaces: row['available_spaces'] as int?,
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
    );
  }

  final String id;
  final String name;
  final String description;
  final String address;
  final String campus;
  final double? distanceKm;
  final double monthlyPrice;
  final String roomType;
  final bool nsfasAccredited;
  final bool verifiedLandlord;
  final List<String> amenities;
  final List<String> images;
  final String contactName;
  final String contactPhone;
  final String contactEmail;
  final int? availableSpaces;
  final DateTime? updatedAt;

  String get priceLabel => nsfasAccredited
      ? 'NSFAS funded'
      : 'R${monthlyPrice.toStringAsFixed(0)} / month';
  String get distanceLabel => distanceKm == null
      ? address
      : '${distanceKm!.toStringAsFixed(distanceKm! < 1 ? 1 : 0)} km from campus';
  String get availabilityLabel => switch (availableSpaces) {
    null => 'Check availability',
    0 => 'Fully occupied',
    1 || 2 => 'Limited spaces',
    final int count => '$count spaces available',
  };
}

class _PropertyCard extends StatelessWidget {
  const _PropertyCard({required this.property, required this.onOpen});

  final _AccommodationProperty property;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .88),
        borderRadius: AppStyles.bentoRadius,
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppStyles.glassShadow,
      ),
      child: ClipRRect(
        borderRadius: AppStyles.bentoRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _PropertyImageCarousel(
              images: property.images,
              height: 215,
              borderRadius: BorderRadius.zero,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          property.name,
                          style: const TextStyle(
                            color: AppColors.midnightInk,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (property.verifiedLandlord)
                        const Tooltip(
                          message: 'Landlord details verified by OG Vibes',
                          child: Icon(
                            Icons.verified_rounded,
                            color: AppColors.success,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    property.priceLabel,
                    style: const TextStyle(
                      color: AppColors.vibeBlue,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _InfoLine(
                    icon: Icons.location_on_outlined,
                    text: property.distanceLabel,
                  ),
                  const SizedBox(height: 6),
                  _InfoLine(
                    icon: Icons.bed_outlined,
                    text:
                        '${property.roomType} · ${property.availabilityLabel}',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: <Widget>[
                      _ListingBadge(
                        label: property.nsfasAccredited
                            ? 'NSFAS accredited'
                            : 'Private paid',
                        positive: property.nsfasAccredited,
                      ),
                      if (property.verifiedLandlord)
                        const _ListingBadge(
                          label: 'Verified landlord',
                          positive: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('View property'),
                    ),
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

class _AccommodationDetailsScreen extends StatelessWidget {
  const _AccommodationDetailsScreen({
    required this.property,
    required this.onWhatsApp,
    required this.onCall,
    required this.onDirections,
    required this.onReport,
  });

  final _AccommodationProperty property;
  final VoidCallback onWhatsApp;
  final VoidCallback onCall;
  final VoidCallback onDirections;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Property details'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Report listing',
            onPressed: onReport,
            icon: const Icon(Icons.flag_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
        children: <Widget>[
          _PropertyImageCarousel(
            images: property.images,
            height: 280,
            borderRadius: BorderRadius.circular(26),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      property.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.5,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      property.priceLabel,
                      style: const TextStyle(
                        color: AppColors.vibeBlue,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (property.verifiedLandlord)
                const Icon(Icons.verified_rounded, color: AppColors.success),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _ListingBadge(
                label: property.nsfasAccredited
                    ? 'NSFAS accredited'
                    : 'Private paid',
                positive: property.nsfasAccredited,
              ),
              _ListingBadge(
                label: property.availabilityLabel,
                positive: property.availableSpaces != 0,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _DetailCard(
            child: Column(
              children: <Widget>[
                _InfoLine(
                  icon: Icons.location_on_outlined,
                  text: property.address,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onDirections,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Get directions'),
                  ),
                ),
                const Divider(height: 24),
                _InfoLine(
                  icon: Icons.directions_walk_rounded,
                  text: property.distanceLabel,
                ),
                const Divider(height: 24),
                _InfoLine(icon: Icons.bed_outlined, text: property.roomType),
              ],
            ),
          ),
          if (property.description.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            const _SectionTitle('About this property'),
            const SizedBox(height: 9),
            Text(
              property.description,
              style: const TextStyle(color: AppColors.textMuted, height: 1.55),
            ),
          ],
          const SizedBox(height: 20),
          const _SectionTitle('What is included'),
          const SizedBox(height: 10),
          if (property.amenities.isEmpty)
            const Text(
              'Ask the landlord which services and facilities are included.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: property.amenities
                  .map(
                    (amenity) => _AmenityChip(
                      label: amenity,
                      icon: _amenityIcon(amenity),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 22),
          _DetailCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Property contact',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  property.contactName,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onWhatsApp,
                        icon: const Icon(Icons.chat_rounded),
                        label: const Text('WhatsApp'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A765),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onCall,
                        icon: const Icon(Icons.call_rounded),
                        label: const Text('Call'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _AccommodationSafetyNotice(),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onReport,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Report incorrect or unsafe information'),
          ),
        ],
      ),
    );
  }
}

class _PropertyImageCarousel extends StatefulWidget {
  const _PropertyImageCarousel({
    required this.images,
    required this.height,
    required this.borderRadius,
  });

  final List<String> images;
  final double height;
  final BorderRadius borderRadius;

  @override
  State<_PropertyImageCarousel> createState() => _PropertyImageCarouselState();
}

class _PropertyImageCarouselState extends State<_PropertyImageCarousel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: Container(
          height: widget.height,
          color: const Color(0xFFF7F9FD),
          child: const Center(
            child: Icon(
              Icons.apartment_rounded,
              color: AppColors.vibeBlue,
              size: 54,
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            PageView.builder(
              itemCount: widget.images.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (_, index) => CachedNetworkImage(
                imageUrl: widget.images[index],
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    Container(color: const Color(0xFFF7F9FD)),
                errorWidget: (_, _, _) => Container(
                  color: const Color(0xFFF7F9FD),
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
            if (widget.images.length > 1)
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_index + 1}/${widget.images.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
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

class _AccommodationReportDialog extends StatefulWidget {
  const _AccommodationReportDialog({required this.propertyName});

  final String propertyName;

  @override
  State<_AccommodationReportDialog> createState() =>
      _AccommodationReportDialogState();
}

class _AccommodationReportDialogState
    extends State<_AccommodationReportDialog> {
  static const _reasons = <String>[
    'Incorrect information',
    'No longer available',
    'Accreditation concern',
    'Suspicious listing',
    'Unsafe property',
    'Other',
  ];
  final _detailsController = TextEditingController();
  String _reason = _reasons.first;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report listing'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.propertyName,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: _reasons
                  .map(
                    (reason) =>
                        DropdownMenuItem(value: reason, child: Text(reason)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _reason = value ?? _reason),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _detailsController,
              maxLength: 1000,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What should the administrator know?',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _AccommodationReportDraft(
              reason: _reason,
              details: _detailsController.text.trim(),
            ),
          ),
          child: const Text('Send report'),
        ),
      ],
    );
  }
}

class _AccommodationReportDraft {
  const _AccommodationReportDraft({
    required this.reason,
    required this.details,
  });

  final String reason;
  final String details;
}

class _AccommodationLoading extends StatelessWidget {
  const _AccommodationLoading();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: List<Widget>.generate(
          3,
          (_) => Container(
            height: 340,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppStyles.bentoRadius,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyAccommodation extends StatelessWidget {
  const _EmptyAccommodation({
    required this.tab,
    required this.hasActiveFilters,
    required this.onClearFilters,
  });

  final String tab;
  final bool hasActiveFilters;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.home_work_outlined,
              size: 54,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              hasActiveFilters
                  ? 'No matches yet'
                  : tab == 'All'
                  ? 'No accommodation yet'
                  : 'No $tab listings yet',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            Text(
              hasActiveFilters
                  ? 'Try clearing one or more filters, then look again.'
                  : 'New active listings will appear here automatically.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (hasActiveFilters) ...<Widget>[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccommodationFilterMenu extends StatelessWidget {
  const _AccommodationFilterMenu({
    required this.icon,
    required this.label,
    required this.options,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Change filter',
      onSelected: onSelected,
      itemBuilder: (_) => options
          .map(
            (option) => CheckedPopupMenuItem<String>(
              value: option,
              checked: option == label,
              child: Text(option),
            ),
          )
          .toList(),
      child: Semantics(
        button: true,
        label: 'Filter: $label',
        child: Chip(
          avatar: Icon(icon, size: 18, color: AppColors.vibeBlue),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(label),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccommodationSafetyNotice extends StatelessWidget {
  const _AccommodationSafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6D6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFC107)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.shield_outlined, color: Color(0xFF775700)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Safety first: visit the property and confirm its details before paying. Do not send a deposit because of a listing alone.',
              style: TextStyle(color: Color(0xFF775700), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
        ),
      ),
    );
  }
}

class _ListingBadge extends StatelessWidget {
  const _ListingBadge({required this.label, required this.positive});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive ? AppColors.success : AppColors.vibeBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textMuted,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .86),
        borderRadius: AppStyles.bentoRadius,
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppStyles.glassShadow,
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.midnightInk,
        fontSize: 17,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _AmenityChip extends StatelessWidget {
  const _AmenityChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 17, color: AppColors.vibeBlue),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

IconData _amenityIcon(String amenity) {
  final value = amenity.toLowerCase();
  if (value.contains('wifi') || value.contains('internet')) {
    return Icons.wifi_rounded;
  }
  if (value.contains('security') || value.contains('cctv')) {
    return Icons.shield_rounded;
  }
  if (value.contains('water')) return Icons.water_drop_rounded;
  if (value.contains('electric')) return Icons.bolt_rounded;
  if (value.contains('laundry')) return Icons.local_laundry_service_rounded;
  if (value.contains('parking')) return Icons.local_parking_rounded;
  if (value.contains('kitchen')) return Icons.kitchen_rounded;
  if (value.contains('furnish')) return Icons.chair_rounded;
  if (value.contains('study')) return Icons.menu_book_rounded;
  if (value.contains('transport')) return Icons.directions_bus_rounded;
  return Icons.check_circle_rounded;
}
