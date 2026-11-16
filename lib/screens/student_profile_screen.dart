import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/offline_data_adapter.dart';

import '../utils/theme_constants.dart';
import '../widgets/post_card.dart';
import '../widgets/vibe_scaffold.dart';
import '../widgets/profile_photo_viewer.dart';
import 'chat_detail_screen.dart';
import 'profile_screen.dart';
import '../services/offline_cache_service.dart';

class StudentProfileNavigator {
  const StudentProfileNavigator._();

  static Future<void> open(BuildContext context, String? userId) {
    if (userId == null || userId.isEmpty) return Future.value();
    final ownId = OfflineData.instance.client.auth.currentUser?.id;
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ownId == userId
            ? const ProfileScreen()
            : StudentProfileScreen(studentId: userId),
      ),
    );
  }
}

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key, required this.studentId});

  final String studentId;

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  late Future<_StudentProfileData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_StudentProfileData> _load() async {
    final db = OfflineData.instance.client;
    List<dynamic> responses;
    try {
      responses = await Future.wait<dynamic>([
        db
            .from('profiles')
            .select(
              'id,nickname,photo_url,campus,faculty,course,department,level,student_type,is_verified,is_online,created_at',
            )
            .eq('id', widget.studentId)
            .single(),
        db
            .from('posts')
            .select(
              '*,profiles!posts_author_id_fkey(nickname,photo_url,campus,department)',
            )
            .eq('user_id', widget.studentId)
            .eq('is_deleted', false)
            .order('created_at', ascending: false)
            .limit(30),
      ]);
      unawaited(
        OfflineCacheService.writeList(
          'student_profile_${widget.studentId}',
          <Map<String, dynamic>>[
            {'results': responses},
          ],
          maxRecords: 1,
        ),
      );
    } catch (_) {
      final cached = await OfflineCacheService.readList(
        'student_profile_${widget.studentId}',
      );
      if (cached.isEmpty || cached.first['results'] is! List) rethrow;
      responses = List<dynamic>.from(cached.first['results'] as List);
    }
    return _StudentProfileData(
      profile: Map<String, dynamic>.from(responses.first as Map),
      posts: List<Map<String, dynamic>>.from(responses.last as List),
    );
  }

  @override
  Widget build(BuildContext context) => VibeScaffold(
    appBar: AppBar(title: const Text('Student profile')),
    body: FutureBuilder<_StudentProfileData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) {
          return _MessageState(
            icon: Icons.person_off_outlined,
            title: 'Profile unavailable',
            message: 'We could not open this student profile right now.',
            onRetry: () => setState(() => _future = _load()),
          );
        }
        return _content(snapshot.data!);
      },
    ),
  );

  Widget _content(_StudentProfileData data) {
    final profile = data.profile;
    final nickname = _value(profile['nickname'], 'OG Vibester');
    final photo = _value(profile['photo_url']);
    final campus = _value(profile['campus'], 'Campus not added');
    final course = _value(
      profile['course'] ?? profile['department'],
      'Course not added',
    );
    final level = _value(profile['level'], 'Level not added');
    return RefreshIndicator(
      onRefresh: () async {
        final next = _load();
        setState(() => _future = next);
        await next;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: AppStyles.brandGradient,
                borderRadius: AppStyles.bentoRadius,
                boxShadow: AppStyles.glassShadow,
              ),
              child: Column(
                children: [
                  ProfilePhotoButton(
                    url: photo,
                    name: nickname,
                    child: Container(
                      width: 112,
                      height: 112,
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        backgroundColor: AppColors.vibeBlue.withValues(
                          alpha: .12,
                        ),
                        backgroundImage: photo.isEmpty
                            ? null
                            : CachedNetworkImageProvider(photo),
                        child: photo.isEmpty
                            ? Text(
                                nickname.characters.first.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          nickname,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (profile['is_verified'] == true) ...[
                        const SizedBox(width: 7),
                        const Icon(
                          Icons.verified_rounded,
                          color: AppColors.electricCyan,
                          size: 21,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    profile['is_online'] == true
                        ? 'Online now'
                        : 'OG Vibes student',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ProfileChip(Icons.location_on_outlined, campus),
                      _ProfileChip(Icons.school_outlined, course),
                      _ProfileChip(Icons.stairs_outlined, level),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.deepBlue,
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatDetailScreen(
                          chatId: widget.studentId,
                          chatTitle: nickname,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.chat_bubble_rounded),
                    label: const Text('Open chat'),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  const Icon(
                    Icons.grid_view_rounded,
                    color: AppColors.vibeBlue,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '$nickname’s posts',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${data.posts.length}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (data.posts.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Text('No posts shared yet.'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
              sliver: SliverList.separated(
                itemCount: data.posts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) => PostCard(data: data.posts[index]),
              ),
            ),
        ],
      ),
    );
  }

  String _value(dynamic value, [String fallback = '']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _StudentProfileData {
  const _StudentProfileData({required this.profile, required this.posts});
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> posts;
}
