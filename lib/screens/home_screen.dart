// ignore_for_file: unused_element_parameter

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:og_vibes_student/screens/home/widgets/home_bottom_navigation_bar.dart';
import 'package:shimmer/shimmer.dart';

import '../../widgets/app_drawer.dart';
import '../../widgets/post_card.dart';
import '../../widgets/vibe_scaffold.dart';
import 'announcements_screen.dart';
import 'create_post_screen.dart';
import 'events_screen.dart';
import 'lost_and_found_screen.dart';
import 'messages_screen.dart';
import 'document_wallet_screen.dart';
import 'my_campus_friends_screen.dart';
import 'assignment_submission_screen.dart';
import 'assessments_calendar_screen.dart';
import 'portal_screen.dart';
import 'timetable_screen.dart';
import 'trivia_game_screen.dart';
import 'online_classes_screen.dart';
import 'group_chats_screen.dart';
import 'icass_checker_screen.dart';
import 'past_question_papers_screen.dart';
import 'slides_screen.dart';
import 'career_screen.dart';
import 'market_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;

  // Pagination & Scroll State
  late final ScrollController _scrollController;
  int _postLimit = 10; // Start with only 10 posts
  bool _isFetchingMore = false;
  bool _isFabVisible = true;
  bool _showBackToTopPill = false;

  bool _isLoadingPosts = true;
  List<Map<String, dynamic>> _posts = [];
  StreamSubscription<List<Map<String, dynamic>>>? _postSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _likesSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _commentsSubscription;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);
    _loadPosts();
    _listenForPosts();
  }

  Future<void> _loadPosts({bool reset = false}) async {
    if (reset) {
      _postLimit = 10;
      setState(() {
        _isLoadingPosts = true;
      });
    }

    try {
      final data = await Supabase.instance.client
          .from('posts')
          .select('*, profiles(name, surname, nickname, photo_url, campus, department), comments(id)')
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .limit(_postLimit);

      if (!mounted) return;

      setState(() {
        _posts = List<Map<String, dynamic>>.from(data as List<dynamic>? ?? []);
        _isLoadingPosts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPosts = false;
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

  void _listenForPosts() {
    _postSubscription = Supabase.instance.client
        .from('posts')
        .stream(primaryKey: ['id'])
        .listen((_) {
      if (!mounted) return;
      _loadPosts();
    }, onError: (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingPosts = false;
      });
    });

    _likesSubscription = Supabase.instance.client
        .from('post_likes')
        .stream(primaryKey: ['id'])
        .listen((_) {
      if (!mounted) return;
      _loadPosts();
    });

    _commentsSubscription = Supabase.instance.client
        .from('comments')
        .stream(primaryKey: ['id'])
        .listen((_) {
      if (!mounted) return;
      _loadPosts();
    });
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
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_isFetchingMore) {
      setState(() => _isFetchingMore = true);
      _postLimit += 10;
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

  String _getDynamicGreeting() {
    final hour = DateTime.now().hour;
    final user = Supabase.instance.client.auth.currentUser;
    final name = user?.userMetadata?['name']?.toString().split(' ').first ??
        user?.email?.split('@').first ??
        'Viber';
    if (hour < 12) return 'Good morning, $name ☀️';
    if (hour < 17) return 'Good afternoon, $name 🌤️';
    return 'Good evening, $name 🌙';
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
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                _buildFeedSliverAppBar(),
                if (_isLoadingPosts)
                  _buildLoadingSliver()
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: _scrollToTop,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  SliverToBoxAdapter _buildFeedSliverAppBar() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 36, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Builder(
                  builder: (context) => IconButton(
                    icon: Icon(Icons.menu, color: Theme.of(context).colorScheme.onSurface),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Center(child: Image.asset('assets/images/logo.jpeg', height: 40)),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _getDynamicGreeting(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'See what is happening on campus right now.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
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
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
            title: Text(
              'Study Hub',
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
                Text(
                  'Core study tools for your MVP experience',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 24),

                _buildSectionHeader('Study Hub'),
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
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
            title: Text(
              'Campus Life',
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
                Text(
                  'Campus Life features for student services and campus essentials.',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('Campus Services'),
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.3,
      ),
      itemBuilder: (context, index) {
        final card = cards[index];
        final gradientColors = card.gradientColors?.map((color) => color.withOpacity(0.9)).toList();

        return Card(
          elevation: 4,
          shadowColor: card.color.withOpacity(0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => card.onTap(context),
            child: Container(
              decoration: BoxDecoration(
                gradient: gradientColors != null
                    ? LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : null,
                color: gradientColors == null ? Colors.white : null,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: gradientColors != null ? Colors.white.withOpacity(0.2) : card.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(card.icon, color: gradientColors != null ? Colors.white : card.color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      card.title,
                      maxLines: 2,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: gradientColors != null ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<_HubCardInfo> _getStudyHubCards() {
    return [
      _HubCardInfo(
        title: 'Past Question Papers',
        icon: Icons.picture_as_pdf,
        color: Colors.indigo,
        gradientColors: const [Color(0xFF3F51B5), Color(0xFF5C6BC0)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PastQuestionPapersScreen())),
      ),
      _HubCardInfo(
        title: 'Lecture Slides',
        icon: Icons.slideshow,
        color: Colors.deepPurple,
        gradientColors: const [Color(0xFF4527A0), Color(0xFF7E57C2)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SlidesScreen())),
      ),
      _HubCardInfo(
        title: 'Timetable',
        icon: Icons.event_note_rounded,
        color: Colors.deepPurpleAccent,
        gradientColors: const [Color(0xFF3949AB), Color(0xFF5C6BC0)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TimetableScreen())),
      ),
      _HubCardInfo(
        title: 'Online Classes',
        icon: Icons.cast_for_education_rounded,
        color: Colors.blueAccent,
        gradientColors: const [Color(0xFF039BE5), Color(0xFF29B6F6)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnlineClassesScreen())),
      ),
      _HubCardInfo(
        title: 'Portal',
        icon: Icons.language_rounded,
        color: Colors.green,
        gradientColors: const [Color(0xFF2E7D32), Color(0xFF43A047)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PortalScreen())),
      ),
      _HubCardInfo(
        title: 'Assessment Submission',
        icon: Icons.upload_file,
        color: Colors.orange,
        gradientColors: const [Color(0xFFF57C00), Color(0xFFFFB300)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AssignmentSubmissionScreen())),
      ),
      _HubCardInfo(
        title: 'Assessment Schedule',
        icon: Icons.calendar_month_rounded,
        color: Colors.pink,
        gradientColors: const [Color(0xFFD81B60), Color(0xFFE91E63)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AssessmentsCalendarScreen())),
      ),
      _HubCardInfo(
        title: 'Quiz',
        icon: Icons.quiz_rounded,
        color: Colors.redAccent,
        gradientColors: const [Color(0xFFC62828), Color(0xFFD32F2F)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TriviaGameScreen())),
      ),
      _HubCardInfo(
        title: 'Group Chats',
        icon: Icons.chat,
        color: Colors.cyan,
        gradientColors: const [Color(0xFF00838F), Color(0xFF26C6DA)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GroupChatsScreen())),
      ),
      _HubCardInfo(
        title: 'ICASS Marks',
        icon: Icons.bar_chart_rounded,
        color: Colors.amber,
        gradientColors: const [Color(0xFFF57F17), Color(0xFFFBC02D)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IcassCheckerScreen())),
      ),
    ];
  }

  List<_HubCardInfo> _getStudyTabCards() {
    return [
      _HubCardInfo(
        title: 'Events',
        icon: Icons.event,
        color: Colors.pinkAccent,
        gradientColors: const [Color(0xFFE91E63), Color(0xFFF06292)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventsScreen())),
      ),
      _HubCardInfo(
        title: 'Lost & Found',
        icon: Icons.search_rounded,
        color: Colors.brown,
        gradientColors: const [Color(0xFF6D4C41), Color(0xFF8D6E63)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LostAndFoundScreen())),
      ),
      _HubCardInfo(
        title: 'Find Friends',
        icon: Icons.person_search_rounded,
        color: Colors.deepPurpleAccent,
        gradientColors: const [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyCampusFriendsScreen())),
      ),
      _HubCardInfo(
        title: 'Marketplace',
        icon: Icons.storefront_rounded,
        color: Colors.indigo,
        gradientColors: const [Color(0xFF3949AB), Color(0xFF5C6BC0)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MarketScreen())),
      ),
      _HubCardInfo(
        title: 'Document Wallet',
        icon: Icons.badge,
        color: Colors.blueGrey,
        gradientColors: const [Color(0xFF37474F), Color(0xFF546E7A)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DocumentWalletScreen())),
      ),
      _HubCardInfo(
        title: 'Career & Funding',
        icon: Icons.trending_up_rounded,
        color: Colors.teal,
        gradientColors: const [Color(0xFF00695C), Color(0xFF00897B)],
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CareerScreen())),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: PostCard(data: posts[index]),
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
              child: Icon(Icons.campaign_outlined, size: 64, color: Theme.of(context).primaryColor),
            ),
            const SizedBox(height: 24),
            Text('Campus is quiet...', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),
            const Text('Be the first to post a vibe today!', style: TextStyle(color: Colors.black54, fontSize: 16)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Post a Vibe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
      delegate: SliverChildBuilderDelegate((context, index) => _buildShimmerFeedCard(), childCount: 3),
    );
  }

  Widget _buildShimmerFeedCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 250,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
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
            const Icon(Icons.wifi_off, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text('Could not connect to server', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: Colors.redAccent)),
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
        onPressed: () async {
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const CreatePostScreen()),
          );
          if (result == true) {
            await _refreshFeed();
          }
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Post Vibe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

}

class _HubCardInfo {
  const _HubCardInfo({
    required this.title,
    required this.icon,
    required this.color,
    this.gradientColors,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Color>? gradientColors;
  final void Function(BuildContext context) onTap;
}    