import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class GroupChatsScreen extends StatefulWidget {
  const GroupChatsScreen({super.key});

  @override
  State<GroupChatsScreen> createState() => _GroupChatsScreenState();
}

class _GroupChatsScreenState extends State<GroupChatsScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<_GroupChat> _groups = [];
  _GroupChat? _selectedGroup;
  bool _isLoadingGroups = true;
  bool _isLoadingMessages = false;
  bool _isSending = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadGroups();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim();
    });
  }

  Future<void> _loadGroups() async {
    setState(() {
      _isLoadingGroups = true;
    });

    try {
      final raw = await Supabase.instance.client
          .from('group_chats')
          .select('id, name, description, member_count')
          .order('created_at', ascending: false) as List<dynamic>?;

      final loadedGroups = <_GroupChat>[];
      for (final item in raw ?? []) {
        loadedGroups.add(_GroupChat(
          id: item['id'].toString(),
          name: item['name'] as String? ?? 'Unnamed Group',
          description: item['description'] as String? ?? '',
          memberCount: item['member_count'] is int
              ? item['member_count'] as int
              : int.tryParse(item['member_count']?.toString() ?? '') ?? 0,
          messages: [],
        ));
      }

      if (!mounted) return;
      setState(() {
        _groups = loadedGroups;
        if (_selectedGroup == null && _groups.isNotEmpty) {
          _selectedGroup = _groups.first;
          _loadGroupMessages(_selectedGroup!.id);
        }
        _isLoadingGroups = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingGroups = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load groups: $error')),
      );
    }
  }

  Future<void> _loadGroupMessages(String groupId) async {
    setState(() {
      _isLoadingMessages = true;
    });

    try {
      final raw = await Supabase.instance.client
          .from('group_messages')
          .select('id, sender_id, text, created_at')
          .eq('group_id', groupId)
          .order('created_at', ascending: true) as List<dynamic>?;

      final senderIds = <String>{};
      for (final item in raw ?? []) {
        final senderId = (item['sender_id'] as String?)?.trim() ?? '';
        if (senderId.isNotEmpty) {
          senderIds.add(senderId);
        }
      }

      final profiles = <String, String>{};
      if (senderIds.isNotEmpty) {
        final profileRaw = await Supabase.instance.client
            .from('profiles')
            .select('id, name, surname, nickname')
            .inFilter('id', senderIds.toList()) as List<dynamic>?;

        for (final profile in profileRaw ?? []) {
          final id = (profile['id'] as String?)?.trim();
          if (id == null) continue;
          final nickname = ((profile['nickname'] ?? '') as String).trim();
          final fullName = [profile['name'], profile['surname']]
              .where((part) => part is String && (part).trim().isNotEmpty)
              .join(' ')
              .trim();
          final displayName = nickname.isNotEmpty
              ? nickname
              : fullName.isNotEmpty
                  ? fullName
                  : id;
          profiles[id] = displayName;
        }
      }

      final userId = Supabase.instance.client.auth.currentUser?.id;
      final loadedMessages = <_Message>[];
      for (final item in raw ?? []) {
        final senderId = (item['sender_id'] as String?)?.trim() ?? '';
        if (senderId.isEmpty) continue;

        loadedMessages.add(_Message(
          id: item['id'].toString(),
          senderId: senderId,
          senderName: senderId == userId
              ? 'You'
              : profiles[senderId] ?? senderId,
          content: item['text'] as String? ?? '',
          createdAt: item['created_at'] is DateTime
              ? item['created_at'] as DateTime
              : DateTime.tryParse(item['created_at']?.toString() ?? '') ?? DateTime.now(),
        ));
      }

      if (!mounted) return;
      setState(() {
        final selected = _groups.firstWhere((group) => group.id == groupId, orElse: () => _selectedGroup!);
        selected.messages
          ..clear()
          ..addAll(loadedMessages);
        _selectedGroup = selected;
        _isLoadingMessages = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingMessages = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load messages: $error')),
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedGroup == null) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to send messages.')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final response = await Supabase.instance.client.from('group_messages').insert({
        'group_id': _selectedGroup!.id,
        'sender_id': user.id,
        'text': text,
      }).select() as List<dynamic>?;

      final inserted = List<Map<String, dynamic>>.from(response ?? []);
      final messageRecord = inserted.isNotEmpty ? inserted.first : null;
      final newMessage = _Message(
        id: messageRecord?['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: user.id,
        senderName: 'You',
        content: text,
        createdAt: messageRecord?['created_at'] is DateTime
            ? messageRecord!['created_at'] as DateTime
            : DateTime.tryParse(messageRecord?['created_at']?.toString() ?? '') ?? DateTime.now(),
      );

      if (!mounted) return;
      setState(() {
        _selectedGroup?.messages.add(newMessage);
        _messageController.clear();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to send message: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _selectGroup(_GroupChat group) async {
    if (_selectedGroup?.id == group.id) return;
    setState(() {
      _selectedGroup = group;
    });
    await _loadGroupMessages(group.id);
  }

  void _showCreateGroup() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Group name')),
            const SizedBox(height: 8),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final dialogNavigator = Navigator.of(context);
              final dialogMessenger = ScaffoldMessenger.of(context);
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final description = descCtrl.text.trim();
              final user = Supabase.instance.client.auth.currentUser;
              if (user == null) {
                if (!mounted) return;
                dialogMessenger.showSnackBar(
                  const SnackBar(content: Text('Sign in to create a group.')),
                );
                return;
              }

              try {
                final response = await Supabase.instance.client.from('group_chats').insert({
                  'name': name,
                  'description': description,
                  'member_count': 1,
                  'created_by': user.id,
                }).select() as List<dynamic>?;

                final inserted = List<Map<String, dynamic>>.from(response ?? []);
                if (inserted.isNotEmpty) {
                  final newGroup = _GroupChat(
                    id: inserted.first['id'].toString(),
                    name: name,
                    description: description,
                    memberCount: 1,
                    messages: [],
                  );
                  if (!mounted) return;
                  setState(() {
                    _groups.insert(0, newGroup);
                    _selectedGroup = newGroup;
                  });
                  await _loadGroupMessages(newGroup.id);
                  if (!mounted) return;
                }
                dialogNavigator.pop();
              } catch (error) {
                if (!mounted) return;
                dialogMessenger.showSnackBar(
                  SnackBar(content: Text('Unable to create group: $error')),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 800;

    final filteredGroups = _searchQuery.isEmpty
        ? _groups
        : _groups.where((group) => group.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    final groupList = _buildGroupsList(filteredGroups);

    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Group Chats'),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Create Group',
            onPressed: _showCreateGroup,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: isMobile
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search groups...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                Expanded(
                  child: filteredGroups.isEmpty
                      ? _buildEmptyState()
                      : Column(
                          children: [
                            Expanded(child: groupList),
                            if (_selectedGroup != null)
                              Expanded(child: _buildChatArea()),
                          ],
                        ),
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 320,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search groups...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      Expanded(child: groupList),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, color: Color(0xFFE0E0E0)),
                Expanded(
                  child: _selectedGroup == null ? _buildEmptyState() : _buildChatArea(),
                ),
              ],
            ),
    );
  }

  Widget _buildGroupsList(List<_GroupChat> groups) {
    if (_isLoadingGroups) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final group = groups[index];
        final isSelected = _selectedGroup?.id == group.id;
        return _buildGroupTile(group, isSelected);
      },
    );
  }

  Widget _buildGroupTile(_GroupChat group, bool isSelected) {
    return Material(
      color: isSelected ? Colors.grey[100] : Colors.transparent,
      child: InkWell(
        onTap: () => _selectGroup(group),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border(
              left: isSelected
                  ? BorderSide(color: Theme.of(context).primaryColor, width: 4)
                  : BorderSide.none,
            ),
            color: isSelected ? Colors.white : null,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                  fontSize: 14,
                  color: isSelected ? Theme.of(context).primaryColor : Colors.black,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                group.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Text(
                '${group.memberCount} members',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'Select a group to view messages',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea() {
    final group = _selectedGroup!;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor,
                    child: Text(
                      group.name.isNotEmpty ? group.name[0] : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Members: ${group.memberCount}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _showGroupInfo,
                    icon: const Icon(Icons.info_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingMessages
              ? const Center(child: CircularProgressIndicator())
              : group.messages.isEmpty
                  ? const Center(child: Text('No messages yet. Start the conversation.'))
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: group.messages.length,
                      itemBuilder: (context, index) {
                        final message = group.messages[group.messages.length - 1 - index];
                        return _buildMessageBubble(message);
                      },
                    ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  maxLines: null,
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton(
                onPressed: _isSending ? null : _sendMessage,
                mini: true,
                backgroundColor: Theme.of(context).primaryColor,
                child: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(_Message message) {
    final isYourMessage = message.senderName == 'You';
    return Align(
      alignment: isYourMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment:
              isYourMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isYourMessage)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.senderName,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isYourMessage ? Theme.of(context).primaryColor : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isYourMessage ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: isYourMessage ? Colors.white70 : Colors.black54,
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

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  void _showGroupInfo() {
    if (_selectedGroup == null) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Group Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Name: ${_selectedGroup!.name}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Description: ${_selectedGroup!.description}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Members: ${_selectedGroup!.memberCount}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _GroupChat {
  _GroupChat({
    required this.id,
    required this.name,
    required this.description,
    required this.memberCount,
    required this.messages,
  });

  final String id;
  final String name;
  final String description;
  final int memberCount;
  final List<_Message> messages;
}

class _Message {
  _Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime createdAt;
}
