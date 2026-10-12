import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../utils/theme_constants.dart';
import 'comment_sheet.dart';

class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  final _db = Supabase.instance.client;
  late PageController _pageController;

  StreamSubscription<List<Map<String, dynamic>>>? _likesSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _commentsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _pollSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _optionsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _votesSubscription;

  int _mediaIndex = 0;
  bool _expanded = false;
  bool _liked = false;
  bool _likeBusy = false;
  bool _deleted = false;
  bool _commentsLoading = true;
  bool _pollLoading = true;
  int _likeCount = 0;
  int _commentCount = 0;
  String? _pollQuestion;
  String? _selectedOptionId;
  List<_PollOption> _pollOptions = const [];
  List<Map<String, dynamic>> _pollVotes = const [];
  List<_CommentPreview> _commentPreviews = const [];

  String get _postId =>
      widget.data['id']?.toString() ??
      widget.data['post_id']?.toString() ??
      '';
  String? get _currentUserId => _db.auth.currentUser?.id;
  String? get _authorId => widget.data['user_id']?.toString();
  bool get _isOwner =>
      _currentUserId != null && _currentUserId == _authorId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startRealtime();
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.data['id']?.toString() ??
        oldWidget.data['post_id']?.toString() ??
        '';
    if (oldId != _postId) {
      _cancelRealtime();
      _mediaIndex = 0;
      _expanded = false;
      _deleted = false;
      _pageController.dispose();
      _pageController = PageController();
      _startRealtime();
    }
  }

  @override
  void dispose() {
    _cancelRealtime();
    _pageController.dispose();
    super.dispose();
  }

  void _cancelRealtime() {
    _likesSubscription?.cancel();
    _commentsSubscription?.cancel();
    _pollSubscription?.cancel();
    _optionsSubscription?.cancel();
    _votesSubscription?.cancel();
  }

  void _startRealtime() {
    if (_postId.isEmpty) return;
    _likesSubscription = _db
        .from('post_likes')
        .stream(primaryKey: ['post_id', 'user_id'])
        .eq('post_id', _postId)
        .listen(
          (rows) {
            if (!mounted || _likeBusy) return;
            final userId = _currentUserId;
            setState(() {
              _likeCount = rows.length;
              _liked = userId != null &&
                  rows.any((row) => row['user_id']?.toString() == userId);
            });
          },
          onError: (Object error) => debugPrint('Post likes stream: $error'),
        );

    _commentsSubscription = _db
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('post_id', _postId)
        .listen(
          (rows) {
            if (!mounted) return;
            setState(() {
              _commentCount = rows.length;
              _commentsLoading = false;
            });
            unawaited(_loadCommentPreviews());
          },
          onError: (Object error) {
            if (mounted) setState(() => _commentsLoading = false);
          },
        );

    _pollSubscription = _db
        .from('post_polls')
        .stream(primaryKey: ['post_id'])
        .eq('post_id', _postId)
        .listen(
          (rows) {
            if (!mounted) return;
            setState(() {
              _pollQuestion = rows.isEmpty
                  ? null
                  : rows.first['question']?.toString();
              _pollLoading = false;
            });
          },
          onError: (Object error) {
            if (mounted) setState(() => _pollLoading = false);
          },
        );

    _optionsSubscription = _db
        .from('post_poll_options')
        .stream(primaryKey: ['id'])
        .eq('post_id', _postId)
        .order('position')
        .listen(
          (rows) {
            if (!mounted) return;
            setState(() {
              _pollOptions = rows.map(_PollOption.fromRow).toList();
              _pollLoading = false;
            });
          },
          onError: (Object error) {
            if (mounted) setState(() => _pollLoading = false);
          },
        );

    _votesSubscription = _db
        .from('post_poll_votes')
        .stream(primaryKey: ['post_id', 'user_id'])
        .eq('post_id', _postId)
        .listen(
          (rows) {
            if (!mounted) return;
            final userId = _currentUserId;
            final ownVote = userId == null
                ? null
                : rows.cast<Map<String, dynamic>?>().firstWhere(
                      (row) => row?['user_id']?.toString() == userId,
                      orElse: () => null,
                    );
            setState(() {
              _pollVotes = rows;
              _selectedOptionId = ownVote?['option_id']?.toString();
              _pollLoading = false;
            });
          },
          onError: (Object error) {
            if (mounted) setState(() => _pollLoading = false);
          },
        );
  }

  Future<void> _loadCommentPreviews() async {
    if (_postId.isEmpty) return;
    try {
      final rows = await _db
          .from('comments')
          .select(
            'id,text,author_id,created_at,'
            'profiles!comments_author_id_fkey(name,surname,nickname,photo_url)',
          )
          .eq('post_id', _postId)
          .order('created_at', ascending: false)
          .limit(2);
      if (!mounted) return;
      setState(() {
        _commentPreviews = (rows as List)
            .map((row) => _CommentPreview.fromRow(
                  Map<String, dynamic>.from(row as Map),
                ))
            .toList()
            .reversed
            .toList();
        _commentsLoading = false;
      });
    } catch (error) {
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_deleted) return const SizedBox.shrink();

    final data = widget.data;
    final content = _string(data['content']);
    final isAnonymous = data['is_anonymous'] == true;
    final authorName = isAnonymous
        ? 'Anonymous student'
        : _authorName(data);
    final authorPhoto = isAnonymous ? null : _authorPhoto(data);
    final media = _extractMedia(data);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final cached = data['is_offline_cached'] == true;

    return Semantics(
      container: true,
      label: 'Post by $authorName. $content',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _GlassSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(
                  authorName: authorName,
                  authorPhoto: authorPhoto,
                  anonymous: isAnonymous,
                  cached: cached,
                ),
                if (content.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ExpandablePostText(
                    text: content,
                    expanded: _expanded,
                    onToggle: () => setState(() => _expanded = !_expanded),
                  ),
                ],
                if (media.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _MediaCarousel(
                    items: media,
                    controller: _pageController,
                    currentIndex: _mediaIndex,
                    onChanged: (index) => setState(() => _mediaIndex = index),
                    onOpen: (index) => _openMedia(media, index),
                  ),
                ],
                if (_pollLoading) ...[
                  const SizedBox(height: 16),
                  const _PollSkeleton(),
                ] else if (_pollQuestion != null && _pollOptions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _PollCard(
                    question: _pollQuestion!,
                    options: _pollOptions,
                    votes: _pollVotes,
                    selectedOptionId: _selectedOptionId,
                    onVote: _vote,
                  ),
                ],
                if (_commentsLoading || _commentPreviews.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _CommentsPreview(
                    comments: _commentPreviews,
                    loading: _commentsLoading,
                    total: _commentCount,
                    onOpen: _openComments,
                  ),
                ],
                const SizedBox(height: 14),
                _InteractionBar(
                  liked: _liked,
                  likeCount: _likeCount,
                  commentCount: _commentCount,
                  busy: _likeBusy,
                  onLike: _toggleLike,
                  onComment: _openComments,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required String authorName,
    required String? authorPhoto,
    required bool anonymous,
    required bool cached,
  }) {
    return Row(
      children: [
        _AuthorAvatar(
          name: authorName,
          photoUrl: authorPhoto,
          anonymous: anonymous,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 7,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _formatTimestamp(widget.data['created_at']),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (cached)
                    const _HeaderPill(
                      icon: Icons.offline_pin_rounded,
                      label: 'Offline copy',
                    ),
                ],
              ),
            ],
          ),
        ),
        PopupMenuButton<_PostMenuAction>(
          tooltip: 'Post actions',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: _handleMenuAction,
          itemBuilder: (context) => [
            if (!_isOwner)
              const PopupMenuItem(
                value: _PostMenuAction.report,
                child: _MenuLabel(
                  icon: Icons.flag_outlined,
                  label: 'Report post',
                ),
              ),
            if (!_isOwner && _authorId != null)
              const PopupMenuItem(
                value: _PostMenuAction.block,
                child: _MenuLabel(
                  icon: Icons.block_rounded,
                  label: 'Block author',
                ),
              ),
            if (_isOwner)
              const PopupMenuItem(
                value: _PostMenuAction.delete,
                child: _MenuLabel(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete post',
                  danger: true,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _toggleLike() async {
    final userId = _currentUserId;
    if (userId == null) {
      _showSnack('Sign in to like posts.');
      return;
    }
    if (_postId.isEmpty || _likeBusy) return;

    final previousLiked = _liked;
    final previousCount = _likeCount;
    setState(() {
      _likeBusy = true;
      _liked = !previousLiked;
      _likeCount = (previousCount + (previousLiked ? -1 : 1))
          .clamp(0, 1 << 30)
          .toInt();
    });
    try {
      if (previousLiked) {
        await _db
            .from('post_likes')
            .delete()
            .eq('post_id', _postId)
            .eq('user_id', userId);
      } else {
        await _db.from('post_likes').insert({
          'post_id': _postId,
          'user_id': userId,
        });
      }
      if (mounted) setState(() => _likeBusy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _likeBusy = false;
        _liked = previousLiked;
        _likeCount = previousCount;
      });
      _showSnack('Your like could not be saved. Please try again.');
    }
  }

  Future<void> _vote(_PollOption option) async {
    final userId = _currentUserId;
    if (userId == null) {
      _showSnack('Sign in to vote.');
      return;
    }
    final previous = _selectedOptionId;
    setState(() {
      _selectedOptionId = option.id;
      _pollVotes = [
        ..._pollVotes.where((row) => row['user_id']?.toString() != userId),
        {'post_id': _postId, 'option_id': option.id, 'user_id': userId},
      ];
    });
    try {
      await _db.from('post_poll_votes').upsert(
        {'post_id': _postId, 'option_id': option.id, 'user_id': userId},
        onConflict: 'post_id,user_id',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _selectedOptionId = previous;
        _pollVotes = [
          ..._pollVotes.where((row) => row['user_id']?.toString() != userId),
          if (previous != null)
            {'post_id': _postId, 'option_id': previous, 'user_id': userId},
        ];
      });
      _showSnack('Your vote could not be saved.');
    }
  }

  Future<void> _openComments() async {
    if (_postId.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CommentSheet(postId: _postId),
    );
    await _loadCommentPreviews();
  }

  Future<void> _openMedia(List<_MediaItem> media, int index) async {
    final item = media[index];
    if (item.isVideo) {
      final uri = Uri.tryParse(item.url);
      if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showSnack('This video could not be opened.');
      }
      return;
    }
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, _, _) => _FullScreenGallery(
          media: media,
          initialIndex: index,
        ),
      ),
    );
  }

  void _handleMenuAction(_PostMenuAction action) {
    switch (action) {
      case _PostMenuAction.report:
        _reportPost();
        return;
      case _PostMenuAction.block:
        _blockAuthor();
        return;
      case _PostMenuAction.delete:
        _deletePost();
        return;
    }
  }

  Future<void> _reportPost() async {
    final userId = _currentUserId;
    if (userId == null) {
      _showSnack('Sign in to report posts.');
      return;
    }
    final reason = await _reportReason();
    if (reason == null || reason.isEmpty) return;
    try {
      await _db.from('reports').insert({
        'reporter_id': userId,
        'post_id': _postId,
        'reason': reason,
      });
      _showSnack('Report submitted for review.');
    } catch (error) {
      _showSnack('Could not submit this report.');
    }
  }

  Future<String?> _reportReason() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.flag_outlined),
        title: const Text('Report this post'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Tell us what is wrong with this post…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isNotEmpty) Navigator.pop(dialogContext, reason);
            },
            child: const Text('Submit report'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _blockAuthor() async {
    final userId = _currentUserId;
    final authorId = _authorId;
    if (userId == null || authorId == null || userId == authorId) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.block_rounded, color: AppColors.danger),
        title: const Text('Block this author?'),
        content: const Text(
          'They will no longer be able to message or interact with you. You can manage blocked users in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Block author'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.from('blocked_users').upsert(
        {'user_id': userId, 'blocked_user_id': authorId, 'reason': 'post'},
        onConflict: 'user_id,blocked_user_id',
      );
      if (mounted) setState(() => _deleted = true);
      _showSnack('Author blocked.');
    } catch (error) {
      _showSnack('Could not block this author.');
    }
  }

  Future<void> _deletePost() async {
    if (!_isOwner) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        title: const Text('Delete this post?'),
        content: const Text('This removes the post from the student feed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep post'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete post'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleted = true);
    try {
      await _db.from('posts').delete().eq('id', _postId);
      _showSnack('Post deleted.');
    } catch (error) {
      if (mounted) setState(() => _deleted = false);
      _showSnack('The post could not be deleted.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: AppStyles.bentoRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: dark
                ? const Color(0xD9182B47)
                : Colors.white.withValues(alpha: 0.82),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(
              color: dark
                  ? const Color(0xFF304663)
                  : Colors.white.withValues(alpha: 0.94),
            ),
            boxShadow: AppStyles.glassShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({
    required this.name,
    required this.photoUrl,
    required this.anonymous,
  });
  final String name;
  final String? photoUrl;
  final bool anonymous;

  @override
  Widget build(BuildContext context) => Container(
        width: 50,
        height: 50,
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [AppColors.electricCyan, AppColors.vibeBlue],
          ),
        ),
        child: ClipOval(
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: photoUrl != null && photoUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photoUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => _AvatarFallback(
                      name: name,
                      anonymous: anonymous,
                    ),
                  )
                : _AvatarFallback(name: name, anonymous: anonymous),
          ),
        ),
      );
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name, required this.anonymous});
  final String name;
  final bool anonymous;

  @override
  Widget build(BuildContext context) => Center(
        child: anonymous
            ? const Icon(Icons.person_outline_rounded, color: AppColors.vibeBlue)
            : Text(
                name.isEmpty ? 'O' : name[0].toUpperCase(),
                style: const TextStyle(
                  color: AppColors.vibeBlue,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
      );
}

class _ExpandablePostText extends StatelessWidget {
  const _ExpandablePostText({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final long = text.length > 180;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: MediaQuery.maybeOf(context)?.disableAnimations == true
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Text(
            text,
            maxLines: long && !expanded ? 4 : null,
            overflow: long && !expanded ? TextOverflow.ellipsis : null,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.52),
          ),
        ),
        if (long) ...[
          const SizedBox(height: 5),
          TextButton(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(expanded ? 'Show less' : 'Read more'),
          ),
        ],
      ],
    );
  }
}

