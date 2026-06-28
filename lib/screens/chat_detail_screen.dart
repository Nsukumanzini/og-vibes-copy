import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({super.key, required this.chatId, this.chatTitle});

  final String chatId;
  final String? chatTitle;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadMessages() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showSnack('Please sign in to view messages.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final raw = await Supabase.instance.client
          .from('messages')
          .select('id, sender_id, recipient_id, text, created_at')
          .or('and(sender_id.eq.${user.id},recipient_id.eq.${widget.chatId}),and(sender_id.eq.${widget.chatId},recipient_id.eq.${user.id})')
          .order('created_at', ascending: true) as List<dynamic>?;

      final loadedMessages = <Map<String, dynamic>>[];
      for (final item in raw ?? []) {
        final senderId = (item['sender_id'] as String?)?.trim() ?? '';
        final recipientId = (item['recipient_id'] as String?)?.trim() ?? '';
        if (senderId.isEmpty || recipientId.isEmpty) continue;

        final isMine = senderId == user.id;
        loadedMessages.add({
          'sender': isMine ? 'Me' : widget.chatTitle ?? senderId,
          'mine': isMine,
          'type': 'text',
          'text': item['text'] as String? ?? '',
          'time': _formatTimestamp(item['created_at']),
          'messageId': item['id'],
          'senderId': senderId,
          'recipientId': recipientId,
        });
      }

      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(loadedMessages);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showSnack('Failed to load chat: $error');
    }
  }

  String _formatTimestamp(dynamic createdAt) {
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

  Future<void> _sendMessage() async {
    final rawText = _messageController.text.trim();
    if (rawText.isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showSnack('Please sign in to send messages.');
      return;
    }

    final recipientId = widget.chatId;
    setState(() => _isSending = true);

    try {
      final response = await Supabase.instance.client.from('messages').insert({
        'sender_id': user.id,
        'recipient_id': recipientId,
        'text': rawText,
      }).select() as List<dynamic>?;

      final inserted = List<Map<String, dynamic>>.from(response ?? []);
      final messageRecord = inserted.isNotEmpty ? inserted.first : null;
      final newMessage = {
        'sender': 'Me',
        'mine': true,
        'type': 'text',
        'text': rawText,
        'time': _formatTimestamp(DateTime.now()),
        'messageId': messageRecord?['id'],
        'senderId': user.id,
        'recipientId': recipientId,
      };

      if (!mounted) return;
      setState(() {
        _messages.add(newMessage);
        _messageController.clear();
      });
    } catch (error) {
      _showSnack('Failed to send message: $error');
    }

    if (!mounted) return;
    setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.chatTitle ?? 'Private Chat',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'Delete') {
                _confirmDeleteChat();
              } else if (value == 'Report') {
                _reportChat();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'Delete',
                child: Text('Delete Chat'),
              ),
              PopupMenuItem<String>(
                value: 'Report',
                child: Text('Report Chat'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFFE3F2FD),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, color: Color(0xFF1565C0), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This chat is private and visible only to you and ${widget.chatTitle ?? 'your friend'}.',
                    style: const TextStyle(
                      color: Color(0xFF1565C0),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return _ChatBubble(message: message);
                    },
                  ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteChat() async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete chat'),
          content: const Text('This will remove the chat history for you. Continue?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (choice == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chat deleted with ${widget.chatTitle ?? 'your friend'}.'),),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _reportChat() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Report Chat'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('Inappropriate messages'),
              child: const Text('Inappropriate messages'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('Harassment or abuse'),
              child: const Text('Harassment or abuse'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('Spam or phishing'),
              child: const Text('Spam or phishing'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (reason != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reported chat: $reason')),
      );
    }
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade200),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  filled: true,
                  fillColor: const Color(0xFFF4F7FB),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _isSending ? null : _sendMessage,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _isSending ? Colors.grey : const Color(0xFF1565C0),
                  shape: BoxShape.circle,
                ),
                child: _isSending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                      )
                    : const Icon(Icons.send, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final bool mine = message['mine'] as bool;
    final String sender = message['sender'] as String;
    final String type = message['type'] as String;
    final String time = message['time'] as String;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text(
                  sender,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF607D8B),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: mine ? const Color(0xFF0D47A1) : const Color(0xFFF4F7FB),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (type == 'text')
                    Text(
                      message['text'] as String,
                      style: TextStyle(
                        color: mine ? Colors.white : const Color(0xFF1E293B),
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      time,
                      style: TextStyle(
                        color: mine ? Colors.white70 : const Color(0xFF6B7280),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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
