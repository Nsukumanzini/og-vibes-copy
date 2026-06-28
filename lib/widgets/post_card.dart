import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'comment_sheet.dart';

class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late final PageController _pageController;
  int _currentImageIndex = 0;
  bool _isExpanded = false;
  final List<TapGestureRecognizer> _tagRecognizers = [];
  bool _hasLiked = false;
  int _likeCount = 0;
  bool _likesLoading = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    final postId = widget.data['id']?.toString() ?? widget.data['post_id']?.toString() ?? '';
    if (postId.isNotEmpty) {
      _loadLikeState(postId);
    }
  }

  @override
  void dispose() {
    _resetTagRecognizers();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    final authorOverride = (data['author_name'] as String?)?.trim();
    final content = (data['content'] as String?)?.trim() ?? '';
    final department = (data['department'] as String?)?.trim() ?? 'General';
    final campus = (data['campus'] as String?)?.trim() ?? 'Campus';
    final isAnonymous = data['is_anonymous'] == true;
    final isVerified = data['is_verified'] == true;
    final isOnline = data['is_online'] == true;
    final poll = data['poll'] as Map<String, dynamic>?;
    final timestamp = data['created_at'];

    final rawLikes = data['likes'];
    if (_likeCount == 0) {
      if (rawLikes is List) {
        _likeCount = rawLikes.whereType<String>().length;
      } else if (rawLikes is int) {
        _likeCount = rawLikes;
      } else if (rawLikes is Iterable) {
        _likeCount = List<String>.from(rawLikes).length;
      }
    }

    final postId = data['id']?.toString() ?? data['post_id']?.toString() ?? '';
    final authorName = _extractAuthorName(data) ?? authorOverride;
    final authorPhoto = _extractAuthorPhoto(data);
    final authorCampus = _extractAuthorCampus(data) ?? campus;
    final authorDepartment = _extractAuthorDepartment(data) ?? department;
    final commentCount = data['comments'] is List
        ? (data['comments'] as List).length
        : (data['comments_count'] as int?) ?? 0;

    final images = _extractImages(data);
    final imageCount = images.length;
    final targetIndex = imageCount == 0
        ? 0
        : (_currentImageIndex >= imageCount
              ? imageCount - 1
              : _currentImageIndex);
    if (targetIndex != _currentImageIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _currentImageIndex = targetIndex);
      });
    }

    final bool shouldTrimText = content.length > 100 && !_isExpanded;

    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(
              author: authorName,
              authorPhotoUrl: authorPhoto,
              campus: authorCampus,
              isAnonymous: isAnonymous,
              isVerified: isVerified,
              isOnline: isOnline,
              department: authorDepartment,
              timestamp: timestamp,
              textTheme: textTheme,
              colorScheme: colorScheme,
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildPostText(content, shouldTrimText, textTheme),
            ],
            if (images.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildImageCarousel(images),
            ],
            if (poll != null) ...[const SizedBox(height: 16), _buildPoll(poll)],
            const SizedBox(height: 12),
            _buildFooter(
              likeCount: _likeCount,
              hasLiked: _hasLiked,
              commentCount: commentCount,
              postId: postId,
              data: data,
              textTheme: textTheme,
              colorScheme: colorScheme,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({
    required String? author,
    required String? authorPhotoUrl,
    required String campus,
    required bool isAnonymous,
    required bool isVerified,
    required bool isOnline,
    required String department,
    required dynamic timestamp,
    required TextTheme textTheme,
    required ColorScheme colorScheme,
  }) {
    final displayName = isAnonymous
        ? 'Spotted @ $campus'
        : (author?.isNotEmpty == true ? author! : 'OG Vibester');

    final deptIcon = _getDeptIcon(department);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isOnline ? Colors.green : colorScheme.secondary,
              width: 2,
            ),
          ),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(context).cardTheme.color,
            backgroundImage: authorPhotoUrl != null && authorPhotoUrl.isNotEmpty
                ? NetworkImage(authorPhotoUrl)
                : null,
            child: authorPhotoUrl == null || authorPhotoUrl.isEmpty
                ? isAnonymous
                    ? Icon(
                        Icons.emoji_emotions_outlined,
                        color: colorScheme.secondary,
                      )
                    : Text(
                        displayName[0].toUpperCase(),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      )
                : null,
          ),
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
                      displayName,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isVerified)
                    Icon(
                      Icons.verified,
                      color: colorScheme.secondary,
                      size: 16,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.secondary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$deptIcon $department',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatTimestamp(timestamp),
              style: textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
            ),
            IconButton(
              icon: Icon(Icons.more_vert, color: Colors.grey[400]),
              splashRadius: 20,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('More actions coming soon.')),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPostText(
    String content,
    bool shouldTrimText,
    TextTheme textTheme,
  ) {
    _resetTagRecognizers();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          maxLines: shouldTrimText ? 3 : null,
          overflow: shouldTrimText
              ? TextOverflow.ellipsis
              : TextOverflow.visible,
          text: TextSpan(
            style: textTheme.bodyLarge?.copyWith(height: 1.5),
            children: _buildBodySpans(content),
          ),
        ),
        if (shouldTrimText) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _isExpanded = true),
            child: Text(
              'Read More',
              style: textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImageCarousel(List<String> images) {
    return Column(
      children: [
        SizedBox(
          height: 300,
          child: PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            onPageChanged: (index) =>
                setState(() => _currentImageIndex = index),
            itemBuilder: (context, index) {
              final imageUrl = images[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              );
            },
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(images.length, (index) {
              final isActive = index == _currentImageIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 10 : 8,
                height: isActive ? 10 : 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? Colors.blue : Colors.grey[400],
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildPoll(Map<String, dynamic> poll) {
    final optionA = (poll['optionA'] as String?)?.trim();
    final optionB = (poll['optionB'] as String?)?.trim();

    if ((optionA == null || optionA.isEmpty) &&
        (optionB == null || optionB.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Poll',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
        ),
        const SizedBox(height: 8),
        if (optionA != null && optionA.isNotEmpty) _PollChoice(label: optionA),
        if (optionB != null && optionB.isNotEmpty) ...[
          const SizedBox(height: 8),
          _PollChoice(label: optionB),
        ],
      ],
    );
  }

  Widget _buildFooter({
    required int likeCount,
    required bool hasLiked,
    required int commentCount,
    required String postId,
    required Map<String, dynamic> data,
    required TextTheme textTheme,
    required ColorScheme colorScheme,
  }) {
    final likeLabel = likeCount == 0 ? 'Like' : 'Like ($likeCount)';

    return Column(
      children: [
        Divider(color: Colors.grey[200], thickness: 1, height: 24),
        Row(
          children: [
            _ActionButton(
              icon: _likesLoading
                  ? Icons.hourglass_empty
                  : (hasLiked ? Icons.favorite : Icons.favorite_border),
              label: likeLabel,
              highlighted: hasLiked,
              onTap: () => _togglePostLike(postId),
            ),
            _ActionButton(
              icon: Icons.chat_bubble_outline,
              label: commentCount == 0 ? 'Comment' : 'Comment ($commentCount)',
              onTap: () => _openComments(postId),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _togglePostLike(String postId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to like posts.')));
      return;
    }

    if (postId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to identify the post.')));
      return;
    }

    final hasLiked = _hasLiked;
    try {
      if (hasLiked) {
        await Supabase.instance.client
            .from('post_likes')
            .delete()
              .eq('post_id', postId)
              .eq('user_id', userId);
      } else {
            await Supabase.instance.client
              .from('post_likes')
              .insert({'post_id': postId, 'user_id': userId});
      }

      if (!mounted) return;
      await _loadLikeState(postId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update like: $error')));
    }
  }

  void _openComments(String postId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CommentSheet(postId: postId),
    );
  }

  Future<void> _loadLikeState(String postId) async {
    if (postId.isEmpty) return;
    setState(() {
      _likesLoading = true;
    });

    final res = await Supabase.instance.client
      .from('post_likes')
      .select('user_id')
      .eq('post_id', postId);

    if (!mounted) return;

    setState(() {
      _likesLoading = false;
    });

    // Handle multiple shapes returned by different Supabase client versions
    final dynamicDyn = res as dynamic;
    try {
      final err = dynamicDyn.error;
      if (err != null) return;
    } catch (_) {}

    List<dynamic> rows = [];
    if (dynamicDyn is List) {
      rows = dynamicDyn;
    } else if (dynamicDyn is Map && dynamicDyn['data'] is List) {
      rows = dynamicDyn['data'] as List<dynamic>;
    }

    final likedUsers = rows
            .map((item) => item['user_id']?.toString())
            .whereType<String>()
            .toList();

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    setState(() {
      _likeCount = likedUsers.length;
      _hasLiked = currentUserId != null && likedUsers.contains(currentUserId);
    });
  }


  List<String> _extractImages(Map<String, dynamic> data) {
    final images = <String>[];
    final rawList = data['images'];
    if (rawList is List) {
      images.addAll(
        rawList
            .whereType<String>()
            .map((url) => url.trim())
            .where((url) => url.isNotEmpty),
      );
    }

    final legacy = (data['imageUrl'] as String?)?.trim();
    if (legacy != null && legacy.isNotEmpty && !images.contains(legacy)) {
      images.add(legacy);
    }

    return images;
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is String) {
      final parsed = DateTime.tryParse(timestamp);
      if (parsed != null) {
        return timeago.format(parsed);
      }
    }
    if (timestamp is DateTime) {
      return timeago.format(timestamp);
    }
    return 'Moments ago';
  }

  void _resetTagRecognizers() {
    for (final recognizer in _tagRecognizers) {
      recognizer.dispose();
    }
    _tagRecognizers.clear();
  }

  List<InlineSpan> _buildBodySpans(String content) {
    if (content.isEmpty) {
      return const [TextSpan(text: '')];
    }
    final spans = <InlineSpan>[];
    final spaceRegex = RegExp(r'(\s+)');
    var lastEnd = 0;
    for (final match in spaceRegex.allMatches(content)) {
      if (match.start > lastEnd) {
        final segment = content.substring(lastEnd, match.start);
        spans.add(_buildWordSpan(segment));
      }
      spans.add(TextSpan(text: content.substring(match.start, match.end)));
      lastEnd = match.end;
    }
    if (lastEnd < content.length) {
      spans.add(_buildWordSpan(content.substring(lastEnd)));
    }
    return spans;
  }

  InlineSpan _buildWordSpan(String word) {
    if (word.startsWith('#') && word.length > 1) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _showTagToast(word);
      _tagRecognizers.add(recognizer);
      return TextSpan(
        text: word,
        style: const TextStyle(
          color: Color(0xFF1E5CFF),
          fontWeight: FontWeight.w700,
        ),
        recognizer: recognizer,
      );
    }
    return TextSpan(text: word);
  }

  void _showTagToast(String word) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Searching tag...')));
  }

  String _getDeptIcon(String dept) {
    final lower = dept.toLowerCase();
    if (lower.contains('civil')) return '🏗️';
    if (lower.contains('electrical')) return '⚡';
    if (lower.contains('office') || lower.contains('it')) return '💻';
    if (lower.contains('finance') || lower.contains('business')) return '💰';
    if (lower.contains('education') || lower.contains('primary')) return '📚';
    if (lower.contains('health')) return '🩺';
    if (lower.contains('tourism')) return '🧭';
    if (lower.contains('hospitality')) return '🍽️';
    return '🎓';
  }

  String? _extractAuthorName(Map<String, dynamic> data) {
    final profiles = data['profiles'];
    if (profiles is Map) {
      final nickname = ((profiles['nickname'] ?? '') as String).trim();
      if (nickname.isNotEmpty) return nickname;
      final name = (profiles['name'] as String?)?.trim();
      final surname = (profiles['surname'] as String?)?.trim();
      final full = [if (name != null && name.isNotEmpty) name, if (surname != null && surname.isNotEmpty) surname].join(' ');
      if (full.isNotEmpty) return full;
    }
    return (data['author_name'] as String?)?.trim() ?? (data['author'] as String?)?.trim();
  }

  String? _extractAuthorPhoto(Map<String, dynamic> data) {
    final profiles = data['profiles'];
    if (profiles is Map) {
      final photo = (profiles['photo_url'] as String?)?.trim();
      if (photo != null && photo.isNotEmpty) return photo;
    }
    return (data['author_photo'] as String?)?.trim() ?? (data['avatarUrl'] as String?)?.trim();
  }

  String? _extractAuthorCampus(Map<String, dynamic> data) {
    final profiles = data['profiles'];
    if (profiles is Map) {
      final campus = (profiles['campus'] as String?)?.trim();
      if (campus != null && campus.isNotEmpty) return campus;
    }
    return (data['campus'] as String?)?.trim();
  }

  String? _extractAuthorDepartment(Map<String, dynamic> data) {
    final profiles = data['profiles'];
    if (profiles is Map) {
      final dept = (profiles['department'] as String?)?.trim();
      if (dept != null && dept.isNotEmpty) return dept;
    }
    return (data['department'] as String?)?.trim();
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? Colors.blue : Colors.black54;
    return Expanded(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color),
        label: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _PollChoice extends StatelessWidget {
  const _PollChoice({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey[100]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Icon(Icons.how_to_vote, color: Colors.blueGrey),
        ],
      ),
    );
  }
}
