import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/offline_data_adapter.dart';

import '../services/notification_badge_service.dart';
import '../utils/theme_constants.dart';
import '../widgets/standard_ui.dart';
import '../widgets/vibe_scaffold.dart';
import 'announcements_screen.dart';
import 'assessments_calendar_screen.dart';
import 'career_screen.dart';
import 'chat_detail_screen.dart';
import 'events_screen.dart';
import 'friend_requests_screen.dart';
import 'group_chats_screen.dart';
import 'icass_checker_screen.dart';
import 'lost_and_found_screen.dart';
import 'market_screen.dart';
import 'messages_screen.dart';
import 'online_classes_screen.dart';
import 'past_question_papers_screen.dart';
import 'quiz_screen.dart';
import 'slides_screen.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  static const int _pageSize = 30;
  final List<Map<String, dynamic>> _items = [];
  OfflineRealtimeChannel? _channel;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = true;
  String _filter = 'All';
  DateTime? _oldestCursor;
  String? _error;

  String get _cacheKey =>
      'student_notification_inbox_cache_v3_${OfflineData.instance.client.auth.currentUser?.id ?? 'signed_out'}';
  int get _unreadCount =>
      _items.where((item) => item['read_at'] == null).length;

  @override
  void initState() {
    super.initState();
    unawaited(_initialise());
  }

  Future<void> _initialise() async {
    await _restoreCache();
    await _load(reset: true);
    final userId = OfflineData.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _channel = OfflineData.instance.client.channel('notification-inbox:$userId')
      ..onPostgresChanges(
        event: OfflinePostgresChangeEvent.all,
        schema: 'public',
        table: 'student_notifications',
        filter: OfflinePostgresChangeFilter(
          type: OfflinePostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (_) => unawaited(_load(reset: true, showLoader: false)),
      )
      ..subscribe();
  }

  Future<void> _restoreCache() async {
    final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      final cached = (jsonDecode(raw) as List<dynamic>)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
      setState(() {
        _items
          ..clear()
          ..addAll(cached);
        _loading = false;
      });
    } catch (_) {}
  }

  Future<void> _load({bool reset = false, bool showLoader = true}) async {
    if (_loadingOlder) return;
    if (reset) {
      _oldestCursor = null;
      _hasMore = true;
    }
    if (!_hasMore && !reset) return;
    if (showLoader && _items.isEmpty && mounted) {
      setState(() => _loading = true);
    } else if (!reset && mounted) {
      setState(() => _loadingOlder = true);
    }
    try {
      var query = OfflineData.instance.client
          .from('student_notifications')
          .select();
      final cursor = _oldestCursor;
      if (cursor != null && !reset) {
        query = query.lt('created_at', cursor.toUtc().toIso8601String());
      }
      final rows = List<Map<String, dynamic>>.from(
        await query.order('created_at', ascending: false).limit(_pageSize)
            as List<dynamic>,
      );
      if (!mounted) return;
      final merged = reset
          ? rows
          : <Map<String, dynamic>>[
              ..._items,
              ...rows.where(
                (row) => !_items.any((item) => item['id'] == row['id']),
              ),
            ];
      setState(() {
        _items
          ..clear()
          ..addAll(merged);
        _oldestCursor = rows.isEmpty
            ? _oldestCursor
            : DateTime.tryParse(rows.last['created_at']?.toString() ?? '');
        _hasMore = rows.length == _pageSize;
        _loading = false;
        _loadingOlder = false;
        _error = null;
      });
      await (await SharedPreferences.getInstance()).setString(
        _cacheKey,
        jsonEncode(_items.take(90).toList()),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingOlder = false;
        _error = _items.isEmpty
            ? 'Notifications could not be refreshed. Check your connection.'
            : 'Showing saved notifications. Pull down to try again.';
      });
    }
  }

  @override
  void dispose() {
    if (_channel != null) {
      unawaited(OfflineData.instance.client.removeChannel(_channel!));
    }
    super.dispose();
  }

  Iterable<Map<String, dynamic>> get _visible sync* {
    for (final item in _items) {
      final route = item['route']?.toString() ?? '';
      final category = item['category']?.toString() ?? '';
      if (_filter == 'Messages' &&
          !{'chat', 'messages', 'group_chats'}.contains(route)) {
        continue;
      }
      if (_filter == 'Academic' && category != 'academics') continue;
      if (_filter == 'Alerts' &&
          ({'chat', 'messages', 'group_chats'}.contains(route) ||
              category == 'academics')) {
        continue;
      }
      yield item;
    }
  }

  Future<void> _markAllRead() async {
    final unreadIds = _items
        .where((item) => item['read_at'] == null)
        .map((item) => item['id']?.toString())
        .whereType<String>()
        .toList();
    if (unreadIds.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    setState(() {
      for (final item in _items) {
        if (item['read_at'] == null) item['read_at'] = now;
      }
    });
    try {
      await OfflineData.instance.client
          .from('student_notifications')
          .update({'read_at': now})
          .inFilter('id', unreadIds);
      await NotificationBadgeService.instance.refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update every notification.')),
        );
      }
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    if (id != null && item['read_at'] == null) {
      final now = DateTime.now().toUtc().toIso8601String();
      setState(() => item['read_at'] = now);
      await OfflineData.instance.client
          .from('student_notifications')
          .update({'read_at': now})
          .eq('id', id);
      await NotificationBadgeService.instance.refresh();
    }
    if (!mounted) return;
    final route = item['route']?.toString() ?? '';
    final entity = item['entity_id']?.toString();
    final title = item['title']?.toString();
    final destination = switch (route) {
      'chat' when entity?.isNotEmpty == true => ChatDetailScreen(
        chatId: entity!,
        chatTitle: title,
      ),
      'messages' => const MessagesScreen(),
      'group_chats' => const GroupChatsScreen(),
      'quiz' || 'quizzes' => const QuizScreen(),
      'assessments' => const AssessmentsCalendarScreen(),
      'online_classes' => const OnlineClassesScreen(),
      'alerts' => const AnnouncementsScreen(),
      'events' => const EventsScreen(),
      'friends' => const FriendRequestsScreen(),
      'marketplace' => const MarketScreen(),
      'lost_found' => const LostAndFoundScreen(),
      'icass' => const IcassCheckerScreen(),
      'career' => const CareerScreen(),
      'past_papers' => const PastQuestionPapersScreen(),
      'lecture_slides' => const SlidesScreen(),
      _ => const AnnouncementsScreen(),
    };
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible.toList();
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
          IconButton(
            tooltip: 'Refresh notifications',
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              sliver: SliverToBoxAdapter(child: _buildHero()),
            ),
            SliverToBoxAdapter(child: _buildFilters()),
            if (_error != null && _items.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: OgErrorCard(
                    message: _error!,
                    onRetry: () => _load(reset: true),
                  ),
                ),
              ),
            if (_loading && _items.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _items.isEmpty)
              SliverFillRemaining(
                child: OgErrorCard(
                  message: _error!,
                  onRetry: () => _load(reset: true),
                ),
              )
            else if (visible.isEmpty)
              const SliverFillRemaining(
                child: OgEmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'You are all caught up',
                  message:
                      'New messages, academic updates and alerts will appear here.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                sliver: SliverList.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (_, index) => _NotificationCard(
                    item: visible[index],
                    onTap: () => _open(visible[index]),
                  ),
                ),
              ),
            if (!_loading && visible.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                  child: OgLoadOlderButton(
                    loading: _loadingOlder,
                    label: _hasMore
                        ? 'Load older notifications'
                        : 'You have reached the beginning',
                    onPressed: _hasMore ? () => _load() : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: AppStyles.bentoRadius,
        boxShadow: AppStyles.glassShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: AppColors.electricCyan,
              size: 28,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _unreadCount == 0
                      ? 'Nothing new right now'
                      : '$_unreadCount unread ${_unreadCount == 1 ? 'update' : 'updates'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Messages, study updates and campus activity in one place.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    const filters = <(String, IconData)>[
      ('All', Icons.grid_view_rounded),
      ('Messages', Icons.chat_bubble_rounded),
      ('Academic', Icons.school_rounded),
      ('Alerts', Icons.campaign_rounded),
    ];
    return SizedBox(
      height: 58,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final entry = filters[index];
          return ChoiceChip(
            avatar: Icon(entry.$2, size: 17),
            label: Text(entry.$1),
            selected: _filter == entry.$1,
            showCheckmark: false,
            onSelected: (_) => setState(() => _filter = entry.$1),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = item['read_at'] == null;
    final category = item['category']?.toString() ?? 'update';
    final accent = _color(category);
    return Semantics(
      button: true,
      label:
          '${unread ? 'Unread' : 'Read'} notification. ${item['title'] ?? 'OG Vibes update'}',
      child: Material(
        color: unread
            ? accent.withValues(alpha: .075)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: unread
                    ? accent.withValues(alpha: .28)
                    : AppColors.glassBorder,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(_icon(item), color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['title']?.toString() ?? 'OG Vibes update',
                              style: TextStyle(
                                fontWeight: unread
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                              ),
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item['body']?.toString() ?? '',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .1),
                              borderRadius: AppStyles.pillRadius,
                            ),
                            child: Text(
                              _categoryLabel(category),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: accent,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatTime(item['created_at']),
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _icon(Map<String, dynamic> item) =>
      switch (item['route']?.toString()) {
        'chat' || 'messages' => Icons.chat_bubble_rounded,
        'group_chats' => Icons.groups_rounded,
        'quiz' || 'quizzes' => Icons.quiz_rounded,
        'assessments' => Icons.assignment_rounded,
        'online_classes' => Icons.cast_for_education_rounded,
        'alerts' => Icons.campaign_rounded,
        'events' => Icons.event_rounded,
        _ => Icons.notifications_rounded,
      };

  static Color _color(String category) => switch (category) {
    'messages' => AppColors.electricCyan,
    'academics' => AppColors.vibeBlue,
    'campus' => AppColors.ogGold,
    'danger' || 'critical' => AppColors.danger,
    _ => AppColors.deepBlue,
  };

  static String _categoryLabel(String category) => switch (category) {
    'academics' => 'ACADEMIC',
    'messages' => 'MESSAGE',
    'campus' => 'CAMPUS',
    'danger' || 'critical' => 'IMPORTANT',
    _ => 'UPDATE',
  };

  static String _formatTime(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'Now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return '${difference.inHours}h';
    if (difference.inDays < 7) return '${difference.inDays}d';
    return '${date.day}/${date.month}/${date.year}';
  }
}
