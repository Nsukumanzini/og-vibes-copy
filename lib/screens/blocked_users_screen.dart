import 'package:flutter/material.dart';
import '../widgets/glass_card.dart';
import '../services/offline_data_adapter.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchBlockedUsers();
  }

  Future<List<Map<String, dynamic>>> _fetchBlockedUsers() async {
    final user = OfflineData.instance.client.auth.currentUser;
    if (user == null) return [];
    final response = await OfflineData.instance.client
        .from('blocked_users')
        .select('*, profiles(*)')
        .eq('user_id', user.id)
        .order('blocked_at', ascending: false);

    final raw = response as List<dynamic>? ?? [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _unblock(Map<String, dynamic> row) async {
    final user = OfflineData.instance.client.auth.currentUser;
    if (user == null || row['user_id']?.toString() != user.id) {
      _showMessage('You can only unblock accounts you blocked yourself.');
      return;
    }
    final blockedUserId = row['blocked_user_id']?.toString();
    if (blockedUserId == user.id) {
      _showMessage('You cannot unblock your own account.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unblock account?'),
        content: const Text(
          'This person may be able to message, call and interact with you again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep blocked'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await OfflineData.instance.client
          .from('blocked_users')
          .delete()
          .eq('id', row['id'])
          .eq('user_id', user.id);
      setState(() {
        _future = _fetchBlockedUsers();
      });
    } catch (e) {
      if (!mounted) return;
      _showMessage('We could not unblock this account. Please try again.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = OfflineData.instance.client.auth.currentUser;
    if (user == null) {
      return VibeScaffold(
        appBar: AppBar(title: const Text('Blocked accounts')),
        body: const Center(child: Text('Sign in to manage blocked users.')),
      );
    }

    return VibeScaffold(
      appBar: AppBar(title: const Text('Blocked accounts')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Blocked accounts could not be loaded. Please try again.',
              ),
            );
          }
          final docs = snapshot.data ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.shield_outlined,
                      size: 64,
                      color: Colors.white70,
                    ),
                    SizedBox(height: 14),
                    Text(
                      'No blocked accounts',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Accounts you block will appear here. They will not be able to message, call or interact with you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final row = docs[index];
              final profile = row['profiles'] as Map<String, dynamic>?;
              final nickname = (profile?['nickname'] as String?)?.trim();
              final name = nickname?.isNotEmpty == true
                  ? nickname!
                  : 'OG Vibester';
              final avatarUrl = (profile?['photo_url'] as String?) ?? '';
              final reason = (row['reason'] as String?)?.trim();

              return GlassCard(
                color: Colors.white.withOpacity(0.08),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: avatarUrl.isNotEmpty
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: avatarUrl.isEmpty
                        ? const Icon(Icons.person_rounded)
                        : null,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    reason?.isNotEmpty == true
                        ? 'Blocked by you • $reason'
                        : 'Blocked by you',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: OutlinedButton(
                    onPressed: () => _unblock(row),
                    child: const Text('Unblock'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
