import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/offline_data_adapter.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';
import 'messages_screen.dart';
import 'outgoing_call_screen.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final _db = OfflineData.instance.client;
  List<_CallItem> _calls = const [];
  final List<OfflineRealtimeChannel> _channels = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  String _filter = 'All';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
    final userId = _db.auth.currentUser?.id;
    if (userId != null) {
      final directChannel = _db.channel('call-history:$userId')
        ..onPostgresChanges(
          event: OfflinePostgresChangeEvent.all,
          schema: 'public',
          table: 'calls',
          callback: (_) => unawaited(_load(showLoader: false)),
        )
        ..subscribe();
      final groupChannel = _db.channel('group-call-history:$userId')
        ..onPostgresChanges(
          event: OfflinePostgresChangeEvent.all,
          schema: 'public',
          table: 'group_calls',
          callback: (_) => unawaited(_load(showLoader: false)),
        )
        ..subscribe();
      final participantChannel = _db.channel('group-call-participation:$userId')
        ..onPostgresChanges(
          event: OfflinePostgresChangeEvent.all,
          schema: 'public',
          table: 'group_call_participants',
          filter: OfflinePostgresChangeFilter(
            type: OfflinePostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => unawaited(_load(showLoader: false)),
        )
        ..subscribe();
      _channels.addAll([directChannel, groupChannel, participantChannel]);
    }
  }

  @override
  void dispose() {
    for (final channel in _channels) {
      unawaited(_db.removeChannel(channel));
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoader = true}) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (showLoader && mounted) setState(() => _loading = true);
    try {
      final hiddenRows = List<Map<String, dynamic>>.from(
        await _db
                .from('call_history_hidden')
                .select('call_kind,call_id')
                .eq('user_id', userId)
            as List<dynamic>,
      );
      final hiddenDirect = hiddenRows
          .where((row) => row['call_kind'] == 'direct')
          .map((row) => row['call_id'].toString())
          .toSet();
      final hiddenGroup = hiddenRows
          .where((row) => row['call_kind'] == 'group')
          .map((row) => row['call_id'].toString())
          .toSet();
      final rows = List<Map<String, dynamic>>.from(
        await _db
                .from('calls')
                .select(
                  'id,caller_id,callee_id,type,status,started_at,answered_at,ended_at,created_at',
                )
                .or('caller_id.eq.$userId,callee_id.eq.$userId')
                .order('started_at', ascending: false)
                .limit(200)
            as List<dynamic>,
      );
      rows.removeWhere((row) => hiddenDirect.contains(row['id'].toString()));
      final participantRows = List<Map<String, dynamic>>.from(
        await _db
                .from('group_call_participants')
                .select('call_id,status,invited_at,joined_at,left_at')
                .eq('user_id', userId)
                .order('invited_at', ascending: false)
                .limit(200)
            as List<dynamic>,
      );
      final groupCallIds = participantRows
          .map((row) => row['call_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final visibleGroupCallIds = groupCallIds
          .where((id) => !hiddenGroup.contains(id))
          .toList();
      final groupCallRows = visibleGroupCallIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _db
                      .from('group_calls')
                      .select(
                        'id,group_id,started_by,call_type,status,created_at,started_at,ended_at',
                      )
                      .inFilter('id', visibleGroupCallIds)
                  as List<dynamic>,
            );
      final rosterRows = visibleGroupCallIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _db
                      .from('group_call_participants')
                      .select('call_id,user_id')
                      .inFilter('call_id', visibleGroupCallIds)
                  as List<dynamic>,
            );
      final groupIds = groupCallRows
          .map((row) => row['group_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final groupRows = groupIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _db
                      .from('group_chats')
                      .select('id,name,avatar_url')
                      .inFilter('id', groupIds)
                  as List<dynamic>,
            );
      final contactIds = rows
          .map(
            (row) => row['caller_id']?.toString() == userId
                ? row['callee_id']?.toString()
                : row['caller_id']?.toString(),
          )
          .whereType<String>()
          .toSet()
          .toList();
      final rosterUserIds = rosterRows
          .map((row) => row['user_id']?.toString())
          .whereType<String>()
          .where((id) => id != userId)
          .toSet()
          .toList();
      final profileIds = {...contactIds, ...rosterUserIds}.toList();
      final profiles = profileIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _db
                      .from('profiles')
                      .select('id,nickname,photo_url')
                      .inFilter('id', profileIds)
                  as List<dynamic>,
            );
      final byId = {
        for (final profile in profiles) profile['id'].toString(): profile,
      };
      final rosterNames = {
        for (final id in rosterUserIds)
          id: byId[id]?['nickname']?.toString().trim().isNotEmpty == true
              ? byId[id]!['nickname'].toString().trim()
              : 'OG Vibes student',
      };
      final namesByCall = <String, List<String>>{};
      for (final row in rosterRows) {
        final callId = row['call_id']?.toString();
        final memberId = row['user_id']?.toString();
        if (callId == null || memberId == null) continue;
        final name = memberId == userId ? 'You' : rosterNames[memberId];
        if (name != null) (namesByCall[callId] ??= <String>[]).add(name);
      }
      final calls = rows.map((row) {
        final otherId = row['caller_id']?.toString() == userId
            ? row['callee_id']?.toString()
            : row['caller_id']?.toString();
        return _CallItem.fromRow(
          row,
          currentUserId: userId,
          profile: byId[otherId],
        );
      }).toList();
      final participantsByCall = {
        for (final row in participantRows) row['call_id'].toString(): row,
      };
      final groupsById = {
        for (final row in groupRows) row['id'].toString(): row,
      };
      calls.addAll(
        groupCallRows.map(
          (row) => _CallItem.fromGroupRow(
            row,
            participant: participantsByCall[row['id']?.toString()],
            group: groupsById[row['group_id']?.toString()],
            currentUserId: userId,
            participantNames:
                namesByCall[row['id']?.toString()] ?? const <String>[],
          ),
        ),
      );
      calls.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Your call history could not be loaded.';
      });
    }
  }

  List<_CallItem> get _visible => _calls.where((call) {
    if (_filter == 'Missed' && !call.missed) return false;
    if (_filter == 'Video' && !call.video) return false;
    if (_filter == 'Audio' && call.video) return false;
    final query = _search.trim().toLowerCase();
    return query.isEmpty ||
        call.name.toLowerCase().contains(query) ||
        call.participantNames.any((name) => name.toLowerCase().contains(query));
  }).toList();

  List<Widget> _groupedCallSlivers(List<_CallItem> calls) {
    final groups = <String, List<_CallItem>>{};
    for (final call in calls) {
      groups.putIfAbsent(_dateGroupLabel(call.startedAt), () => []).add(call);
    }
    return groups.entries
        .expand<Widget>(
          (group) => [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  group.key,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverList.separated(
                itemCount: group.value.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) => _CallCard(
                  call: group.value[index],
                  onCallBack:
                      group.value[index].peerId == null ||
                          group.value[index].groupCall
                      ? null
                      : () => _callBack(group.value[index]),
                ),
              ),
            ),
          ],
        )
        .toList();
  }

  String _dateGroupLabel(DateTime value) {
    final local = value.toLocal();
    final today = DateTime.now();
    final date = DateTime(local.year, local.month, local.day);
    final todayDate = DateTime(today.year, today.month, today.day);
    if (date == todayDate) return 'Today';
    if (date == todayDate.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('EEEE, d MMMM').format(local);
  }

  Future<void> _callBack(_CallItem call) async {
    final peerId = call.peerId;
    if (peerId == null || peerId.isEmpty || call.groupCall) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OutgoingCallScreen(
          contactName: call.name,
          contactPhotoUrl: call.photo.isEmpty ? null : call.photo,
          callType: call.type,
          calleeId: peerId,
        ),
      ),
    );
  }

  Future<void> _clearHistory() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear call history?'),
        content: const Text(
          'This hides your call history from your account only. Other participants keep their records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear history'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final hiddenRows = <Map<String, dynamic>>[];
      var offset = 0;
      while (true) {
        final page = List<Map<String, dynamic>>.from(
          await _db
                  .from('calls')
                  .select('id')
                  .or('caller_id.eq.$userId,callee_id.eq.$userId')
                  .range(offset, offset + 499)
              as List<dynamic>,
        );
        hiddenRows.addAll(
          page.map(
            (row) => {
              'user_id': userId,
              'call_kind': 'direct',
              'call_id': row['id'].toString(),
            },
          ),
        );
        if (page.length < 500) break;
        offset += 500;
      }
      offset = 0;
      while (true) {
        final page = List<Map<String, dynamic>>.from(
          await _db
                  .from('group_call_participants')
                  .select('call_id')
                  .eq('user_id', userId)
                  .range(offset, offset + 499)
              as List<dynamic>,
        );
        hiddenRows.addAll(
          page.map(
            (row) => {
              'user_id': userId,
              'call_kind': 'group',
              'call_id': row['call_id'].toString(),
            },
          ),
        );
        if (page.length < 500) break;
        offset += 500;
      }
      for (var start = 0; start < hiddenRows.length; start += 500) {
        await _db
            .from('call_history_hidden')
            .upsert(
              hiddenRows.skip(start).take(500).toList(),
              onConflict: 'user_id,call_kind,call_id',
              ignoreDuplicates: true,
            );
      }
      await _load(showLoader: false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Call history could not be cleared. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final calls = _visible;
    final answered = _calls.where((call) => call.duration != null).length;
    final missed = _calls.where((call) => call.missed).length;
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Call History'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Call history options',
            onSelected: (value) {
              if (value == 'clear') unawaited(_clearHistory());
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear call history')),
            ],
          ),
          IconButton(
            tooltip: 'Refresh call history',
            onPressed: () => _load(showLoader: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(showLoader: false),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              sliver: SliverToBoxAdapter(
                child: _HistoryHeader(
                  total: _calls.length,
                  answered: answered,
                  missed: missed,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _search = value),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Search people or groups',
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
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'All', label: Text('All')),
                    ButtonSegment(value: 'Missed', label: Text('Missed')),
                    ButtonSegment(value: 'Video', label: Text('Video')),
                    ButtonSegment(value: 'Audio', label: Text('Audio')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (value) =>
                      setState(() => _filter = value.first),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Empty(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load calls',
                  message: _error!,
                ),
              )
            else if (calls.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Empty(
                  icon: Icons.phone_in_talk_outlined,
                  title: _filter == 'All'
                      ? (_search.trim().isEmpty
                            ? 'No calls yet'
                            : 'No matching calls')
                      : 'No $_filter calls',
                  message:
                      'Voice and video calls with other students will appear here.',
                  actionLabel: 'Open chats',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MessagesScreen(),
                    ),
                  ),
                ),
              )
            else
              ..._groupedCallSlivers(calls),
          ],
        ),
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.total,
    required this.answered,
    required this.missed,
  });
  final int total;
  final int answered;
  final int missed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: AppStyles.brandGradient,
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: AppColors.vibeBlue.withValues(alpha: .22),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 30),
        const SizedBox(height: 14),
        const Text(
          'Your recent conversations',
          style: TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'See who called, when it happened and how long you spoke.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(label: '$total calls'),
            _Pill(label: '$answered answered'),
            _Pill(label: '$missed missed'),
          ],
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white24),
    ),
    child: Text(
      label,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    ),
  );
}

