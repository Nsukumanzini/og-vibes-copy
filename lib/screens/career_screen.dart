import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';

class CareerScreen extends StatefulWidget {
  const CareerScreen({super.key});

  @override
  State<CareerScreen> createState() => _CareerScreenState();
}

class _CareerScreenState extends State<CareerScreen> {
  static const _opportunitiesCacheKey = 'career_opportunities_cache_v2';
  static const _resourcesCacheKey = 'career_resources_cache_v1';

  final _searchController = TextEditingController();
  final _client = Supabase.instance.client;

  StreamSubscription<List<Map<String, dynamic>>>? _opportunitySubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _applicationSubscription;
  List<Map<String, dynamic>> _opportunities = [];
  List<Map<String, dynamic>> _applications = [];
  List<Map<String, dynamic>> _documents = [];
  List<Map<String, dynamic>> _resources = [];
  Map<String, dynamic>? _profile;

  int _selectedTab = 0;
  bool _loading = true;
  bool _refreshing = false;
  bool _offlineData = false;
  String? _error;
  Set<String> _typeFilters = {};
  String? _locationFilter;
  String? _courseFilter;
  String? _facultyFilter;
  String? _levelFilter;
  bool _remoteOnly = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _opportunitySubscription?.cancel();
    _applicationSubscription?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    await _loadCache();
    await _loadSupportingData();
    _subscribeToRealtime();
  }

  Future<void> _loadCache() async {
    final preferences = await SharedPreferences.getInstance();
    final opportunityJson = preferences.getString(_opportunitiesCacheKey);
    final resourceJson = preferences.getString(_resourcesCacheKey);
    if (!mounted) return;

    setState(() {
      if (opportunityJson != null) {
        _opportunities = _decodeRows(opportunityJson);
      }
      if (resourceJson != null) {
        _resources = _decodeRows(resourceJson);
      }
      _offlineData = _opportunities.isNotEmpty || _resources.isNotEmpty;
      _loading = !_offlineData;
    });
  }

  List<Map<String, dynamic>> _decodeRows(String raw) {
    try {
      return List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List<dynamic>).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
    } catch (_) {
      return [];
    }
  }

  Future<void> _cacheRows(String key, List<Map<String, dynamic>> rows) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, jsonEncode(rows));
  }

  Future<void> _loadSupportingData({bool showRefresh = false}) async {
    if (showRefresh && mounted) setState(() => _refreshing = true);
    final user = _client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _error = 'Sign in to explore career opportunities.';
        });
      }
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        _client
            .from('profiles')
            .select('id, name, surname, campus, faculty, course, level')
            .eq('id', user.id)
            .maybeSingle(),
        _client
            .from('student_documents')
            .select(
              'id, title, file_name, file_type, mime_type, folder, '
              'file_size, updated_at',
            )
            .eq('user_id', user.id)
            .order('updated_at', ascending: false),
        _client
            .from('career_resources')
            .select(
              'id, slug, title, summary, body, icon_name, sort_order, '
              'updated_at',
            )
            .eq('is_active', true)
            .order('sort_order'),
      ]);

      final resources = List<Map<String, dynamic>>.from(
        results[2] as List<dynamic>,
      );
      await _cacheRows(_resourcesCacheKey, resources);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as Map<String, dynamic>?;
        _documents = List<Map<String, dynamic>>.from(
          results[1] as List<dynamic>,
        );
        _resources = resources;
        _loading = false;
        _refreshing = false;
        _offlineData = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = _offlineData
            ? 'Offline mode · showing your latest saved career data.'
            : 'Career Hub could not connect. Pull down to try again.';
      });
    }
  }

  void _subscribeToRealtime() {
    final user = _client.auth.currentUser;
    if (user == null) return;

    _opportunitySubscription?.cancel();
    _applicationSubscription?.cancel();

    _opportunitySubscription = _client
        .from('career_opportunities')
        .stream(primaryKey: ['id'])
        .eq('is_published', true)
        .order('created_at', ascending: false)
        .listen(
          (rows) async {
            await _cacheRows(_opportunitiesCacheKey, rows);
            if (!mounted) return;
            setState(() {
              _opportunities = rows;
              _loading = false;
              _offlineData = false;
              _error = null;
            });
          },
          onError: (_) {
            if (!mounted || _opportunities.isEmpty) return;
            setState(() {
              _offlineData = true;
              _error = 'Offline mode · showing your latest saved career data.';
            });
          },
        );

    _applicationSubscription = _client
        .from('career_applications')
        .stream(primaryKey: ['id'])
        .eq('student_id', user.id)
        .order('updated_at', ascending: false)
        .listen((rows) {
          if (!mounted) return;
          setState(() => _applications = rows);
        }, onError: (_) {});
  }

  Future<void> _refresh() async {
    HapticFeedback.selectionClick();
    await _loadSupportingData(showRefresh: true);
    _subscribeToRealtime();
  }

  List<Map<String, dynamic>> get _filteredOpportunities {
    final query = _searchController.text.trim().toLowerCase();
    return _opportunities.where((opportunity) {
      final searchText = [
        opportunity['title'],
        opportunity['company'],
        opportunity['qualification'],
        opportunity['description'],
        opportunity['course'],
        opportunity['faculty'],
      ].whereType<Object>().join(' ').toLowerCase();
      final type = _opportunityType(opportunity).toLowerCase();
      final location = (opportunity['location'] ?? '').toString();
      final course = (opportunity['course'] ?? '').toString();
      final faculty = (opportunity['faculty'] ?? '').toString();
      final level = (opportunity['level'] ?? '').toString();

      return (query.isEmpty || searchText.contains(query)) &&
          (_typeFilters.isEmpty || _typeFilters.contains(type)) &&
          (_locationFilter == null || location == _locationFilter) &&
          (_courseFilter == null || course == _courseFilter) &&
          (_facultyFilter == null || faculty == _facultyFilter) &&
          (_levelFilter == null || level == _levelFilter) &&
          (!_remoteOnly || opportunity['is_remote'] == true);
    }).toList();
  }

  int get _activeFilterCount =>
      _typeFilters.length +
      (_locationFilter == null ? 0 : 1) +
      (_courseFilter == null ? 0 : 1) +
      (_facultyFilter == null ? 0 : 1) +
      (_levelFilter == null ? 0 : 1) +
      (_remoteOnly ? 1 : 0);

  String _opportunityType(Map<String, dynamic> opportunity) {
    final category = (opportunity['category'] ?? '').toString().trim();
    final type = (opportunity['type'] ?? '').toString().trim();
    return category.isNotEmpty ? category : (type.isNotEmpty ? type : 'Other');
  }

  String _opportunityTitle(String? id) {
    for (final opportunity in _opportunities) {
      if (opportunity['id']?.toString() == id) {
        return (opportunity['title'] ?? 'Opportunity').toString();
      }
    }
    return 'Career opportunity';
  }

  Map<String, dynamic>? _opportunityById(String? id) {
    for (final opportunity in _opportunities) {
      if (opportunity['id']?.toString() == id) return opportunity;
    }
    return null;
  }

  void _selectTab(int value) {
    HapticFeedback.selectionClick();
    setState(() => _selectedTab = value);
  }

  void _clearFilters() {
    HapticFeedback.selectionClick();
    setState(() {
      _typeFilters = {};
      _locationFilter = null;
      _courseFilter = null;
      _facultyFilter = null;
      _levelFilter = null;
      _remoteOnly = false;
    });
  }

  Future<void> _showFilters() async {
    HapticFeedback.selectionClick();
    var types = Set<String>.from(_typeFilters);
    var location = _locationFilter;
    var course = _courseFilter;
    var faculty = _facultyFilter;
    var level = _levelFilter;
    var remote = _remoteOnly;

    final result = await showModalBottomSheet<_CareerFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => _FilterSheet(
          selectedTypes: types,
          location: location,
          course: course,
          faculty: faculty,
          level: level,
          remoteOnly: remote,
          locations: _distinctValues('location'),
          courses: _distinctValues('course'),
          faculties: _distinctValues('faculty'),
          levels: _distinctValues('level'),
          onTypesChanged: (value) => setSheetState(() => types = value),
          onLocationChanged: (value) => setSheetState(() => location = value),
          onCourseChanged: (value) => setSheetState(() => course = value),
          onFacultyChanged: (value) => setSheetState(() => faculty = value),
          onLevelChanged: (value) => setSheetState(() => level = value),
          onRemoteChanged: (value) => setSheetState(() => remote = value),
        ),
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      _typeFilters = result.types;
      _locationFilter = result.location;
      _courseFilter = result.course;
      _facultyFilter = result.faculty;
      _levelFilter = result.level;
      _remoteOnly = result.remoteOnly;
    });
  }

  List<String> _distinctValues(String field) {
    final values =
        _opportunities
            .map((item) => (item[field] ?? '').toString().trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return values;
  }

  Future<void> _showOpportunity(Map<String, dynamic> opportunity) async {
    HapticFeedback.lightImpact();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OpportunitySheet(
        opportunity: opportunity,
        hasApplied: _applications.any(
          (application) =>
              application['opportunity_id'] == opportunity['id'] &&
              application['status'] != 'withdrawn',
        ),
        onApply: () {
          Navigator.pop(context);
          _startApplication(opportunity);
        },
      ),
    );
  }

  Future<void> _startApplication(Map<String, dynamic> opportunity) async {
    HapticFeedback.mediumImpact();
    final result = await showDialog<_ApplicationPayload>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ApplicationWizard(
        opportunity: opportunity,
        profile: _profile,
        documents: _documents,
      ),
    );
    if (result == null || !mounted) return;
    await _submitApplication(opportunity, result);
  }

  Future<void> _submitApplication(
    Map<String, dynamic> opportunity,
    _ApplicationPayload payload,
  ) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final application = await _client
          .from('career_applications')
          .upsert({
            'opportunity_id': opportunity['id'],
            'student_id': user.id,
            'status': 'submitted',
            'cover_note': payload.coverNote.trim(),
            'submitted_at': now,
            'updated_at': now,
          }, onConflict: 'opportunity_id,student_id')
          .select('id')
          .single();

      final applicationId = application['id'].toString();
      await _client
          .from('career_application_documents')
          .delete()
          .eq('application_id', applicationId);
      await _client
          .from('career_application_documents')
          .insert(
            payload.documentIds
                .map(
                  (documentId) => {
                    'application_id': applicationId,
                    'document_id': documentId,
                  },
                )
                .toList(),
          );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      HapticFeedback.heavyImpact();
      setState(() => _selectedTab = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Application submitted for ${opportunity['title']}.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Application could not be submitted. Please retry.'),
        ),
      );
    }
  }

  Future<void> _withdrawApplication(Map<String, dynamic> application) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw application?'),
        content: const Text(
          'This keeps the application in your history but marks it withdrawn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep application'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _client
          .from('career_applications')
          .update({
            'status': 'withdrawn',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', application['id']);
      HapticFeedback.mediumImpact();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not withdraw this application.')),
      );
    }
  }

  void _showResource(Map<String, dynamic> resource) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ResourceSheet(resource: resource),
    );
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Career & Funding'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          Semantics(
            button: true,
            label: 'Refresh career data',
            child: IconButton(
              tooltip: 'Refresh',
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 900 ? 32.0 : 16.0;
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    8,
                    horizontalPadding,
                    24,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _CareerHero(
                              opportunityCount: _opportunities.length,
                              applicationCount: _applications
                                  .where(
                                    (item) => item['status'] != 'withdrawn',
                                  )
                                  .length,
                              offline: _offlineData,
                            ),
                            const SizedBox(height: 18),
                            _CareerTabBar(
                              selectedIndex: _selectedTab,
                              opportunityCount: _opportunities.length,
                              applicationCount: _applications.length,
                              onSelected: _selectTab,
                            ),
                            const SizedBox(height: 18),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              switchInCurve: Curves.easeOutCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0.025, 0),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: _selectedTab == 0
                                  ? _buildOpportunities(
                                      key: const ValueKey('opportunities'),
                                      wide: constraints.maxWidth >= 820,
                                    )
                                  : _buildApplications(
                                      key: const ValueKey('applications'),
                                    ),
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildOpportunities({required Key key, required bool wide}) {
    final filtered = _filteredOpportunities;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search title, employer, qualification or keyword',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                _activeFilterCount == 0
                    ? 'Explore opportunities matched to your goals'
                    : '$_activeFilterCount active '
                          'filter${_activeFilterCount == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_activeFilterCount > 0)
              TextButton(onPressed: _clearFilters, child: const Text('Clear')),
            Badge(
              isLabelVisible: _activeFilterCount > 0,
              label: Text('$_activeFilterCount'),
              child: OutlinedButton.icon(
                onPressed: _showFilters,
                icon: const Icon(Icons.tune_rounded, size: 19),
                label: const Text('Filters'),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _StatusBanner(
            message: _error!,
            offline: _offlineData,
            onRetry: _refresh,
          ),
        ],
        const SizedBox(height: 18),
        if (_loading)
          const _CareerLoading()
        else if (filtered.isEmpty)
          _EmptyCareerState(
            filtered: _opportunities.isNotEmpty,
            onClear: _clearFilters,
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: wide ? 2 : 1,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent: 250,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) => TweenAnimationBuilder<double>(
              duration: Duration(milliseconds: 260 + (index.clamp(0, 5) * 45)),
              tween: Tween(begin: 0, end: 1),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Transform.translate(
                offset: Offset(0, 12 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              ),
              child: _OpportunityCard(
                opportunity: filtered[index],
                applied: _applications.any(
                  (application) =>
                      application['opportunity_id'] == filtered[index]['id'] &&
                      application['status'] != 'withdrawn',
                ),
                onTap: () => _showOpportunity(filtered[index]),
              ),
            ),
          ),
        if (_resources.isNotEmpty) ...[
          const SizedBox(height: 28),
          Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                  eyebrow: 'CAREER TOOLKIT',
                  title: 'Prepare with confidence',
                ),
              ),
              Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.ogGold.withValues(alpha: .9),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 174,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _resources.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _ResourceCard(
                resource: _resources[index],
                onTap: () => _showResource(_resources[index]),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildApplications({required Key key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          eyebrow: 'YOUR JOURNEY',
          title: 'Applications',
          subtitle:
              'Submissions update in real time and stay private to your account.',
        ),
        const SizedBox(height: 16),
        if (_applications.isEmpty)
          _ApplicationEmptyState(onBrowse: () => _selectTab(0))
        else
          ..._applications.asMap().entries.map((entry) {
            final application = entry.value;
            final opportunity = _opportunityById(
              application['opportunity_id']?.toString(),
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ApplicationCard(
                application: application,
                title: _opportunityTitle(
                  application['opportunity_id']?.toString(),
                ),
                company: (opportunity?['company'] ?? 'Opportunity provider')
                    .toString(),
                onWithdraw: application['status'] == 'submitted'
                    ? () => _withdrawApplication(application)
                    : null,
              ),
            );
          }),
      ],
    );
  }
}

