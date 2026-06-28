import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/screens/chat_detail_screen.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedLevel = 'All';
  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;

  final List<Map<String, dynamic>> _students = [];
  final List<Map<String, dynamic>> _incoming = [];
  final List<String> _levels = ['All'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
          .select('id, name, surname, department, level, photo_url')
          .neq('id', currentUserId)
          .order('name', ascending: true);

      final profileRows = List<Map<String, dynamic>>.from(profilesResponse as List<dynamic>);
      final students = <Map<String, dynamic>>[];
      final seenLevels = <String>{'All'};

      for (final row in profileRows) {
        final level = ((row['level'] ?? '') as String).trim();
        if (level.isNotEmpty) {
          seenLevels.add(level);
        }

        students.add({
          'id': row['id'],
          'name': _fullName(row),
          'course': ((row['department'] ?? '') as String).trim().isEmpty
              ? 'No department set'
              : (row['department'] as String).trim(),
          'level': level.isEmpty ? 'Unspecified' : level,
          'status': 'Available',
          'photo_url': row['photo_url'],
        });
      }

      final requestsResponse = await Supabase.instance.client
          .from('friend_requests')
          .select('id, sender_id, receiver_id, status, created_at')
          .eq('receiver_id', currentUserId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final requestRows = List<Map<String, dynamic>>.from(requestsResponse as List<dynamic>);
      final senderIds = requestRows.map((row) => row['sender_id'].toString()).toSet().toList();
      final incoming = <Map<String, dynamic>>[];

      if (senderIds.isNotEmpty) {
        final senderProfilesResponse = await Supabase.instance.client
            .from('profiles')
            .select('id, name, surname, department, level, photo_url')
            .inFilter('id', senderIds);

        final senderRows = List<Map<String, dynamic>>.from(senderProfilesResponse as List<dynamic>);
        final senderMap = {for (final row in senderRows) row['id'].toString(): row};

        for (final request in requestRows) {
          final senderRow = senderMap[request['sender_id'].toString()];
          if (senderRow == null) {
            continue;
          }

          final level = ((senderRow['level'] ?? '') as String).trim();
          incoming.add({
            'id': request['id'],
            'sender_id': request['sender_id'],
            'name': _fullName(senderRow),
            'course': ((senderRow['department'] ?? '') as String).trim().isEmpty
                ? 'No department set'
                : (senderRow['department'] as String).trim(),
            'level': level.isEmpty ? 'Unspecified' : level,
            'status': 'Pending',
            'photo_url': senderRow['photo_url'],
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

  String _fullName(Map<String, dynamic> row) {
    final name = ((row['name'] ?? '') as String).trim();
    final surname = ((row['surname'] ?? '') as String).trim();
    if (name.isEmpty && surname.isEmpty) {
      return 'Student';
    }
    return [name, surname].where((part) => part.isNotEmpty).join(' ');
  }

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
      setState(() => _incoming.removeWhere((request) => request['id'] == requestId));
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
      setState(() => _incoming.removeWhere((request) => request['id'] == requestId));
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

  @override
  Widget build(BuildContext context) {
    final matches = _filteredStudents;

    return VibeScaffold(
      appBar: AppBar(title: const Text('Friend Requests')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildErrorState()
                : Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          hintText: 'Search student name',
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
                      if (_incoming.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Incoming requests',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 120,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _incoming.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final request = _incoming[index];
                              return _IncomingRequestCard(
                                request: request,
                                onAccept: () => _acceptRequest(request['id'].toString(), request['sender_id'].toString()),
                                onDecline: () => _declineRequest(request['id'].toString()),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Expanded(
                        child: matches.isEmpty
                            ? _buildEmptyState()
                            : ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: matches.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final student = matches[index];
                                  return _StudentCard(
                                    student: student,
                                    onTap: () {
                                      Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => ChatDetailScreen(
                                          chatId: student['id'].toString(),
                                          chatTitle: student['name'].toString(),
                                        ),
                                      ));
                                    },
                                    onRequest: () => _sendFriendRequest(student['id'].toString()),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.search_off_outlined, size: 54, color: Colors.black38),
          SizedBox(height: 10),
          Text(
            'No students match your search.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _IncomingRequestCard extends StatelessWidget {
  const _IncomingRequestCard({
    required this.request,
    required this.onAccept,
    required this.onDecline,
  });

  final Map<String, dynamic> request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request['name'].toString(),
            style: const TextStyle(fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            request['course'].toString(),
            style: const TextStyle(color: Color(0xFF607D8B), fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2962FF)),
                  child: const Text('Accept'),
                ),
              ),
              const SizedBox(width: 8),
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
              child: Text(
                student['name'].toString().split(' ').map((part) => part[0]).take(2).join(),
                style: const TextStyle(color: Color(0xFF2962FF), fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student['name'].toString(),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    student['course'].toString(),
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
                      student['level'].toString(),
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
                  onPressed: onRequest,
                  icon: const Icon(Icons.person_add_alt_1_outlined, color: Color(0xFF2962FF)),
                  tooltip: 'Send request',
                ),
                const SizedBox(height: 4),
                Text(
                  student['status'].toString(),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF607D8B)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
