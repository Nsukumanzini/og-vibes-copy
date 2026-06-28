import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_detail_screen.dart';
import 'my_campus_friends_screen.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late Future<List<Map<String, dynamic>>> _inboxFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _inboxFuture = _loadConversations();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadConversations() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return [];
    }

    final raw = await Supabase.instance.client
        .from('messages')
        .select('id, sender_id, recipient_id, text, created_at')
        .or('sender_id.eq.${user.id},recipient_id.eq.${user.id}')
        .order('created_at', ascending: false) as List<dynamic>?;

    final messages = List<Map<String, dynamic>>.from(raw ?? []);
    final peerIds = <String>{};
    final conversationMap = <String, Map<String, dynamic>>{};

    for (final message in messages) {
      final senderId = (message['sender_id'] as String?)?.trim() ?? '';
      final recipientId = (message['recipient_id'] as String?)?.trim() ?? '';
      if (senderId.isEmpty || recipientId.isEmpty) continue;

      final peerId = senderId == user.id ? recipientId : senderId;
      if (peerId.isEmpty) continue;

      if (!conversationMap.containsKey(peerId)) {
        conversationMap[peerId] = {
          'id': peerId,
          'name': peerId,
          'type': 'Friend',
          'lastMessage': message['text'] as String? ?? 'Sent an attachment',
          'unread': 0,
          'time': _formatTime(message['created_at']),
          'avatarType': 'letter',
          'avatarText': peerId.isNotEmpty ? peerId[0].toUpperCase() : '?',
          'avatarColor': const Color(0xFF2E7D32),
          'isOnline': false,
        };
        peerIds.add(peerId);
      }
    }

    if (peerIds.isNotEmpty) {
      final profileRaw = await Supabase.instance.client
          .from('profiles')
          .select('id, name, surname, photo_url')
          .in_('id', peerIds.toList()) as List<dynamic>?;

      final profileList = List<Map<String, dynamic>>.from(profileRaw ?? []);
      for (final profile in profileList) {
        final id = (profile['id'] as String?)?.trim();
        if (id == null || !conversationMap.containsKey(id)) continue;

        final displayName = [profile['name'], profile['surname']]
            .where((element) => element is String && (element as String).trim().isNotEmpty)
            .join(' ')
            .trim();
        final chat = conversationMap[id]!;
        chat['name'] = displayName.isEmpty ? id : displayName;
        chat['avatarType'] = profile['photo_url'] != null ? 'image' : 'letter';
        chat['avatarText'] = displayName.isEmpty ? id[0].toUpperCase() : displayName[0].toUpperCase();
      }
    }

    return conversationMap.values.toList();
  }

  String _formatTime(dynamic createdAt) {
    if (createdAt == null) return '';
    final dateTime = createdAt is DateTime
        ? createdAt
        : DateTime.tryParse(createdAt.toString()) ?? DateTime.now();

    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return VibeScaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const MyCampusFriendsScreen(),
            ),
          );
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('New Friend Chat'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _inboxFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingState();
          }

          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _inboxFuture = _loadConversations();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry loading inbox'),
              ),
            );
          }

          final conversations = snapshot.data!
              .where((chat) => chat['type'] == 'Friend')
              .toList();

          final filteredConversations = _searchQuery.isEmpty
              ? conversations
              : conversations.where((chat) {
                  final name = (chat['name'] as String).toLowerCase();
                  return name.contains(_searchQuery.toLowerCase());
                }).toList();

          return Column(
            children: [
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF3F51B5), Color(0xFF5C6BC0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chats',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Stay connected with study buddies',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by name...',
                          prefixIcon: const Icon(Icons.search, color: Colors.white70),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.16),
                          hintStyle: const TextStyle(color: Colors.white70),
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                        cursorColor: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: filteredConversations.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat_bubble_outline, size: 64, color: Color(0xFF78909C)),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No chats yet. Start a conversation with a friend.'
                                  : 'No matches for "$_searchQuery".',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.black54,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        itemCount: filteredConversations.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final chat = filteredConversations[index];
                          return _ConversationTile(
                            chat: chat,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => ChatDetailScreen(
                                    chatId: chat['id'] as String,
                                    chatTitle: chat['name'] as String,
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

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: [
            Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: 4,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) => Container(
                  height: 92,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
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

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.chat, required this.onTap});

  final Map<String, dynamic> chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = chat['unread'] as int;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: unread > 0 ? const Color(0xFFE8F0FF) : Colors.white,
          gradient: unread > 0
              ? const LinearGradient(
                  colors: [Color(0xFFDDE8FF), Color(0xFFF4F8FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: unread > 0
                ? const Color(0xFF4F83CC)
                : const Color(0xFFE3EAF2),
            width: unread > 0 ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _ConversationAvatar(chat: chat),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat['name'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w700,
                            color: const Color(0xFF111111),
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                      if (chat['isOnline'] as bool)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2E7D32),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    chat['type'] as String,
                    style: const TextStyle(
                      color: Color(0xFF607D8B),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    chat['lastMessage'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: unread > 0
                          ? const Color(0xFF1B2838)
                          : const Color(0xFF607D8B),
                      fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  chat['time'] as String,
                  style: TextStyle(
                    color: unread > 0
                        ? const Color(0xFF1565C0)
                        : const Color(0xFF78909C),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      unread.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  const Icon(
                    Icons.done_all_rounded,
                    size: 18,
                    color: Color(0xFF00ACC1),
                  ),
              ],
            ),
          ],
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
    final Color color = chat['avatarColor'] as Color;
    final String avatarType = chat['avatarType'] as String;

    return CircleAvatar(
      radius: 24,
      backgroundColor: color.withValues(alpha: 0.14),
      child: avatarType == 'icon'
          ? Icon(
              chat['avatarIcon'] as IconData,
              color: color,
              size: 22,
            )
          : Text(
              chat['avatarText'] as String,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
    );
  }
}
