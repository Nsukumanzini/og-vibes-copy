import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';
import 'outgoing_call_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({super.key, required this.chatId, this.chatTitle});
  final String chatId;
  final String? chatTitle;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _db = Supabase.instance.client;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  final List<_ChatMessage> _messages = [];
  final Map<String, List<Map<String, dynamic>>> _reactions = {};
  final Map<String, String> _mediaUrls = {};
  final List<Uint8List> _voiceChunks = [];
  final List<double> _levels = [];
  RealtimeChannel? _channel;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  StreamSubscription<Uint8List>? _voiceStream;
  StreamSubscription<Amplitude>? _amplitudes;
  Timer? _reloadTimer;
  Timer? _typingTimer;
  Timer? _recordTimer;
  Map<String, dynamic>? _peer;
  bool _loading = true, _sending = false, _offline = false;
  bool _typing = false, _recording = false, _blocked = false;
  int _recordSeconds = 0;

  String? get _uid => _db.auth.currentUser?.id;
  String get _queueKey => 'chat_queue_${_uid}_${widget.chatId}';
  String get _name {
    final nick = (_peer?['nickname'] ?? '').toString().trim();
    if (nick.isNotEmpty) return nick;
    final full = [
      _peer?['name'],
      _peer?['surname'],
    ].whereType<String>().where((v) => v.trim().isNotEmpty).join(' ');
    return full.isEmpty ? (widget.chatTitle ?? 'Private chat') : full;
  }

  @override
  void initState() {
    super.initState();
    _text.addListener(_composerChanged);
    _start();
  }

  @override
  void dispose() {
    _text.removeListener(_composerChanged);
    _text.dispose();
    _scroll.dispose();
    _reloadTimer?.cancel();
    _typingTimer?.cancel();
    _recordTimer?.cancel();
    _connectivity?.cancel();
    _voiceStream?.cancel();
    _amplitudes?.cancel();
    unawaited(_setTyping(false));
    unawaited(_recorder.dispose());
    if (_channel != null) unawaited(_db.removeChannel(_channel!));
    super.dispose();
  }

  Future<void> _start() async {
    final status = await Connectivity().checkConnectivity();
    _offline = status.contains(ConnectivityResult.none);
    _connectivity = Connectivity().onConnectivityChanged.listen((status) {
      final offline = status.contains(ConnectivityResult.none);
      if (mounted) setState(() => _offline = offline);
      if (!offline) unawaited(_flushQueue());
    });
    await _load();
    _listen();
  }

  Future<void> _load({bool loader = true}) async {
    final uid = _uid;
    if (uid == null) return;
    if (loader && _messages.isEmpty && mounted) setState(() => _loading = true);
    try {
      final data = await Future.wait<dynamic>([
        _db
            .from('messages')
            .select(
              'id,sender_id,recipient_id,text,message_type,attachment_url,'
              'attachment_name,attachment_mime,attachment_size,metadata,is_read,'
              'delivered_at,read_at,created_at',
            )
            .or(
              'and(sender_id.eq.$uid,recipient_id.eq.${widget.chatId}),'
              'and(sender_id.eq.${widget.chatId},recipient_id.eq.$uid)',
            )
            .eq('is_deleted', false)
            .order('created_at')
            .limit(300),
        _db
            .from('profiles')
            .select(
              'id,name,surname,nickname,photo_url,is_online,is_verified,course,campus',
            )
            .eq('id', widget.chatId)
            .maybeSingle(),
        _db
            .from('blocked_users')
            .select('id')
            .eq('user_id', uid)
            .eq('blocked_user_id', widget.chatId)
            .maybeSingle(),
      ]);
      final rows = List<Map<String, dynamic>>.from(data[0] as List<dynamic>);
      final messages = rows.map(_ChatMessage.fromRow).toList();
      await Future.wait(messages.map(_signMedia));
      await _loadReactions(messages);
      messages.addAll(await _queued());
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(messages);
        _peer = data[1] as Map<String, dynamic>?;
        _blocked = data[2] != null;
        _loading = false;
      });
      unawaited(_markRead());
      unawaited(_loadTyping());
      WidgetsBinding.instance.addPostFrameCallback((_) => _goBottom());
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      _snack('Unable to load this conversation.');
    }
  }

  Future<void> _signMedia(_ChatMessage message) async {
    if (message.path == null) return;
    try {
      _mediaUrls[message.id] = await _db.storage
          .from('chat-media')
          .createSignedUrl(message.path!, 3600);
    } catch (_) {}
  }

  Future<void> _loadReactions(List<_ChatMessage> messages) async {
    _reactions.clear();
    final ids = messages.map((m) => m.id).toList();
    if (ids.isEmpty) return;
    final rows = await _db
        .from('message_reactions')
        .select('message_id,user_id,emoji')
        .inFilter('message_id', ids);
    for (final row in List<Map<String, dynamic>>.from(rows as List<dynamic>)) {
      _reactions.putIfAbsent(row['message_id'].toString(), () => []).add(row);
    }
  }

  Future<List<_ChatMessage>> _queued() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_queueKey) ?? [])
        .map(
          (raw) => _ChatMessage.queued(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          ),
        )
        .toList();
  }

  void _listen() {
    final uid = _uid;
    if (uid == null) return;
    _channel = _db
        .channel('chat-$uid-${widget.chatId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final r = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            final a = r['sender_id']?.toString(),
                b = r['recipient_id']?.toString();
            if ((a == uid && b == widget.chatId) ||
                (a == widget.chatId && b == uid)) {
              _scheduleLoad();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (_) => _scheduleLoad(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_typing_status',
          callback: (_) => unawaited(_loadTyping()),
        )
        .subscribe();
  }

  void _scheduleLoad() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(
      const Duration(milliseconds: 280),
      () => _load(loader: false),
    );
  }

  Future<void> _markRead() async {
    if (_uid == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _db
          .from('messages')
          .update({'is_read': true, 'read_at': now, 'updated_at': now})
          .eq('sender_id', widget.chatId)
          .eq('recipient_id', _uid!)
          .eq('is_read', false);
    } catch (_) {}
  }

  void _composerChanged() {
    if (mounted) setState(() {});
    final active = _text.text.trim().isNotEmpty;
    unawaited(_setTyping(active));
    _typingTimer?.cancel();
    if (active) {
      _typingTimer = Timer(const Duration(seconds: 2), () => _setTyping(false));
    }
  }

  Future<void> _setTyping(bool active) async {
    if (_uid == null) return;
    try {
      await _db.from('chat_typing_status').upsert({
        'user_id': _uid,
        'peer_id': widget.chatId,
        'is_typing': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _loadTyping() async {
    if (_uid == null) return;
    try {
      final row = await _db
          .from('chat_typing_status')
          .select('is_typing,updated_at')
          .eq('user_id', widget.chatId)
          .eq('peer_id', _uid!)
          .maybeSingle();
      final at = DateTime.tryParse(row?['updated_at']?.toString() ?? '');
      final active =
          row?['is_typing'] == true &&
          at != null &&
          DateTime.now().toUtc().difference(at.toUtc()).inSeconds < 6;
      if (mounted) setState(() => _typing = active);
    } catch (_) {}
  }

  Future<void> _sendText() async {
    final value = _text.text.trim();
    if (value.isEmpty || _blocked) return;
    _text.clear();
    final link = _urlIn(value);
    await _sendOrQueue({
      'sender_id': _uid,
      'recipient_id': widget.chatId,
      'text': value,
      'message_type': link == null ? 'text' : 'link',
      'metadata': link == null ? {} : {'link_url': link},
    });
  }

  Future<void> _sendOrQueue(Map<String, dynamic> payload) async {
    if (_offline) return _queue(payload);
    setState(() => _sending = true);
    try {
      await _db.from('messages').insert(payload);
      HapticFeedback.lightImpact();
      await _load(loader: false);
    } catch (_) {
      if (payload['attachment_url'] == null) {
        await _queue(payload);
      } else {
        _snack('Unable to send this attachment.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _queue(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_queueKey) ?? [];
    list.add(
      jsonEncode({
        ...payload,
        'local_id': 'queued-${DateTime.now().microsecondsSinceEpoch}',
        'queued_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    await prefs.setStringList(_queueKey, list);
    await _load(loader: false);
    _snack('Message queued until you reconnect.');
  }

  Future<void> _flushQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_queueKey) ?? [];
    final remaining = <String>[];
    for (final raw in list) {
      try {
        final p = Map<String, dynamic>.from(jsonDecode(raw) as Map)
          ..remove('local_id')
          ..remove('queued_at');
        await _db.from('messages').insert(p);
      } catch (_) {
        remaining.add(raw);
      }
    }
    await prefs.setStringList(_queueKey, remaining);
    await _load(loader: false);
  }

  Future<void> _pickFile() async {
    if (_offline || _blocked) return _snack('Connect before sending a file.');
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'mp4',
        'webm',
        'mp3',
        'm4a',
        'wav',
        'ogg',
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'txt',
      ],
    );
    if (result == null) return;
    final file = result.files.single, bytes = file.bytes;
    if (bytes == null) return _snack('Unable to read this file.');
    if (bytes.length > 25 * 1024 * 1024) {
      return _snack('Files must be 25 MB or smaller.');
    }
    final ext = (file.extension ?? 'bin').toLowerCase();
    await _upload(bytes, file.name, ext, _kind(ext), _mime(ext), {});
  }

  Future<void> _upload(
    Uint8List bytes,
    String name,
    String ext,
    String type,
    String mime,
    Map<String, dynamic> metadata,
  ) async {
    if (_uid == null) return;
    setState(() => _sending = true);
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '$_uid/${widget.chatId}/${DateTime.now().microsecondsSinceEpoch}-$safe';
    try {
      await _db.storage
          .from('chat-media')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      await _db.from('messages').insert({
        'sender_id': _uid,
        'recipient_id': widget.chatId,
        'text': '',
        'message_type': type,
        'attachment_url': path,
        'attachment_name': name,
        'attachment_mime': mime,
        'attachment_size': bytes.length,
        'metadata': metadata,
      });
      await _load(loader: false);
      HapticFeedback.mediumImpact();
    } catch (_) {
      try {
        await _db.storage.from('chat-media').remove([path]);
      } catch (_) {}
      _snack('Attachment upload failed.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleRecording() async =>
      _recording ? _finishVoice() : _startVoice();
  Future<void> _startVoice() async {
    if (_offline || !await _recorder.hasPermission()) {
      return _snack('Microphone and internet access are required.');
    }
    _voiceChunks.clear();
    _levels.clear();
    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _voiceStream = stream.listen(_voiceChunks.add);
      _amplitudes = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 140))
          .listen((a) {
            if (!mounted) return;
            setState(() {
              _levels.add(((a.current + 60) / 60).clamp(.08, 1));
              if (_levels.length > 28) _levels.removeAt(0);
            });
          });
      setState(() {
        _recording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
        if (_recordSeconds >= 120) unawaited(_finishVoice());
      });
    } catch (_) {
      _snack('Voice recording is unavailable on this device.');
    }
  }

  Future<void> _finishVoice() async {
    _recordTimer?.cancel();
    await _recorder.stop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await _voiceStream?.cancel();
    await _amplitudes?.cancel();
    final bytes = Uint8List.fromList(_voiceChunks.expand((e) => e).toList());
    final seconds = _recordSeconds;
    if (mounted) setState(() => _recording = false);
    if (bytes.isEmpty || seconds < 1) {
      return _snack('Voice note was too short.');
    }
    await _upload(bytes, 'Voice note.wav', 'wav', 'audio', 'audio/wav', {
      'duration_seconds': seconds,
    });
  }

  Future<void> _cancelVoice() async {
    _recordTimer?.cancel();
    await _recorder.cancel();
    await _voiceStream?.cancel();
    await _amplitudes?.cancel();
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _react(_ChatMessage message) async {
    if (message.queued || _blocked) return;
    const choices = ['❤️', '👍', '😂', '😮', '😢', '🔥'];
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: _Glass(
          margin: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: choices
                .map(
                  (e) => InkWell(
                    onTap: () => Navigator.pop(context, e),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (emoji != null) await _toggleReaction(message, emoji);
  }

  Future<void> _toggleReaction(_ChatMessage message, String emoji) async {
    final mine = (_reactions[message.id] ?? []).any(
      (r) => r['user_id'] == _uid && r['emoji'] == emoji,
    );
    try {
      if (mine) {
        await _db
            .from('message_reactions')
            .delete()
            .eq('message_id', message.id)
            .eq('user_id', _uid!)
            .eq('emoji', emoji);
      } else {
        await _db.from('message_reactions').insert({
          'message_id': message.id,
          'user_id': _uid,
          'emoji': emoji,
        });
      }
      await _load(loader: false);
    } catch (_) {
      _snack('Unable to update reaction.');
    }
  }

  Future<void> _openMedia(_ChatMessage m) async {
    final url = _mediaUrls[m.id];
    if (url == null) return _snack('Attachment is temporarily unavailable.');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MediaPage(message: m, url: url),
      ),
    );
  }

  Future<void> _report() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Report conversation'),
        children: [
          for (final r in const [
            'Harassment or abuse',
            'Inappropriate messages',
            'Spam or phishing',
            'Impersonation',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, r),
              child: Text(r),
            ),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await _db.from('chat_reports').insert({
        'reporter_id': _uid,
        'reported_user_id': widget.chatId,
        'reason': reason,
      });
      _snack('Report submitted for review.');
    } catch (_) {
      _snack('Unable to submit report.');
    }
  }

  Future<void> _toggleBlock() async {
    if (_uid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_blocked ? 'Unblock student?' : 'Block student?'),
        content: Text(
          _blocked
              ? 'Messaging will be enabled again.'
              : 'New messages, reactions and typing signals will be stopped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_blocked ? 'Unblock' : 'Block'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (_blocked) {
        await _db
            .from('blocked_users')
            .delete()
            .eq('user_id', _uid!)
            .eq('blocked_user_id', widget.chatId);
      } else {
        await _db.from('blocked_users').insert({
          'user_id': _uid,
          'blocked_user_id': widget.chatId,
          'reason': 'Blocked from direct chat',
        });
      }
      if (mounted) setState(() => _blocked = !_blocked);
    } catch (_) {
      _snack('Unable to update privacy setting.');
    }
  }

  void _goBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _snack(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(value)),
      );
    }
  }

  Future<void> _startCall(String type) async {
    if (_offline) return _snack('Connect to the internet before calling.');
    if (_blocked) return _snack('Unblock this student before calling.');
    if (_uid == null) return _snack('Sign in before starting a call.');
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OutgoingCallScreen(
          contactName: _name,
          callType: type,
          calleeId: widget.chatId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => VibeScaffold(
    appBar: AppBar(
      backgroundColor: Colors.white.withValues(alpha: .72),
      titleSpacing: 0,
      title: _Header(name: _name, peer: _peer, typing: _typing),
      actions: [
        IconButton(
          tooltip: 'Voice call',
          onPressed: () => _startCall('audio'),
          icon: const Icon(Icons.call_rounded),
        ),
        IconButton(
          tooltip: 'Video call',
          onPressed: () => _startCall('video'),
          icon: const Icon(Icons.videocam_rounded),
        ),
        PopupMenuButton<String>(
          tooltip: 'Privacy and safety',
          onSelected: (v) {
            if (v == 'report') {
              _report();
            } else {
              _toggleBlock();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'report',
              child: Text('Report conversation'),
            ),
            PopupMenuItem(
              value: 'block',
              child: Text(_blocked ? 'Unblock student' : 'Block student'),
            ),
          ],
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: Column(
      children: [
        _Banner(name: _name, offline: _offline, blocked: _blocked),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                  ? _Empty(name: _name)
                  : _messageList(),
            ),
          ),
        ),
        _composer(),
      ],
    ),
  );

  Widget _messageList() => ListView.builder(
    controller: _scroll,
    padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
    itemCount: _messages.length,
    itemBuilder: (context, i) {
      final m = _messages[i], prev = i > 0 ? _messages[i - 1] : null;
      final date =
          prev == null || !DateUtils.isSameDay(prev.createdAt, m.createdAt);
      return Column(
        children: [
          if (date) _Day(date: m.createdAt),
          _Bubble(
            message: m,
            mine: m.senderId == _uid,
            reactions: _reactions[m.id] ?? const [],
            url: _mediaUrls[m.id],
            onMedia: () => _openMedia(m),
            onReact: () => _react(m),
            onReaction: (e) => _toggleReaction(m, e),
            onRetry: _flushQueue,
          ),
        ],
      );
    },
  );

  Widget _composer() {
    if (_blocked) {
      return _Glass(
        margin: const EdgeInsets.all(10),
        child: Row(
          children: [
            const Icon(Icons.block, color: AppColors.danger),
            const SizedBox(width: 8),
            const Expanded(child: Text('Messaging is disabled while blocked.')),
            TextButton(onPressed: _toggleBlock, child: const Text('Unblock')),
          ],
        ),
      );
    }
    if (_recording) {
      return _Glass(
        margin: const EdgeInsets.all(10),
        child: Row(
          children: [
            IconButton(
              onPressed: _cancelVoice,
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            ),
            const Icon(Icons.circle, size: 10, color: AppColors.danger),
            const SizedBox(width: 7),
            Text(
              _duration(_recordSeconds),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            Expanded(child: _Wave(values: _levels)),
            IconButton.filled(
              onPressed: _finishVoice,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      );
    }
    final hasText = _text.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: _Glass(
        margin: const EdgeInsets.fromLTRB(10, 5, 10, 10),
        padding: const EdgeInsets.all(7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Attach file',
              onPressed: _sending ? null : _pickFile,
              icon: const Icon(Icons.add_circle_outline),
            ),
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Message',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: hasText ? 'Send message' : 'Record voice note',
              child: IconButton.filled(
                onPressed: _sending
                    ? null
                    : (hasText ? _sendText : _toggleRecording),
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(hasText ? Icons.send : Icons.mic),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.peer, required this.typing});
  final String name;
  final Map<String, dynamic>? peer;
  final bool typing;
  @override
  Widget build(BuildContext context) {
    final photo = (peer?['photo_url'] ?? '').toString();
    final online = peer?['is_online'] == true;
    return Row(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
              child: photo.isEmpty
                  ? Text(name.isEmpty ? '?' : name[0].toUpperCase())
                  : null,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online ? AppColors.success : Colors.grey,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (peer?['is_verified'] == true)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.verified,
                        color: AppColors.vibeBlue,
                        size: 16,
                      ),
                    ),
                ],
              ),
              Text(
                typing ? 'typing…' : (online ? 'Online' : 'Offline'),
                style: TextStyle(
                  fontSize: 11,
                  color: typing ? AppColors.vibeBlue : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.name,
    required this.offline,
    required this.blocked,
  });
  final String name;
  final bool offline, blocked;
  @override
  Widget build(BuildContext context) {
    final c = blocked
        ? AppColors.danger
        : offline
        ? AppColors.warning
        : AppColors.vibeBlue;
    return Container(
      width: double.infinity,
      color: c.withValues(alpha: .08),
      padding: const EdgeInsets.all(9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            blocked
                ? Icons.block
                : offline
                ? Icons.cloud_off
                : Icons.lock_outline,
            size: 16,
            color: c,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              blocked
                  ? '$name is blocked.'
                  : offline
                  ? 'Offline · text messages will be queued.'
                  : 'Private conversation with $name.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.reactions,
    required this.url,
    required this.onMedia,
    required this.onReact,
    required this.onReaction,
    required this.onRetry,
  });
  final _ChatMessage message;
  final bool mine;
  final List<Map<String, dynamic>> reactions;
  final String? url;
  final VoidCallback onMedia, onReact, onRetry;
  final ValueChanged<String> onReaction;
  @override
  Widget build(BuildContext context) {
    final groups = <String, int>{};
    for (final r in reactions) {
      final e = r['emoji'].toString();
      groups[e] = (groups[e] ?? 0) + 1;
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        label: '${mine ? 'You' : 'Friend'} sent ${message.label}',
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width < 600 ? 340 : 520,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: onReact,
                child: Container(
                  padding: message.type == 'image'
                      ? const EdgeInsets.all(5)
                      : const EdgeInsets.fromLTRB(13, 10, 13, 8),
                  decoration: BoxDecoration(
                    gradient: mine ? AppStyles.brandGradient : null,
                    color: mine ? null : Colors.white.withValues(alpha: .82),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white),
                    boxShadow: AppStyles.glassShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Content(
                        message: message,
                        mine: mine,
                        url: url,
                        onMedia: onMedia,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('HH:mm').format(message.createdAt),
                            style: TextStyle(
                              fontSize: 10,
                              color: mine
                                  ? Colors.white70
                                  : AppColors.textMuted,
                            ),
                          ),
                          if (mine) ...[
                            const SizedBox(width: 4),
                            Icon(
                              message.queued
                                  ? Icons.schedule
                                  : message.read || message.deliveredAt != null
                                  ? Icons.done_all
                                  : Icons.done,
                              size: 14,
                              color: message.read
                                  ? AppColors.electricCyan
                                  : Colors.white70,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (groups.isNotEmpty)
                Wrap(
                  spacing: 4,
                  children: groups.entries
                      .map(
                        (e) => ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text('${e.key} ${e.value}'),
                          onPressed: () => onReaction(e.key),
                        ),
                      )
                      .toList(),
                ),
              if (message.queued)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Queued · retry'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.message,
    required this.mine,
    required this.url,
    required this.onMedia,
  });
  final _ChatMessage message;
  final bool mine;
  final String? url;
  final VoidCallback onMedia;
  @override
  Widget build(BuildContext context) {
    if (message.type == 'image') {
      return InkWell(
        onTap: onMedia,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 270,
            height: 190,
            child: url == null
                ? const Center(child: Icon(Icons.image, size: 40))
                : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover),
          ),
        ),
      );
    }
    if (message.type == 'audio') {
      return _Audio(url: url, seconds: message.seconds, mine: mine);
    }
    if (message.type == 'video' || message.type == 'document') {
      return InkWell(
        onTap: onMedia,
        child: SizedBox(
          width: 250,
          child: Row(
            children: [
              Icon(
                message.type == 'video'
                    ? Icons.play_circle_outline
                    : Icons.description_outlined,
                color: mine ? Colors.white : AppColors.vibeBlue,
                size: 30,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message.name ??
                      (message.type == 'video' ? 'Video' : 'Document'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mine ? Colors.white : AppColors.midnightInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final link = message.link ?? _urlIn(message.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.text.isNotEmpty)
          SelectableText(
            message.text,
            style: TextStyle(
              color: mine ? Colors.white : AppColors.midnightInk,
              height: 1.4,
            ),
          ),
        if (link != null) ...[
          const SizedBox(height: 8),
          _Link(url: link, mine: mine),
        ],
      ],
    );
  }
}

class _Audio extends StatefulWidget {
  const _Audio({required this.url, required this.seconds, required this.mine});
  final String? url;
  final int seconds;
  final bool mine;
  @override
  State<_Audio> createState() => _AudioState();
}

class _AudioState extends State<_Audio> {
  final p = AudioPlayer();
  bool playing = false;
  StreamSubscription<PlayerState>? sub;
  @override
  void initState() {
    super.initState();
    sub = p.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => playing = s == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: Row(
      children: [
        IconButton.filledTonal(
          onPressed: widget.url == null
              ? null
              : () async {
                  if (playing) {
                    await p.pause();
                  } else {
                    await p.play(UrlSource(widget.url!));
                  }
                },
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: _Wave(
            values: const [.2, .7, .4, .9, .3, .8, .5, .9, .4, .7, .2],
          ),
        ),
        const SizedBox(width: 7),
        Text(
          _duration(widget.seconds),
          style: TextStyle(
            color: widget.mine ? Colors.white70 : AppColors.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}

class _Link extends StatelessWidget {
  const _Link({required this.url, required this.mine});
  final String url;
  final bool mine;
  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    return InkWell(
      onTap: uri == null ? null : () => launchUrl(uri),
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: mine ? .14 : .75),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.link, color: mine ? Colors.white : AppColors.vibeBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                uri?.host ?? url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mine ? Colors.white : AppColors.midnightInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(Icons.open_in_new, size: 16),
          ],
        ),
      ),
    );
  }
}

class _MediaPage extends StatelessWidget {
  const _MediaPage({required this.message, required this.url});
  final _ChatMessage message;
  final String url;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.midnightInk,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      title: Text(message.name ?? 'Attachment'),
      actions: [
        IconButton(
          onPressed: () => launchUrl(Uri.parse(url)),
          icon: const Icon(Icons.open_in_new),
        ),
      ],
    ),
    body: Center(
      child: message.type == 'image'
          ? InteractiveViewer(
              maxScale: 5,
              child: CachedNetworkImage(imageUrl: url),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  message.type == 'video'
                      ? Icons.play_circle_outline
                      : Icons.description_outlined,
                  size: 80,
                  color: AppColors.electricCyan,
                ),
                const SizedBox(height: 18),
                Text(
                  message.name ?? 'Attachment',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse(url)),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open attachment'),
                ),
              ],
            ),
    ),
  );
}

class _Wave extends StatelessWidget {
  const _Wave({required this.values});
  final List<double> values;
  @override
  Widget build(BuildContext context) {
    final v = values.isEmpty ? List<double>.filled(18, .15) : values;
    return SizedBox(
      height: 30,
      child: Row(
        children: v
            .take(24)
            .map(
              (x) => Expanded(
                child: Container(
                  height: 5 + x * 23,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    gradient: AppStyles.brandGradient,
                    borderRadius: AppStyles.pillRadius,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .75),
        borderRadius: AppStyles.pillRadius,
      ),
      child: Text(
        DateUtils.isSameDay(DateTime.now(), date)
            ? 'Today'
            : DateFormat('d MMM yyyy').format(date),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Center(
    child: _Glass(
      margin: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.waving_hand, color: AppColors.ogGold, size: 42),
          const SizedBox(height: 12),
          const Text(
            'Start the conversation',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            'Say hello to $name. This chat is private.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    ),
  );
}

class _Glass extends StatelessWidget {
  const _Glass({
    required this.child,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(14),
  });
  final Widget child;
  final EdgeInsetsGeometry margin, padding;
  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(23),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .8),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: Colors.white),
            boxShadow: AppStyles.glassShadow,
          ),
          child: child,
        ),
      ),
    ),
  );
}

class _ChatMessage {
  const _ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    required this.path,
    required this.name,
    required this.size,
    required this.meta,
    required this.read,
    required this.deliveredAt,
    required this.createdAt,
    required this.queued,
  });
  factory _ChatMessage.fromRow(Map<String, dynamic> r) => _ChatMessage(
    id: r['id'].toString(),
    senderId: r['sender_id'].toString(),
    text: (r['text'] ?? '').toString(),
    type: (r['message_type'] ?? 'text').toString(),
    path: _opt(r['attachment_url']),
    name: _opt(r['attachment_name']),
    size: (r['attachment_size'] as num?)?.toInt(),
    meta: r['metadata'] is Map
        ? Map<String, dynamic>.from(r['metadata'] as Map)
        : {},
    read: r['is_read'] == true,
    deliveredAt: r['delivered_at'] == null
        ? null
        : _date(r['delivered_at']),
    createdAt: _date(r['created_at']),
    queued: false,
  );
  factory _ChatMessage.queued(Map<String, dynamic> r) => _ChatMessage(
    id: r['local_id'].toString(),
    senderId: r['sender_id'].toString(),
    text: (r['text'] ?? '').toString(),
    type: (r['message_type'] ?? 'text').toString(),
    path: null,
    name: null,
    size: null,
    meta: r['metadata'] is Map
        ? Map<String, dynamic>.from(r['metadata'] as Map)
        : {},
    read: false,
    deliveredAt: null,
    createdAt: _date(r['queued_at']),
    queued: true,
  );
  final String id, senderId, text, type;
  final String? path, name;
  final int? size;
  final Map<String, dynamic> meta;
  final bool read, queued;
  final DateTime? deliveredAt;
  final DateTime createdAt;
  int get seconds => (meta['duration_seconds'] as num?)?.toInt() ?? 0;
  String? get link => _opt(meta['link_url']);
  String get label => switch (type) {
    'image' => 'an image',
    'video' => 'a video',
    'audio' => 'a voice note',
    'document' => 'a document',
    _ => text,
  };
}

String? _opt(dynamic v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

DateTime _date(dynamic v) =>
    DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();
String? _urlIn(String text) => RegExp(
  r'https?://[^\s]+',
  caseSensitive: false,
).firstMatch(text)?.group(0)?.replaceAll(RegExp(r'[.,;!?]+$'), '');
String _kind(String e) =>
    const ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(e)
    ? 'image'
    : const ['mp4', 'webm'].contains(e)
    ? 'video'
    : const ['mp3', 'm4a', 'wav', 'ogg'].contains(e)
    ? 'audio'
    : 'document';
String _mime(String e) =>
    const {
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
    }[e] ??
    'application/octet-stream';
String _duration(int s) =>
    '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
