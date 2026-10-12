import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';
import 'chat_detail_screen.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final List<FriendProfile> _discover = <FriendProfile>[];
  final List<FriendRequestEntry> _incoming = <FriendRequestEntry>[];
  final List<FriendRequestEntry> _outgoing = <FriendRequestEntry>[];
  final List<FriendProfile> _friends = <FriendProfile>[];

  late final TabController _tabController;
  bool _loading = true;
  bool _refreshing = false;
  bool _filtersExpanded = false;
  String? _error;
  String _search = '';
  String _campus = 'All';
  String _faculty = 'All';
  String _course = 'All';
  String _level = 'All';

  SupabaseClient get _supabase => Supabase.instance.client;
  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging && mounted) setState(() {});
      });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    final user = _user;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sign in to discover your campus community.';
      });
      return;
    }

    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _refreshing = true);
    }

    try {
      final responses = await Future.wait<dynamic>(<Future<dynamic>>[
        _supabase
            .from('profiles')
            .select(
              'id, name, surname, nickname, campus, department, faculty, '
              'course, level, photo_url, is_verified, is_online',
            )
            .neq('id', user.id)
            .order('name'),
        _supabase
            .from('friend_requests')
            .select(
              'id, sender_id, receiver_id, status, created_at, updated_at',
            )
            .or('sender_id.eq.${user.id},receiver_id.eq.${user.id}')
            .eq('status', 'pending')
            .order('created_at', ascending: false),
        _supabase
            .from('friendships')
            .select('user_id, friend_id, created_at')
            .or('user_id.eq.${user.id},friend_id.eq.${user.id}'),
      ]);

      final profileRows = List<Map<String, dynamic>>.from(
        responses[0] as List<dynamic>,
      );
      final requestRows = List<Map<String, dynamic>>.from(
        responses[1] as List<dynamic>,
      );
      final friendshipRows = List<Map<String, dynamic>>.from(
        responses[2] as List<dynamic>,
      );
      final profiles = profileRows.map(FriendProfile.fromRow).toList();
      final profileMap = <String, FriendProfile>{
        for (final profile in profiles) profile.id: profile,
      };

      final friendIds = friendshipRows.map((row) {
        final first = row['user_id'].toString();
        return first == user.id ? row['friend_id'].toString() : first;
      }).toSet();

      final counts = <String, int>{};
      if (profiles.isNotEmpty) {
        final mutualRows = List<Map<String, dynamic>>.from(
          await _supabase.rpc(
                'get_mutual_friend_counts',
                params: <String, dynamic>{
                  'candidate_ids': profiles
                      .map((profile) => profile.id)
                      .toList(),
                },
              )
              as List<dynamic>,
        );
        for (final row in mutualRows) {
          counts[row['candidate_id'].toString()] =
              int.tryParse(row['mutual_count']?.toString() ?? '') ?? 0;
        }
      }

      final enrichedProfiles = profiles
          .map(
            (profile) =>
                profile.copyWith(mutualFriendCount: counts[profile.id] ?? 0),
          )
          .toList();
      final enrichedMap = <String, FriendProfile>{
        for (final profile in enrichedProfiles) profile.id: profile,
      };

      final incoming = <FriendRequestEntry>[];
      final outgoing = <FriendRequestEntry>[];
      for (final row in requestRows) {
        final senderId = row['sender_id'].toString();
        final receiverId = row['receiver_id'].toString();
        if (receiverId == user.id) {
          final profile = enrichedMap[senderId] ?? profileMap[senderId];
          if (profile != null) {
            incoming.add(FriendRequestEntry.fromRow(row, profile));
          }
        } else if (senderId == user.id) {
          final profile = enrichedMap[receiverId] ?? profileMap[receiverId];
          if (profile != null) {
            outgoing.add(FriendRequestEntry.fromRow(row, profile));
          }
        }
      }

      final incomingIds = incoming.map((entry) => entry.profile.id).toSet();
      final outgoingIds = outgoing.map((entry) => entry.profile.id).toSet();
      final friends =
          enrichedProfiles
              .where((profile) => friendIds.contains(profile.id))
              .toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));
      final discover =
          enrichedProfiles
              .where(
                (profile) =>
                    !friendIds.contains(profile.id) &&
                    !incomingIds.contains(profile.id) &&
                    !outgoingIds.contains(profile.id),
              )
              .toList()
            ..sort((a, b) {
              final mutualComparison = b.mutualFriendCount.compareTo(
                a.mutualFriendCount,
              );
              return mutualComparison != 0
                  ? mutualComparison
                  : a.displayName.compareTo(b.displayName);
            });

      if (!mounted) return;
      setState(() {
        _discover
          ..clear()
          ..addAll(discover);
        _incoming
          ..clear()
          ..addAll(incoming);
        _outgoing
          ..clear()
          ..addAll(outgoing);
        _friends
          ..clear()
          ..addAll(friends);
        _loading = false;
        _refreshing = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = _friendlyError(error);
      });
    }
  }

  List<FriendProfile> get _allProfiles => <FriendProfile>[
    ..._incoming.map((entry) => entry.profile),
    ..._outgoing.map((entry) => entry.profile),
    ..._friends,
    ..._discover,
  ];

  List<String> _options(String Function(FriendProfile) value) {
    final values =
        _allProfiles
            .map(value)
            .where((entry) => entry.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return <String>['All', ...values];
  }

  bool _matches(FriendProfile profile) {
    final nameMatches =
        _search.isEmpty ||
        profile.displayName.toLowerCase().contains(_search.toLowerCase());
    return nameMatches &&
        (_campus == 'All' || profile.campus == _campus) &&
        (_faculty == 'All' || profile.faculty == _faculty) &&
        (_course == 'All' || profile.course == _course) &&
        (_level == 'All' || profile.level == _level);
  }

  int get _activeFilterCount => <bool>[
    _campus != 'All',
    _faculty != 'All',
    _course != 'All',
    _level != 'All',
  ].where((active) => active).length;

  void _clearFilters() {
    HapticFeedback.selectionClick();
    setState(() {
      _campus = 'All';
      _faculty = 'All';
      _course = 'All';
      _level = 'All';
    });
  }

  Future<void> _sendRequest(FriendProfile profile) async {
    final user = _user;
    if (user == null) return;
    try {
      HapticFeedback.mediumImpact();
      await _supabase.from('friend_requests').insert(<String, dynamic>{
        'sender_id': user.id,
        'receiver_id': profile.id,
        'status': 'pending',
      });
      await _loadData(showLoader: false);
      _tabController.animateTo(1);
      _showSnack('Friend request sent to ${profile.displayName}.');
    } on PostgrestException catch (error) {
      _showSnack(
        error.code == '23505'
            ? 'A request between you is already pending.'
            : _friendlyError(error),
      );
    } catch (error) {
      _showSnack(_friendlyError(error));
    }
  }

  Future<void> _acceptRequest(FriendRequestEntry entry) async {
    try {
      HapticFeedback.mediumImpact();
      await _supabase.rpc(
        'accept_friend_request',
        params: <String, dynamic>{'request_id': entry.id},
      );
      await _loadData(showLoader: false);
      _tabController.animateTo(2);
      _showSnack('${entry.profile.displayName} is now your friend.');
    } catch (error) {
      _showSnack(_friendlyError(error));
    }
  }

  Future<void> _declineRequest(FriendRequestEntry entry) async {
    try {
      await _supabase
          .from('friend_requests')
          .update(<String, dynamic>{
            'status': 'declined',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', entry.id);
      HapticFeedback.selectionClick();
      await _loadData(showLoader: false);
      _showSnack('Request declined.');
    } catch (error) {
      _showSnack(_friendlyError(error));
    }
  }

  Future<void> _cancelRequest(FriendRequestEntry entry) async {
    try {
      await _supabase
          .from('friend_requests')
          .update(<String, dynamic>{
            'status': 'cancelled',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', entry.id);
      HapticFeedback.selectionClick();
      await _loadData(showLoader: false);
      _showSnack('Friend request cancelled.');
    } catch (error) {
      _showSnack(_friendlyError(error));
    }
  }

  Future<void> _removeFriend(FriendProfile profile) async {
    final user = _user;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.person_remove_outlined,
          color: AppColors.danger,
          size: 32,
        ),
        title: Text('Remove ${profile.displayName}?'),
        content: const Text(
          'You will need to send a new request before chatting from Find Friends again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep friend'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase.from('friendships').delete().match(<String, Object>{
        'user_id': user.id,
        'friend_id': profile.id,
      });
      await _supabase.from('friendships').delete().match(<String, Object>{
        'user_id': profile.id,
        'friend_id': user.id,
      });
      HapticFeedback.mediumImpact();
      await _loadData(showLoader: false);
      _showSnack('${profile.displayName} was removed.');
    } catch (error) {
      _showSnack(_friendlyError(error));
    }
  }

  void _openChat(FriendProfile friend) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChatDetailScreen(chatId: friend.id, chatTitle: friend.displayName),
      ),
    );
  }

  void _showProfile(
    FriendProfile profile, {
    FriendRelationship relationship = FriendRelationship.discover,
    FriendRequestEntry? request,
  }) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.glassBorder,
                    borderRadius: AppStyles.pillRadius,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  _ProfileAvatar(profile: profile, radius: 40),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                profile.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.midnightInk,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (profile.isVerified) ...<Widget>[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.verified_rounded,
                                color: AppColors.vibeBlue,
                                size: 19,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          profile.course,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _InfoChip(
                    icon: Icons.location_on_outlined,
                    label: profile.campus,
                  ),
                  _InfoChip(
                    icon: Icons.account_balance_outlined,
                    label: profile.faculty,
                  ),
                  _InfoChip(icon: Icons.stairs_outlined, label: profile.level),
                  if (profile.mutualFriendCount > 0)
                    _InfoChip(
                      icon: Icons.people_outline_rounded,
                      label:
                          '${profile.mutualFriendCount} mutual friend${profile.mutualFriendCount == 1 ? '' : 's'}',
                      highlight: true,
                    ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Campus profile',
                style: TextStyle(
                  color: AppColors.midnightInk,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              _ProfileInfoPanel(profile: profile),
              const SizedBox(height: 24),
              if (relationship == FriendRelationship.friend)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _removeFriend(profile);
                        },
                        icon: const Icon(Icons.person_remove_outlined),
                        label: const Text('Remove'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _openChat(profile);
                        },
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: const Text('Chat'),
                      ),
                    ),
                  ],
                )
              else if (relationship == FriendRelationship.incoming &&
                  request != null)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _declineRequest(request);
                        },
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _acceptRequest(request);
                        },
                        child: const Text('Accept request'),
                      ),
                    ),
                  ],
                )
              else if (relationship == FriendRelationship.outgoing &&
                  request != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _cancelRequest(request);
                    },
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel sent request'),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _sendRequest(profile);
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Send friend request'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('permission') || raw.contains('row-level')) {
      return 'This action is not permitted for your account.';
    }
    if (raw.contains('network') || raw.contains('socket')) {
      return 'Check your connection and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Find Friends'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh connections',
            onPressed: _refreshing ? null : () => _loadData(showLoader: false),
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppStyles.auroraGradient),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _loadData)
            : RefreshIndicator(
                onRefresh: () => _loadData(showLoader: false),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: <Widget>[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      sliver: SliverToBoxAdapter(child: _buildHero()),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _FriendTabsDelegate(child: _buildTabs()),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      sliver: SliverToBoxAdapter(child: _buildSearch()),
                    ),
                    if (_filtersExpanded)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                        sliver: SliverToBoxAdapter(child: _buildFilterPanel()),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                      sliver: _buildActiveTab(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHero() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final hero = Container(
      constraints: const BoxConstraints(minHeight: 202),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: AppStyles.bentoRadius,
        boxShadow: AppStyles.glassShadow,
      ),
      child: Stack(
        children: <Widget>[
          const Positioned(
            right: -35,
            top: -45,
            child: _HeroOrb(size: 165, color: AppColors.electricCyan),
          ),
          const Positioned(
            right: 95,
            bottom: -55,
            child: _HeroOrb(size: 120, color: AppColors.ogGold),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: AppStyles.pillRadius,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.hub_outlined, color: AppColors.ogGold, size: 16),
                    SizedBox(width: 7),
                    Text(
                      'OG CAMPUS NETWORK',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                'Your people are closer\nthan you think.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 17),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _HeroMetric(
                    icon: Icons.mark_email_unread_outlined,
                    value: '${_incoming.length}',
                    label: 'Requests',
                    highlight: _incoming.isNotEmpty,
                  ),
                  _HeroMetric(
                    icon: Icons.outgoing_mail,
                    value: '${_outgoing.length}',
                    label: 'Sent',
                  ),
                  _HeroMetric(
                    icon: Icons.people_alt_outlined,
                    value: '${_friends.length}',
                    label: 'Friends',
                  ),
                  _HeroMetric(
                    icon: Icons.travel_explore_rounded,
                    value: '${_discover.length}',
                    label: 'Discover',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return reduceMotion
        ? hero
        : hero.animate().fadeIn(duration: 420.ms).slideY(begin: .05, end: 0);
  }

  Widget _buildTabs() {
    return Container(
      color: AppColors.auroraCanvas.withValues(alpha: .95),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: ClipRRect(
        borderRadius: AppStyles.controlRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .84),
              borderRadius: AppStyles.controlRadius,
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: AppStyles.softShadow,
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                gradient: AppStyles.brandGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
              onTap: (_) {
                HapticFeedback.selectionClick();
                setState(() {});
              },
              tabs: const <Tab>[
                Tab(
                  icon: Icon(Icons.mark_email_unread_outlined, size: 18),
                  text: 'Requests',
                ),
                Tab(icon: Icon(Icons.outgoing_mail, size: 18), text: 'Sent'),
                Tab(
                  icon: Icon(Icons.people_alt_outlined, size: 18),
                  text: 'My Friends',
                ),
                Tab(
                  icon: Icon(Icons.travel_explore_rounded, size: 18),
                  text: 'Discover',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _search = value.trim()),
            decoration: InputDecoration(
              hintText: 'Search by name',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Badge(
          isLabelVisible: _activeFilterCount > 0,
          label: Text('$_activeFilterCount'),
          child: IconButton.filledTonal(
            tooltip: 'Filter students',
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _filtersExpanded = !_filtersExpanded);
            },
            icon: Icon(
              _filtersExpanded
                  ? Icons.filter_list_off_rounded
                  : Icons.tune_rounded,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterPanel() {
    return ClipRRect(
      borderRadius: AppStyles.bentoRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .83),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: AppStyles.softShadow,
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.tune_rounded,
                    color: AppColors.vibeBlue,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Refine your campus network',
                      style: TextStyle(
                        color: AppColors.midnightInk,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (_activeFilterCount > 0)
                    TextButton(
                      onPressed: _clearFilters,
                      child: const Text('Clear all'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 620;
                  final width = twoColumns
                      ? (constraints.maxWidth - 10) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      SizedBox(
                        width: width,
                        child: _FilterDropdown(
                          label: 'Campus',
                          icon: Icons.location_on_outlined,
                          value: _campus,
                          options: _options((profile) => profile.campus),
                          onChanged: (value) => setState(() => _campus = value),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _FilterDropdown(
                          label: 'Faculty',
                          icon: Icons.account_balance_outlined,
                          value: _faculty,
                          options: _options((profile) => profile.faculty),
                          onChanged: (value) =>
                              setState(() => _faculty = value),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _FilterDropdown(
                          label: 'Course',
                          icon: Icons.school_outlined,
                          value: _course,
                          options: _options((profile) => profile.course),
                          onChanged: (value) => setState(() => _course = value),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _FilterDropdown(
                          label: 'Level',
                          icon: Icons.stairs_outlined,
                          value: _level,
                          options: _options((profile) => profile.level),
                          onChanged: (value) => setState(() => _level = value),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTab() {
    return switch (_tabController.index) {
      0 => _buildRequestsGrid(),
      1 => _buildSentGrid(),
      2 => _buildFriendsGrid(),
      _ => _buildDiscoverGrid(),
    };
  }

  Widget _buildRequestsGrid() {
    final entries = _incoming
        .where((entry) => _matches(entry.profile))
        .toList();
    return _entryGrid(
      entries: entries,
      empty: _EmptyState(
        icon: Icons.mark_email_read_outlined,
        title: _searchOrFiltersActive
            ? 'No requests match your filters'
            : 'Your request inbox is clear',
        subtitle: _searchOrFiltersActive
            ? 'Try another name or broaden the filters.'
            : 'New friend requests will appear here.',
      ),
      builder: (entry) => _ConnectionCard(
        profile: entry.profile,
        eyebrow: 'WANTS TO CONNECT',
        accent: AppColors.vibeBlue,
        onTap: () => _showProfile(
          entry.profile,
          relationship: FriendRelationship.incoming,
          request: entry,
        ),
        actions: <Widget>[
          Expanded(
            child: OutlinedButton(
              onPressed: () => _declineRequest(entry),
              child: const Text('Decline'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: () => _acceptRequest(entry),
              child: const Text('Accept'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentGrid() {
    final entries = _outgoing
        .where((entry) => _matches(entry.profile))
        .toList();
    return _entryGrid(
      entries: entries,
      empty: _EmptyState(
        icon: Icons.outgoing_mail,
        title: _searchOrFiltersActive
            ? 'No sent requests match'
            : 'No requests waiting',
        subtitle: _searchOrFiltersActive
            ? 'Adjust your search or filters.'
            : 'Discover students and send your first request.',
        actionLabel: _searchOrFiltersActive ? null : 'Discover students',
        onAction: _searchOrFiltersActive
            ? null
            : () => _tabController.animateTo(3),
      ),
      builder: (entry) => _ConnectionCard(
        profile: entry.profile,
        eyebrow: 'REQUEST PENDING',
        accent: AppColors.warning,
        onTap: () => _showProfile(
          entry.profile,
          relationship: FriendRelationship.outgoing,
          request: entry,
        ),
        actions: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _cancelRequest(entry),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancel request'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsGrid() {
    final friends = _friends.where(_matches).toList();
    return _profileGrid(
      profiles: friends,
      empty: _EmptyState(
        icon: Icons.people_outline_rounded,
        title: _searchOrFiltersActive
            ? 'No friends match your filters'
            : 'Build your campus circle',
        subtitle: _searchOrFiltersActive
            ? 'Try another name or broader filters.'
            : 'Accept a request or discover someone new.',
        actionLabel: _searchOrFiltersActive ? null : 'Discover students',
        onAction: _searchOrFiltersActive
            ? null
            : () => _tabController.animateTo(3),
      ),
      builder: (profile) => _ConnectionCard(
        profile: profile,
        eyebrow: 'YOUR FRIEND',
        accent: AppColors.success,
        onTap: () =>
            _showProfile(profile, relationship: FriendRelationship.friend),
        actions: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showProfile(
                profile,
                relationship: FriendRelationship.friend,
              ),
              icon: const Icon(Icons.person_outline_rounded),
              label: const Text('Profile'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _openChat(profile),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Chat'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverGrid() {
    final profiles = _discover.where(_matches).toList();
    return _profileGrid(
      profiles: profiles,
      empty: _EmptyState(
        icon: Icons.travel_explore_rounded,
        title: _searchOrFiltersActive
            ? 'No students match your search'
            : 'You have explored everyone',
        subtitle: _searchOrFiltersActive
            ? 'Try another name or broaden the filters.'
            : 'Pull to refresh when more students join OG Vibes.',
      ),
      builder: (profile) => _ConnectionCard(
        profile: profile,
        eyebrow: profile.mutualFriendCount > 0
            ? '${profile.mutualFriendCount} MUTUAL CONNECTION${profile.mutualFriendCount == 1 ? '' : 'S'}'
            : 'DISCOVER',
        accent: AppColors.electricCyan,
        onTap: () => _showProfile(profile),
        actions: <Widget>[
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _sendRequest(profile),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Connect'),
            ),
          ),
        ],
      ),
    );
  }

  bool get _searchOrFiltersActive =>
      _search.isNotEmpty || _activeFilterCount > 0;

  Widget _entryGrid({
    required List<FriendRequestEntry> entries,
    required Widget empty,
    required Widget Function(FriendRequestEntry) builder,
  }) {
    if (entries.isEmpty) return SliverToBoxAdapter(child: empty);
    return _responsiveGrid(
      count: entries.length,
      builder: (index) => builder(entries[index]),
    );
  }

  Widget _profileGrid({
    required List<FriendProfile> profiles,
    required Widget empty,
    required Widget Function(FriendProfile) builder,
  }) {
    if (profiles.isEmpty) return SliverToBoxAdapter(child: empty);
    return _responsiveGrid(
      count: profiles.length,
      builder: (index) => builder(profiles[index]),
    );
  }

  Widget _responsiveGrid({
    required int count,
    required Widget Function(int) builder,
  }) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.crossAxisExtent >= 1080
            ? 3
            : constraints.crossAxisExtent >= 700
            ? 2
            : 1;
        return SliverGrid(
          delegate: SliverChildBuilderDelegate((context, index) {
            final card = builder(index);
            if (MediaQuery.disableAnimationsOf(context)) return card;
            return card
                .animate(delay: (45 * (index % 6)).ms)
                .fadeIn(duration: 320.ms)
                .slideY(begin: .06, end: 0);
          }, childCount: count),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: columns == 1 ? 1.25 : 1.15,
          ),
        );
      },
    );
  }
}

enum FriendRelationship { discover, incoming, outgoing, friend }

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.profile,
    required this.eyebrow,
    required this.accent,
    required this.onTap,
    required this.actions,
  });

  final FriendProfile profile;
  final String eyebrow;
  final Color accent;
  final VoidCallback onTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          '${profile.displayName}, ${profile.course}, ${profile.campus}, ${profile.mutualFriendCount} mutual friends',
      child: ClipRRect(
        borderRadius: AppStyles.bentoRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Material(
            color: Colors.white.withValues(alpha: .86),
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: AppStyles.bentoRadius,
                  border: Border.all(color: AppColors.glassBorder),
                  boxShadow: AppStyles.softShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        _ProfileAvatar(profile: profile, radius: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Flexible(
                                    child: Text(
                                      profile.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.midnightInk,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (profile.isVerified) ...<Widget>[
                                    const SizedBox(width: 5),
                                    const Icon(
                                      Icons.verified_rounded,
                                      color: AppColors.vibeBlue,
                                      size: 17,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                eyebrow,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 9,
                                  letterSpacing: .8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: AppColors.textMuted,
                          size: 14,
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Text(
                      profile.course,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.midnightInk,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${profile.faculty} • ${profile.level}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        _MiniChip(
                          icon: Icons.location_on_outlined,
                          label: profile.campus,
                        ),
                        if (profile.mutualFriendCount > 0)
                          _MiniChip(
                            icon: Icons.people_outline_rounded,
                            label: '${profile.mutualFriendCount} mutual',
                            highlight: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(children: actions),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile, required this.radius});

  final FriendProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.vibeBlue.withValues(alpha: .12),
          backgroundImage: profile.photoUrl == null
              ? null
              : NetworkImage(profile.photoUrl!),
          child: profile.photoUrl == null
              ? Text(
                  profile.initials,
                  style: TextStyle(
                    color: AppColors.vibeBlue,
                    fontSize: radius * .55,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : null,
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: radius * .38,
            height: radius * .38,
            decoration: BoxDecoration(
              color: profile.isOnline ? AppColors.success : AppColors.textMuted,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.vibeBlue : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 135),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.vibeBlue : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: AppStyles.pillRadius,
        border: Border.all(
          color: highlight
              ? AppColors.vibeBlue.withValues(alpha: .24)
              : AppColors.glassBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoPanel extends StatelessWidget {
  const _ProfileInfoPanel({required this.profile});

  final FriendProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FC),
        borderRadius: AppStyles.controlRadius,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: <Widget>[
          _ProfileInfoRow(label: 'Campus', value: profile.campus),
          _ProfileInfoRow(label: 'Faculty', value: profile.faculty),
          _ProfileInfoRow(label: 'Course', value: profile.course),
          _ProfileInfoRow(label: 'Level', value: profile.level),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 75,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontWeight: FontWeight.w800,
              ),
            ),
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
    required this.options,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = options.contains(value) ? value : 'All';
    return DropdownButtonFormField<String>(
      initialValue: safeValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        isDense: true,
      ),
      items: options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 52),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .8),
        borderRadius: AppStyles.bentoRadius,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: AppColors.vibeBlue.withValues(alpha: .09),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.vibeBlue, size: 34),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.midnightInk,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.travel_explore_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_outlined,
              size: 52,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendTabsDelegate extends SliverPersistentHeaderDelegate {
  const _FriendTabsDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 82;

  @override
  double get maxExtent => 82;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(covariant _FriendTabsDelegate oldDelegate) =>
      oldDelegate.child != child;
}

class _HeroOrb extends StatelessWidget {
  const _HeroOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .12),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: .16),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.icon,
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            color: highlight ? AppColors.ogGold : AppColors.electricCyan,
            size: 17,
          ),
          const SizedBox(width: 7),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class FriendProfile {
  const FriendProfile({
    required this.id,
    required this.displayName,
    required this.campus,
    required this.faculty,
    required this.course,
    required this.level,
    required this.photoUrl,
    required this.isVerified,
    required this.isOnline,
    this.mutualFriendCount = 0,
  });

  factory FriendProfile.fromRow(Map<String, dynamic> row) {
    final nickname = row['nickname']?.toString().trim() ?? '';
    final fullName = '${row['name'] ?? ''} ${row['surname'] ?? ''}'.trim();
    final department = row['department']?.toString().trim() ?? '';
    final course = row['course']?.toString().trim() ?? '';
    final faculty = row['faculty']?.toString().trim() ?? '';
    return FriendProfile(
      id: row['id'].toString(),
      displayName: nickname.isNotEmpty
          ? nickname
          : fullName.isNotEmpty
          ? fullName
          : 'OG Student',
      campus: _valueOr(row['campus'], 'Campus not set'),
      faculty: faculty.isNotEmpty ? faculty : 'Faculty not set',
      course: course.isNotEmpty
          ? course
          : department.isNotEmpty
          ? department
          : 'Course not set',
      level: _valueOr(row['level'], 'Level not set'),
      photoUrl: _optional(row['photo_url']),
      isVerified: row['is_verified'] == true,
      isOnline: row['is_online'] == true,
    );
  }

  final String id;
  final String displayName;
  final String campus;
  final String faculty;
  final String course;
  final String level;
  final String? photoUrl;
  final bool isVerified;
  final bool isOnline;
  final int mutualFriendCount;

  FriendProfile copyWith({int? mutualFriendCount}) => FriendProfile(
    id: id,
    displayName: displayName,
    campus: campus,
    faculty: faculty,
    course: course,
    level: level,
    photoUrl: photoUrl,
    isVerified: isVerified,
    isOnline: isOnline,
    mutualFriendCount: mutualFriendCount ?? this.mutualFriendCount,
  );

  String get initials => displayName
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
}

class FriendRequestEntry {
  const FriendRequestEntry({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.profile,
    required this.createdAt,
  });

  factory FriendRequestEntry.fromRow(
    Map<String, dynamic> row,
    FriendProfile profile,
  ) => FriendRequestEntry(
    id: row['id'].toString(),
    senderId: row['sender_id'].toString(),
    receiverId: row['receiver_id'].toString(),
    profile: profile,
    createdAt:
        DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
  );

  final String id;
  final String senderId;
  final String receiverId;
  final FriendProfile profile;
  final DateTime createdAt;
}

String _valueOr(dynamic value, String fallback) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String? _optional(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
