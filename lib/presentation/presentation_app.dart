import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../utils/theme_constants.dart';

class PresentationApp extends StatefulWidget {
  const PresentationApp({super.key});

  @override
  State<PresentationApp> createState() => _PresentationAppState();
}

class _PresentationAppState extends State<PresentationApp> {
  int _selectedPage = 0;
  final Set<int> _likedPosts = <int>{};
  final Set<int> _goingToEvents = <int>{};
  final List<_DemoPost> _posts = <_DemoPost>[
    const _DemoPost(
      author: 'Maya Dlamini',
      initials: 'MD',
      campus: 'Braamfontein Campus',
      time: '12 min ago',
      text:
          'Found the perfect quiet corner for exam prep. The new study lounge is a whole mood 📚',
      tag: 'Campus life',
      likes: 28,
      color: Color(0xFF7957E8),
    ),
    const _DemoPost(
      author: 'Siyabonga Ndlovu',
      initials: 'SN',
      campus: 'Braamfontein Campus',
      time: '38 min ago',
      text: 'Anyone keen for a coffee run after the 2pm lecture? ☕',
      tag: 'Community',
      likes: 14,
      color: Color(0xFF138B91),
    ),
    const _DemoPost(
      author: 'Lerato Molefe',
      initials: 'LM',
      campus: 'Braamfontein Campus',
      time: '1 hr ago',
      text:
          'Our group project finally came together. Shoutout to the team for showing up for each other ✨',
      tag: 'Wins',
      likes: 46,
      color: Color(0xFFE36D4F),
    ),
  ];

  static const List<_DemoEvent> _events = <_DemoEvent>[
    _DemoEvent(
      title: 'Creative Campus Mixer',
      category: 'COMMUNITY',
      date: 'THU, 4:30 PM',
      place: 'Student Union Courtyard',
      color: Color(0xFF5540C9),
      icon: Icons.auto_awesome_rounded,
    ),
    _DemoEvent(
      title: 'Study Sprint: Finals Edition',
      category: 'STUDY GROUP',
      date: 'FRI, 10:00 AM',
      place: 'Library, Level 2',
      color: Color(0xFF087F83),
      icon: Icons.bolt_rounded,
    ),
    _DemoEvent(
      title: 'Market Day Pop-Up',
      category: 'CAMPUS MARKET',
      date: 'SAT, 11:00 AM',
      place: 'Main Quad',
      color: Color(0xFFB55C25),
      icon: Icons.storefront_rounded,
    ),
  ];

  static const List<_DemoMessage> _messages = <_DemoMessage>[
    _DemoMessage(
      'Thandi M.',
      'Are we still meeting in the library?',
      '2 min',
      'TM',
      Color(0xFFCA5C83),
      2,
    ),
    _DemoMessage(
      'Study Group · BIO 204',
      'Lerato: I added the notes from today',
      '18 min',
      'SG',
      Color(0xFF4F64D8),
      4,
    ),
    _DemoMessage(
      'Campus Creatives',
      'Maya: See you all at the mixer ✨',
      '1 hr',
      'CC',
      Color(0xFF138B91),
      0,
    ),
  ];

  static const List<_NavItem> _navItems = <_NavItem>[
    _NavItem('Overview', Icons.dashboard_rounded),
    _NavItem('Vibe Feed', Icons.dynamic_feed_rounded),
    _NavItem('Study Hub', Icons.school_rounded),
    _NavItem('Events', Icons.event_rounded),
    _NavItem('Marketplace', Icons.storefront_rounded),
    _NavItem('Messages', Icons.chat_bubble_rounded),
  ];