class _CallCard extends StatelessWidget {
  const _CallCard({required this.call, this.onCallBack});
  final _CallItem call;
  final VoidCallback? onCallBack;

  @override
  Widget build(BuildContext context) {
    final color = call.missed ? AppColors.danger : AppColors.vibeBlue;
    return Semantics(
      label: '${call.name}, ${call.description}, ${call.dateLabel}',
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: color.withValues(alpha: .12),
                backgroundImage: call.photo.isEmpty
                    ? null
                    : CachedNetworkImageProvider(call.photo),
                child: call.photo.isEmpty
                    ? Text(
                        call.name.characters.first.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(call.directionIcon, size: 17, color: color),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            call.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      call.dateLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (call.groupCall && call.participantNames.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        call.participantNames.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (onCallBack != null)
                IconButton.filledTonal(
                  tooltip: 'Call back',
                  onPressed: onCallBack,
                  icon: const Icon(Icons.call_rounded),
                )
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    call.groupCall
                        ? call.video
                              ? Icons.video_call_rounded
                              : Icons.groups_rounded
                        : call.video
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    color: color,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onPressed,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: AppColors.vibeBlue),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onPressed != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    ),
  );
}

class _CallItem {
  const _CallItem({
    required this.name,
    required this.photo,
    required this.type,
    required this.status,
    required this.outgoing,
    required this.startedAt,
    this.groupCall = false,
    this.duration,
    this.peerId,
    this.participantNames = const [],
  });
  final String name;
  final String photo;
  final String type;
  final String status;
  final bool outgoing;
  final DateTime startedAt;
  final bool groupCall;
  final Duration? duration;
  final String? peerId;
  final List<String> participantNames;

