import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/screens/chat_detail_screen.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;
  String _selectedLevel = 'All';
  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;

  final List<Map<String, dynamic>> _students = [];
  final List<Map<String, dynamic>> _incoming = [];
  final List<Map<String, dynamic>> _friends = [];
  final Set<String> _pendingOutgoingIds = {};
  final Set<String> _pendingIncomingIds = {};
  final Set<String> _friendIds = {};
  final List<String> _levels = ['All'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _parseRows(dynamic response) {
    if (response is List) {
      return response
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (response is Map) {
      final data = response['data'];
      if (data is List) {
        return data
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    }

    return [];
  }

  String _displayName(Map<String, dynamic> row) {
    final nickname = ((row['nickname'] ?? '') as String).trim();
    if (nickname.isNotEmpty) return nickname;

    final name = ((row['name'] ?? '') as String).trim();
    final surname = ((row['surname'] ?? '') as String).trim();
    final full = [if (name.isNotEmpty) name, if (surname.isNotEmpty) surname].join(' ');
    return full.isNotEmpty ? full : 'Student';
  }

  String _courseLabel(Map<String, dynamic> row) {
    final department = ((row['department'] ?? '') as String).trim();
    return department.isEmpty ? 'No department set' : department;
  }

  String _profileSubtitle(Map<String, dynamic> row) {
    final campus = ((row['campus'] ?? '') as String).trim();
    if (campus.isNotEmpty) {
      return campus;
    }
    return _courseLabel(row);
  }

  String _profileLevel(Map<String, dynamic> row) {
    final level = ((row['level'] ?? '') as String).trim();
    return level.isEmpty ? 'Unspecified' : level;
  }

  Future<void> _loadData() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'You need to be signed in to view friend requests.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profilesResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, name, surname, nickname, department, level, campus, photo_url')
          .neq('id', currentUserId)
          .order('name', ascending: true);

      final profileRows = _parseRows(profilesResponse);
      final students = <Map<String, dynamic>>[];
      final seenLevels = <String>{'All'};

      for (final row in profileRows) {
        final levelLabel = _profileLevel(row);
        seenLevels.add(levelLabel);

        students.add({
          'id': row['id'],
          'name': _displayName(row),
          'course': _courseLabel(row),
          'subtitle': _profileSubtitle(row),
          'level': levelLabel,
          'photo_url': row['photo_url'],
          'profile': row,
        });
      }

      final incomingRequestResponse = await Supabase.instance.client
          .from('friend_requests')
          .select('id, sender_id, receiver_id, status, created_at')
          .eq('receiver_id', currentUserId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      final incomingRequestRows = _parseRows(incomingRequestResponse);
      final senderIds = incomingRequestRows.map((row) => row['sender_id'].toString()).toSet().toList();
      _pendingIncomingIds
        ..clear()
        ..addAll(senderIds);

      final outgoingRequestResponse = await Supabase.instance.client
          .from('friend_requests')
          .select('receiver_id')
          .eq('sender_id', currentUserId)
          .eq('status', 'pending');
      final outgoingRequestRows = _parseRows(outgoingRequestResponse);
      _pendingOutgoingIds
        ..clear()
        ..addAll(outgoingRequestRows.map((row) => row['receiver_id'].toString()));

      final friendshipResponse = await Supabase.instance.client
          .from('friendships')
          .select('friend_id')
          .eq('user_id', currentUserId);
      final friendshipRows = _parseRows(friendshipResponse);
      _friendIds
        ..clear()
        ..addAll(friendshipRows.map((row) => row['friend_id'].toString()));

      final incoming = <Map<String, dynamic>>[];
      if (senderIds.isNotEmpty) {
        final senderProfilesResponse = await Supabase.instance.client
            .from('profiles')
            .select('id, name, surname, nickname, department, level, campus, photo_url')
            .inFilter('id', senderIds);
        final senderRows = _parseRows(senderProfilesResponse);
        final senderMap = {for (final row in senderRows) row['id'].toString(): row};

        for (final request in incomingRequestRows) {
          final senderRow = senderMap[request['sender_id'].toString()];
          if (senderRow == null) continue;
          final levelLabel = _profileLevel(senderRow);
          incoming.add({
            'id': request['id'],
            'sender_id': request['sender_id'],
            'name': _displayName(senderRow),
            'course': _courseLabel(senderRow),
            'subtitle': _profileSubtitle(senderRow),
            'level': levelLabel,
            'photo_url': senderRow['photo_url'],
            'profile': senderRow,
          });
        }
      }

      final friends = <Map<String, dynamic>>[];
      if (_friendIds.isNotEmpty) {
        final friendProfilesResponse = await Supabase.instance.client
            .from('profiles')
            .select('id, name, surname, nickname, department, level, campus, photo_url')
            .inFilter('id', _friendIds.toList());
        final friendRows = _parseRows(friendProfilesResponse);

        for (final row in friendRows) {
          final levelLabel = _profileLevel(row);
          friends.add({
            'id': row['id'],
            'name': _displayName(row),
            'course': _courseLabel(row),
            'subtitle': _profileSubtitle(row),
            'level': levelLabel,
            'photo_url': row['photo_url'],
            'profile': row,
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _students
          ..clear()
          ..addAll(students);
        _incoming
          ..clear()
          ..addAll(incoming);
        _friends
          ..clear()
          ..addAll(friends);
        _levels
          ..clear()
          ..addAll(seenLevels.toList()..sort());
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'We could not load friend data right now.';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    return _students.where((student) {
      final levelMatch = _selectedLevel == 'All' || student['level'] == _selectedLevel;
      final name = (student['name'] as String).toLowerCase();
      final searchMatch = _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
      return levelMatch && searchMatch;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredIncoming {
    return _incoming.where((request) {
      final levelMatch = _selectedLevel == 'All' || request['level'] == _selectedLevel;
      final name = (request['name'] as String).toLowerCase();
      final searchMatch = _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
      return levelMatch && searchMatch;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredFriends {
    return _friends.where((friend) {
      final levelMatch = _selectedLevel == 'All' || friend['level'] == _selectedLevel;
      final name = (friend['name'] as String).toLowerCase();
      final searchMatch = _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
      return levelMatch && searchMatch;
    }).toList();
  }

  bool _hasOutgoingRequest(String profileId) => _pendingOutgoingIds.contains(profileId);
  bool _hasIncomingRequest(String profileId) => _pendingIncomingIds.contains(profileId);
  bool _isFriend(String profileId) => _friendIds.contains(profileId);

  Future<void> _sendFriendRequest(String recipientId) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      await Supabase.instance.client.from('friend_requests').insert({
        'sender_id': currentUserId,
        'receiver_id': recipientId,
        'status': 'pending',
      });

      if (!mounted) return;
      setState(() {
        _pendingOutgoingIds.add(recipientId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request sent.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send the request.')),
      );
    }
  }

  Future<void> _acceptRequest(String requestId, String senderId) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await Supabase.instance.client.from('friend_requests').update({
        'status': 'accepted',
        'updated_at': now,
      }).eq('id', requestId);

      await Supabase.instance.client.from('friendships').insert({
        'user_id': currentUserId,
        'friend_id': senderId,
        'created_at': now,
      });
      await Supabase.instance.client.from('friendships').insert({
        'user_id': senderId,
        'friend_id': currentUserId,
        'created_at': now,
      });

      if (!mounted) return;
      final acceptedRequest = _incoming.firstWhere(
        (request) => request['id'] == requestId,
        orElse: () => <String, dynamic>{},
      );
      final acceptedProfile = acceptedRequest['profile'] is Map
          ? Map<String, dynamic>.from(acceptedRequest['profile'] as Map)
          : null;

      setState(() {
        _incoming.removeWhere((request) => request['id'] == requestId);
        _pendingIncomingIds.remove(senderId);
        _friendIds.add(senderId);
        if (acceptedProfile != null) {
          _friends.add({
            'id': acceptedProfile['id'],
            'name': _displayName(acceptedProfile),
            'course': _courseLabel(acceptedProfile),
            'subtitle': _profileSubtitle(acceptedProfile),
            'level': _profileLevel(acceptedProfile),
            'photo_url': acceptedProfile['photo_url'],
            'profile': acceptedProfile,
          });
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request accepted.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not accept the request.')),
      );
    }
  }

  Future<void> _declineRequest(String requestId) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await Supabase.instance.client.from('friend_requests').update({
        'status': 'declined',
        'updated_at': now,
      }).eq('id', requestId);

      if (!mounted) return;
      setState(() {
        _incoming.removeWhere((request) => request['id'] == requestId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request declined.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not decline the request.')),
      );
    }
  }

  Future<void> _unfriend(String friendId) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      await Supabase.instance.client.from('friendships').delete().match({
        'user_id': currentUserId,
        'friend_id': friendId,
      });
      await Supabase.instance.client.from('friendships').delete().match({
        'user_id': friendId,
        'friend_id': currentUserId,
      });

      if (!mounted) return;
      setState(() {
        _friends.removeWhere((friend) => friend['id'] == friendId);
        _friendIds.remove(friendId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend removed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove friend.')),
      );
    }
  }

  void _showProfileDetails(Map<String, dynamic> profile) {
    final displayName = _displayName(profile);
    final nickname = ((profile['nickname'] ?? '') as String).trim();
    final department = _courseLabel(profile);
    final campus = ((profile['campus'] ?? '') as String).trim();
    final level = _profileLevel(profile);
    final photoUrl = ((profile['photo_url'] ?? '') as String).trim();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF2962FF).withOpacity(0.15),
                    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    child: photoUrl.isEmpty
                        ? Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : 'S',
                            style: const TextStyle(color: Color(0xFF2962FF), fontSize: 24, fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        if (nickname.isNotEmpty && nickname != displayName)
                          Text('Nickname: $nickname', style: const TextStyle(color: Color(0xFF607D8B))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _detailRow(Icons.school_outlined, 'Department', department),
              const SizedBox(height: 12),
              _detailRow(Icons.location_on_outlined, 'Campus', campus.isNotEmpty ? campus : 'Not set'),
              const SizedBox(height: 12),
              _detailRow(Icons.bar_chart_outlined, 'Level', level),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF2962FF)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: Color(0xFF607D8B))),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Connections'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Find'),
            Tab(text: 'Requests'),
            Tab(text: 'Friends'),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildErrorState()
                : Column(
                    children: [
                      _buildSearchHeader(),
                      const SizedBox(height: 16),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildFindFriendsTab(),
                            _buildRequestsTab(),
                            _buildMyFriendsTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
          decoration: InputDecoration(
            hintText: 'Search by name or level',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_levels.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _levels.map((level) {
                final isSelected = _selectedLevel == level;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ChoiceChip(
                    label: Text(level),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedLevel = level),
                    selectedColor: const Color(0xFF2962FF),
                    backgroundColor: const Color(0xFFE3F2FD),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF102027),
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildFindFriendsTab() {
    final matches = _filteredStudents;
    return matches.isEmpty
        ? _buildEmptyState('No students match your search.', 'Try another name or level filter.')
        : RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: matches.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final student = matches[index];
                final profileId = student['id'].toString();
                final isFriend = _isFriend(profileId);
                final hasOutgoing = _hasOutgoingRequest(profileId);
                final hasIncoming = _hasIncomingRequest(profileId);
                final status = isFriend
                    ? 'Friend'
                    : hasOutgoing
                        ? 'Request sent'
                        : hasIncoming
                            ? 'Incoming request'
                            : 'Available';

                return _StudentCard(
                  student: {
                    ...student,
                    'status': status,
                  },
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ChatDetailScreen(
                        chatId: profileId,
                        chatTitle: student['name'].toString(),
                      ),
                    ));
                  },
                  onRequest: isFriend || hasOutgoing || hasIncoming
                      ? () => _showProfileDetails(student['profile'] as Map<String, dynamic>)
                      : () => _sendFriendRequest(profileId),
                );
              },
            ),
          );
  }

  Widget _buildRequestsTab() {
    final requests = _filteredIncoming;
    return requests.isEmpty
        ? _buildEmptyState('No pending friend requests.', 'Ask classmates to connect with you.')
        : RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final request = requests[index];
                return _RequestCard(
                  request: request,
                  onAccept: () => _acceptRequest(request['id'].toString(), request['sender_id'].toString()),
                  onDecline: () => _declineRequest(request['id'].toString()),
                  onViewProfile: () => _showProfileDetails(request['profile'] as Map<String, dynamic>),
                );
              },
            ),
          );
  }

  Widget _buildMyFriendsTab() {
    final friends = _filteredFriends;
    return friends.isEmpty
        ? _buildEmptyState('You do not have any friends yet.', 'Accept a request or send one to start connecting.')
        : RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: friends.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final friend = friends[index];
                return _FriendCard(
                  friend: friend,
                  onChat: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ChatDetailScreen(
                        chatId: friend['id'].toString(),
                        chatTitle: friend['name'].toString(),
                      ),
                    ));
                  },
                  onViewProfile: () => _showProfileDetails(friend['profile'] as Map<String, dynamic>),
                  onUnfriend: () => _unfriend(friend['id'].toString()),
                );
              },
            ),
          );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 54, color: Colors.black38),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? 'Could not load friend data.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 40),
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_outlined, size: 54, color: Colors.black38),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF607D8B)),
            ),
          ],
        ),
      ],
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.student,
    required this.onTap,
    required this.onRequest,
  });

  final Map<String, dynamic> student;
  final VoidCallback onTap;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final name = student['name']?.toString() ?? 'Student';
    final course = student['course']?.toString() ?? 'No department set';
    final subtitle = student['subtitle']?.toString() ?? '';
    final level = student['level']?.toString() ?? 'Unspecified';
    final status = student['status']?.toString() ?? 'Available';
    final photoUrl = student['photo_url']?.toString() ?? '';

    final actionLabel = status == 'Request sent'
        ? 'Pending'
        : status == 'Incoming request'
            ? 'View'
            : status == 'Friend'
                ? 'View'
                : 'Connect';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFF2962FF).withOpacity(0.15),
              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
              child: photoUrl.isEmpty
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'S',
                      style: const TextStyle(color: Color(0xFF2962FF), fontWeight: FontWeight.w800),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    course,
                    style: const TextStyle(color: Color(0xFF607D8B), fontWeight: FontWeight.w600),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFF607D8B)),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      level,
                      style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w700),
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
                  status,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF607D8B), fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: status == 'Request sent' ? null : onRequest,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2962FF)),
                  child: Text(actionLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onAccept,
    required this.onDecline,
    required this.onViewProfile,
  });

  final Map<String, dynamic> request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF2962FF).withOpacity(0.15),
                child: Text(
                  request['name'].toString().split(' ').map((part) => part[0]).take(2).join(),
                  style: const TextStyle(color: Color(0xFF2962FF), fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['name'].toString(),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      request['course'].toString(),
                      style: const TextStyle(color: Color(0xFF607D8B), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        request['level'].toString(),
                        style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onViewProfile,
                icon: const Icon(Icons.person, color: Color(0xFF2962FF)),
                tooltip: 'View profile',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2962FF)),
                  child: const Text('Accept'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  child: const Text('Decline'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.friend,
    required this.onChat,
    required this.onViewProfile,
    required this.onUnfriend,
  });

  final Map<String, dynamic> friend;
  final VoidCallback onChat;
  final VoidCallback onViewProfile;
  final VoidCallback onUnfriend;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChat,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFF2962FF).withOpacity(0.15),
              child: Text(
                friend['name'].toString().split(' ').map((part) => part[0]).take(2).join(),
                style: const TextStyle(color: Color(0xFF2962FF), fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend['name'].toString(),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    friend['course'].toString(),
                    style: const TextStyle(color: Color(0xFF607D8B), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      friend['level'].toString(),
                      style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onViewProfile,
                  icon: const Icon(Icons.person, color: Color(0xFF2962FF)),
                  tooltip: 'View profile',
                ),
                const SizedBox(height: 4),
                OutlinedButton(
                  onPressed: onUnfriend,
                  child: const Text('Unfriend'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
