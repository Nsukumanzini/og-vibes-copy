// ignore_for_file: unused_element_parameter

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:og_vibes_student/screens/home/widgets/home_bottom_navigation_bar.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme_constants.dart';

import '../../widgets/app_drawer.dart';
import '../../widgets/post_card.dart';
import '../../widgets/vibe_scaffold.dart';
import '../../widgets/notification_bell_button.dart';
import 'announcements_screen.dart';
import 'create_post_screen.dart';
import 'events_screen.dart';
import 'lost_and_found_screen.dart';
import 'messages_screen.dart';
import 'document_wallet_redesign.dart';
import 'friend_requests_screen.dart';
import 'assignment_submission_screen.dart';
import 'assessments_calendar_screen.dart';
import 'portal_screen.dart';
import 'timetable_screen.dart';
import 'quiz_screen.dart';
import 'online_classes_screen.dart';
import 'icass_checker_screen.dart';
import 'past_question_papers_screen.dart';
import 'slides_screen.dart';
import 'career_screen.dart';
import 'market_screen.dart';
import 'accredited_accommodation_screen.dart';
import 'donation_screen.dart';
import 'cafeteria_screen.dart';
import 'src_voting_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  String _nickname = 'OG Vibester';
  String? _profilePhotoUrl;

  // Pagination & Scroll State
  late final ScrollController _scrollController;
  static const int _pageSize = 25;
  DateTime? _oldestPostCursor;
  bool _hasMorePosts = true;
  bool _isFetchingMore = false;
  bool _isFabVisible = true;
  bool _showBackToTopPill = false;
  bool _newPostsWaiting = false;

  bool _isLoadingPosts = true;
  List<Map<String, dynamic>> _posts = [];
  final Set<String> _seenPostIds = <String>{};
  String? _feedError;
  StreamSubscription<List<Map<String, dynamic>>>? _postSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _likesSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _commentsSubscription;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);
    _initialiseFeed();
  }

  Future<void> _initialiseFeed() async {
    await _loadSeenPosts();
    await _loadCachedPosts();
    if (mounted) setState(() => _isLoadingPosts = false);
  }

  String? get _feedCacheKey {
    return 'og_vibes_feed_cache_guest';
  }

  String get _seenPostsCacheKey => 'og_vibes_seen_posts_guest';

  Future<void> _loadSeenPosts() async {
    final preferences = await SharedPreferences.getInstance();
    _seenPostIds.addAll(
      preferences.getStringList(_seenPostsCacheKey) ?? const <String>[],
    );
  }

  List<Map<String, dynamic>> _personaliseFeed(
    Iterable<Map<String, dynamic>> posts,
  ) {
    final result = posts.map((post) {
      final id = post['id']?.toString();
      return <String, dynamic>{
        ...post,
        'is_unseen': id != null && !_seenPostIds.contains(id),
      };
    }).toList();
    result.sort((left, right) {
      final leftUnseen = left['is_unseen'] == true;
      final rightUnseen = right['is_unseen'] == true;
      if (leftUnseen != rightUnseen) return leftUnseen ? -1 : 1;
      final leftDate = DateTime.tryParse('${left['created_at']}');
      final rightDate = DateTime.tryParse('${right['created_at']}');
      return (rightDate ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        leftDate ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
    return result;
  }

  Future<void> _markPostSeen(String postId) async {
    if (postId.isEmpty || !_seenPostIds.add(postId)) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_seenPostsCacheKey, _seenPostIds.toList());
  }

  Future<void> _loadCachedPosts() async {
    final key = _feedCacheKey;
    if (key == null) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List || !mounted) return;
      final cached = _personaliseFeed(
        decoded
            .whereType<Map>()
            .map(
              (row) => <String, dynamic>{
                ...Map<String, dynamic>.from(row),
                'is_offline_cached': true,
              },
            )
            .toList(),
      );
      if (cached.isEmpty) return;
      setState(() {
        _posts = cached;
        _isLoadingPosts = false;
        _feedError = null;
      });
    } catch (error) {
      debugPrint('Feed cache read error: $error');
    }
  }

  Future<void> _cachePosts(List<Map<String, dynamic>> posts) async {
    final key = _feedCacheKey;
    if (key == null) return;
    try {
      final cleanRows = posts
          .take(50)
          .map(
            (row) =>
                Map<String, dynamic>.from(row)..remove('is_offline_cached'),
          )
          .toList();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(key, jsonEncode(cleanRows));
    } catch (error) {
      debugPrint('Feed cache write error: $error');
    }
  }

  Future<void> _loadPosts({bool reset = false, bool showLoading = true}) async {
    if (reset && showLoading && mounted) {
      setState(() {
        _isLoadingPosts = true;
        _feedError = null;
      });
    }
    await _loadCachedPosts();
    if (mounted) {
      setState(() {
        _isLoadingPosts = false;
        _hasMorePosts = false;
        _feedError = null;
      });
    }
  }

  @override
  void dispose() {
    _postSubscription?.cancel();
    _likesSubscription?.cancel();
    _commentsSubscription?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshFeed() async {
    await _loadPosts(reset: true);
  }

  Future<void> _handleScroll() async {
    if (!_scrollController.hasClients) return;

    // 1. Handle FAB and Back to Top Pill visibility
    final direction = _scrollController.position.userScrollDirection;
    if (direction == ScrollDirection.reverse && _isFabVisible) {
      setState(() => _isFabVisible = false);
    } else if (direction == ScrollDirection.forward && !_isFabVisible) {
      setState(() => _isFabVisible = true);
    }

    final shouldShowPill = _scrollController.offset > 300;
    if (shouldShowPill != _showBackToTopPill) {
      setState(() => _showBackToTopPill = shouldShowPill);
    }

    // 2. Handle Pagination (Load more when reaching the bottom)
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isFetchingMore &&
        _hasMorePosts) {
      setState(() => _isFetchingMore = true);
      await _loadPosts();
      if (!mounted) return;
      setState(() => _isFetchingMore = false);
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _showLatestPosts() async {
    await _loadPosts(reset: true, showLoading: false);
    if (!mounted || !_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  String _getDynamicGreeting() {
    return 'Sawubona $_nickname';
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      drawer: const AppDrawer(),
      floatingActionButton: _currentTab == 0 ? _buildPostFab() : null,
      bottomNavigationBar: HomeBottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) {
          setState(() => _currentTab = index);
        },
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _currentTab,
            children: [
              _buildFeedTab(),
              _buildStudyHubTab(),
              const AnnouncementsScreen(),
              _buildStudyTab(),
              const MessagesScreen(),
            ],
          ),
        ],
      ),
    );
  }

  // ================= FEED TAB =================
  Widget _buildFeedTab() {
    return Stack(
      fit: StackFit.expand,
      children: [
        RefreshIndicator(
          color: Theme.of(context).primaryColor,
          backgroundColor: Colors.white,
          onRefresh: _refreshFeed,
          child: AnimationLimiter(
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                _buildFeedSliverAppBar(),
                _buildComposerSliver(),
                if (_isLoadingPosts)
                  _buildLoadingSliver()
                else if (_feedError != null)
                  _buildErrorSliver(_feedError)
                else if (_posts.isEmpty)
                  _buildEmptyStateSliver()
                else
                  _buildPostsSliver(_posts),
                if (_isFetchingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        ),
        Positioned(
          top: 20,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedOpacity(
              opacity: _showBackToTopPill ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: !_showBackToTopPill,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_upward, size: 16),
                  label: const Text('Back to Top'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    foregroundColor: Theme.of(context).primaryColor,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _scrollToTop,
                ),
              ),
            ),
          ),
        ),
        if (_newPostsWaiting)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.icon(
                onPressed: _showLatestPosts,
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                label: const Text('See new posts'),
              ),
            ),
          ),
      ],
    );
  }

  SliverToBoxAdapter _buildFeedSliverAppBar() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 12, 8),
        child: Row(
          children: [
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Open menu',
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            const SizedBox(width: 4),
            Image.asset(
              'assets/images/logo_transparent.png',
              height: 40,
              width: 40,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _getDynamicGreeting(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const NotificationBellButton(),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildComposerSliver() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _openCreatePost,
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.blueTint,
                    foregroundColor: AppColors.vibeBlue,
                    backgroundImage: _profilePhotoUrl == null
                        ? null
                        : NetworkImage(_profilePhotoUrl!),
                    child: _profilePhotoUrl == null
                        ? Text(
                            _nickname.trim().isEmpty
                                ? 'O'
                                : _nickname.trim()[0].toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          )
                        : null,
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Text(
                      'Share something with campus…',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Create a post',
                    onPressed: _openCreatePost,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCreatePost() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const CreatePostScreen()));
    if (result == true) await _refreshFeed();
  }

  // ================= STUDY HUB TAB =================
  Widget _buildStudyHubTab() {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 100.0,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          actions: const [NotificationBellButton(), SizedBox(width: 12)],
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
            title: Text(
              'Academics',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Your study tools'),
                _buildHubGrid(_getStudyHubCards()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudyTab() {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 100.0,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          actions: const [NotificationBellButton(), SizedBox(width: 12)],
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
            title: Text(
              'Campus',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Campus life'),
                _buildHubGrid(_getStudyTabCards()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildHubGrid(List<_HubCardInfo> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 2;
        final tileWidth =
            (constraints.maxWidth - ((columns - 1) * 12)) / columns;
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1.0, 1.6);
        final tileHeight = 146.0 + ((textScale - 1) * 42);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: tileWidth / tileHeight,
          ),
          itemBuilder: (context, index) {
            final card = cards[index];

            return Semantics(
              button: true,
              label: 'Open ${card.title}',
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.glassBorder),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.deepBlue.withValues(alpha: .07),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: InkWell(
                    onTap: () => card.onTap(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.blueTint,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              card.icon,
                              color: AppColors.vibeBlue,
                              size: 22,
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Text(
                                  card.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.midnightInk,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    height: 1.18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_outward_rounded,
                                color: AppColors.vibeBlue,
                                size: 20,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<_HubCardInfo> _getStudyHubCards() {
    return [
      _HubCardInfo(
        title: 'Past question papers',
        icon: Icons.history_edu_rounded,
        onTap: (context) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PastQuestionPapersScreen()),
        ),
      ),
      _HubCardInfo(
        title: 'Lecture slides',
        icon: Icons.co_present_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SlidesScreen())),
      ),
      _HubCardInfo(
        title: 'Class timetable',
        icon: Icons.event_note_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TimetableScreen())),
      ),
      _HubCardInfo(
        title: 'Online classes',
        icon: Icons.cast_for_education_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OnlineClassesScreen())),
      ),
      _HubCardInfo(
        title: 'Student portal',
        icon: Icons.language_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PortalScreen())),
      ),
      _HubCardInfo(
        title: 'Assessment submissions',
        icon: Icons.cloud_upload_rounded,
        onTap: (context) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AssignmentSubmissionScreen()),
        ),
      ),
      _HubCardInfo(
        title: 'Assessment schedule',
        icon: Icons.calendar_month_rounded,
        onTap: (context) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AssessmentsCalendarScreen()),
        ),
      ),
      _HubCardInfo(
        title: 'Quizzes',
        icon: Icons.quiz_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const QuizScreen())),
      ),
      _HubCardInfo(
        title: 'ICASS results',
        icon: Icons.bar_chart_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const IcassCheckerScreen())),
      ),
    ];
  }

  List<_HubCardInfo> _getStudyTabCards() {
    return [
      _HubCardInfo(
        title: 'Cafeteria',
        icon: Icons.restaurant_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CafeteriaScreen())),
      ),
      _HubCardInfo(
        title: 'SRC election',
        icon: Icons.how_to_vote_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SrcVotingScreen())),
      ),
      _HubCardInfo(
        title: 'Campus events',
        icon: Icons.event,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const EventsScreen())),
      ),
      _HubCardInfo(
        title: 'Lost and found',
        icon: Icons.search_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LostAndFoundScreen())),
      ),
      _HubCardInfo(
        title: 'Find friends',
        icon: Icons.person_search_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const FriendRequestsScreen())),
      ),
      _HubCardInfo(
        title: 'Student marketplace',
        icon: Icons.storefront_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MarketScreen())),
      ),
      _HubCardInfo(
        title: 'Student accommodation',
        icon: Icons.home_work_outlined,
        onTap: (context) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AccreditedAccommodationScreen(),
          ),
        ),
      ),
      _HubCardInfo(
        title: 'Donations',
        icon: Icons.volunteer_activism_outlined,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DonationScreen())),
      ),
      _HubCardInfo(
        title: 'Document wallet',
        icon: Icons.folder_special_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DocumentWalletScreen())),
      ),
      _HubCardInfo(
        title: 'Careers and funding',
        icon: Icons.trending_up_rounded,
        onTap: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CareerScreen())),
      ),
    ];
  }

  // ================= FEED HELPERS & BUILDERS =================
  SliverList _buildPostsSliver(List<Map<String, dynamic>> posts) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        return AnimationConfiguration.staggeredList(
          position: index,
          duration: const Duration(milliseconds: 375),
          child: SlideAnimation(
            verticalOffset: 50,
            child: FadeInAnimation(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: _PostSeenImpression(
                  onSeen: () => unawaited(
                    _markPostSeen(posts[index]['id']?.toString() ?? ''),
                  ),
                  child: PostCard(data: posts[index]),
                ),
              ),
            ),
          ),
        );
      }, childCount: posts.length),
    );
  }

  SliverFillRemaining _buildEmptyStateSliver() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.campaign_outlined,
                size: 64,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Campus is quiet...',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 22,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Be the first to post a vibe today!',
              style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Post a Vibe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                );
                if (result == true) {
                  await _refreshFeed();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  SliverList _buildLoadingSliver() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildShimmerFeedCard(),
        childCount: 3,
      ),
    );
  }

  Widget _buildShimmerFeedCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 250,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }

  SliverFillRemaining _buildErrorSliver(Object? error) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: AppColors.danger),
            const SizedBox(height: 16),
            const Text(
              'Could not connect to server',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: _refreshFeed,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostFab() {
    return AnimatedScale(
      duration: const Duration(milliseconds: 200),
      scale: _isFabVisible ? 1.0 : 0.0,
      child: FloatingActionButton.extended(
        elevation: 6,
        backgroundColor: Theme.of(context).primaryColor,
        onPressed: _openCreatePost,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Create post',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _HubCardInfo {
  const _HubCardInfo({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final void Function(BuildContext context) onTap;
}

class _PostSeenImpression extends SingleChildRenderObjectWidget {
  const _PostSeenImpression({required this.onSeen, required super.child});

  final VoidCallback onSeen;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PostSeenRenderObject(onSeen);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _PostSeenRenderObject renderObject,
  ) {
    renderObject.onSeen = onSeen;
  }
}

class _PostSeenRenderObject extends RenderProxyBox {
  _PostSeenRenderObject(this._onSeen);

  VoidCallback _onSeen;
  Timer? _timer;
  bool _reported = false;

  set onSeen(VoidCallback value) => _onSeen = value;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_reported || _timer != null || !attached) return;
    _timer = Timer(const Duration(milliseconds: 700), () {
      _timer = null;
      if (_reported || !attached || !hasSize) return;
      final view = PlatformDispatcher.instance.views.first;
      final viewport =
          Offset.zero &
          Size(
            view.physicalSize.width / view.devicePixelRatio,
            view.physicalSize.height / view.devicePixelRatio,
          );
      final bounds = localToGlobal(Offset.zero) & size;
      if (!bounds.overlaps(viewport)) return;
      _reported = true;
      _onSeen();
    });
  }

  @override
  void detach() {
    _timer?.cancel();
    _timer = null;
    super.detach();
  }
}
