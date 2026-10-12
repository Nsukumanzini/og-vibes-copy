import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';
import 'chat_detail_screen.dart';
import 'friend_requests_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();

  RealtimeChannel? _channel;
  Timer? _reloadDebounce;
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _friends = [];
  int _selectedTab = 0;
  bool _loading = true;
  bool _refreshing = false;
  bool _offline = false;
  String? _error;

  String get _cacheKey =>
      'chat_inbox_cache_v2_${_client.auth.currentUser?.id ?? 'signed_out'}';

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
    _reloadDebounce?.cancel();
    final channel = _channel;
    if (channel != null) unawaited(_client.removeChannel(channel));
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    await _loadCache();
    await _loadInbox();
    _subscribeToChanges();
  }

  Future<void> _loadCache() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_cacheKey);
    if (raw == null || !mounted) return;
    try {
      final rows = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List<dynamic>).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      setState(() {
        _conversations = rows;
        _loading = false;
        _offline = true;
      });
    } catch (_) {
      // Ignore a stale or incompatible cache and continue with live data.
    }
  }

  Future<void> _saveCache(List<Map<String, dynamic>> rows) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_cacheKey, jsonEncode(rows));
  }

  Future<void> _loadInbox({bool showRefresh = false}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = 'Sign in to view your private chats.';
      });
      return;
    }

    if (showRefresh && mounted) setState(() => _refreshing = true);
    try {
      final results = await Future.wait<dynamic>([
        _client
            .from('messages')
            .select(
              'id, sender_id, recipient_id, text, message_type, '
              'attachment_url, is_read, is_deleted, created_at, updated_at',
            )
            .or('sender_id.eq.${user.id},recipient_id.eq.${user.id}')
            .eq('is_deleted', false)
            .order('created_at', ascending: false),
        _client
            .from('chat_preferences')
            .select('peer_id, is_archived')
            .eq('user_id', user.id),
        _client
            .from('friendships')
            .select('user_id, friend_id')
            .or('user_id.eq.${user.id},friend_id.eq.${user.id}'),
      ]);

      final messages = List<Map<String, dynamic>>.from(
        results[0] as List<dynamic>,
      );
      final preferences = List<Map<String, dynamic>>.from(
        results[1] as List<dynamic>,
      );
      final friendships = List<Map<String, dynamic>>.from(
        results[2] as List<dynamic>,
      );

      final peerIds = <String>{};
      for (final message in messages) {
        final senderId = message['sender_id']?.toString();
        final recipientId = message['recipient_id']?.toString();
        if (senderId == null || recipientId == null) continue;
        peerIds.add(senderId == user.id ? recipientId : senderId);
      }

      final friendIds = <String>{};
      for (final friendship in friendships) {
        final first = friendship['user_id']?.toString();
        final second = friendship['friend_id']?.toString();
        if (first == null || second == null) continue;
        friendIds.add(first == user.id ? second : first);
      }

      final profileIds = {...peerIds, ...friendIds}.toList();
      final profiles = profileIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _client
                      .from('profiles')
                      .select(
                        'id, name, surname, photo_url, is_online, is_verified, '
                        'course, campus',
                      )
                      .inFilter('id', profileIds)
                  as List<dynamic>,
            );

      final profileMap = <String, Map<String, dynamic>>{
        for (final profile in profiles) profile['id'].toString(): profile,
      };
      final archivedPeers = <String>{
        for (final preference in preferences)
          if (preference['is_archived'] == true)
            preference['peer_id'].toString(),
      };

      final conversations = buildChatInboxRows(
        messages: messages,
        profiles: profileMap,
        currentUserId: user.id,
        archivedPeers: archivedPeers,
      );
      final friends =
          friendIds
              .map((id) => profileMap[id])
              .whereType<Map<String, dynamic>>()
              .toList()
            ..sort((a, b) => _displayName(a).compareTo(_displayName(b)));

      await _saveCache(conversations);
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _friends = friends;
        _loading = false;
        _refreshing = false;
        _offline = false;
        _error = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Chats inbox load error: $error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _offline = _conversations.isNotEmpty;
        _error = _conversations.isNotEmpty
            ? 'Offline mode · showing your most recent saved chats.'
            : 'Chats could not connect. Pull down to try again.';
      });
    }
  }

  void _subscribeToChanges() {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final existing = _channel;
    if (existing != null) unawaited(_client.removeChannel(existing));

    _channel = _client
        .channel('chat-inbox-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => _scheduleReload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_preferences',
          callback: (_) => _scheduleReload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: (_) => _scheduleReload(),
        )
        .subscribe();
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadInbox(),
    );
  }

  Future<void> _refresh() async {
    HapticFeedback.selectionClick();
    await _loadInbox(showRefresh: true);
    _subscribeToChanges();
  }

  int get _unreadTotal => _conversations.fold<int>(
    0,
    (total, chat) => total + (chat['unread'] as int? ?? 0),
  );

  int get _onlineFriends =>
      _friends.where((friend) => friend['is_online'] == true).length;

  List<Map<String, dynamic>> get _visibleConversations {
    final query = _searchController.text.trim().toLowerCase();
    return _conversations.where((chat) {
      final archived = chat['isArchived'] == true;
      final unread = (chat['unread'] as int? ?? 0) > 0;
      final matchesTab = switch (_selectedTab) {
        1 => !archived && unread,
        2 => archived,
        _ => !archived,
      };
      final name = (chat['name'] ?? '').toString().toLowerCase();
      return matchesTab && (query.isEmpty || name.contains(query));
    }).toList();
  }

  Future<void> _openChat(Map<String, dynamic> chat) async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          chatId: chat['id'].toString(),
          chatTitle: chat['name'].toString(),
        ),
      ),
    );
    await _loadInbox();
  }

  Future<void> _setArchived(Map<String, dynamic> chat, bool archived) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    HapticFeedback.mediumImpact();
    final peerId = chat['id'].toString();
    setState(() => chat['isArchived'] = archived);
    try {
      await _client.from('chat_preferences').upsert({
        'user_id': user.id,
        'peer_id': peerId,
        'is_archived': archived,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _saveCache(_conversations);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(archived ? 'Chat archived.' : 'Chat restored.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => chat['isArchived'] = !archived);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update this chat.')),
      );
    }
  }

  Future<void> _showNewChat() async {
    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _NewChatSheet(
        friends: _friends,
        onFriendSelected: (friend) {
          Navigator.pop(sheetContext);
          _openChat({
            'id': friend['id'].toString(),
            'name': _displayName(friend),
          });
        },
        onFindFriends: () {
          Navigator.pop(sheetContext);
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FriendRequestsScreen()),
          );
        },
      ),
    );
  }

  void _selectTab(int index) {
    HapticFeedback.selectionClick();
    setState(() => _selectedTab = index);
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewChat,
        icon: const Icon(Icons.edit_square),
        label: const Text('New chat'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) => CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  constraints.maxWidth >= 900 ? 32 : 16,
                  14,
                  constraints.maxWidth >= 900 ? 32 : 16,
                  104,
                ),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 920),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ChatsHero(
                            conversationCount: _conversations.length,
                            unreadCount: _unreadTotal,
                            onlineCount: _onlineFriends,
                            offline: _offline,
                            refreshing: _refreshing,
                            onRefresh: _refresh,
                          ),
                          const SizedBox(height: 16),
                          _ChatsTabBar(
                            selectedIndex: _selectedTab,
                            allCount: _conversations
                                .where((chat) => chat['isArchived'] != true)
                                .length,
                            unreadCount: _conversations
                                .where(
                                  (chat) =>
                                      chat['isArchived'] != true &&
                                      (chat['unread'] as int? ?? 0) > 0,
                                )
                                .length,
                            archivedCount: _conversations
                                .where((chat) => chat['isArchived'] == true)
                                .length,
                            onSelected: _selectTab,
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Search by name',
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
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            _ConnectionBanner(
                              message: _error!,
                              offline: _offline,
                              onRetry: _refresh,
                            ),
                          ],
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutCubic,
                            child: _buildConversationList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList() {
    if (_loading) return const _InboxSkeleton(key: ValueKey('loading'));
    final visible = _visibleConversations;
    if (visible.isEmpty) {
      return _ChatsEmptyState(
        key: ValueKey('empty-$_selectedTab-${_searchController.text}'),
        tab: _selectedTab,
        searching: _searchController.text.trim().isNotEmpty,
        onStartChat: _showNewChat,
      );
    }

    return Column(
      key: ValueKey('list-$_selectedTab'),
      children: visible.asMap().entries.map((entry) {
        final index = entry.key;
        final chat = entry.value;
        return TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 240 + index.clamp(0, 6) * 45),
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 0, end: 1),
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: Opacity(opacity: value, child: child),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ConversationCard(
              chat: chat,
              onTap: () => _openChat(chat),
              onArchive: () => _setArchived(chat, chat['isArchived'] != true),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ChatsHero extends StatelessWidget {
  const _ChatsHero({
    required this.conversationCount,
    required this.unreadCount,
    required this.onlineCount,
    required this.offline,
    required this.refreshing,
    required this.onRefresh,
  });

  final int conversationCount;
  final int unreadCount;
  final int onlineCount;
  final bool offline;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 210),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: AppStyles.bentoRadius,
        boxShadow: AppStyles.glassShadow,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -68,
            top: -80,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.electricCyan.withValues(alpha: .14),
              ),
            ),
          ),
          Positioned(
            right: 80,
            bottom: -95,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.ogGold.withValues(alpha: .11),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .13),
                        borderRadius: AppStyles.pillRadius,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .18),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forum_rounded,
                            size: 16,
                            color: AppColors.electricCyan,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'OG CONNECTIONS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      button: true,
                      label: 'Refresh chats',
                      child: IconButton.filledTonal(
                        tooltip: 'Refresh chats',
                        onPressed: refreshing ? null : onRefresh,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: .12),
                          foregroundColor: Colors.white,
                        ),
                        icon: refreshing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Chats',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  offline
                      ? 'Offline · your recent conversations are still here.'
                      : 'Private conversations with your student community.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .72),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    _HeroStat(value: '$conversationCount', label: 'Chats'),
                    _HeroStat(value: '$unreadCount', label: 'Unread'),
                    _HeroStat(value: '$onlineCount', label: 'Friends online'),
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

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatsTabBar extends StatelessWidget {
  const _ChatsTabBar({
    required this.selectedIndex,
    required this.allCount,
    required this.unreadCount,
    required this.archivedCount,
    required this.onSelected,
  });

  final int selectedIndex;
  final int allCount;
  final int unreadCount;
  final int archivedCount;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      padding: const EdgeInsets.all(5),
      radius: 20,
      child: Row(
        children: [
          _InboxTab(
            label: 'All',
            count: allCount,
            selected: selectedIndex == 0,
            onTap: () => onSelected(0),
          ),
          _InboxTab(
            label: 'Unread',
            count: unreadCount,
            selected: selectedIndex == 1,
            onTap: () => onSelected(1),
          ),
          _InboxTab(
            label: 'Archived',
            count: archivedCount,
            selected: selectedIndex == 2,
            onTap: () => onSelected(2),
          ),
        ],
      ),
    );
  }
}

