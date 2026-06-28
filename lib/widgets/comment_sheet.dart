import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommentSheet extends StatefulWidget {
  const CommentSheet({super.key, required this.postId});

  final String postId;

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSending = false;
  String? _replyingToId;
  String? _replyingToName;
  String? _userName;
  String? _userAvatar;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserProfile();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
        final data = await Supabase.instance.client
          .from('profiles')
          .select('name, avatar_url')
          .eq('id', user.id)
          .single();
        final map = data as Map<String, dynamic>?;
      setState(() {
        _userName = map?['name'] as String? ?? user.email ?? 'OG Vibester';
        _userAvatar = map?['avatar_url'] as String?;
      });
    } catch (_) {
      // ignore errors, fall back to auth defaults
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to comment.')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final response = await Supabase.instance.client.from('comments').insert({
        'post_id': widget.postId,
        'author_id': user.id,
        'text': text,
        'parent_id': _replyingToId,
      });

      // Newer Supabase clients often return raw data instead of a
      // PostgrestResponse. Attempt to read `.error` dynamically,
      // otherwise assume success if no exception was thrown.
      try {
        final err = (response as dynamic).error;
        if (err != null) throw err.message ?? err.toString();
      } catch (_) {
        // no `.error` getter — treat as success
      }

      setState(() {
        _commentController.clear();
        _replyingToId = null;
        _replyingToName = null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add comment: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _likeComment(Map<String, dynamic> comment) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to like comments.')),
      );
      return;
    }

    final commentId = comment['id']?.toString();
    if (commentId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('comment_likes')
          .insert({'comment_id': commentId, 'user_id': user.id});
      try {
        final err = (response as dynamic).error;
        if (err != null) throw err.message ?? err.toString();
      } catch (_) {}
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to like comment: $error')));
    }
  }

  Future<void> _reportComment(Map<String, dynamic> comment) async {
    final reason = await _showReportDialog();
    if (reason == null || reason.trim().isEmpty) return;

    try {
      final response = await Supabase.instance.client.from('reports').insert({
        'post_id': widget.postId,
        'comment_id': comment['id']?.toString(),
        'reason': reason.trim(),
      });
      try {
        final err = (response as dynamic).error;
        if (err != null) throw err.message ?? err.toString();
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report submitted.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to report: $error')));
    }
  }

  Future<String?> _showReportDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Report Comment'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Reason (optional)'),
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Report'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.7;
    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          const SizedBox(height: 8),
          Expanded(child: _buildCommentsList()),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Comments',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        if ((_userAvatar != null && _userAvatar!.isNotEmpty) || (_userName != null && _userName!.isNotEmpty)) ...[
          CircleAvatar(
            radius: 16,
            backgroundImage: (_userAvatar != null && _userAvatar!.isNotEmpty) ? NetworkImage(_userAvatar!) : null,
            child: (_userAvatar == null || _userAvatar!.isEmpty) ? Text((_userName ?? 'U')[0].toUpperCase()) : null,
          ),
          const SizedBox(width: 8),
          if (_userName != null)
            Text(
              _userName!,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          const SizedBox(width: 12),
        ],
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  Widget _buildCommentsList() {
    return FutureBuilder<List<dynamic>>(
      future: _fetchComments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmerPlaceholder();
        }

        if (snapshot.hasError) {
          final error = snapshot.error;
          return Center(
            child: Text('Error loading comments: $error'),
          );
        }

        final data = snapshot.data ?? [];
        if (data.isEmpty) {
          return const Center(child: Text('No comments yet. Be the first!'));
        }

        return ListView.builder(
          itemCount: data.length,
          itemBuilder: (context, index) {
            final comment = Map<String, dynamic>.from(data[index] as Map);
            return _buildCommentTile(comment);
          },
        );
      },
    );
  }

  Future<List<dynamic>> _fetchComments() async {
    try {
      final res = await Supabase.instance.client
          .from('comments')
          .select('*, profiles(name, surname, nickname, photo_url)')
          .eq('post_id', widget.postId)
          .order('created_at', ascending: true);

      // Newer clients may return the data directly or wrap it.
      try {
        final dyn = res as dynamic;
        if (dyn is List) return dyn;
        if (dyn is Map && dyn['data'] is List) return dyn['data'] as List<dynamic>;
      } catch (_) {}
      return <dynamic>[];
    } catch (e) {
      rethrow;
    }
  }

  String _extractCommentAuthorName(Map<String, dynamic>? profile) {
    if (profile == null) return 'OG Vibester';

    final nickname = (profile['nickname'] as String?)?.trim();
    if (nickname != null && nickname.isNotEmpty) {
      return nickname;
    }

    final name = (profile['name'] as String?)?.trim();
    final surname = (profile['surname'] as String?)?.trim();
    if ((name?.isNotEmpty ?? false) && (surname?.isNotEmpty ?? false)) {
      return '$name ${surname!}';
    }
    return name ?? surname ?? 'OG Vibester';
  }

  Widget _buildShimmerPlaceholder() {
    return ListView.separated(
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCommentTile(Map<String, dynamic> comment) {
    final parentId = comment['parent_id'] as String?;
    final profile = comment['profiles'] as Map<String, dynamic>?;
    final authorName = _extractCommentAuthorName(profile);
    final text = (comment['text'] as String?) ?? '';
    final likes = comment['likes_count'] as int? ?? 0;
    final timestamp = comment['created_at'];
    final avatarUrl = (profile?['photo_url'] as String?)?.trim();

    return Container(
      margin: EdgeInsets.only(left: parentId == null ? 0 : 24, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundImage: avatarUrl != null
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl == null
                    ? Text(
                        authorName.isNotEmpty
                            ? authorName[0].toUpperCase()
                            : 'O',
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _formatTimestamp(timestamp),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(text),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _replyingToId = comment['id']?.toString();
                    _replyingToName = authorName;
                  });
                },
                icon: const Icon(Icons.reply, size: 18),
                label: const Text('Reply'),
              ),
              TextButton.icon(
                onPressed: () => _likeComment(comment),
                icon: const Icon(Icons.favorite_border, size: 18),
                label: Text('Like ($likes)'),
              ),
              TextButton.icon(
                onPressed: () => _reportComment(comment),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Report'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final hint = _replyingToName != null
        ? 'Replying to $_replyingToName...'
        : 'Add a public comment';
    return SafeArea(
      top: false,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: hint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                suffixIcon: _replyingToName != null
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Cancel reply',
                        onPressed: () => setState(() {
                          _replyingToId = null;
                          _replyingToName = null;
                        }),
                      )
                    : null,
              ),
              minLines: 1,
              maxLines: 3,
            ),
          ),
          const SizedBox(width: 12),
          _isSending
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.send),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _addComment,
                ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    DateTime? date;
    if (timestamp is String) {
      date = DateTime.tryParse(timestamp);
    } else if (timestamp is DateTime) {
      date = timestamp;
    }

    if (date == null) {
      return 'Just now';
    }

    final difference = DateTime.now().difference(date);
    if (difference.inSeconds < 60) {
      return 'Just now';
    }
    if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return '$mins min${mins == 1 ? '' : 's'} ago';
    }
    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours hour${hours == 1 ? '' : 's'} ago';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}