  bool get video => type == 'video';
  bool get missed =>
      status == 'missed' ||
      status == 'invited' ||
      (!outgoing && const {'declined', 'cancelled'}.contains(status));
  IconData get directionIcon => missed
      ? Icons.call_missed_rounded
      : outgoing
      ? Icons.call_made_rounded
      : Icons.call_received_rounded;
  String get dateLabel =>
      DateFormat('EEE, d MMM yyyy • HH:mm').format(startedAt.toLocal());
  String get description {
    final direction = groupCall
        ? (outgoing ? 'Group call started by you' : 'Group call')
        : (outgoing ? 'Outgoing' : 'Incoming') +
              (video ? ' video call' : ' voice call');
    if (missed) return '$direction • Missed';
    if (duration != null) return '$direction • ${_duration(duration!)}';
    return '$direction • ${_status(status)}';
  }

  factory _CallItem.fromRow(
    Map<String, dynamic> row, {
    required String currentUserId,
    Map<String, dynamic>? profile,
  }) {
    final outgoing = row['caller_id']?.toString() == currentUserId;
    final answered = DateTime.tryParse(row['answered_at']?.toString() ?? '');
    final ended = DateTime.tryParse(row['ended_at']?.toString() ?? '');
    final nickname = profile?['nickname']?.toString().trim() ?? '';
    return _CallItem(
      name: nickname.isEmpty ? 'OG Vibes student' : nickname,
      photo: profile?['photo_url']?.toString().trim() ?? '',
      type: row['type']?.toString() ?? 'audio',
      status: row['status']?.toString() ?? 'ended',
      outgoing: outgoing,
      peerId: (outgoing ? row['callee_id'] : row['caller_id'])?.toString(),
      startedAt:
          DateTime.tryParse(
            row['started_at']?.toString() ??
                row['created_at']?.toString() ??
                '',
          ) ??
          DateTime.now(),
      duration: answered != null && ended != null && ended.isAfter(answered)
          ? ended.difference(answered)
          : null,
    );
  }