  void _showNotice(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.auto_awesome_rounded, color: AppColors.vibeBlue),
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _createPost() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share a campus moment'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'What is happening on campus?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _posts.insert(
        0,
        _DemoPost(
          author: 'Alex Morgan',
          initials: 'AM',
          campus: 'Braamfontein Campus',
          time: 'Just now · Demo',
          text: text,
          tag: 'Your post',
          likes: 0,
          color: AppColors.vibeBlue,
        ),
      );
      _selectedPage = 1;
    });
    _showNotice(
      'Post added',
      'Your demo post is saved in this presentation session only.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OG Vibes · Presentation',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 920;
          return Scaffold(
            backgroundColor: AppColors.auroraCanvas,
            body: SafeArea(
              child: Row(
                children: <Widget>[
                  if (wide) _sideRail(constraints.maxHeight),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _topBar(wide: wide),
                        Expanded(child: _pageBody(wide: wide)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: wide ? null : _bottomBar(),
            floatingActionButton: _selectedPage == 1
                ? FloatingActionButton.extended(
                    onPressed: _createPost,
                    backgroundColor: AppColors.vibeBlue,
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create post'),
                  )
                : null,
          );
        },
      ),
    );
  }

  Widget _sideRail(double height) => Container(
    width: 252,
    height: height,
    padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: Color(0xFFE7ECF5))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _brand(),
        const SizedBox(height: 34),
        const _SectionLabel('CAMPUS SPACE'),
        const SizedBox(height: 12),
        ...List<Widget>.generate(_navItems.length, (index) => _railItem(index)),
        const Spacer(),
        _railDemoNote(),
      ],
    ),
  );

  Widget _brand() => Row(
    children: <Widget>[
      ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.asset(
          'assets/images/logo_transparent.png',
          width: 42,
          height: 42,
          fit: BoxFit.cover,
        ),
      ),
      const SizedBox(width: 11),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'OG VIBES',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: AppColors.midnightInk,
            ),
          ),
          Text(
            'STUDENT COMMUNITY',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.05,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _railItem(int index) {
    final selected = _selectedPage == index;
    final item = _navItems[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _selectedPage = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.blueTint : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                item.icon,
                size: 20,
                color: selected ? AppColors.vibeBlue : AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? AppColors.vibeBlue
                        : AppColors.midnightInk,
                  ),
                ),
              ),
              if (index == 5) const _CountDot('3'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _railDemoNote() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.wifi_off_rounded, color: AppColors.success, size: 18),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            'Presentation mode\nLocal demo content · no accounts or live services',
            style: TextStyle(
              fontSize: 10,
              height: 1.5,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _topBar({required bool wide}) => Container(
    height: 72,
    padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE7ECF5))),
    ),
    child: Row(
      children: <Widget>[
        if (!wide) ...<Widget>[_brand(), const Spacer()],
        if (wide) Expanded(child: _searchBox()),
        if (!wide)
          IconButton(
            onPressed: _showNotifications,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        if (wide) ...<Widget>[
          const SizedBox(width: 14),
          IconButton(
            onPressed: _showNotifications,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
        const SizedBox(width: 8),
        const CircleAvatar(
          radius: 18,
          backgroundColor: Color(0xFFE4ECFF),
          child: Text(
            'AM',
            style: TextStyle(
              color: AppColors.vibeBlue,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (wide) ...<Widget>[
          const SizedBox(width: 10),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Alex Morgan',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              Text(
                'Student · Demo account',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _searchBox() => Container(
    constraints: const BoxConstraints(maxWidth: 480),
    height: 42,
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(14),
    ),
    child: TextField(
      onSubmitted: (_) => _showNotice(
        'Demo search',
        'Search is shown as a presentation preview. No data is sent anywhere.',
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        hintText: 'Search campus, people, events…',
        prefixIcon: Icon(Icons.search_rounded),
        contentPadding: EdgeInsets.symmetric(vertical: 10),
      ),
    ),
  );

  Widget _bottomBar() => NavigationBar(
    selectedIndex: _selectedPage > 4 ? 0 : _selectedPage,
    onDestinationSelected: (index) => setState(() => _selectedPage = index),
    destinations: const <NavigationDestination>[
      NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: 'Home'),
      NavigationDestination(
        icon: Icon(Icons.dynamic_feed_rounded),
        label: 'Feed',
      ),
      NavigationDestination(icon: Icon(Icons.school_rounded), label: 'Study'),
      NavigationDestination(icon: Icon(Icons.event_rounded), label: 'Events'),
      NavigationDestination(icon: Icon(Icons.menu_rounded), label: 'More'),
    ],
  );

  Widget _pageBody({required bool wide}) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(wide ? 34 : 18, 25, wide ? 34 : 18, 34),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1260),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _pageHeading(),
              const SizedBox(height: 22),
              if (_selectedPage == 0) _overview(wide: wide),
              if (_selectedPage == 1) _feedPage(wide: wide),
              if (_selectedPage == 2) _studyPage(wide: wide),
              if (_selectedPage == 3) _eventsPage(wide: wide),
              if (_selectedPage == 4) _marketPage(wide: wide),
              if (_selectedPage == 5) _messagesPage(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageHeading() {
    final title = _selectedPage == 0
        ? 'Your campus, together.'
        : _navItems[_selectedPage].label;
    final subtitle = _selectedPage == 0
        ? 'Good morning, Alex. Here’s what’s happening around you.'
        : 'A connected campus experience, ready to explore.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _demoBadge(),
              const SizedBox(height: 11),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 29,
                  height: 1.16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.1,
                  color: AppColors.midnightInk,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (_selectedPage == 0)
          FilledButton.icon(
            onPressed: _createPost,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Share a moment'),
          ),
      ],
    );
  }

  Widget _demoBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.successSurface,
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.circle, size: 7, color: AppColors.success),
        SizedBox(width: 7),
        Text(
          'PRESENTATION MODE · SAMPLE CONTENT',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: .9,
            color: AppColors.success,
          ),
        ),
      ],
    ),
  );

  Widget _overview({required bool wide}) => Column(
    children: <Widget>[
      _heroCard(wide: wide),
      const SizedBox(height: 18),
      _statsRow(wide),
      const SizedBox(height: 26),
      _sectionHeader(
        'Your campus pulse',
        action: 'See all',
        onAction: () => setState(() => _selectedPage = 1),
      ),
      const SizedBox(height: 13),
      _twoColumn(
        wide,
        left: Column(
          children: <Widget>[
            ..._posts
                .take(2)
                .toList()
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 13),
                    child: _postCard(entry.key, entry.value),
                  ),
                ),
          ],
        ),
        right: _upcomingCard(),
      ),
      const SizedBox(height: 24),
      _sectionHeader(
        'Explore OG Vibes',
        action: 'Browse spaces',
        onAction: () => setState(() => _selectedPage = 2),
      ),
      const SizedBox(height: 13),
      _featureGrid(wide),
    ],
  );

  Widget _heroCard({required bool wide}) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(wide ? 30 : 21),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(
        colors: <Color>[
          Color(0xFF07172F),
          Color(0xFF123F9F),
          Color(0xFF286CF6),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: AppColors.vibeBlue.withValues(alpha: .2),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: Stack(
      children: <Widget>[
        Positioned(
          right: 4,
          top: -35,
          child: Icon(
            Icons.blur_circular_rounded,
            size: wide ? 230 : 150,
            color: Colors.white.withValues(alpha: .055),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 760 : 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'THE STUDENT COMMUNITY APP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Text(
                'Make campus feel\na little more connected.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: wide ? 30 : 24,
                  height: 1.13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 11),
              const Text(
                'Find your people, stay on top of student life, and make the most of every day on campus.',
                style: TextStyle(
                  color: Color(0xFFDCE8FF),
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 9,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () => setState(() => _selectedPage = 1),
                    icon: const Icon(Icons.explore_rounded, size: 17),
                    label: const Text('Explore the feed'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.deepBlue,
                      minimumSize: const Size(44, 42),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _selectedPage = 3),
                    icon: const Icon(Icons.event_available_rounded, size: 17),
                    label: const Text('Find an event'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: .5),
                      ),
                      minimumSize: const Size(44, 42),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _statsRow(bool wide) {
    final items = <_StatData>[
      const _StatData(
        '12.4k',
        'students connected',
        Icons.people_alt_rounded,
        Color(0xFF2457F5),
      ),
      const _StatData(
        '34',
        'campus events',
        Icons.event_available_rounded,
        Color(0xFFE87935),
      ),
      const _StatData(
        '128',
        'active study groups',
        Icons.groups_rounded,
        Color(0xFF138B91),
      ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items
          .map(
            (item) => SizedBox(width: wide ? 230 : 155, child: _statCard(item)),
          )
          .toList(),
    );
  }

  Widget _statCard(_StatData item) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.glassBorder),
    ),
    child: Row(
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(item.icon, color: item.color, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.midnightInk,
                ),
              ),
              Text(
                item.label,
                style: const TextStyle(
                  fontSize: 9,
                  height: 1.3,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _sectionHeader(
    String title, {
    String? action,
    VoidCallback? onAction,
  }) => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: -.3,
            color: AppColors.midnightInk,
          ),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onAction,
          child: Text(
            action,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
    ],
  );

  Widget _twoColumn(bool wide, {required Widget left, required Widget right}) =>
      wide
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 7, child: left),
            const SizedBox(width: 18),
            Expanded(flex: 4, child: right),
          ],
        )
      : Column(children: <Widget>[left, right]);

  Widget _postCard(int index, _DemoPost post) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.glassBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _avatar(post.initials, post.color, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    post.author,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.midnightInk,
                    ),
                  ),
                  Text(
                    '${post.campus} · ${post.time}',
                    style: const TextStyle(
                      fontSize: 8,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            _tag(post.tag),
            IconButton(
              onPressed: () => _showNotice(
                'More options',
                'Post options are shown for the demo only.',
              ),
              icon: const Icon(Icons.more_horiz_rounded),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          post.text,
          style: const TextStyle(
            fontSize: 11,
            height: 1.6,
            color: Color(0xFF35445B),
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 7),
        Row(
          children: <Widget>[
            _actionButton(
              _likedPosts.contains(index)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              '${post.likes + (_likedPosts.contains(index) ? 1 : 0)}',
              color: _likedPosts.contains(index)
                  ? AppColors.danger
                  : AppColors.textMuted,
              onTap: () => setState(
                () => _likedPosts.contains(index)
                    ? _likedPosts.remove(index)
                    : _likedPosts.add(index),
              ),
            ),
            const SizedBox(width: 16),
            _actionButton(
              Icons.chat_bubble_outline_rounded,
              'Comment',
              onTap: () => _showNotice(
                'Comments',
                'Comments are local demo interactions in presentation mode.',
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => _showNotice(
                'Saved',
                'This demo keeps everything on this device only.',
              ),
              icon: const Icon(
                Icons.bookmark_border_rounded,
                size: 19,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _upcomingCard() => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.glassBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Coming up on campus',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
            Icon(
              Icons.calendar_month_rounded,
              color: AppColors.vibeBlue,
              size: 18,
            ),
          ],
        ),
        const SizedBox(height: 15),
        ...List<Widget>.generate(
          _events.length,
          (index) => Padding(
            padding: EdgeInsets.only(
              bottom: index == _events.length - 1 ? 0 : 12,
            ),
            child: _eventLine(index),
          ),
        ),
      ],
    ),
  );

  Widget _eventLine(int index) {
    final event = _events[index];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 38,
          height: 42,
          decoration: BoxDecoration(
            color: event.color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(event.icon, color: event.color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                event.date,
                style: TextStyle(
                  fontSize: 7,
                  letterSpacing: .7,
                  fontWeight: FontWeight.w800,
                  color: event.color,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                event.title,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.midnightInk,
                ),
              ),
              Text(
                event.place,
                style: const TextStyle(fontSize: 8, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _featureGrid(bool wide) {
    final features = <_FeatureData>[
      const _FeatureData(
        'Find your people',
        'Build your campus circle',
        Icons.diversity_3_rounded,
        Color(0xFF6C53D5),
        1,
      ),
      const _FeatureData(
        'Study together',
        'Groups, notes and support',
        Icons.menu_book_rounded,
        Color(0xFF138B91),
        2,
      ),
      const _FeatureData(
        'Campus events',
        'See what’s happening',
        Icons.celebration_rounded,
        Color(0xFFE87935),
        3,
      ),
      const _FeatureData(
        'Student market',
        'Discover student finds',
        Icons.storefront_rounded,
        Color(0xFFCE5E83),
        4,
      ),
    ];
    final width = wide ? 260.0 : (MediaQuery.sizeOf(context).width - 50) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: features
          .map((item) => SizedBox(width: width, child: _featureCard(item)))
          .toList(),
    );
  }

  Widget _featureCard(_FeatureData feature) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: () => setState(() => _selectedPage = feature.page),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: feature.color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(feature.icon, color: feature.color, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  feature.title,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  feature.subtitle,
                  style: const TextStyle(
                    fontSize: 8,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 12,
            color: AppColors.textMuted,
          ),
        ],
      ),
    ),
  );

  Widget _feedPage({required bool wide}) => Column(
    children: <Widget>[
      _feedIntro(),
      const SizedBox(height: 15),
      _twoColumn(
        wide,
        left: Column(
          children: <Widget>[
            ...List<Widget>.generate(
              _posts.length,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: _postCard(index, _posts[index]),
              ),
            ),
          ],
        ),
        right: _upcomingCard(),
      ),
    ],
  );

  Widget _feedIntro() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.cyanTint,
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      children: <Widget>[
        Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.success),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'This feed uses sample posts. Likes and new posts stay in this session and are never sent to a server.',
            style: TextStyle(
              fontSize: 10,
              height: 1.45,
              color: AppColors.midnightInk,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _studyPage({required bool wide}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      _sectionHeader('Study spaces', action: 'Demo content'),
      const SizedBox(height: 12),
      _featureGrid(wide),
      const SizedBox(height: 23),
      _sectionHeader('Your study week'),
      const SizedBox(height: 12),
      _scheduleCard(),
    ],
  );

  Widget _scheduleCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.glassBorder),
    ),
    child: Column(
      children: const <Widget>[
        _ScheduleRow(
          day: 'MON',
          time: '09:00',
          title: 'Biology 204 · Lab review',
          place: 'Science Building · Room 2.14',
          color: Color(0xFF138B91),
        ),
        Divider(height: 22),
        _ScheduleRow(
          day: 'WED',
          time: '14:00',
          title: 'Design thinking study group',
          place: 'Library · Collaborative zone',
          color: Color(0xFF6C53D5),
        ),
        Divider(height: 22),
        _ScheduleRow(
          day: 'FRI',
          time: '10:00',
          title: 'Finals study sprint',
          place: 'Library · Level 2',
          color: Color(0xFFE87935),
        ),
      ],
    ),
  );

  Widget _eventsPage({required bool wide}) => Column(
    children: <Widget>[
      _feedIntro(),
      const SizedBox(height: 15),
      _twoColumn(
        wide,
        left: Column(
          children: <Widget>[
            ...List<Widget>.generate(
              _events.length,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _eventCard(index),
              ),
            ),
          ],
        ),
        right: _communityCard(),
      ),
    ],
  );

  Widget _eventCard(int index) {
    final event = _events[index];
    final going = _goingToEvents.contains(index);
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 54,
            height: 58,
            decoration: BoxDecoration(
              color: event.color,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(event.icon, color: Colors.white, size: 25),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _tag(event.category),
                const SizedBox(height: 5),
                Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${event.date} · ${event.place}',
                  style: const TextStyle(
                    fontSize: 8,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () => setState(
              () => going
                  ? _goingToEvents.remove(index)
                  : _goingToEvents.add(index),
            ),
            child: Text(
              going ? 'Going ✓' : 'Join',
              style: const TextStyle(fontSize: 9),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(56, 36),
              padding: const EdgeInsets.symmetric(horizontal: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _communityCard() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: <Color>[Color(0xFF101D5B), Color(0xFF4534A5)],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.groups_rounded, color: Color(0xFFB9C5FF), size: 27),
        SizedBox(height: 12),
        Text(
          'Good things happen together.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Discover clubs, join study circles, and meet students who share your interests.',
          style: TextStyle(color: Color(0xFFD5DAFF), fontSize: 10, height: 1.6),
        ),
      ],
    ),
  );

  Widget _marketPage({required bool wide}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      _feedIntro(),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: const <Widget>[
          _MarketTile(
            title: 'Campus essentials',
            subtitle: 'Textbooks, supplies and more',
            price: 'From R80',
            icon: Icons.menu_book_rounded,
            color: Color(0xFF2457F5),
          ),
          _MarketTile(
            title: 'Student style',
            subtitle: 'Pre-loved finds from campus',
            price: 'From R120',
            icon: Icons.checkroom_rounded,
            color: Color(0xFFCE5E83),
          ),
          _MarketTile(
            title: 'Gadgets & tech',
            subtitle: 'Gear for class and beyond',
            price: 'From R250',
            icon: Icons.headphones_rounded,
            color: Color(0xFF138B91),
          ),
          _MarketTile(
            title: 'Made by students',
            subtitle: 'Support campus creators',
            price: 'From R60',
            icon: Icons.palette_rounded,
            color: Color(0xFFE87935),
          ),
        ],
      ),
    ],
  );

  Widget _messagesPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      _feedIntro(),
      const SizedBox(height: 15),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          children: _messages
              .map(
                (message) => ListTile(
                  onTap: () => _showNotice(
                    message.name,
                    'This conversation is a sample preview. No messages are sent or stored.',
                  ),
                  leading: _avatar(message.initials, message.color, size: 44),
                  title: Text(
                    message.name,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    message.preview,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        message.time,
                        style: const TextStyle(
                          fontSize: 8,
                          color: AppColors.textMuted,
                        ),
                      ),
                      if (message.unread > 0) ...<Widget>[
                        const SizedBox(height: 5),
                        _CountDot('${message.unread}'),
                      ],
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    ],
  );

  Widget _avatar(String initials, Color color, {double size = 36}) =>
      CircleAvatar(
        radius: size / 2,
        backgroundColor: color.withValues(alpha: .13),
        child: Text(
          initials,
          style: TextStyle(
            color: color,
            fontSize: size * .28,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _tag(String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.blueTint,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      value.toUpperCase(),
      style: const TextStyle(
        fontSize: 7,
        letterSpacing: .4,
        color: AppColors.vibeBlue,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _actionButton(
    IconData icon,
    String label, {
    Color color = AppColors.textMuted,
    VoidCallback? onTap,
  }) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  void _showNotifications() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 5, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Campus updates',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 18),
            _MiniUpdate(
              icon: Icons.event_available_rounded,
              title: 'Creative Campus Mixer',
              detail: 'Starts Thursday at 4:30 PM',
              color: Color(0xFF5540C9),
            ),
            SizedBox(height: 13),
            _MiniUpdate(
              icon: Icons.groups_rounded,
              title: 'New study group',
              detail: 'BIO 204 has 3 new members',
              color: Color(0xFF138B91),
            ),
            SizedBox(height: 10),
            Text(
              'Sample notifications · stored nowhere',
              style: TextStyle(fontSize: 9, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 8,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w800,
      color: AppColors.textMuted,
    ),
  );
}

class _CountDot extends StatelessWidget {
  const _CountDot(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: AppColors.vibeBlue,
      shape: BoxShape.circle,
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 8,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.day,
    required this.time,
    required this.title,
    required this.place,
    required this.color,
  });
  final String day, time, title, place;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          day,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              place,
              style: const TextStyle(fontSize: 8, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      Text(
        time,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      ),
    ],
  );
}

class _MarketTile extends StatelessWidget {
  const _MarketTile({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.icon,
    required this.color,
  });
  final String title, subtitle, price;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: MediaQuery.sizeOf(context).width >= 920
        ? 260
        : (MediaQuery.sizeOf(context).width - 50) / 2,
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: const Text(
            'Marketplace listings are sample content for this presentation.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 8, color: AppColors.textMuted),
            ),
            const SizedBox(height: 13),
            Text(
              price,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MiniUpdate extends StatelessWidget {
  const _MiniUpdate({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });
  final IconData icon;
  final String title, detail;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
            Text(
              detail,
              style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    ],
  );
}

class _DemoPost {
  const _DemoPost({
    required this.author,
    required this.initials,
    required this.campus,
    required this.time,
    required this.text,
    required this.tag,
    required this.likes,
    required this.color,
  });
  final String author, initials, campus, time, text, tag;
  final int likes;
  final Color color;
}

class _DemoEvent {
  const _DemoEvent({
    required this.title,
    required this.category,
    required this.date,
    required this.place,
    required this.color,
    required this.icon,
  });
  final String title, category, date, place;
  final Color color;
  final IconData icon;
}

class _DemoMessage {
  const _DemoMessage(
    this.name,
    this.preview,
    this.time,
    this.initials,
    this.color,
    this.unread,
  );
  final String name, preview, time, initials;
  final Color color;
  final int unread;
}

class _NavItem {
  const _NavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _StatData {
  const _StatData(this.value, this.label, this.icon, this.color);
  final String value, label;
  final IconData icon;
  final Color color;
}

class _FeatureData {
  const _FeatureData(
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.page,
  );
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final int page;
}
