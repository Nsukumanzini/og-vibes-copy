import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';

class GroupChatsScreen extends StatefulWidget {
  const GroupChatsScreen({super.key});

  @override
  State<GroupChatsScreen> createState() => _GroupChatsScreenState();
}

class _GroupChatsScreenState extends State<GroupChatsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final List<ChatGroup> _groups = <ChatGroup>[];
  final Map<String, GroupMembership> _memberships =
      <String, GroupMembership>{};
  final Map<String, StudentProfile> _profiles = <String, StudentProfile>{};
  final List<GroupMessage> _messages = <GroupMessage>[];
  final Map<String, List<MessageReaction>> _reactions =
      <String, List<MessageReaction>>{};
  final Map<String, List<PollVote>> _pollVotes = <String, List<PollVote>>{};

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  RealtimeChannel? _messageChannel;
  ChatGroup? _selectedGroup;
  GroupMessage? _replyingTo;
  String _search = '';
  bool _loading = true;
  bool _loadingMessages = false;
  bool _sending = false;
  bool _mobileChatOpen = false;
  bool _offline = false;
  String? _error;

  SupabaseClient get _supabase => Supabase.instance.client;
  User? get _user => _supabase.auth.currentUser;
  String get _offlineQueueKey => 'group_chat_outbox_${_user?.id ?? 'guest'}';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging && mounted) setState(() {});
      });
    _searchController.addListener(() {
      final value = _searchController.text.trim().toLowerCase();
      if (value != _search && mounted) setState(() => _search = value);
    });
    _watchConnectivity();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _loadDashboard();
    final token = Uri.base.queryParameters['group_invite'];
    if (token != null && token.trim().isNotEmpty && mounted) {
      await _acceptInviteToken(token.trim(), showWelcome: true);
    }
  }

  @override
  void dispose() {
    _messageChannel?.unsubscribe();
    _connectivitySubscription?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _watchConnectivity() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      final offline =
          results.isEmpty || results.every((item) => item == ConnectivityResult.none);
      if (mounted) setState(() => _offline = offline);
      if (!offline) unawaited(_flushOfflineQueue());
    });
  }

  Future<void> _loadDashboard({bool showLoader = true}) async {
    final user = _user;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to discover and join student groups.';
      });
      return;
    }
    if (showLoader) setState(() => _loading = true);
    try {
      final responses = await Future.wait<dynamic>(<Future<dynamic>>[
        _supabase
            .from('group_members')
            .select('group_id, user_id, role, joined_at, last_read_at, muted')
            .eq('user_id', user.id),
        _supabase
            .from('group_chats')
            .select(
              'id, name, description, member_count, created_by, created_at, '
              'visibility, category, avatar_url, banner_url, accent_color, '
              'rules, updated_at',
            )
            .order('updated_at', ascending: false),
      ]);
      final membershipRows =
          List<Map<String, dynamic>>.from(responses[0] as List<dynamic>);
      final groupRows =
          List<Map<String, dynamic>>.from(responses[1] as List<dynamic>);

      final memberships = <String, GroupMembership>{
        for (final row in membershipRows)
          row['group_id'].toString(): GroupMembership.fromRow(row),
      };
      final groups = groupRows.map(ChatGroup.fromRow).toList();
      await _hydrateGroupAssets(groups);
      await _loadGroupSummaries(groups, memberships);

      if (!mounted) return;
      setState(() {
        _memberships
          ..clear()
          ..addAll(memberships);
        _groups
          ..clear()
          ..addAll(groups);
        _loading = false;
        _error = null;
        final selectedId = _selectedGroup?.id;
        if (selectedId != null) {
          _selectedGroup = _groupById(selectedId);
        }
      });
      unawaited(_flushOfflineQueue());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _hydrateGroupAssets(List<ChatGroup> groups) async {
    await Future.wait(groups.map((group) async {
      if (group.avatarPath != null) {
        group.avatarUrl = await _signedMediaUrl(group.avatarPath!);
      }
      if (group.bannerPath != null) {
        group.bannerUrl = await _signedMediaUrl(group.bannerPath!);
      }
    }));
  }

  Future<void> _loadGroupSummaries(
    List<ChatGroup> groups,
    Map<String, GroupMembership> memberships,
  ) async {
    final joinedIds = memberships.keys.toList();
    if (joinedIds.isEmpty) return;
    final rows = List<Map<String, dynamic>>.from(
      await _supabase
          .from('group_messages')
          .select(
            'id, group_id, sender_id, text, message_type, attachment_name, '
            'created_at, is_deleted',
          )
          .inFilter('group_id', joinedIds)
          .order('created_at', ascending: false)
          .limit(300) as List<dynamic>,
    );
    final firstByGroup = <String, Map<String, dynamic>>{};
    final unreadByGroup = <String, int>{};
    for (final row in rows) {
      final groupId = row['group_id'].toString();
      firstByGroup.putIfAbsent(groupId, () => row);
      final lastRead = memberships[groupId]?.lastReadAt;
      final sentAt = _date(row['created_at']);
      if (lastRead != null && sentAt.isAfter(lastRead)) {
        unreadByGroup[groupId] = (unreadByGroup[groupId] ?? 0) + 1;
      }
    }
    for (final group in groups) {
      final row = firstByGroup[group.id];
      if (row != null) {
        group.lastMessage = row['is_deleted'] == true
            ? 'Message removed'
            : _messagePreview(row);
        group.lastMessageAt = _date(row['created_at']);
      }
      group.unreadCount = unreadByGroup[group.id] ?? 0;
    }
  }

  String _messagePreview(Map<String, dynamic> row) {
    final type = row['message_type']?.toString() ?? 'text';
    final text = row['text']?.toString().trim() ?? '';
    if (type == 'poll') return '📊 ${text.isEmpty ? 'New poll' : text}';
    if (type == 'image') return '📷 ${text.isEmpty ? 'Photo' : text}';
    if (type == 'video') return '🎬 ${text.isEmpty ? 'Video' : text}';
    if (type == 'audio') return '🎙️ ${text.isEmpty ? 'Voice note' : text}';
    if (type == 'document') {
      return '📎 ${row['attachment_name'] ?? 'Document'}';
    }
    return text;
  }

  List<ChatGroup> get _filteredGroups {
    final tab = _tabController.index;
    return _groups.where((group) {
      if (tab == 1 && group.category != 'class') return false;
      if (tab == 2 && group.category != 'src') return false;
      if (_search.isEmpty) return true;
      final memberNames = group.memberPreviewIds
          .map((id) => _profiles[id]?.displayName ?? '')
          .join(' ');
      return '${group.name} ${group.description} ${group.lastMessage} '
              '$memberNames ${group.category}'
          .toLowerCase()
          .contains(_search);
    }).toList()
      ..sort((a, b) {
        final unread = b.unreadCount.compareTo(a.unreadCount);
        if (unread != 0) return unread;
        return (b.lastMessageAt ?? b.createdAt)
            .compareTo(a.lastMessageAt ?? a.createdAt);
      });
  }

  ChatGroup? _groupById(String id) {
    for (final group in _groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  bool _isMember(ChatGroup group) => _memberships.containsKey(group.id);
  bool _isManager(ChatGroup group) =>
      _memberships[group.id]?.isManager ?? false;

  Future<void> _selectGroup(ChatGroup group) async {
    HapticFeedback.selectionClick();
    if (!_isMember(group)) {
      await _showJoinPrompt(group);
      return;
    }
    setState(() {
      _selectedGroup = group;
      _mobileChatOpen = true;
    });
    await _loadConversation(group);
  }

  Future<void> _joinPublicGroup(ChatGroup group) async {
    final user = _user;
    if (user == null || group.visibility != 'public') return;
    try {
      await _supabase.from('group_members').insert(<String, dynamic>{
        'group_id': group.id,
        'user_id': user.id,
        'role': 'student',
      });
      await _loadDashboard(showLoader: false);
      final refreshed = _groupById(group.id);
      if (refreshed != null) await _selectGroup(refreshed);
    } catch (error) {
      _showError('Unable to join group', error);
    }
  }

  Future<void> _showJoinPrompt(ChatGroup group) async {
    if (group.visibility != 'public') return;
    final joined = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _GroupAvatar(group: group, size: 58),
              const SizedBox(height: 16),
              Text(
                group.name,
                style: const TextStyle(
                  color: AppColors.midnightInk,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                group.description.isEmpty
                    ? 'Join this public student community to see its members and messages.'
                    : group.description,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  const Icon(Icons.public, color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Public • ${group.memberCount} members',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Join group'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (joined == true) await _joinPublicGroup(group);
  }

  Future<void> _loadConversation(ChatGroup group) async {
    if (!_isMember(group)) return;
    setState(() => _loadingMessages = true);
    try {
      final responses = await Future.wait<dynamic>(<Future<dynamic>>[
        _supabase
            .from('group_messages')
            .select(
              'id, group_id, sender_id, text, message_type, attachment_url, '
              'attachment_name, attachment_mime, reply_to_id, metadata, '
              'is_edited, is_deleted, created_at, updated_at',
            )
            .eq('group_id', group.id)
            .order('created_at')
            .limit(250),
        _supabase
            .from('group_members')
            .select('group_id, user_id, role, joined_at, last_read_at, muted')
            .eq('group_id', group.id),
      ]);
      final messageRows =
          List<Map<String, dynamic>>.from(responses[0] as List<dynamic>);
      final memberRows =
          List<Map<String, dynamic>>.from(responses[1] as List<dynamic>);
      final memberIds =
          memberRows.map((row) => row['user_id'].toString()).toSet().toList();
      await _loadProfiles(memberIds);

      final messages = messageRows.map(GroupMessage.fromRow).toList();
      await Future.wait(messages.map((message) async {
        if (message.attachmentPath != null) {
          message.attachmentUrl =
              await _signedMediaUrl(message.attachmentPath!);
        }
      }));
      await _loadMessageExtras(messages);
      await _markRead(group.id);

      group.memberPreviewIds
        ..clear()
        ..addAll(memberIds.take(5));
      if (!mounted || _selectedGroup?.id != group.id) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(messages);
        _loadingMessages = false;
      });
      _subscribeToMessages(group.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMessages = false);
      _showError('Unable to load conversation', error);
    }
  }

  Future<void> _loadProfiles(List<String> ids) async {
    final missing = ids.where((id) => !_profiles.containsKey(id)).toList();
    if (missing.isEmpty) return;
    final rows = List<Map<String, dynamic>>.from(
      await _supabase
          .from('profiles')
          .select('id, full_name, avatar_url, role')
          .inFilter('id', missing) as List<dynamic>,
    );
    for (final row in rows) {
      final profile = StudentProfile.fromRow(row);
      _profiles[profile.id] = profile;
    }
  }

  Future<void> _loadMessageExtras(List<GroupMessage> messages) async {
    final ids = messages.map((message) => message.id).toList();
    if (ids.isEmpty) return;
    final responses = await Future.wait<dynamic>(<Future<dynamic>>[
      _supabase
          .from('group_message_reactions')
          .select('message_id, user_id, emoji, created_at')
          .inFilter('message_id', ids),
      _supabase
          .from('group_poll_votes')
          .select('message_id, user_id, option_index, created_at')
          .inFilter('message_id', ids),
    ]);
    _reactions.clear();
    for (final row
        in List<Map<String, dynamic>>.from(responses[0] as List<dynamic>)) {
      final reaction = MessageReaction.fromRow(row);
      _reactions
          .putIfAbsent(reaction.messageId, () => <MessageReaction>[])
          .add(reaction);
    }
    _pollVotes.clear();
    for (final row
        in List<Map<String, dynamic>>.from(responses[1] as List<dynamic>)) {
      final vote = PollVote.fromRow(row);
      _pollVotes.putIfAbsent(vote.messageId, () => <PollVote>[]).add(vote);
    }
  }

  void _subscribeToMessages(String groupId) {
    _messageChannel?.unsubscribe();
    _messageChannel = _supabase
        .channel('group-chat-$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (_) {
            final group = _selectedGroup;
            if (group?.id == groupId) unawaited(_loadConversation(group!));
            unawaited(_loadDashboard(showLoader: false));
          },
        )
        .subscribe();
  }

  Future<void> _markRead(String groupId) async {
    final user = _user;
    if (user == null) return;
    await _supabase
        .from('group_members')
        .update(<String, dynamic>{'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('group_id', groupId)
        .eq('user_id', user.id);
    final membership = _memberships[groupId];
    if (membership != null) membership.lastReadAt = DateTime.now().toUtc();
    final group = _groupById(groupId);
    if (group != null) group.unreadCount = 0;
  }

  Future<void> _sendText() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedGroup == null || _sending) return;
    _messageController.clear();
    await _sendMessage(
      text: text,
      messageType: _looksLikeLink(text) ? 'link' : 'text',
      queueOffline: true,
    );
  }

  Future<void> _sendMessage({
    required String text,
    required String messageType,
    String? attachmentPath,
    String? attachmentName,
    String? attachmentMime,
    Map<String, dynamic>? metadata,
    bool queueOffline = false,
  }) async {
    final user = _user;
    final group = _selectedGroup;
    if (user == null || group == null || !_isMember(group)) return;
    setState(() => _sending = true);
    final payload = <String, dynamic>{
      'group_id': group.id,
      'sender_id': user.id,
      'text': text,
      'message_type': messageType,
      'attachment_url': attachmentPath,
      'attachment_name': attachmentName,
      'attachment_mime': attachmentMime,
      'reply_to_id': _replyingTo?.id,
      'metadata': metadata ?? <String, dynamic>{},
    };
    try {
      await _supabase.from('group_messages').insert(payload);
      _replyingTo = null;
      await _loadConversation(group);
      HapticFeedback.lightImpact();
    } catch (error) {
      if (queueOffline && attachmentPath == null) {
        await _queueOfflineMessage(payload);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message queued and will send after reconnection.'),
            ),
          );
        }
      } else {
        _showError('Unable to send message', error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _queueOfflineMessage(Map<String, dynamic> payload) async {
    final preferences = await SharedPreferences.getInstance();
    final queued = preferences.getStringList(_offlineQueueKey) ?? <String>[];
    queued.add(jsonEncode(<String, dynamic>{
      ...payload,
      'queued_at': DateTime.now().toUtc().toIso8601String(),
    }));
    await preferences.setStringList(_offlineQueueKey, queued);
  }

  Future<void> _flushOfflineQueue() async {
    if (_user == null || _offline) return;
    final preferences = await SharedPreferences.getInstance();
    final queued = preferences.getStringList(_offlineQueueKey) ?? <String>[];
    if (queued.isEmpty) return;
    final remaining = <String>[];
    for (final raw in queued) {
      try {
        final payload =
            Map<String, dynamic>.from(jsonDecode(raw) as Map<dynamic, dynamic>)
              ..remove('queued_at');
        await _supabase.from('group_messages').insert(payload);
      } catch (_) {
        remaining.add(raw);
      }
    }
    await preferences.setStringList(_offlineQueueKey, remaining);
    if (remaining.length != queued.length) {
      await _loadDashboard(showLoader: false);
      final group = _selectedGroup;
      if (group != null) await _loadConversation(group);
    }
  }

  Future<void> _pickAndSendAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: <String>[
        'jpg', 'jpeg', 'png', 'webp', 'gif',
        'mp4', 'webm', 'mp3', 'm4a', 'wav', 'ogg',
        'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    final group = _selectedGroup;
    final user = _user;
    if (bytes == null || group == null || user == null) return;
    if (bytes.length > 25 * 1024 * 1024) {
      _showMessage('Files must be 25 MB or smaller.');
      return;
    }
    setState(() => _sending = true);
    try {
      final extension = file.extension?.toLowerCase() ?? 'bin';
      final type = _attachmentType(extension);
      final mime = _mimeType(extension);
      final path =
          '${group.id}/${user.id}/${DateTime.now().microsecondsSinceEpoch}.$extension';
      await _supabase.storage
          .from('group-media')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      await _sendMessage(
        text: '',
        messageType: type,
        attachmentPath: path,
        attachmentName: file.name,
        attachmentMime: mime,
      );
    } catch (error) {
      _showError('Unable to upload attachment', error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _attachmentType(String extension) {
    if (<String>['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(extension)) {
      return 'image';
    }
    if (<String>['mp4', 'webm'].contains(extension)) return 'video';
    if (<String>['mp3', 'm4a', 'wav', 'ogg'].contains(extension)) {
      return 'audio';
    }
    return 'document';
  }

  String _mimeType(String extension) {
    const values = <String, String>{
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'gif': 'image/gif',
      'mp4': 'video/mp4',
      'webm': 'video/webm',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
    };
    return values[extension] ?? 'application/octet-stream';
  }

  Future<String?> _signedMediaUrl(String path) async {
    try {
      return await _supabase.storage
          .from('group-media')
          .createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  Future<void> _showCreatePoll() async {
    final question = TextEditingController();
    final options = <TextEditingController>[
      TextEditingController(),
      TextEditingController(),
    ];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create a poll'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: question,
                  decoration: const InputDecoration(labelText: 'Question'),
                ),
                ...List<Widget>.generate(options.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: options[index],
                      decoration:
                          InputDecoration(labelText: 'Option ${index + 1}'),
                    ),
                  );
                }),
                if (options.length < 6)
                  TextButton.icon(
                    onPressed: () => setDialogState(
                      () => options.add(TextEditingController()),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add option'),
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
              onPressed: () {
                final values = options
                    .map((controller) => controller.text.trim())
                    .where((value) => value.isNotEmpty)
                    .toList();
                if (question.text.trim().isEmpty || values.length < 2) return;
                Navigator.pop(context, <String, dynamic>{
                  'question': question.text.trim(),
                  'options': values,
                });
              },
              child: const Text('Post poll'),
            ),
          ],
        ),
      ),
    );
    for (final controller in options) {
      controller.dispose();
    }
    question.dispose();
    if (result != null) {
      await _sendMessage(
        text: result['question'].toString(),
        messageType: 'poll',
        metadata: <String, dynamic>{'options': result['options']},
      );
    }
  }

  Future<void> _vote(GroupMessage message, int optionIndex) async {
    final user = _user;
    if (user == null) return;
    try {
      await _supabase.from('group_poll_votes').upsert(
        <String, dynamic>{
          'message_id': message.id,
          'user_id': user.id,
          'option_index': optionIndex,
        },
        onConflict: 'message_id,user_id',
      );
      await _loadMessageExtras(_messages);
      if (mounted) setState(() {});
    } catch (error) {
      _showError('Unable to submit vote', error);
    }
  }

  Future<void> _toggleReaction(GroupMessage message, String emoji) async {
    final user = _user;
    if (user == null) return;
    final existing = (_reactions[message.id] ?? <MessageReaction>[])
        .any((item) => item.userId == user.id && item.emoji == emoji);
    try {
      if (existing) {
        await _supabase
            .from('group_message_reactions')
            .delete()
            .eq('message_id', message.id)
            .eq('user_id', user.id)
            .eq('emoji', emoji);
      } else {
        await _supabase.from('group_message_reactions').insert(
          <String, dynamic>{
            'message_id': message.id,
            'user_id': user.id,
            'emoji': emoji,
          },
        );
      }
      await _loadMessageExtras(_messages);
      if (mounted) setState(() {});
    } catch (error) {
      _showError('Unable to update reaction', error);
    }
  }

  Future<void> _showCreateGroup() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final rules = TextEditingController();
    String category = 'class';
    String visibility = 'public';
    String accent = '#2457F5';
    PlatformFile? avatar;
    PlatformFile? banner;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            4,
            22,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Create a student group',
                  style: TextStyle(
                    color: AppColors.midnightInk,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Creators automatically become group administrators.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Group name',
                    prefixIcon: Icon(Icons.groups_2_outlined),
                  ),
                ),
                TextField(
                  controller: description,
                  maxLines: 2,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment(
                      value: 'class',
                      label: Text('Class'),
                      icon: Icon(Icons.school_outlined),
                    ),
                    ButtonSegment(
                      value: 'src',
                      label: Text('SRC'),
                      icon: Icon(Icons.campaign_outlined),
                    ),
                  ],
                  selected: <String>{category},
                  onSelectionChanged: (value) =>
                      setSheetState(() => category = value.first),
                ),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment(
                      value: 'public',
                      label: Text('Public'),
                      icon: Icon(Icons.public),
                    ),
                    ButtonSegment(
                      value: 'private',
                      label: Text('Private'),
                      icon: Icon(Icons.lock_outline),
                    ),
                  ],
                  selected: <String>{visibility},
                  onSelectionChanged: (value) =>
                      setSheetState(() => visibility = value.first),
                ),
                const SizedBox(height: 10),
                Text(
                  visibility == 'public'
                      ? 'Anyone can discover and join. Messages stay hidden until they join.'
                      : 'Students can only join with an invitation link created by a group manager.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: rules,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Community rules (optional)',
                    prefixIcon: Icon(Icons.gavel_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Brand colour',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: <String>[
                    '#2457F5',
                    '#7C3AED',
                    '#0F9D7A',
                    '#E45170',
                    '#E2A500',
                  ].map((value) {
                    final color = _hexColor(value);
                    return ChoiceChip(
                      label: const SizedBox.shrink(),
                      selected: accent == value,
                      avatar: CircleAvatar(backgroundColor: color),
                      onSelected: (_) =>
                          setSheetState(() => accent = value),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                          withData: true,
                        );
                        if (result != null) {
                          setSheetState(() => avatar = result.files.single);
                        }
                      },
                      icon: const Icon(Icons.account_circle_outlined),
                      label: Text(
                        avatar == null ? 'Add avatar' : 'Avatar selected',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                          withData: true,
                        );
                        if (result != null) {
                          setSheetState(() => banner = result.files.single);
                        }
                      },
                      icon: const Icon(Icons.panorama_outlined),
                      label: Text(
                        banner == null ? 'Add banner' : 'Banner selected',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      if (name.text.trim().isEmpty) return;
                      Navigator.pop(context, true);
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Create group'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (created != true) {
      name.dispose();
      description.dispose();
      rules.dispose();
      return;
    }

    final user = _user;
    if (user == null) return;
    try {
      final row = Map<String, dynamic>.from(
        await _supabase
            .from('group_chats')
            .insert(<String, dynamic>{
              'name': name.text.trim(),
              'description': description.text.trim(),
              'created_by': user.id,
              'visibility': visibility,
              'category': category,
              'accent_color': accent,
              'rules': rules.text.trim(),
            })
            .select()
            .single(),
      );
      final groupId = row['id'].toString();
      final assetUpdates = <String, dynamic>{};
      if (avatar?.bytes != null) {
        assetUpdates['avatar_url'] =
            await _uploadGroupImage(groupId, 'avatar', avatar!);
      }
      if (banner?.bytes != null) {
        assetUpdates['banner_url'] =
            await _uploadGroupImage(groupId, 'banner', banner!);
      }
      if (assetUpdates.isNotEmpty) {
        await _supabase
            .from('group_chats')
            .update(assetUpdates)
            .eq('id', groupId);
      }
      await _loadDashboard(showLoader: false);
      final group = _groupById(groupId);
      if (group != null) await _selectGroup(group);
      if (visibility == 'private' && group != null) {
        await _showInvite(group);
      }
    } catch (error) {
      _showError('Unable to create group', error);
    } finally {
      name.dispose();
      description.dispose();
      rules.dispose();
    }
  }

  Future<String> _uploadGroupImage(
    String groupId,
    String label,
    PlatformFile file,
  ) async {
    final user = _user!;
    final extension = file.extension?.toLowerCase() ?? 'jpg';
    final path = '$groupId/${user.id}/$label.$extension';
    await _supabase.storage.from('group-media').uploadBinary(
          path,
          file.bytes!,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _mimeType(extension),
          ),
        );
    return path;
  }

  Future<void> _showJoinByInvite() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a private group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Paste the invitation link or invitation token sent by the group creator.',
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Invitation link',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null || raw.isEmpty) return;
    final token = _extractInviteToken(raw);
    await _acceptInviteToken(token, showWelcome: true);
  }

  Future<void> _acceptInviteToken(
    String token, {
    required bool showWelcome,
  }) async {
    try {
      final groupId = await _supabase.rpc(
        'accept_group_invite',
        params: <String, dynamic>{'p_token': token},
      );
      await _loadDashboard(showLoader: false);
      final group = _groupById(groupId.toString());
      if (group != null) {
        await _selectGroup(group);
        if (showWelcome) _showMessage('Welcome to ${group.name}.');
      }
    } catch (error) {
      _showError('Unable to accept invitation', error);
    }
  }

  String _extractInviteToken(String raw) {
    final uri = Uri.tryParse(raw.trim());
    final queryToken = uri?.queryParameters['token'];
    if (queryToken != null && queryToken.isNotEmpty) return queryToken;
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return raw.trim();
  }

  Future<void> _showInvite(ChatGroup group) async {
    if (!_isManager(group) || group.visibility != 'private') return;
    try {
      final rows = List<Map<String, dynamic>>.from(
        await _supabase.rpc(
          'create_group_invite',
          params: <String, dynamic>{
            'p_group_id': group.id,
            'p_expires_hours': 168,
          },
        ) as List<dynamic>,
      );
      if (rows.isEmpty) return;
      final token = rows.first['invite_token'].toString();
      final link =
          'https://og-vibes.vercel.app/?group_invite=${Uri.encodeQueryComponent(token)}';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Private invitation'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: QrImageView(
                    data: link,
                    size: 190,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: AppColors.midnightInk,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: AppColors.midnightInk,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Only students with this link or QR code can join. It expires in 7 days.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, height: 1.4),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  link,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (mounted) _showMessage('Invitation copied.');
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy'),
            ),
            FilledButton.icon(
              onPressed: () => Share.share(
                'Join ${group.name} on OG Vibes: $link',
              ),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share'),
            ),
          ],
        ),
      );
    } catch (error) {
      _showError('Unable to create invitation', error);
    }
  }

  Future<void> _showGroupInfo() async {
    final group = _selectedGroup;
    if (group == null) return;
    List<GroupMembership> members = <GroupMembership>[];
    try {
      final rows = List<Map<String, dynamic>>.from(
        await _supabase
            .from('group_members')
            .select('group_id, user_id, role, joined_at, last_read_at, muted')
            .eq('group_id', group.id)
            .order('joined_at') as List<dynamic>,
      );
      members = rows.map(GroupMembership.fromRow).toList();
      await _loadProfiles(members.map((item) => item.userId).toList());
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        minChildSize: .5,
        maxChildSize: .94,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
          children: <Widget>[
            _GroupAvatar(group: group, size: 68),
            const SizedBox(height: 14),
            Text(
              group.name,
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${group.visibilityLabel} • ${group.categoryLabel} • '
              '${members.length} members',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (group.rules.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              const Text(
                'Community rules',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                group.rules,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (_isManager(group) && group.visibility == 'private')
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(_showInvite(group));
                    },
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Invite'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _toggleMute(group),
                  icon: Icon(
                    (_memberships[group.id]?.muted ?? false)
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                  ),
                  label: Text(
                    (_memberships[group.id]?.muted ?? false)
                        ? 'Unmute'
                        : 'Mute',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    unawaited(_reportGroup(group));
                  },
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Report'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Members',
              style: TextStyle(
                color: AppColors.midnightInk,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            ...members.map((member) {
              final profile = _profiles[member.userId] ??
                  StudentProfile.fallback(member.userId);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _ProfileAvatar(profile: profile),
                title: Text(
                  profile.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(member.roleLabel),
                trailing: _isManager(group) && member.role != 'creator'
                    ? PopupMenuButton<String>(
                        onSelected: (role) =>
                            _changeMemberRole(group, member, role),
                        itemBuilder: (_) => const <PopupMenuEntry<String>>[
                          PopupMenuItem(
                            value: 'student',
                            child: Text('Student'),
                          ),
                          PopupMenuItem(
                            value: 'moderator',
                            child: Text('Moderator'),
                          ),
                          PopupMenuItem(
                            value: 'admin',
                            child: Text('Admin'),
                          ),
                        ],
                      )
                    : _RoleBadge(role: member.role),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleMute(ChatGroup group) async {
    final membership = _memberships[group.id];
    final user = _user;
    if (membership == null || user == null) return;
    final muted = !membership.muted;
    try {
      await _supabase
          .from('group_members')
          .update(<String, dynamic>{'muted': muted})
          .eq('group_id', group.id)
          .eq('user_id', user.id);
      membership.muted = muted;
      if (mounted) setState(() {});
    } catch (error) {
      _showError('Unable to update notifications', error);
    }
  }

  Future<void> _changeMemberRole(
    ChatGroup group,
    GroupMembership member,
    String role,
  ) async {
    try {
      await _supabase
          .from('group_members')
          .update(<String, dynamic>{'role': role})
          .eq('group_id', group.id)
          .eq('user_id', member.userId);
      _showMessage('Member role updated.');
    } catch (error) {
      _showError('Unable to change role', error);
    }
  }

  Future<void> _reportGroup(ChatGroup group) async {
    final reason = await _askForReason('Report ${group.name}');
    if (reason == null || _user == null) return;
    try {
      await _supabase.from('group_reports').insert(<String, dynamic>{
        'group_id': group.id,
        'reporter_id': _user!.id,
        'reason': reason,
      });
      _showMessage('Report sent privately to group moderators.');
    } catch (error) {
      _showError('Unable to send report', error);
    }
  }

  Future<void> _showMessageActions(GroupMessage message) async {
    final group = _selectedGroup;
    if (group == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined),
              title: const Text('React'),
              onTap: () => Navigator.pop(context, 'react'),
            ),
            if (message.senderId != _user?.id)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Block this member'),
                onTap: () => Navigator.pop(context, 'block'),
              ),
            if (message.senderId != _user?.id)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report message'),
                onTap: () => Navigator.pop(context, 'report'),
              ),
            if (message.senderId == _user?.id || _isManager(group))
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: AppColors.danger),
                title: const Text(
                  'Remove message',
                  style: TextStyle(color: AppColors.danger),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == 'reply') {
      setState(() => _replyingTo = message);
    } else if (action == 'react') {
      await _showReactionPicker(message);
    } else if (action == 'block') {
      await _blockMember(message.senderId);
    } else if (action == 'report') {
      await _reportMessage(message);
    } else if (action == 'delete') {
      await _deleteMessage(message);
    }
  }

  Future<void> _showReactionPicker(GroupMessage message) async {
    final emoji = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('React to message'),
        content: Wrap(
          spacing: 8,
          children: <String>['👍', '❤️', '😂', '🎉', '🙏', '💡']
              .map(
                (item) => InkWell(
                  onTap: () => Navigator.pop(context, item),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(item, style: const TextStyle(fontSize: 27)),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (emoji != null) await _toggleReaction(message, emoji);
  }

  Future<void> _blockMember(String memberId) async {
    final group = _selectedGroup;
    final user = _user;
    if (group == null || user == null) return;
    try {
      await _supabase.from('group_user_blocks').upsert(<String, dynamic>{
        'group_id': group.id,
        'blocker_id': user.id,
        'blocked_user_id': memberId,
      });
      await _loadConversation(group);
      _showMessage('Member blocked. Their messages are now hidden.');
    } catch (error) {
      _showError('Unable to block member', error);
    }
  }

  Future<void> _reportMessage(GroupMessage message) async {
    final group = _selectedGroup;
    final user = _user;
    if (group == null || user == null) return;
    final reason = await _askForReason('Report message');
    if (reason == null) return;
    try {
      await _supabase.from('group_reports').insert(<String, dynamic>{
        'group_id': group.id,
        'message_id': message.id,
        'reported_user_id': message.senderId,
        'reporter_id': user.id,
        'reason': reason,
      });
      _showMessage('Message reported to the group moderators.');
    } catch (error) {
      _showError('Unable to report message', error);
    }
  }

  Future<String?> _askForReason(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'What happened?',
            hintText: 'Provide enough detail for a fair review.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 3) Navigator.pop(context, value);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _deleteMessage(GroupMessage message) async {
    try {
      await _supabase
          .from('group_messages')
          .update(<String, dynamic>{
            'is_deleted': true,
            'text': '',
            'attachment_url': null,
            'attachment_name': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', message.id);
      final group = _selectedGroup;
      if (group != null) await _loadConversation(group);
    } catch (error) {
      _showError('Unable to remove message', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    return VibeScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: !desktop && _mobileChatOpen
            ? IconButton(
                onPressed: () => setState(() => _mobileChatOpen = false),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        title: Text(
          !desktop && _mobileChatOpen && _selectedGroup != null
              ? _selectedGroup!.name
              : 'Group Chats',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: <Widget>[
          if (!(!desktop && _mobileChatOpen))
            IconButton(
              tooltip: 'Join private group',
              onPressed: _showJoinByInvite,
              icon: const Icon(Icons.link_rounded),
            ),
          if (!(!desktop && _mobileChatOpen))
            IconButton(
              tooltip: 'Create group',
              onPressed: _showCreateGroup,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          if (_selectedGroup != null && (desktop || _mobileChatOpen))
            IconButton(
              tooltip: 'Group information',
              onPressed: _showGroupInfo,
              icon: const Icon(Icons.info_outline_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.vibeBlue),
            )
          : _error != null
              ? _buildError()
              : desktop
                  ? _buildDesktop()
                  : _mobileChatOpen && _selectedGroup != null
                      ? _buildConversation()
                      : _buildGroupDirectory(),
    );
  }

  Widget _buildDesktop() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
      child: Row(
        children: <Widget>[
          SizedBox(width: 390, child: _buildGroupDirectory(compact: true)),
          const SizedBox(width: 16),
          Expanded(
            child: _selectedGroup == null
                ? _buildConversationPlaceholder()
                : _buildConversation(),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupDirectory({bool compact = false}) {
    return Column(
      children: <Widget>[
        if (!compact) _buildHero(),
        if (!compact) const SizedBox(height: 16),
        _buildSearchAndTabs(compact: compact),
        if (_offline)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: <Widget>[
                Icon(Icons.cloud_off_outlined, size: 17),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Offline — text messages will be queued.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        Expanded(child: _buildGroupList()),
      ],
    );
  }

  Widget _buildHero() {
    final joined = _memberships.length;
    final unread = _groups.fold<int>(
      0,
      (total, group) => total + group.unreadCount,
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(23),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: AppStyles.bentoRadius,
        boxShadow: AppStyles.glassShadow,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'OG CAMPUS CIRCLES',
                  style: TextStyle(
                    color: AppColors.electricCyan,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Your campus,\ncloser together.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$joined joined • $unread unread',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white12),
            ),
            child: const Icon(
              Icons.forum_rounded,
              color: AppColors.electricCyan,
              size: 42,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: .08, end: 0);
  }

  Widget _buildSearchAndTabs({required bool compact}) {
    return _GlassPanel(
      margin: EdgeInsets.fromLTRB(compact ? 0 : 16, 0, compact ? 0 : 16, 0),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search groups, members or messages',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF3F6FC),
              border: OutlineInputBorder(
                borderRadius: AppStyles.controlRadius,
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TabBar(
            controller: _tabController,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: AppColors.midnightInk,
              borderRadius: BorderRadius.circular(13),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textMuted,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900),
            tabs: const <Tab>[
              Tab(text: 'All'),
              Tab(text: 'Class'),
              Tab(text: 'SRC'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupList() {
    final groups = _filteredGroups;
    if (groups.isEmpty) {
      return _EmptyState(
        icon: Icons.groups_2_outlined,
        title: _search.isEmpty ? 'No groups here yet' : 'No matching groups',
        subtitle: _search.isEmpty
            ? 'Create a group or join a private group with an invitation.'
            : 'Try a different group, member, or message search.',
        action: _search.isEmpty
            ? FilledButton.icon(
                onPressed: _showCreateGroup,
                icon: const Icon(Icons.add),
                label: const Text('Create group'),
              )
            : null,
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadDashboard(showLoader: false),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          final group = groups[index];
          return _GroupCard(
            group: group,
            joined: _isMember(group),
            selected: _selectedGroup?.id == group.id,
            muted: _memberships[group.id]?.muted ?? false,
            profiles: _profiles,
            onTap: () => _selectGroup(group),
          ).animate(delay: (index * 35).ms).fadeIn().slideX(begin: .04, end: 0);
        },
      ),
    );
  }

  Widget _buildConversationPlaceholder() {
    return _GlassPanel(
      child: const _EmptyState(
        icon: Icons.mark_chat_unread_outlined,
        title: 'Choose a conversation',
        subtitle:
            'Join a public group or use a private invitation to start chatting.',
      ),
    );
  }

  Widget _buildConversation() {
    final group = _selectedGroup!;
    return _GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          _buildConversationHeader(group),
          Expanded(
            child: _loadingMessages
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const _EmptyState(
                        icon: Icons.waving_hand_outlined,
                        title: 'Start the conversation',
                        subtitle:
                            'Be the first person to share something useful.',
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
                        itemCount: _messages.length,
                        itemBuilder: (_, reverseIndex) {
                          final index = _messages.length - 1 - reverseIndex;
                          final message = _messages[index];
                          final reply = message.replyToId == null
                              ? null
                              : _messages.cast<GroupMessage?>().firstWhere(
                                    (item) => item?.id == message.replyToId,
                                    orElse: () => null,
                                  );
                          return _MessageBubble(
                            message: message,
                            reply: reply,
                            profile: _profiles[message.senderId] ??
                                StudentProfile.fallback(message.senderId),
                            mine: message.senderId == _user?.id,
                            reactions:
                                _reactions[message.id] ?? <MessageReaction>[],
                            votes: _pollVotes[message.id] ?? <PollVote>[],
                            currentUserId: _user?.id ?? '',
                            onLongPress: () => _showMessageActions(message),
                            onReact: (emoji) =>
                                _toggleReaction(message, emoji),
                            onVote: (index) => _vote(message, index),
                            onOpenAttachment: () =>
                                _openAttachment(message),
                          );
                        },
                      ),
          ),
          _buildComposer(group),
        ],
      ),
    );
  }

  Widget _buildConversationHeader(ChatGroup group) {
    return Container(
      height: group.bannerUrl == null ? null : 128,
      decoration: BoxDecoration(
        gradient: group.bannerUrl == null
            ? LinearGradient(
                colors: <Color>[
                  group.accentColor.withValues(alpha: .16),
                  Colors.white,
                ],
              )
            : null,
        image: group.bannerUrl == null
            ? null
            : DecorationImage(
                image: NetworkImage(group.bannerUrl!),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  AppColors.midnightInk.withValues(alpha: .5),
                  BlendMode.darken,
                ),
              ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          _GroupAvatar(group: group, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        group.bannerUrl == null ? AppColors.midnightInk : Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${group.memberCount} members • ${group.visibilityLabel}',
                  style: TextStyle(
                    color: group.bannerUrl == null
                        ? AppColors.textMuted
                        : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: _showGroupInfo,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(ChatGroup group) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_replyingTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.vibeBlue.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.reply_rounded, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _replyingTo!.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _replyingTo = null),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              PopupMenuButton<String>(
                tooltip: 'Add to message',
                icon: const Icon(Icons.add_circle_outline_rounded),
                onSelected: (value) {
                  if (value == 'file') unawaited(_pickAndSendAttachment());
                  if (value == 'poll') unawaited(_showCreatePoll());
                },
                itemBuilder: (_) => const <PopupMenuEntry<String>>[
                  PopupMenuItem(
                    value: 'file',
                    child: ListTile(
                      leading: Icon(Icons.attach_file_rounded),
                      title: Text('Media or document'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'poll',
                    child: ListTile(
                      leading: Icon(Icons.poll_outlined),
                      title: Text('Poll'),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Message ${group.name}…',
                    filled: true,
                    fillColor: const Color(0xFFF2F5FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              IconButton.filled(
                onPressed: _sending ? null : _sendText,
                style: IconButton.styleFrom(
                  backgroundColor: group.accentColor,
                  foregroundColor: Colors.white,
                ),
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openAttachment(GroupMessage message) async {
    final url = message.attachmentUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildError() {
    return _EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Group Chats could not load',
      subtitle: _error!,
      action: FilledButton.icon(
        onPressed: _loadDashboard,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showError(String title, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title: ${_friendlyError(error)}')),
    );
  }

  static String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('Network') || text.contains('Socket')) {
      return 'Check your connection and try again.';
    }
    if (text.contains('row-level security')) {
      return 'You do not have permission for this action.';
    }
    return text.replaceFirst('PostgrestException(message: ', '').split(',').first;
  }

  static bool _looksLikeLink(String text) =>
      RegExp(r'https?://\S+', caseSensitive: false).hasMatch(text);

  static DateTime _date(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal() ?? DateTime.now();
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: AppStyles.bentoRadius,
        boxShadow: AppStyles.softShadow,
      ),
      child: ClipRRect(
        borderRadius: AppStyles.bentoRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .78),
              borderRadius: AppStyles.bentoRadius,
              border: Border.all(color: Colors.white.withValues(alpha: .86)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.joined,
    required this.selected,
    required this.muted,
    required this.profiles,
    required this.onTap,
  });

  final ChatGroup group;
  final bool joined;
  final bool selected;
  final bool muted;
  final Map<String, StudentProfile> profiles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppStyles.controlRadius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? group.accentColor.withValues(alpha: .09)
                : Colors.white.withValues(alpha: .76),
            borderRadius: AppStyles.controlRadius,
            border: Border.all(
              color: selected ? group.accentColor : AppColors.glassBorder,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _GroupAvatar(group: group, size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            group.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.midnightInk,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (muted)
                          const Icon(
                            Icons.notifications_off_outlined,
                            size: 15,
                            color: AppColors.textMuted,
                          ),
                        if (group.unreadCount > 0) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: group.accentColor,
                              borderRadius: AppStyles.pillRadius,
                            ),
                            child: Text(
                              group.unreadCount > 99
                                  ? '99+'
                                  : '${group.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      joined
                          ? (group.lastMessage.isEmpty
                              ? 'No messages yet'
                              : group.lastMessage)
                          : group.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Icon(
                          group.visibility == 'private'
                              ? Icons.lock_outline_rounded
                              : Icons.public_rounded,
                          size: 13,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${group.categoryLabel} • ${group.memberCount}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (!joined)
                          Text(
                            'JOIN',
                            style: TextStyle(
                              color: group.accentColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
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
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.reply,
    required this.profile,
    required this.mine,
    required this.reactions,
    required this.votes,
    required this.currentUserId,
    required this.onLongPress,
    required this.onReact,
    required this.onVote,
    required this.onOpenAttachment,
  });

  final GroupMessage message;
  final GroupMessage? reply;
  final StudentProfile profile;
  final bool mine;
  final List<MessageReaction> reactions;
  final List<PollVote> votes;
  final String currentUserId;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReact;
  final ValueChanged<int> onVote;
  final VoidCallback onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'Message removed',
            style: TextStyle(
              color: AppColors.textMuted.withValues(alpha: .7),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }
    final grouped = <String, int>{};
    for (final reaction in reactions) {
      grouped[reaction.emoji] = (grouped[reaction.emoji] ?? 0) + 1;
    }
    return Semantics(
      label: '${profile.displayName}: ${message.preview}',
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.only(bottom: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                if (!mine) ...<Widget>[
                  _ProfileAvatar(profile: profile, radius: 15),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Column(
                    crossAxisAlignment:
                        mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: <Widget>[
                      if (!mine)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 4),
                          child: Text(
                            profile.displayName,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: mine
                              ? AppColors.vibeBlue
                              : const Color(0xFFF0F3F8),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(mine ? 18 : 5),
                            bottomRight: Radius.circular(mine ? 5 : 18),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (reply != null)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: mine
                                      ? Colors.white.withValues(alpha: .13)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  reply!.preview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: mine
                                        ? Colors.white70
                                        : AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            _MessageContent(
                              message: message,
                              mine: mine,
                              votes: votes,
                              currentUserId: currentUserId,
                              onVote: onVote,
                              onOpenAttachment: onOpenAttachment,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _relativeTime(message.createdAt) +
                                  (message.isEdited ? ' • edited' : ''),
                              style: TextStyle(
                                color: mine ? Colors.white60 : AppColors.textMuted,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (grouped.isNotEmpty)
                        Transform.translate(
                          offset: const Offset(0, -3),
                          child: Wrap(
                            spacing: 4,
                            children: grouped.entries.map((entry) {
                              final mineReaction = reactions.any(
                                (item) =>
                                    item.emoji == entry.key &&
                                    item.userId == currentUserId,
                              );
                              return InkWell(
                                onTap: () => onReact(entry.key),
                                borderRadius: AppStyles.pillRadius,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mineReaction
                                        ? AppColors.vibeBlue
                                            .withValues(alpha: .14)
                                        : Colors.white,
                                    borderRadius: AppStyles.pillRadius,
                                    border: Border.all(
                                      color: mineReaction
                                          ? AppColors.vibeBlue
                                          : AppColors.glassBorder,
                                    ),
                                  ),
                                  child: Text(
                                    '${entry.key} ${entry.value}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
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

class _MessageContent extends StatelessWidget {
  const _MessageContent({
    required this.message,
    required this.mine,
    required this.votes,
    required this.currentUserId,
    required this.onVote,
    required this.onOpenAttachment,
  });

  final GroupMessage message;
  final bool mine;
  final List<PollVote> votes;
  final String currentUserId;
  final ValueChanged<int> onVote;
  final VoidCallback onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final textColor = mine ? Colors.white : AppColors.midnightInk;
    if (message.messageType == 'poll') {
      final options = List<String>.from(
        message.metadata['options'] as List<dynamic>? ?? <dynamic>[],
      );
      final myVote = votes
          .where((vote) => vote.userId == currentUserId)
          .map((vote) => vote.optionIndex)
          .firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.poll_outlined, color: textColor, size: 19),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  message.text,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...List<Widget>.generate(options.length, (index) {
            final count =
                votes.where((vote) => vote.optionIndex == index).length;
            final selected = myVote == index;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () => onVote(index),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? (mine ? Colors.white24 : AppColors.vibeBlue.withValues(alpha: .12))
                        : (mine ? Colors.white10 : Colors.white),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          options[index],
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '$count',
                        style: TextStyle(color: textColor, fontSize: 11),
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
    if (message.messageType == 'image' && message.attachmentUrl != null) {
      return InkWell(
        onTap: onOpenAttachment,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            message.attachmentUrl!,
            width: 260,
            height: 180,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _AttachmentFallback(
              message: message,
              mine: mine,
            ),
          ),
        ),
      );
    }
    if (<String>['video', 'audio', 'document']
        .contains(message.messageType)) {
      return InkWell(
        onTap: onOpenAttachment,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: mine ? Colors.white12 : Colors.white,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                message.messageType == 'audio'
                    ? Icons.graphic_eq_rounded
                    : message.messageType == 'video'
                        ? Icons.play_circle_outline_rounded
                        : Icons.description_outlined,
                color: textColor,
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  message.attachmentName ?? message.messageType,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new_rounded, size: 16, color: textColor),
            ],
          ),
        ),
      );
    }
    if (message.messageType == 'link') {
      final match =
          RegExp(r'https?://\S+', caseSensitive: false).firstMatch(message.text);
      final link = match?.group(0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(message.text, style: TextStyle(color: textColor, height: 1.35)),
          if (link != null) ...<Widget>[
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                final uri = Uri.tryParse(link);
                if (uri != null) launchUrl(uri);
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: mine ? Colors.white12 : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.link_rounded, color: textColor, size: 18),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        Uri.tryParse(link)?.host ?? link,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    }
    return Text(
      message.text,
      style: TextStyle(color: textColor, height: 1.38),
    );
  }
}

class _AttachmentFallback extends StatelessWidget {
  const _AttachmentFallback({required this.message, required this.mine});

  final GroupMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: 120,
      alignment: Alignment.center,
      color: mine ? Colors.white12 : Colors.white,
      child: const Icon(Icons.broken_image_outlined),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.group, required this.size});

  final ChatGroup group;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: group.accentColor,
        borderRadius: BorderRadius.circular(size * .32),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: group.accentColor.withValues(alpha: .22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: group.avatarUrl == null
          ? Center(
              child: Text(
                group.initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * .34,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          : Image.network(
              group.avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  group.initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * .34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile, this.radius = 20});

  final StudentProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.vibeBlue.withValues(alpha: .12),
      backgroundImage:
          profile.avatarUrl == null ? null : NetworkImage(profile.avatarUrl!),
      child: profile.avatarUrl == null
          ? Text(
              profile.initials,
              style: TextStyle(
                color: AppColors.vibeBlue,
                fontSize: radius * .65,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    if (role == 'student') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ogGold.withValues(alpha: .18),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Text(
        role.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF8A6500),
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.vibeBlue.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.vibeBlue, size: 34),
            ),
            const SizedBox(height: 15),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.midnightInk,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class ChatGroup {
  ChatGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.memberCount,
    required this.createdBy,
    required this.createdAt,
    required this.visibility,
    required this.category,
    required this.avatarPath,
    required this.bannerPath,
    required this.accentHex,
    required this.rules,
  });

  factory ChatGroup.fromRow(Map<String, dynamic> row) => ChatGroup(
        id: row['id'].toString(),
        name: row['name']?.toString().trim() ?? 'Student group',
        description: row['description']?.toString().trim() ?? '',
        memberCount:
            int.tryParse(row['member_count']?.toString() ?? '') ?? 0,
        createdBy: row['created_by']?.toString() ?? '',
        createdAt: _GroupChatsScreenState._date(row['created_at']),
        visibility: row['visibility']?.toString() ?? 'public',
        category: row['category']?.toString() ?? 'class',
        avatarPath: _optional(row['avatar_url']),
        bannerPath: _optional(row['banner_url']),
        accentHex: row['accent_color']?.toString() ?? '#2457F5',
        rules: row['rules']?.toString().trim() ?? '',
      );

  final String id;
  final String name;
  final String description;
  final int memberCount;
  final String createdBy;
  final DateTime createdAt;
  final String visibility;
  final String category;
  final String? avatarPath;
  final String? bannerPath;
  final String accentHex;
  final String rules;
  final List<String> memberPreviewIds = <String>[];
  String? avatarUrl;
  String? bannerUrl;
  String lastMessage = '';
  DateTime? lastMessageAt;
  int unreadCount = 0;

  Color get accentColor => _hexColor(accentHex);
  String get visibilityLabel =>
      visibility == 'private' ? 'Private' : 'Public';
  String get categoryLabel => category == 'src' ? 'SRC' : 'Class';
  String get initials {
    final words = name
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .take(2);
    return words.map((word) => word[0].toUpperCase()).join();
  }
}

class GroupMembership {
  GroupMembership({
    required this.groupId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    required this.lastReadAt,
    required this.muted,
  });

  factory GroupMembership.fromRow(Map<String, dynamic> row) => GroupMembership(
        groupId: row['group_id'].toString(),
        userId: row['user_id'].toString(),
        role: row['role']?.toString() ?? 'student',
        joinedAt: _GroupChatsScreenState._date(row['joined_at']),
        lastReadAt: _GroupChatsScreenState._date(row['last_read_at']),
        muted: row['muted'] == true,
      );

  final String groupId;
  final String userId;
  String role;
  final DateTime joinedAt;
  DateTime lastReadAt;
  bool muted;

  bool get isManager =>
      role == 'creator' || role == 'admin' || role == 'moderator';
  String get roleLabel => switch (role) {
        'creator' => 'Group creator',
        'admin' => 'Administrator',
        'moderator' => 'Moderator',
        _ => 'Student',
      };
}

class GroupMessage {
  GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.text,
    required this.messageType,
    required this.attachmentPath,
    required this.attachmentName,
    required this.attachmentMime,
    required this.replyToId,
    required this.metadata,
    required this.isEdited,
    required this.isDeleted,
    required this.createdAt,
  });

  factory GroupMessage.fromRow(Map<String, dynamic> row) => GroupMessage(
        id: row['id'].toString(),
        groupId: row['group_id'].toString(),
        senderId: row['sender_id'].toString(),
        text: row['text']?.toString() ?? '',
        messageType: row['message_type']?.toString() ?? 'text',
        attachmentPath: _optional(row['attachment_url']),
        attachmentName: _optional(row['attachment_name']),
        attachmentMime: _optional(row['attachment_mime']),
        replyToId: _optional(row['reply_to_id']),
        metadata: row['metadata'] is Map
            ? Map<String, dynamic>.from(row['metadata'] as Map)
            : <String, dynamic>{},
        isEdited: row['is_edited'] == true,
        isDeleted: row['is_deleted'] == true,
        createdAt: _GroupChatsScreenState._date(row['created_at']),
      );

  final String id;
  final String groupId;
  final String senderId;
  final String text;
  final String messageType;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentMime;
  final String? replyToId;
  final Map<String, dynamic> metadata;
  final bool isEdited;
  final bool isDeleted;
  final DateTime createdAt;
  String? attachmentUrl;

  String get preview {
    if (isDeleted) return 'Message removed';
    if (messageType == 'poll') return 'Poll: $text';
    if (messageType == 'image') return 'Photo';
    if (messageType == 'audio') return 'Voice note';
    if (messageType == 'video') return 'Video';
    if (messageType == 'document') return attachmentName ?? 'Document';
    return text;
  }
}

class StudentProfile {
  const StudentProfile({
    required this.id,
    required this.displayName,
    required this.avatarUrl,
  });

  factory StudentProfile.fromRow(Map<String, dynamic> row) => StudentProfile(
        id: row['id'].toString(),
        displayName: row['full_name']?.toString().trim().isNotEmpty == true
            ? row['full_name'].toString().trim()
            : 'OG Student',
        avatarUrl: _optional(row['avatar_url']),
      );

  factory StudentProfile.fallback(String id) => StudentProfile(
        id: id,
        displayName: 'OG Student',
        avatarUrl: null,
      );

  final String id;
  final String displayName;
  final String? avatarUrl;

  String get initials => displayName
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .map((word) => word[0].toUpperCase())
      .join();
}

class MessageReaction {
  const MessageReaction({
    required this.messageId,
    required this.userId,
    required this.emoji,
  });

  factory MessageReaction.fromRow(Map<String, dynamic> row) => MessageReaction(
        messageId: row['message_id'].toString(),
        userId: row['user_id'].toString(),
        emoji: row['emoji'].toString(),
      );

  final String messageId;
  final String userId;
  final String emoji;
}

class PollVote {
  const PollVote({
    required this.messageId,
    required this.userId,
    required this.optionIndex,
  });

  factory PollVote.fromRow(Map<String, dynamic> row) => PollVote(
        messageId: row['message_id'].toString(),
        userId: row['user_id'].toString(),
        optionIndex: int.tryParse(row['option_index'].toString()) ?? 0,
      );

  final String messageId;
  final String userId;
  final int optionIndex;
}

String? _optional(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

Color _hexColor(String value) {
  final clean = value.replaceAll('#', '');
  final parsed = int.tryParse(clean, radix: 16) ?? 0x2457F5;
  return Color(0xFF000000 | parsed);
}

String _relativeTime(DateTime date) {
  final difference = DateTime.now().difference(date);
  if (difference.inMinutes < 1) return 'now';
  if (difference.inHours < 1) return '${difference.inMinutes}m';
  if (difference.inDays < 1) return '${difference.inHours}h';
  if (difference.inDays < 7) return '${difference.inDays}d';
  return '${date.day}/${date.month}/${date.year}';
}