class _CareerHero extends StatelessWidget {
  const _CareerHero({
    required this.opportunityCount,
    required this.applicationCount,
    required this.offline,
  });

  final int opportunityCount;
  final int applicationCount;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: AppStyles.bentoRadius,
        boxShadow: AppStyles.glassShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -48,
            top: -70,
            child: Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.electricCyan.withValues(alpha: .14),
              ),
            ),
          ),
          Positioned(
            right: 42,
            bottom: -84,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.ogGold.withValues(alpha: .12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .13),
                        borderRadius: AppStyles.pillRadius,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .2),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            size: 16,
                            color: AppColors.electricCyan,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'OG CAREER HUB',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (offline)
                      const _HeroStatus(
                        icon: Icons.cloud_off_rounded,
                        label: 'Offline',
                      )
                    else
                      const _HeroStatus(
                        icon: Icons.wifi_tethering_rounded,
                        label: 'Live',
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'Your next move\nstarts here.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Discover opportunities, prepare your documents and apply '
                  'with confidence.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .76),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _HeroStat(
                      value: '$opportunityCount',
                      label: 'Live opportunities',
                    ),
                    _HeroStat(
                      value: '$applicationCount',
                      label: 'Active applications',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStatus extends StatelessWidget {
  const _HeroStatus({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .72),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _CareerTabBar extends StatelessWidget {
  const _CareerTabBar({
    required this.selectedIndex,
    required this.opportunityCount,
    required this.applicationCount,
    required this.onSelected,
  });

  final int selectedIndex;
  final int opportunityCount;
  final int applicationCount;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      padding: const EdgeInsets.all(5),
      radius: 20,
      child: Row(
        children: [
          Expanded(
            child: _CareerTab(
              selected: selectedIndex == 0,
              icon: Icons.explore_rounded,
              label: 'Opportunities',
              count: opportunityCount,
              onTap: () => onSelected(0),
            ),
          ),
          Expanded(
            child: _CareerTab(
              selected: selectedIndex == 1,
              icon: Icons.assignment_turned_in_rounded,
              label: 'Applications',
              count: applicationCount,
              onTap: () => onSelected(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _CareerTab extends StatelessWidget {
  const _CareerTab({
    required this.selected,
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label tab, $count items',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            gradient: selected ? AppStyles.brandGradient : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.vibeBlue.withValues(alpha: .2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? Colors.white : AppColors.textMuted,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.midnightInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: .16)
                      : AppColors.vibeBlue.withValues(alpha: .08),
                  borderRadius: AppStyles.pillRadius,
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.vibeBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({
    required this.opportunity,
    required this.applied,
    required this.onTap,
  });

  final Map<String, dynamic> opportunity;
  final bool applied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final company = (opportunity['company'] ?? 'Opportunity provider')
        .toString();
    final logoUrl = (opportunity['employer_logo_url'] ?? '').toString();
    final location = (opportunity['location'] ?? '').toString();
    final remote = opportunity['is_remote'] == true;
    final closingAt = DateTime.tryParse(
      (opportunity['closing_at'] ?? '').toString(),
    );

    return Semantics(
      button: true,
      label: '${opportunity['title']} at $company',
      child: _GlassSurface(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppStyles.bentoRadius,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EmployerLogo(name: company, url: logoUrl),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            company,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: AppColors.vibeBlue,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (opportunity['title'] ?? 'Untitled opportunity')
                                .toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: AppColors.midnightInk,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (opportunity['is_verified'] == true)
                      const Tooltip(
                        message: 'Verified opportunity',
                        child: Icon(
                          Icons.verified_rounded,
                          size: 20,
                          color: AppColors.vibeBlue,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _MetaPill(
                      icon: Icons.work_outline_rounded,
                      label: _prettyType(opportunity),
                    ),
                    if (remote)
                      const _MetaPill(
                        icon: Icons.public_rounded,
                        label: 'Remote',
                      )
                    else if (location.isNotEmpty)
                      _MetaPill(
                        icon: Icons.location_on_outlined,
                        label: location,
                      ),
                    if (closingAt != null)
                      _MetaPill(
                        icon: Icons.event_outlined,
                        label:
                            'Closes ${DateFormat('d MMM').format(closingAt)}',
                        accent: _isClosingSoon(closingAt),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        applied ? 'Application submitted' : 'View opportunity',
                        style: TextStyle(
                          color: applied
                              ? AppColors.success
                              : AppColors.midnightInk,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      applied
                          ? Icons.check_circle_rounded
                          : Icons.arrow_forward_rounded,
                      color: applied ? AppColors.success : AppColors.vibeBlue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _prettyType(Map<String, dynamic> opportunity) {
    final value = (opportunity['category'] ?? opportunity['type'] ?? 'Other')
        .toString();
    return value
        .split(RegExp(r'[_\s]+'))
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  static bool _isClosingSoon(DateTime date) {
    final days = date.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 7;
  }
}

class _EmployerLogo extends StatelessWidget {
  const _EmployerLogo({required this.name, required this.url});

  final String name;
  final String url;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      alignment: Alignment.center,
      color: AppColors.vibeBlue.withValues(alpha: .08),
      child: Text(
        name.trim().isEmpty ? 'OG' : name.trim()[0].toUpperCase(),
        style: const TextStyle(
          color: AppColors.vibeBlue,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    return Container(
      width: 54,
      height: 54,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: url.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppColors.danger : AppColors.textMuted;
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpportunitySheet extends StatelessWidget {
  const _OpportunitySheet({
    required this.opportunity,
    required this.hasApplied,
    required this.onApply,
  });

  final Map<String, dynamic> opportunity;
  final bool hasApplied;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final requirements = List<String>.from(
      (opportunity['requirements'] as List<dynamic>? ?? const []).map(
        (item) => item.toString(),
      ),
    );
    final company = (opportunity['company'] ?? 'Opportunity provider')
        .toString();
    final qualification = (opportunity['qualification'] ?? '').toString();
    final closingAt = DateTime.tryParse(
      (opportunity['closing_at'] ?? '').toString(),
    );

    return _BottomSheetShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EmployerLogo(
                name: company,
                url: (opportunity['employer_logo_url'] ?? '').toString(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company,
                      style: const TextStyle(
                        color: AppColors.vibeBlue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (opportunity['title'] ?? 'Opportunity').toString(),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.midnightInk,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaPill(
                icon: Icons.work_outline_rounded,
                label: _OpportunityCard._prettyType(opportunity),
              ),
              if (opportunity['is_remote'] == true)
                const _MetaPill(icon: Icons.public_rounded, label: 'Remote')
              else if ((opportunity['location'] ?? '').toString().isNotEmpty)
                _MetaPill(
                  icon: Icons.location_on_outlined,
                  label: opportunity['location'].toString(),
                ),
              if (closingAt != null)
                _MetaPill(
                  icon: Icons.event_outlined,
                  label: 'Closes ${DateFormat('d MMM yyyy').format(closingAt)}',
                ),
            ],
          ),
          if (qualification.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _SheetHeading('Qualification'),
            const SizedBox(height: 7),
            Text(qualification),
          ],
          const SizedBox(height: 22),
          const _SheetHeading('About this opportunity'),
          const SizedBox(height: 7),
          Text(
            (opportunity['description'] ?? 'No description supplied.')
                .toString(),
            style: const TextStyle(height: 1.55),
          ),
          if (requirements.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _SheetHeading('What you will need'),
            const SizedBox(height: 8),
            ...requirements.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 19,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 9),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: hasApplied ? null : onApply,
              icon: Icon(
                hasApplied
                    ? Icons.check_circle_rounded
                    : Icons.arrow_forward_rounded,
              ),
              label: Text(
                hasApplied ? 'Application submitted' : 'Start application',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicationWizard extends StatefulWidget {
  const _ApplicationWizard({
    required this.opportunity,
    required this.profile,
    required this.documents,
  });

  final Map<String, dynamic> opportunity;
  final Map<String, dynamic>? profile;
  final List<Map<String, dynamic>> documents;

  @override
  State<_ApplicationWizard> createState() => _ApplicationWizardState();
}

class _ApplicationWizardState extends State<_ApplicationWizard> {
  final _coverNoteController = TextEditingController();
  final Set<String> _selectedDocuments = {};
  int _step = 0;
  String? _validationMessage;

  @override
  void dispose() {
    _coverNoteController.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_step == 1 && _selectedDocuments.isEmpty) {
      setState(() {
        _validationMessage =
            'Select at least one Document Wallet file to continue.';
      });
      return;
    }
    setState(() {
      _validationMessage = null;
      _step++;
    });
  }

  void _back() {
    HapticFeedback.selectionClick();
    setState(() {
      _validationMessage = null;
      _step--;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 620, maxHeight: size.height * .9),
        child: _GlassSurface(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 12, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: AppStyles.brandGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.rocket_launch_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Application assistant',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Step ${_step + 1} of 3',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close application',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: List.generate(
                    3,
                    (index) => Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: 4,
                        margin: EdgeInsets.only(right: index == 2 ? 0 : 7),
                        decoration: BoxDecoration(
                          color: index <= _step
                              ? AppColors.vibeBlue
                              : AppColors.glassBorder,
                          borderRadius: AppStyles.pillRadius,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: [
                      _buildProfileStep(),
                      _buildDocumentsStep(),
                      _buildReviewStep(),
                    ][_step],
                  ),
                ),
              ),
              if (_validationMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _validationMessage!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
                child: Row(
                  children: [
                    if (_step > 0)
                      OutlinedButton.icon(
                        onPressed: _back,
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Back'),
                      ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _step == 2
                          ? () {
                              HapticFeedback.mediumImpact();
                              Navigator.pop(
                                context,
                                _ApplicationPayload(
                                  documentIds: _selectedDocuments.toList(),
                                  coverNote: _coverNoteController.text,
                                ),
                              );
                            }
                          : _next,
                      icon: Icon(
                        _step == 2
                            ? Icons.send_rounded
                            : Icons.arrow_forward_rounded,
                      ),
                      label: Text(
                        _step == 2 ? 'Submit application' : 'Continue',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileStep() {
    final profile = widget.profile;
    return Column(
      key: const ValueKey('profile-step'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SheetHeading('Review your fit'),
        const SizedBox(height: 6),
        Text(
          (widget.opportunity['title'] ?? 'Opportunity').toString(),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 18),
        _ReviewRow(
          icon: Icons.person_outline_rounded,
          label: 'Student',
          value: profile == null
              ? 'Profile details unavailable'
              : '${profile['name'] ?? ''} ${profile['surname'] ?? ''}'.trim(),
        ),
        _ReviewRow(
          icon: Icons.school_outlined,
          label: 'Course',
          value: (profile?['course'] ?? 'Not specified').toString(),
        ),
        _ReviewRow(
          icon: Icons.account_balance_outlined,
          label: 'Faculty',
          value: (profile?['faculty'] ?? 'Not specified').toString(),
        ),
        _ReviewRow(
          icon: Icons.stairs_outlined,
          label: 'Level',
          value: (profile?['level'] ?? 'Not specified').toString(),
        ),
        const SizedBox(height: 8),
        const _InfoCallout(
          icon: Icons.shield_outlined,
          text:
              'Your profile and attached documents remain private to your '
              'account.',
        ),
      ],
    );
  }

  Widget _buildDocumentsStep() {
    return Column(
      key: const ValueKey('documents-step'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SheetHeading('Choose Document Wallet files'),
        const SizedBox(height: 6),
        const Text(
          'Select the documents required for this application. Files remain '
          'in your private wallet.',
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 16),
        if (widget.documents.isEmpty)
          const _InfoCallout(
            icon: Icons.folder_off_outlined,
            text:
                'Your Document Wallet is empty. Add a document there, then '
                'restart this application.',
          )
        else
          ...widget.documents.map((document) {
            final id = document['id'].toString();
            final selected = _selectedDocuments.contains(id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (selected) {
                      _selectedDocuments.remove(id);
                    } else {
                      _selectedDocuments.add(id);
                    }
                    _validationMessage = null;
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.vibeBlue.withValues(alpha: .07)
                        : Colors.white.withValues(alpha: .58),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? AppColors.vibeBlue
                          : AppColors.glassBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        color: selected
                            ? AppColors.vibeBlue
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (document['title'] ?? document['file_name'])
                                  .toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              (document['folder'] ?? 'Personal').toString(),
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Checkbox(
                        value: selected,
                        onChanged: (_) {
                          setState(() {
                            if (selected) {
                              _selectedDocuments.remove(id);
                            } else {
                              _selectedDocuments.add(id);
                            }
                            _validationMessage = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildReviewStep() {
    return Column(
      key: const ValueKey('review-step'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SheetHeading('Final review'),
        const SizedBox(height: 6),
        const Text(
          'Add a short, tailored note and confirm your selected files.',
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _coverNoteController,
          minLines: 4,
          maxLines: 7,
          maxLength: 1200,
          decoration: const InputDecoration(
            labelText: 'Cover note (optional)',
            hintText: 'Why are you a strong fit for this opportunity?',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        _ReviewRow(
          icon: Icons.attach_file_rounded,
          label: 'Documents',
          value:
              '${_selectedDocuments.length} file'
              '${_selectedDocuments.length == 1 ? '' : 's'} selected',
        ),
        const _InfoCallout(
          icon: Icons.info_outline_rounded,
          text:
              'Submitting records this application in Career Hub. Review the '
              'opportunity provider’s instructions for any external steps.',
        ),
      ],
    );
  }
}

class _ApplicationPayload {
  const _ApplicationPayload({
    required this.documentIds,
    required this.coverNote,
  });

  final List<String> documentIds;
  final String coverNote;
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.application,
    required this.title,
    required this.company,
    required this.onWithdraw,
  });

  final Map<String, dynamic> application;
  final String title;
  final String company;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final status = (application['status'] ?? 'submitted').toString();
    final date = DateTime.tryParse(
      (application['submitted_at'] ?? application['created_at'] ?? '')
          .toString(),
    );
    final statusColor = switch (status) {
      'withdrawn' => AppColors.textMuted,
      'draft' => AppColors.warning,
      _ => AppColors.success,
    };

    return _GlassSurface(
      padding: const EdgeInsets.all(17),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              status == 'withdrawn'
                  ? Icons.undo_rounded
                  : Icons.assignment_turned_in_rounded,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.midnightInk,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  company,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: .08),
                        borderRadius: AppStyles.pillRadius,
                      ),
                      child: Text(
                        status[0].toUpperCase() + status.substring(1),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (date != null) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          DateFormat('d MMM yyyy').format(date),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (onWithdraw != null)
            PopupMenuButton<String>(
              tooltip: 'Application actions',
              onSelected: (_) => onWithdraw!(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'withdraw',
                  child: Row(
                    children: [
                      Icon(Icons.undo_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Withdraw'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.resource, required this.onTap});

  final Map<String, dynamic> resource;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 272,
      child: _GlassSurface(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppStyles.bentoRadius,
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: AppStyles.brandGradient,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    _resourceIcon(resource['icon_name']?.toString()),
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  (resource['title'] ?? 'Career resource').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.midnightInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  (resource['summary'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.35,
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

class _ResourceSheet extends StatelessWidget {
  const _ResourceSheet({required this.resource});

  final Map<String, dynamic> resource;

  @override
  Widget build(BuildContext context) {
    return _BottomSheetShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppStyles.brandGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _resourceIcon(resource['icon_name']?.toString()),
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            (resource['title'] ?? 'Career resource').toString(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.midnightInk,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            (resource['summary'] ?? '').toString(),
            style: const TextStyle(
              color: AppColors.vibeBlue,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            (resource['body'] ?? '').toString(),
            style: const TextStyle(height: 1.7),
          ),
        ],
      ),
    );
  }
}

IconData _resourceIcon(String? name) => switch (name) {
  'task_alt' => Icons.task_alt_rounded,
  'record_voice_over' => Icons.record_voice_over_rounded,
  _ => Icons.description_outlined,
};

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({
    required this.selectedTypes,
    required this.location,
    required this.course,
    required this.faculty,
    required this.level,
    required this.remoteOnly,
    required this.locations,
    required this.courses,
    required this.faculties,
    required this.levels,
    required this.onTypesChanged,
    required this.onLocationChanged,
    required this.onCourseChanged,
    required this.onFacultyChanged,
    required this.onLevelChanged,
    required this.onRemoteChanged,
  });

  final Set<String> selectedTypes;
  final String? location;
  final String? course;
  final String? faculty;
  final String? level;
  final bool remoteOnly;
  final List<String> locations;
  final List<String> courses;
  final List<String> faculties;
  final List<String> levels;
  final ValueChanged<Set<String>> onTypesChanged;
  final ValueChanged<String?> onLocationChanged;
  final ValueChanged<String?> onCourseChanged;
  final ValueChanged<String?> onFacultyChanged;
  final ValueChanged<String?> onLevelChanged;
  final ValueChanged<bool> onRemoteChanged;

  static const types = [
    'job',
    'internship',
    'learnership',
    'bursary',
    'graduate programme',
  ];

  @override
  Widget build(BuildContext context) {
    return _BottomSheetShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Refine opportunities',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Close filters',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _SheetHeading('Opportunity type'),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: types.map((type) {
              final selected = selectedTypes.contains(type);
              return FilterChip(
                selected: selected,
                label: Text(_titleCase(type)),
                avatar: selected
                    ? const Icon(Icons.check_rounded, size: 16)
                    : null,
                onSelected: (value) {
                  final updated = Set<String>.from(selectedTypes);
                  value ? updated.add(type) : updated.remove(type);
                  onTypesChanged(updated);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: remoteOnly,
            onChanged: onRemoteChanged,
            title: const Text(
              'Remote opportunities only',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            secondary: const Icon(Icons.public_rounded),
          ),
          const SizedBox(height: 6),
          _FilterDropdown(
            label: 'Location',
            icon: Icons.location_on_outlined,
            value: location,
            values: locations,
            onChanged: onLocationChanged,
          ),
          const SizedBox(height: 12),
          _FilterDropdown(
            label: 'Faculty',
            icon: Icons.account_balance_outlined,
            value: faculty,
            values: faculties,
            onChanged: onFacultyChanged,
          ),
          const SizedBox(height: 12),
          _FilterDropdown(
            label: 'Course',
            icon: Icons.school_outlined,
            value: course,
            values: courses,
            onChanged: onCourseChanged,
          ),
          const SizedBox(height: 12),
          _FilterDropdown(
            label: 'Level',
            icon: Icons.stairs_outlined,
            value: level,
            values: levels,
            onChanged: onLevelChanged,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      const _CareerFilters(types: {}, remoteOnly: false),
                    );
                  },
                  child: const Text('Reset all'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      _CareerFilters(
                        types: selectedTypes,
                        location: location,
                        course: course,
                        faculty: faculty,
                        level: level,
                        remoteOnly: remoteOnly,
                      ),
                    );
                  },
                  child: const Text('Apply filters'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final String? value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: values.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Any')),
        ...values.map(
          (item) => DropdownMenuItem<String?>(
            value: item,
            child: Text(item, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _CareerFilters {
  const _CareerFilters({
    required this.types,
    this.location,
    this.course,
    this.faculty,
    this.level,
    required this.remoteOnly,
  });

  final Set<String> types;
  final String? location;
  final String? course;
  final String? faculty;
  final String? level;
  final bool remoteOnly;
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: .9),
              width: 1.2,
            ),
            boxShadow: AppStyles.glassShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _BottomSheetShell extends StatelessWidget {
  const _BottomSheetShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: .78,
      minChildSize: .48,
      maxChildSize: .94,
      expand: false,
      builder: (context, controller) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .94),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(color: Colors.white),
            ),
            child: ListView(
              controller: controller,
              padding: EdgeInsets.fromLTRB(22, 10, 22, 24 + bottom),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.glassBorder,
                      borderRadius: AppStyles.pillRadius,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: AppColors.vibeBlue,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.midnightInk,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            style: const TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _SheetHeading extends StatelessWidget {
  const _SheetHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: AppColors.midnightInk,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.vibeBlue.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: AppColors.vibeBlue),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCallout extends StatelessWidget {
  const _InfoCallout({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.electricCyan.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.electricCyan.withValues(alpha: .18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.vibeBlue),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.message,
    required this.offline,
    required this.onRetry,
  });

  final String message;
  final bool offline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 9, 8, 9),
      decoration: BoxDecoration(
        color: (offline ? AppColors.warning : AppColors.danger).withValues(
          alpha: .08,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            offline ? Icons.cloud_off_rounded : Icons.info_outline_rounded,
            size: 19,
            color: offline ? AppColors.warning : AppColors.danger,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _CareerLoading extends StatelessWidget {
  const _CareerLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          height: 170,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .52),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(color: Colors.white),
          ),
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _EmptyCareerState extends StatelessWidget {
  const _EmptyCareerState({required this.filtered, required this.onClear});

  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: AppStyles.brandGradient,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    filtered ? Icons.search_off_rounded : Icons.explore_rounded,
                    size: 34,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  filtered
                      ? 'No opportunities match'
                      : 'Fresh opportunities are on the way',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  filtered
                      ? 'Try another keyword or clear your filters.'
                      : 'Verified jobs, internships, learnerships, bursaries '
                            'and graduate programmes will appear here when '
                            'published.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
                if (filtered) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.filter_alt_off_rounded),
                    label: const Text('Clear filters'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApplicationEmptyState extends StatelessWidget {
  const _ApplicationEmptyState({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            children: [
              const Icon(
                Icons.assignment_outlined,
                size: 50,
                color: AppColors.vibeBlue,
              ),
              const SizedBox(height: 14),
              Text(
                'No applications yet',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 7),
              const Text(
                'Browse opportunities and use the guided assistant to apply.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onBrowse,
                icon: const Icon(Icons.explore_rounded),
                label: const Text('Browse opportunities'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _titleCase(String value) => value
    .split(RegExp(r'[_\s]+'))
    .map(
      (word) => word.isEmpty
          ? word
          : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
    )
    .join(' ');

Map<String, dynamic> mapCareerRowToItem(Map<String, dynamic> row) {
  return {
    'id': row['id'],
    'title': (row['title'] ?? '').toString(),
    'description': (row['description'] ?? '').toString(),
    'category': (row['category'] ?? '').toString(),
    'company': (row['company'] ?? '').toString(),
    'duration': (row['duration'] ?? '').toString(),
    'type': (row['type'] ?? '').toString(),
    'salary': (row['salary'] ?? '').toString(),
    'location': (row['location'] ?? '').toString(),
    'qualification': (row['qualification'] ?? '').toString(),
    'is_remote': row['is_remote'] == true,
  };
}