  factory _CallItem.fromGroupRow(
    Map<String, dynamic> row, {
    required String currentUserId,
    Map<String, dynamic>? participant,
    Map<String, dynamic>? group,
    List<String> participantNames = const [],
  }) {
    final joined = DateTime.tryParse(
      participant?['joined_at']?.toString() ?? '',
    );
    final left = DateTime.tryParse(
      participant?['left_at']?.toString() ?? row['ended_at']?.toString() ?? '',
    );
    final groupName = group?['name']?.toString().trim() ?? '';
    return _CallItem(
      name: groupName.isNotEmpty ? groupName : 'Group call',
      // Group avatars are stored in a private bucket; the group initial keeps
      // this history card reliable without persisting an expiring signed URL.
      photo: '',
      type: row['call_type']?.toString() ?? 'audio',
      status:
          participant?['status']?.toString() ??
          row['status']?.toString() ??
          'ended',
      outgoing: row['started_by']?.toString() == currentUserId,
      startedAt:
          DateTime.tryParse(
            row['started_at']?.toString() ??
                row['created_at']?.toString() ??
                participant?['invited_at']?.toString() ??
                '',
          ) ??
          DateTime.now(),
      duration: joined != null && left != null && left.isAfter(joined)
          ? left.difference(joined)
          : null,
      groupCall: true,
      participantNames: participantNames,
    );
  }

  static String _duration(Duration value) {
    if (value.inHours > 0) {
      return '${value.inHours}h ${value.inMinutes.remainder(60)}m';
    }
    if (value.inMinutes > 0) {
      return '${value.inMinutes}m ${value.inSeconds.remainder(60)}s';
    }
    return '${value.inSeconds}s';
  }

  static String _status(String value) => switch (value) {
    'active' => 'In progress',
    'missed' => 'Missed',
    'declined' => 'Declined',
    'cancelled' => 'Cancelled',
    'invited' => 'Missed',
    'ringing' => 'No answer yet',
    _ => 'Ended',
  };
}