class _MediaCarousel extends StatelessWidget {
  const _MediaCarousel({
    required this.items,
    required this.controller,
    required this.currentIndex,
    required this.onChanged,
    required this.onOpen,
  });
  final List<_MediaItem> items;
  final PageController controller;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: PageView.builder(
              controller: controller,
              itemCount: items.length,
              onPageChanged: onChanged,
              itemBuilder: (context, index) {
                final item = items[index];
                return Semantics(
                  button: true,
                  label: item.isVideo
                      ? 'Open video ${index + 1} of ${items.length}'
                      : 'Open image ${index + 1} of ${items.length}',
                  child: InkWell(
                    onTap: () => onOpen(index),
                    child: item.isVideo
                        ? _VideoPreview(url: item.url)
                        : Hero(
                            tag: 'post-media-${item.url}-$index',
                            child: CachedNetworkImage(
                              imageUrl: item.url,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => const _MediaLoading(),
                              errorWidget: (_, _, _) => const _MediaError(),
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
        ),
        if (items.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(items.length, (index) {
              final active = index == currentIndex;
              return AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active ? AppColors.vibeBlue : AppColors.glassBorder,
                  borderRadius: AppStyles.pillRadius,
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(gradient: AppStyles.brandGradient),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Center(
              child: Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 110),
            ),
            Center(
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white38),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
              ),
            ),
            const Positioned(
              left: 14,
              bottom: 12,
              child: _HeaderPill(icon: Icons.play_circle_outline, label: 'VIDEO'),
            ),
          ],
        ),
      );
}

class _MediaLoading extends StatelessWidget {
  const _MediaLoading();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: dark ? const Color(0xFF172944) : Colors.grey.shade300,
      highlightColor: dark ? const Color(0xFF29415F) : Colors.grey.shade100,
      child: Container(color: Colors.white),
    );
  }
}

