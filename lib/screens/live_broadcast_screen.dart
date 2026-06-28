// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveBroadcastScreen extends StatefulWidget {
  const LiveBroadcastScreen({super.key});

  @override
  State<LiveBroadcastScreen> createState() => _LiveBroadcastScreenState();
}

class _LiveBroadcastScreenState extends State<LiveBroadcastScreen>
    with SingleTickerProviderStateMixin {
  static const Color _navy = Color(0xFF0A192F);
  static const Color _slate = Color(0xFF5B677A);
  static const Color _softSlate = Color(0xFFE7ECF3);

  late final AnimationController _pulseController;
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final List<_LiveQuestion> _questions = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: 0.8,
      upperBound: 1.05,
    )..repeat(reverse: true);
    _loadQuestions();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _chatController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _isLoading = true;
    });

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _questions.clear();
        _isLoading = false;
      });
      return;
    }

    try {
      final raw = await Supabase.instance.client
          .from('live_questions')
          .select('id, author_id, question, created_at')
          .order('created_at', ascending: true) as List<dynamic>?;

      final loadedQuestions = <_LiveQuestion>[];
      for (final item in raw ?? []) {
        final authorId = (item['author_id'] as String?)?.trim() ?? '';
        loadedQuestions.add(_LiveQuestion(
          id: item['id'].toString(),
          author: authorId == user.id ? 'You' : authorId.isNotEmpty ? authorId : 'Guest',
          message: item['question'] as String? ?? '',
          createdAt: item['created_at'] is DateTime
              ? item['created_at'] as DateTime
              : DateTime.tryParse(item['created_at']?.toString() ?? '') ?? DateTime.now(),
        ));
      }

      if (!mounted) return;
      setState(() {
        _questions
          ..clear()
          ..addAll(loadedQuestions);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load live Q&A: $error')),
      );
    }
  }

  Future<void> _sendQuestion() async {
    final questionText = _chatController.text.trim();
    if (questionText.isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to ask a question.')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final response = await Supabase.instance.client.from('live_questions').insert({
        'author_id': user.id,
        'question': questionText,
      }).select() as List<dynamic>?;

      final inserted = List<Map<String, dynamic>>.from(response ?? []);
      final createdAt = inserted.isNotEmpty && inserted.first['created_at'] != null
          ? (inserted.first['created_at'] is DateTime
              ? inserted.first['created_at'] as DateTime
              : DateTime.tryParse(inserted.first['created_at'].toString()) ?? DateTime.now())
          : DateTime.now();

      final newQuestion = _LiveQuestion(
        id: inserted.isNotEmpty ? inserted.first['id'].toString() : DateTime.now().millisecondsSinceEpoch.toString(),
        author: 'You',
        message: questionText,
        createdAt: createdAt,
      );

      if (!mounted) return;
      setState(() {
        _questions.add(newQuestion);
        _chatController.clear();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post question: $error')),
      );
    }

    if (!mounted) return;
    setState(() {
      _isSending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Live Lecture Broadcast',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _BroadcastPlayer(pulseController: _pulseController),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: _SessionContextCard(),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD7DEE8)),
                ),
                child: const TabBar(
                  labelColor: _navy,
                  unselectedLabelColor: _slate,
                  indicatorColor: _navy,
                  indicatorWeight: 3,
                  tabs: [
                    Tab(text: 'Live Q&A'),
                    Tab(text: 'Class Notes'),
                    Tab(text: 'Resources'),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: TabBarView(
                    children: [
                      _LiveQATab(
                        chatController: _chatController,
                        questions: _questions,
                        isLoading: _isLoading,
                        isSending: _isSending,
                        onSend: _sendQuestion,
                      ),
                      _ClassNotesTab(notesController: _notesController),
                      const _ResourcesTab(),
                    ],
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

class _BroadcastPlayer extends StatelessWidget {
  const _BroadcastPlayer({required this.pulseController});

  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220A192F),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF0B1020).withOpacity(0.16),
                          const Color(0xFF0B1020).withOpacity(0.72),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: AnimatedBuilder(
                    animation: pulseController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: pulseController.value,
                        child: child,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD92D20),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '🔴 LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x661E293B),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x33FFFFFF)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.remove_red_eye_outlined,
                            color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          '245 Viewers',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Color(0xFFF8FAFC),
                    size: 76,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xB3000000)],
                      ),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.pause_rounded,
                            color: Colors.white, size: 22),
                        SizedBox(width: 16),
                        Icon(Icons.volume_up_rounded,
                            color: Colors.white, size: 22),
                        Spacer(),
                        Icon(Icons.fullscreen_rounded,
                            color: Colors.white, size: 22),
                      ],
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

class _SessionContextCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7DEE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mathematics N4 - Calculus Fundamentals',
            style: TextStyle(
              color: Color(0xFF0A192F),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Lecturer: Mr. Nkosi | Started 15 mins ago',
            style: TextStyle(
              color: Color(0xFF5B677A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attendance Logged: 15:00 / 30:00',
                  style: TextStyle(
                    color: Color(0xFF0A192F),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    value: 0.5,
                    minHeight: 10,
                    backgroundColor: Color(0xFFE5EAF2),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF0A192F)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveQATab extends StatelessWidget {
  const _LiveQATab({
    required this.chatController,
    required this.questions,
    required this.isLoading,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController chatController;
  final List<_LiveQuestion> questions;
  final bool isLoading;
  final bool isSending;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7DEE8)),
      ),
      child: Column(
        children: [
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : questions.isEmpty
                    ? const Center(
                        child: Text(
                          'No questions yet. Ask one above.',
                          style: TextStyle(color: Color(0xFF5B677A)),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(14),
                        itemBuilder: (context, index) {
                          final question = questions[index];
                          return _ChatBubble(message: question);
                        },
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemCount: questions.length,
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: chatController,
                    decoration: InputDecoration(
                      hintText: 'Ask a question...',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFD7DEE8)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFD7DEE8)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A192F),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: isSending ? null : onSend,
                    icon: isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _LiveQuestion message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.author,
            style: TextStyle(
              color: const Color(0xFF0A192F),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message.message,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message.formattedTime,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class _ClassNotesTab extends StatelessWidget {
  const _ClassNotesTab({required this.notesController});

  final TextEditingController notesController;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7DEE8)),
      ),
      child: TextField(
        controller: notesController,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          hintText:
              'Write your private lecture notes here while the stream continues...',
          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD7DEE8)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD7DEE8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF0A192F), width: 1.4),
          ),
        ),
      ),
    );
  }
}

class _ResourcesTab extends StatelessWidget {
  const _ResourcesTab();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7DEE8)),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: const Color(0xFFF8FAFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFE2E8F0),
            child: Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFB91C1C)),
          ),
          title: const Text(
            'Calculus_Cheat_Sheet.pdf',
            style: TextStyle(
              color: Color(0xFF0A192F),
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: const Text(
            'Live session companion resource',
            style: TextStyle(
              color: Color(0xFF5B677A),
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Resource download started.'),
                ),
              );
            },
            icon: const Icon(Icons.download_rounded, color: Color(0xFF0A192F)),
            tooltip: 'Download',
          ),
        ),
      ),
    );
  }
}

class _LiveQuestion {
  _LiveQuestion({
    required this.id,
    required this.author,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String author;
  final String message;
  final DateTime createdAt;

  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    }
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}
