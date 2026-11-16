import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/offline_data_adapter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';

class DownloadHistoryScreen extends StatefulWidget {
  const DownloadHistoryScreen({super.key});

  @override
  State<DownloadHistoryScreen> createState() => _DownloadHistoryScreenState();
}

class _DownloadHistoryScreenState extends State<DownloadHistoryScreen> {
  final _search = TextEditingController();
  final List<Map<String, dynamic>> _downloads = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String _filter = 'All';

  String get _cacheKey =>
      'download_history_cache_v2_${OfflineData.instance.client.auth.currentUser?.id ?? 'signed_out'}';

  @override
  void initState() {
    super.initState();
    _search.addListener(_redraw);
    unawaited(_initialise());
  }

  @override
  void dispose() {
    _search
      ..removeListener(_redraw)
      ..dispose();
    super.dispose();
  }

  void _redraw() => setState(() {});

  Future<void> _initialise() async {
    await _restoreCache();
    await _load();
  }

  Future<void> _restoreCache() async {
    final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      final rows = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map(
          (row) => Map<String, dynamic>.from(row as Map),
        ),
      );
      setState(() {
        _downloads
          ..clear()
          ..addAll(rows);
        _loading = false;
      });
    } catch (_) {
      // Ignore an outdated or damaged local cache.
    }
  }

  Future<void> _saveCache() async {
    await (await SharedPreferences.getInstance()).setString(
      _cacheKey,
      jsonEncode(_downloads),
    );
  }

  Future<void> _load() async {
    if (_downloads.isEmpty && mounted) setState(() => _loading = true);
    if (mounted) setState(() => _refreshing = true);
    try {
      final rows = List<Map<String, dynamic>>.from(
        await OfflineData.instance.client
                .from('download_history')
                .select(
                  'id,source_type,source_id,title,url,storage_path,storage_bucket,file_size_bytes,downloaded_at',
                )
                .order('downloaded_at', ascending: false)
                .limit(250)
            as List<dynamic>,
      );
      if (!mounted) return;
      setState(() {
        _downloads
          ..clear()
          ..addAll(rows);
        _loading = false;
        _refreshing = false;
        _error = null;
      });
      await _saveCache();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = _downloads.isEmpty
            ? 'Your download history could not be loaded.'
            : 'Showing saved history while the app reconnects.';
      });
    }
  }

  List<Map<String, dynamic>> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _downloads.where((entry) {
      final type = entry['source_type']?.toString() ?? '';
      final matchesFilter = switch (_filter) {
        'Study files' => type != 'document_wallet',
        'My documents' => type == 'document_wallet',
        _ => true,
      };
      final matchesQuery = query.isEmpty ||
          (entry['title']?.toString().toLowerCase().contains(query) ?? false);
      return matchesFilter && matchesQuery;
    }).toList();
  }

  Future<void> _open(Map<String, dynamic> entry) async {
    try {
      var link = entry['url']?.toString().trim() ?? '';
      final path = entry['storage_path']?.toString().trim() ?? '';
      if (path.isNotEmpty) {
        final bucket = entry['storage_bucket']?.toString().trim();
        link = await OfflineData.instance.client.storage
            .from(bucket?.isNotEmpty == true ? bucket! : 'academic-content')
            .createSignedUrl(path, 600);
      }
      final uri = Uri.tryParse(link);
      if (uri == null || !uri.hasScheme) {
        throw StateError('This file no longer has a valid download link.');
      }
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Your device could not open this file.');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> entry) async {
    final id = entry['id']?.toString();
    if (id == null || id.isEmpty) return;
    try {
      await OfflineData.instance.client
          .from('download_history')
          .delete()
          .eq('id', id);
      if (!mounted) return;
      setState(() => _downloads.removeWhere((row) => row['id'] == id));
      await _saveCache();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove this entry.')),
        );
      }
    }
  }

  Future<void> _clearAll() async {
    if (_downloads.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_rounded),
        title: const Text('Clear download history?'),
        content: const Text(
          'This removes the history list only. Files already saved on your device will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear history'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final userId = OfflineData.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await OfflineData.instance.client
          .from('download_history')
          .delete()
          .eq('user_id', userId);
      if (!mounted) return;
      setState(() => _downloads.clear());
      await _saveCache();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not clear your history.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            tooltip: 'Clear history',
            onPressed: _downloads.isEmpty ? null : _clearAll,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              sliver: SliverList.list(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppStyles.brandGradient,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.white24,
                          child: Icon(
                            Icons.download_done_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your downloaded files',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_downloads.length} recent download${_downloads.length == 1 ? '' : 's'}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        if (_refreshing)
                          const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    MaterialBanner(
                      content: Text(_error!),
                      leading: const Icon(Icons.cloud_off_rounded),
                      actions: [
                        TextButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search downloads',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: _search.clear,
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: ['All', 'Study files', 'My documents']
                        .map(
                          (label) => ChoiceChip(
                            label: Text(label),
                            selected: _filter == label,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _filter = label),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyDownloads(searching: _search.text.isNotEmpty),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                sliver: SliverList.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final entry = visible[index];
                    final type = entry['source_type']?.toString() ?? 'file';
                    final date = DateTime.tryParse(
                      entry['downloaded_at']?.toString() ?? '',
                    )?.toLocal();
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        onTap: () => _open(entry),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.vibeBlue.withValues(alpha: .1),
                          child: Icon(_iconFor(type), color: AppColors.vibeBlue),
                        ),
                        title: Text(
                          entry['title']?.toString() ?? 'Downloaded file',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${_labelFor(type)}${date == null ? '' : ' · ${DateFormat('d MMM y, HH:mm').format(date)}'}${_size(entry['file_size_bytes'])}',
                          maxLines: 2,
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Download options',
                          onSelected: (value) {
                            if (value == 'open') unawaited(_open(entry));
                            if (value == 'delete') unawaited(_delete(entry));
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'open',
                              child: ListTile(
                                leading: Icon(Icons.open_in_new_rounded),
                                title: Text('Open again'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                leading: Icon(Icons.delete_outline_rounded),
                                title: Text('Remove from history'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('no longer')) return 'This file is no longer available.';
    if (text.contains('could not open')) return 'Your device could not open this file.';
    return 'This file could not be opened. Check your connection and try again.';
  }

  String _size(dynamic value) {
    final bytes = value is num ? value.toInt() : int.tryParse('$value');
    if (bytes == null || bytes <= 0) return '';
    return ' · ${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  String _labelFor(String type) => switch (type) {
        'past_paper' => 'Past paper',
        'lecture_slide' => 'Lecture slide',
        'timetable' => 'Timetable',
        'document_wallet' => 'Document Wallet',
        _ => 'File',
      };

  IconData _iconFor(String type) => switch (type) {
        'past_paper' => Icons.history_edu_rounded,
        'lecture_slide' => Icons.co_present_rounded,
        'timetable' => Icons.calendar_month_rounded,
        'document_wallet' => Icons.folder_special_rounded,
        _ => Icons.insert_drive_file_rounded,
      };
}

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.download_for_offline_outlined,
              size: 64,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              searching ? 'No matching downloads' : 'No downloads yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? 'Try another file name or filter.'
                  : 'Files you download from study tools and your Document Wallet will appear here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