class _InboxTab extends StatelessWidget {
  const _InboxTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label chats, $count',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 210),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
            decoration: BoxDecoration(
              gradient: selected ? AppStyles.brandGradient : null,
              borderRadius: BorderRadius.circular(15),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.vibeBlue.withValues(alpha: .18),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.midnightInk,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
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

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.chat,
    required this.onTap,
    required this.onArchive,
  });

  final Map<String, dynamic> chat;
  final VoidCallback onTap;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final unread = chat['unread'] as int? ?? 0;
    final isOutgoing = chat['lastIsMine'] == true;
    final isRead = chat['lastIsRead'] == true;
    final messageType = (chat['messageType'] ?? 'text').toString();
    final archived = chat['isArchived'] == true;

    return Semantics(
      button: true,
      label: '${chat['name']}, $unread unread messages',
      child: _GlassSurface(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppStyles.bentoRadius,
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: unread > 0
                  ? LinearGradient(
                      colors: [
                        AppColors.vibeBlue.withValues(alpha: .075),
                        AppColors.electricCyan.withValues(alpha: .035),
                      ],
                    )
                  : null,
              borderRadius: AppStyles.bentoRadius,
            ),
            child: Row(
              children: [
                _ConversationAvatar(chat: chat),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              chat['name'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.midnightInk,
                                fontSize: 15,
                                fontWeight: unread > 0
                                    ? FontWeight.w900
                                    : FontWeight.w800,
                              ),
                            ),
                          ),
                          if (chat['isVerified'] == true)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.verified_rounded,
                                size: 17,
                                color: AppColors.vibeBlue,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (messageType != 'text') ...[
                            Icon(
                              _attachmentIcon(messageType),
                              size: 16,
                              color: unread > 0
                                  ? AppColors.vibeBlue
                                  : AppColors.textMuted,
                            ),
                            const SizedBox(width: 5),
                          ],
                          if (isOutgoing) ...[
                            Icon(
                              isRead
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                              size: 16,
                              color: isRead
                                  ? AppColors.electricCyan
                                  : AppColors.textMuted,
                            ),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              chat['lastMessage'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: unread > 0
                                    ? AppColors.midnightInk
                                    : AppColors.textMuted,
                                fontSize: 13,
                                fontWeight: unread > 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatInboxTime(chat['createdAt']),
                      style: TextStyle(
                        color: unread > 0
                            ? AppColors.vibeBlue
                            : AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (unread > 0)
                          Container(
                            constraints: const BoxConstraints(minWidth: 24),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: AppStyles.brandGradient,
                              borderRadius: AppStyles.pillRadius,
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        PopupMenuButton<String>(
                          tooltip: 'Chat actions',
                          padding: EdgeInsets.zero,
                          onSelected: (_) => onArchive(),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: archived ? 'restore' : 'archive',
                              child: Row(
                                children: [
                                  Icon(
                                    archived
                                        ? Icons.unarchive_outlined
                                        : Icons.archive_outlined,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    archived ? 'Restore chat' : 'Archive chat',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
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
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.chat});

  final Map<String, dynamic> chat;

  @override
  Widget build(BuildContext context) {
    final name = chat['name'].toString();
    final photoUrl = (chat['photoUrl'] ?? '').toString();
    final online = chat['isOnline'] == true;
    final fallback = Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: AppStyles.brandGradient),
      child: Text(
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 54,
          height: 54,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.vibeBlue.withValues(alpha: .12),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: photoUrl.isEmpty
              ? fallback
              : CachedNetworkImage(
                  imageUrl: photoUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => fallback,
                  errorWidget: (_, _, _) => fallback,
                ),
        ),
        Positioned(
          right: -1,
          bottom: 1,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? AppColors.success : const Color(0xFFB7C2D4),
              border: Border.all(color: Colors.white, width: 2.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _NewChatSheet extends StatefulWidget {
  const _NewChatSheet({
    required this.friends,
    required this.onFriendSelected,
    required this.onFindFriends,
  });

  final List<Map<String, dynamic>> friends;
  final ValueChanged<Map<String, dynamic>> onFriendSelected;
  final VoidCallback onFindFriends;

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final friends = widget.friends
        .where((friend) => _displayName(friend).toLowerCase().contains(query))
        .toList();
    return DraggableScrollableSheet(
      initialChildSize: .72,
      minChildSize: .48,
      maxChildSize: .92,
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
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.glassBorder,
                    borderRadius: AppStyles.pillRadius,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start a chat',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const Text(
                              'Only accepted friends are shown.',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
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
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search friends by name',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: friends.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.people_outline_rounded,
                                  size: 50,
                                  color: AppColors.vibeBlue,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  query.isEmpty
                                      ? 'No accepted friends yet'
                                      : 'No friend matches that name',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (query.isEmpty) ...[
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: widget.onFindFriends,
                                    icon: const Icon(Icons.person_add_alt_1),
                                    label: const Text('Find friends'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                          itemCount: friends.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final friend = friends[index];
                            return _FriendTile(
                              friend: friend,
                              onTap: () => widget.onFriendSelected(friend),
                            );
                          },
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

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.friend, required this.onTap});

  final Map<String, dynamic> friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = _displayName(friend);
    return _GlassSurface(
      padding: EdgeInsets.zero,
      radius: 18,
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: CircleAvatar(
          backgroundColor: AppColors.vibeBlue.withValues(alpha: .1),
          foregroundColor: AppColors.vibeBlue,
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          [friend['course'], friend['campus']]
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(
          Icons.arrow_forward_rounded,
          color: AppColors.vibeBlue,
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.message,
    required this.offline,
    required this.onRetry,
  });

  final String message;
  final bool offline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final color = offline ? AppColors.warning : AppColors.danger;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 8, 7, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            offline ? Icons.cloud_off_rounded : Icons.info_outline_rounded,
            size: 19,
            color: color,
          ),
          const SizedBox(width: 8),
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

class _InboxSkeleton extends StatelessWidget {
  const _InboxSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE5ECF8),
      highlightColor: Colors.white,
      child: Column(
        children: List.generate(
          4,
          (_) => Container(
            height: 86,
            margin: const EdgeInsets.only(bottom: 10),
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

class _ChatsEmptyState extends StatelessWidget {
  const _ChatsEmptyState({
    super.key,
    required this.tab,
    required this.searching,
    required this.onStartChat,
  });

  final int tab;
  final bool searching;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    final title = searching
        ? 'No friends match that name'
        : switch (tab) {
            1 => 'You are all caught up',
            2 => 'No archived chats',
            _ => 'Your conversations start here',
          };
    final body = searching
        ? 'Try a different name.'
        : switch (tab) {
            1 => 'New messages will appear here as they arrive.',
            2 => 'Chats you archive will stay safely organised here.',
            _ => 'Start a private conversation with an accepted friend.',
          };

    return _GlassSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
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
                    searching
                        ? Icons.search_off_rounded
                        : Icons.chat_bubble_outline_rounded,
                    size: 34,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 17),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
                if (!searching && tab == 0) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onStartChat,
                    icon: const Icon(Icons.edit_square),
                    label: const Text('Start a chat'),
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
            color: Colors.white.withValues(alpha: .73),
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

List<Map<String, dynamic>> buildChatInboxRows({
  required List<Map<String, dynamic>> messages,
  required Map<String, Map<String, dynamic>> profiles,
  required String currentUserId,
  required Set<String> archivedPeers,
}) {
  final rows = <String, Map<String, dynamic>>{};
  for (final message in messages) {
    final senderId = message['sender_id']?.toString();
    final recipientId = message['recipient_id']?.toString();
    if (senderId == null || recipientId == null) continue;
    final peerId = senderId == currentUserId ? recipientId : senderId;
    final incoming = recipientId == currentUserId;
    final unread = incoming && message['is_read'] != true;
    final type = (message['message_type'] ?? 'text').toString();

    final existing = rows[peerId];
    if (existing == null) {
      final profile = profiles[peerId] ?? const <String, dynamic>{};
      final name = _displayName(profile).trim();
      rows[peerId] = {
        'id': peerId,
        'name': name.isEmpty ? 'Student' : name,
        'photoUrl': (profile['photo_url'] ?? '').toString(),
        'isOnline': profile['is_online'] == true,
        'isVerified': profile['is_verified'] == true,
        'lastMessage': _messagePreview(message),
        'messageType': type,
        'lastIsMine': senderId == currentUserId,
        'lastIsRead': message['is_read'] == true,
        'createdAt': message['created_at']?.toString(),
        'unread': unread ? 1 : 0,
        'isArchived': archivedPeers.contains(peerId),
      };
    } else if (unread) {
      existing['unread'] = (existing['unread'] as int? ?? 0) + 1;
    }
  }
  return rows.values.toList();
}

String _messagePreview(Map<String, dynamic> message) {
  final type = (message['message_type'] ?? 'text').toString().toLowerCase();
  final text = (message['text'] ?? '').toString().trim();
  if (type == 'text' && text.isNotEmpty) return text;
  return switch (type) {
    'image' => 'Photo',
    'video' => 'Video',
    'audio' || 'voice' => 'Voice message',
    'document' || 'file' => 'Document',
    _ => text.isEmpty ? 'Attachment' : text,
  };
}

String _displayName(Map<String, dynamic> profile) {
  final name = (profile['name'] ?? '').toString().trim();
  final surname = (profile['surname'] ?? '').toString().trim();
  return [name, surname].where((value) => value.isNotEmpty).join(' ');
}

IconData _attachmentIcon(String type) => switch (type.toLowerCase()) {
  'image' => Icons.image_outlined,
  'video' => Icons.videocam_outlined,
  'audio' || 'voice' => Icons.mic_none_rounded,
  'document' || 'file' => Icons.description_outlined,
  _ => Icons.attach_file_rounded,
};

String _formatInboxTime(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  final now = DateTime.now();
  if (DateUtils.isSameDay(now, date)) return DateFormat('HH:mm').format(date);
  if (now.difference(date).inDays < 7) return DateFormat('EEE').format(date);
  return DateFormat('d MMM').format(date);
}