class _MediaError extends StatelessWidget {
  const _MediaError();
  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.vibeBlue.withValues(alpha: 0.08),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 38),
            SizedBox(height: 8),
            Text('Media unavailable offline'),
          ],
        ),
      );
}

class _FullScreenGallery extends StatefulWidget {
  const _FullScreenGallery({required this.media, required this.initialIndex});
  final List<_MediaItem> media;
  final int initialIndex;

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xF2071323),
        appBar: AppBar(
          foregroundColor: Colors.white,
          title: Text('${_index + 1} of ${widget.media.length}'),
        ),
        body: PageView.builder(
          controller: _controller,
          itemCount: widget.media.length,
          onPageChanged: (index) => setState(() => _index = index),
          itemBuilder: (context, index) {
            final item = widget.media[index];
            if (item.isVideo) {
              return Center(
                child: FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(item.url);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play video'),
                ),
              );
            }
            return InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(
                child: Hero(
                  tag: 'post-media-${item.url}-$index',
                  child: CachedNetworkImage(
                    imageUrl: item.url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    errorWidget: (_, _, _) => const _MediaError(),
                  ),
                ),
              ),
            );
          },
        ),
      );
}

class _InteractionBar extends StatelessWidget {
  const _InteractionBar({
    required this.liked,
    required this.likeCount,
    required this.commentCount,
    required this.busy,
    required this.onLike,
    required this.onComment,
  });
  final bool liked;
  final int likeCount;
  final int commentCount;
  final bool busy;
  final VoidCallback onLike;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: AppColors.vibeBlue.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.vibeBlue.withValues(alpha: 0.09)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _InteractionButton(
                icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                label: 'Like',
                count: likeCount,
                active: liked,
                busy: busy,
                onTap: onLike,
              ),
            ),
            Container(width: 1, height: 28, color: AppColors.glassBorder),
            Expanded(
              child: _InteractionButton(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Comment',
                count: commentCount,
                onTap: onComment,
              ),
            ),
          ],
        ),
      );
}

