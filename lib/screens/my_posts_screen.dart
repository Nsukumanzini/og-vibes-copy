import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/theme_constants.dart';
import '../widgets/post_card.dart';
import '../widgets/vibe_scaffold.dart';
import 'create_post_screen.dart';

class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key});
  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  final _posts = <Map<String, dynamic>>[];
  RealtimeChannel? _channel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    final id = Supabase.instance.client.auth.currentUser?.id;
    if (id != null) {
      _channel = Supabase.instance.client.channel('my-posts:$id')
        ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'posts', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: id), callback: (_) => unawaited(_load(showLoader: false)))
        ..subscribe();
    }
  }

  Future<void> _load({bool showLoader = true}) async {
    final id = Supabase.instance.client.auth.currentUser?.id;
    if (id == null) { if (mounted) setState(() => _loading = false); return; }
    if (showLoader && mounted) setState(() => _loading = true);
    final rows = List<Map<String, dynamic>>.from(await Supabase.instance.client.from('posts').select('*,profiles!posts_author_id_fkey(nickname,photo_url,campus,department)').eq('user_id', id).eq('is_deleted', false).order('created_at', ascending: false) as List);
    if (!mounted) return;
    setState(() { _posts..clear()..addAll(rows); _loading = false; });
  }

  @override
  void dispose() {
    if (_channel != null) unawaited(Supabase.instance.client.removeChannel(_channel!));
    super.dispose();
  }

  Future<void> _create() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreatePostScreen()));
    await _load(showLoader: false);
  }

  @override
  Widget build(BuildContext context) => VibeScaffold(
    appBar: AppBar(title: const Text('My posts')),
    floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('New post')),
    body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
        SliverToBoxAdapter(child: Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 16), padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(gradient: AppStyles.brandGradient, borderRadius: AppStyles.bentoRadius),
          child: Row(children: [Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(17)), child: const Icon(Icons.auto_awesome_motion_rounded, color: Colors.white)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Your feed activity', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('${_posts.length} post${_posts.length == 1 ? '' : 's'} · Edit, delete or reply to comments', style: const TextStyle(color: Colors.white70))]))]),
        )),
        if (_posts.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.post_add_rounded, size: 50, color: AppColors.textMuted), const SizedBox(height: 12), const Text('You have not posted yet.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 14), FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('Create your first post'))]))))
        else
          SliverPadding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 110), sliver: SliverList.separated(itemCount: _posts.length, separatorBuilder: (_, _) => const SizedBox(height: 12), itemBuilder: (_, index) => PostCard(data: _posts[index]))),
      ]),
    ),
  );
}