class _InteractionButton extends StatelessWidget {
  const _InteractionButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
    this.active = false,
    this.busy = false,
  });
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;
  final bool active;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.danger : AppColors.vibeBlue;
    return Semantics(
      button: true,
      selected: active,
      label: '$label. $count',
      child: TextButton.icon(
        onPressed: busy ? null : onTap,
        icon: AnimatedSwitcher(
          duration: MediaQuery.maybeOf(context)?.disableAnimations == true
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: busy
              ? const SizedBox.square(
                  key: ValueKey('busy'),
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, key: ValueKey(active), color: color, size: 21),
        ),
        label: Text(
          '$label${count > 0 ? ' · $count' : ''}',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _CommentsPreview extends StatelessWidget {
  const _CommentsPreview({
    required this.comments,
    required this.loading,
    required this.total,
    required this.onOpen,
  });
  final List<_CommentPreview> comments;
  final bool loading;
  final int total;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Column(
        children: List.generate(
          2,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _CommentSkeleton(),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.vibeBlue.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        children: [
          for (final comment in comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.vibeBlue.withValues(alpha: 0.12),
                    backgroundImage: comment.photoUrl == null
                        ? null
                        : CachedNetworkImageProvider(comment.photoUrl!),
                    child: comment.photoUrl == null
                        ? Text(
                            comment.name[0].toUpperCase(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                          )
                        : null,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: RichText(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodySmall,
                        children: [
                          TextSpan(
                            text: '${comment.name}  ',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          TextSpan(text: comment.text),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (total > comments.length)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onOpen,
                child: Text('View all $total comments'),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentSkeleton extends StatelessWidget {
  const _CommentSkeleton();
  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Row(
          children: [
            const CircleAvatar(radius: 14, backgroundColor: Colors.white),
            const SizedBox(width: 9),
            Expanded(
              child: Container(
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      );
}

class _PollCard extends StatelessWidget {
  const _PollCard({
    required this.question,
    required this.options,
    required this.votes,
    required this.selectedOptionId,
    required this.onVote,
  });
  final String question;
  final List<_PollOption> options;
  final List<Map<String, dynamic>> votes;
  final String? selectedOptionId;
  final ValueChanged<_PollOption> onVote;

  @override
  Widget build(BuildContext context) {
    final total = votes.length;
    return Semantics(
      container: true,
      label: 'Poll. $question. $total votes.',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.vibeBlue.withValues(alpha: 0.10),
              AppColors.electricCyan.withValues(alpha: 0.07),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.vibeBlue.withValues(alpha: 0.13)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _HeaderPill(icon: Icons.poll_outlined, label: 'POLL'),
            const SizedBox(height: 10),
            Text(question, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final option in options) ...[
              _PollChoice(
                option: option,
                selected: option.id == selectedOptionId,
                votes: votes.where((row) => row['option_id']?.toString() == option.id).length,
                total: total,
                onTap: () => onVote(option),
              ),
              if (option != options.last) const SizedBox(height: 9),
            ],
            const SizedBox(height: 10),
            Text(
              '$total vote${total == 1 ? '' : 's'} · Results update live',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PollChoice extends StatelessWidget {
  const _PollChoice({
    required this.option,
    required this.selected,
    required this.votes,
    required this.total,
    required this.onTap,
  });
  final _PollOption option;
  final bool selected;
  final int votes;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : votes / total;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}, ${(progress * 100).round()} percent',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.vibeBlue.withValues(alpha: 0.10)
                : Theme.of(context).colorScheme.surface.withValues(alpha: 0.60),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? AppColors.vibeBlue : AppColors.glassBorder,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? AppColors.vibeBlue : AppColors.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(option.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Text('${(progress * 100).round()}%'),
                ],
              ),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
                builder: (_, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  borderRadius: AppStyles.pillRadius,
                  backgroundColor: AppColors.glassBorder,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PollSkeleton extends StatelessWidget {
  const _PollSkeleton();
  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Container(
          height: 130,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.vibeBlue.withValues(alpha: 0.10),
          borderRadius: AppStyles.pillRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.vibeBlue),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.vibeBlue,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      );
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label, this.danger = false});
  final IconData icon;
  final String label;
  final bool danger;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: danger ? AppColors.danger : null),
          const SizedBox(width: 11),
          Text(label, style: TextStyle(color: danger ? AppColors.danger : null)),
        ],
      );
}

class _MediaItem {
  const _MediaItem({required this.url, required this.isVideo});
  final String url;
  final bool isVideo;
}

class _PollOption {
  const _PollOption({required this.id, required this.label});
  factory _PollOption.fromRow(Map<String, dynamic> row) => _PollOption(
        id: row['id'].toString(),
        label: _string(row['label'], fallback: 'Option'),
      );
  final String id;
  final String label;
}

class _CommentPreview {
  const _CommentPreview({required this.name, required this.text, this.photoUrl});
  factory _CommentPreview.fromRow(Map<String, dynamic> row) {
    final profile = row['profiles'] is Map
        ? Map<String, dynamic>.from(row['profiles'] as Map)
        : <String, dynamic>{};
    final nickname = _string(profile['nickname']);
    final fullName = [
      _string(profile['name']),
      _string(profile['surname']),
    ].where((value) => value.isNotEmpty).join(' ');
    return _CommentPreview(
      name: nickname.isNotEmpty
          ? nickname
          : fullName.isNotEmpty
              ? fullName
              : 'Student',
      text: _string(row['text']),
      photoUrl: _nullableString(profile['photo_url']),
    );
  }
  final String name;
  final String text;
  final String? photoUrl;
}

enum _PostMenuAction { report, block, delete }

List<_MediaItem> _extractMedia(Map<String, dynamic> data) {
  final items = <_MediaItem>[];
  final seen = <String>{};
  void add(dynamic raw, bool video) {
    final url = _nullableString(raw);
    if (url != null && seen.add(url)) {
      items.add(_MediaItem(url: url, isVideo: video));
    }
  }

  final media = data['media'];
  if (media is List) {
    for (final raw in media) {
      if (raw is Map) {
        final item = Map<String, dynamic>.from(raw);
        final type = _string(item['type']).toLowerCase();
        add(item['url'], type == 'video');
      } else {
        add(raw, _looksLikeVideo(raw?.toString() ?? ''));
      }
    }
  }
  final images = data['images'];
  if (images is List) {
    for (final image in images) {
      add(image, false);
    }
  }
  final videos = data['videos'];
  if (videos is List) {
    for (final video in videos) {
      add(video, true);
    }
  }
  add(data['imageUrl'], false);
  add(data['videoUrl'], true);
  return items;
}

bool _looksLikeVideo(String url) => RegExp(
      r'\.(mp4|webm|mov|m4v)(\?|$)',
      caseSensitive: false,
    ).hasMatch(url);

String _authorName(Map<String, dynamic> data) {
  final profile = data['profiles'];
  if (profile is Map) {
    final nickname = _string(profile['nickname']);
    if (nickname.isNotEmpty) return nickname;
    final fullName = [
      _string(profile['name']),
      _string(profile['surname']),
    ].where((value) => value.isNotEmpty).join(' ');
    if (fullName.isNotEmpty) return fullName;
  }
  return _string(
    data['author_name'] ?? data['author'],
    fallback: 'OG Vibester',
  );
}

String? _authorPhoto(Map<String, dynamic> data) {
  final profile = data['profiles'];
  if (profile is Map) {
    final photo = _nullableString(profile['photo_url']);
    if (photo != null) return photo;
  }
  return _nullableString(data['author_photo'] ?? data['avatarUrl']);
}

String _formatTimestamp(dynamic value) {
  final date = value is DateTime
      ? value
      : DateTime.tryParse(value?.toString() ?? '');
  return date == null ? 'Moments ago' : timeago.format(date.toLocal());
}

String _string(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
