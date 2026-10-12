import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _searchController = TextEditingController();
  final _db = Supabase.instance.client;

  StreamSubscription<List<Map<String, dynamic>>>? _alertsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _readsSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  List<_CampusAlert> _alerts = const [];
  Set<String> _readIds = <String>{};
  bool _loading = true;
  bool _refreshing = false;
  bool _offline = false;
  String? _error;

  String? get _userId => _db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _alertsSubscription?.cancel();
    _readsSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final connection = await Connectivity().checkConnectivity();
    _offline = connection.contains(ConnectivityResult.none);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        final offline = results.contains(ConnectivityResult.none);
        if (!mounted) return;
        final cameOnline = _offline && !offline;
        setState(() => _offline = offline);
        if (cameOnline) unawaited(_refresh());
      },
    );
    await _load();
    _listenForChanges();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final userId = _userId;
      final results = await Future.wait<dynamic>([
        _db
            .from('app_content')
            .select(
              'id,slug,title,subtitle,data,sort_order,is_active,created_at,updated_at',
            )
            .eq('section', 'announcements')
            .eq('is_active', true)
            .order('sort_order'),
        if (userId != null)
          _db
              .from('alert_reads')
              .select('alert_id,read_at')
              .eq('user_id', userId)
        else
          Future.value(<Map<String, dynamic>>[]),
      ]);

      final alerts = (results[0] as List)
          .map((row) => _CampusAlert.fromRow(Map<String, dynamic>.from(row as Map)))
          .toList();
      final readIds = (results[1] as List)
          .map((row) => (row as Map)['alert_id']?.toString())
          .whereType<String>()
          .toSet();
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _readIds = readIds;
        _loading = false;
        _error = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Alerts load failed: $error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'We could not load your alerts.';
      });
    }
  }

  void _listenForChanges() {
    _alertsSubscription = _db
        .from('app_content')
        .stream(primaryKey: ['id'])
        .eq('section', 'announcements')
        .order('sort_order')
        .listen(
          (rows) {
            if (!mounted) return;
            final alerts = rows
                .where((row) => row['is_active'] == true)
                .map(_CampusAlert.fromRow)
                .toList();
            setState(() {
              _alerts = alerts;
              _loading = false;
              _error = null;
            });
          },
          onError: (Object error) {
            if (mounted && _alerts.isEmpty) {
              setState(() => _error = 'Live alerts are temporarily unavailable.');
            }
          },
        );

    final userId = _userId;
    if (userId == null) return;
    _readsSubscription = _db
        .from('alert_reads')
        .stream(primaryKey: ['user_id', 'alert_id'])
        .eq('user_id', userId)
        .listen(
          (rows) {
            if (!mounted) return;
            setState(() {
              _readIds = rows
                  .map((row) => row['alert_id']?.toString())
                  .whereType<String>()
                  .toSet();
            });
          },
          onError: (Object error) => debugPrint('Alert read stream failed: $error'),
        );
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _load(showLoader: false);
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _markRead(_CampusAlert alert) async {
    final userId = _userId;
    if (userId == null || _readIds.contains(alert.id)) return;
    setState(() => _readIds = {..._readIds, alert.id});
    try {
      await _db.from('alert_reads').upsert(
        {
          'user_id': userId,
          'alert_id': alert.id,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,alert_id',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _readIds = {..._readIds}..remove(alert.id));
      _showSnack('Could not update this alert. Please try again.');
    }
  }

  Future<void> _openAlert(_CampusAlert alert) async {
    await _markRead(alert);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _AlertDetails(alert: alert),
    );
  }

  List<_CampusAlert> get _filteredAlerts {
    final query = _searchController.text.trim().toLowerCase();
    final items = _alerts.where((alert) {
      if (query.isEmpty) return true;
      return alert.title.toLowerCase().contains(query) ||
          alert.body.toLowerCase().contains(query) ||
          alert.source.toLowerCase().contains(query);
    }).toList();
    items.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAlerts;
    final unread = _alerts.where((alert) => !_readIds.contains(alert.id)).length;
    final critical = _alerts.where((alert) => alert.isCritical).length;
    final emergency = _alerts.cast<_CampusAlert?>().firstWhere(
          (alert) => alert?.isCritical == true,
          orElse: () => null,
        );

    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 20),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Semantics(
              button: true,
              label: 'Refresh alerts',
              child: IconButton(
                tooltip: 'Refresh alerts',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      constraints.maxWidth >= 900 ? 28 : 16,
                      8,
                      constraints.maxWidth >= 900 ? 28 : 16,
                      0,
                    ),
                    sliver: SliverList.list(
                      children: [
                        _AlertsHero(
                          total: _alerts.length,
                          unread: unread,
                          critical: critical,
                          loading: _loading,
                        ),
                        const SizedBox(height: 14),
                        if (_offline) const _OfflineBanner(),
                        if (_offline) const SizedBox(height: 12),
                        if (emergency != null) ...[
                          _EmergencyBanner(
                            alert: emergency,
                            unread: !_readIds.contains(emergency.id),
                            onTap: () => _openAlert(emergency),
                          ),
                          const SizedBox(height: 14),
                        ],
                        _SearchField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          onClear: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  if (_loading)
                    _LoadingSliver(horizontalPadding: constraints.maxWidth >= 900 ? 28 : 16)
                  else if (_error != null && _alerts.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _ErrorState(message: _error!, onRetry: _refresh),
                    )
                  else if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
                        searching: _searchController.text.trim().isNotEmpty,
                        onClear: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                    )
                  else
                    ..._buildGroupedSlivers(
                      filtered,
                      horizontalPadding: constraints.maxWidth >= 900 ? 28 : 16,
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGroupedSlivers(
    List<_CampusAlert> alerts, {
    required double horizontalPadding,
  }) {
    final groups = <String, List<_CampusAlert>>{};
    for (final alert in alerts) {
      groups.putIfAbsent(_dateGroup(alert.createdAt), () => []).add(alert);
    }
    final slivers = <Widget>[];
    for (final entry in groups.entries) {
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 6, horizontalPadding, 10),
          sliver: SliverToBoxAdapter(
            child: _GroupHeader(label: entry.key, count: entry.value.length),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 16),
          sliver: SliverList.separated(
            itemCount: entry.value.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final alert = entry.value[index];
              return _AlertCard(
                alert: alert,
                unread: !_readIds.contains(alert.id),
                onTap: () => _openAlert(alert),
                onMarkRead: () => _markRead(alert),
              );
            },
          ),
        ),
      );
    }
    return slivers;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AlertsHero extends StatelessWidget {
  const _AlertsHero({
    required this.total,
    required this.unread,
    required this.critical,
    required this.loading,
  });
  final int total;
  final int unread;
  final int critical;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      container: true,
      label: 'Alerts overview. $unread unread, $critical critical, $total total.',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: AppStyles.brandGradient,
            borderRadius: AppStyles.bentoRadius,
            boxShadow: [
              BoxShadow(
                color: AppColors.vibeBlue.withValues(alpha: 0.25),
                blurRadius: 34,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Wrap(
            spacing: 20,
            runSpacing: 18,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: AppColors.electricCyan,
                  size: 31,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 210, maxWidth: 450),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'OG VIBES ALERT CENTRE',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppColors.electricCyan,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      unread == 0 ? 'You’re all caught up' : '$unread alert${unread == 1 ? '' : 's'} need your attention',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Official campus updates, delivered as they happen.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              _HeroMetric(label: 'UNREAD', value: loading ? '—' : '$unread'),
              _HeroMetric(label: 'CRITICAL', value: loading ? '—' : '$critical'),
              _HeroMetric(label: 'TOTAL', value: loading ? '—' : '$total'),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 82),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      );
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => _GlassSurface(
        padding: const EdgeInsets.all(6),
        radius: 20,
        child: Semantics(
          textField: true,
          label: 'Search alerts by title, message, or sender',
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search alerts, updates, or offices…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded),
                    ),
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      );
}

class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner({
    required this.alert,
    required this.unread,
    required this.onTap,
  });
  final _CampusAlert alert;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Critical campus alert. ${alert.title}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Ink(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8E1535), Color(0xFFD83A52)],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.danger.withValues(alpha: 0.24),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.campaign_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'CRITICAL CAMPUS ALERT',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                            if (unread) ...[
                              const SizedBox(width: 8),
                              const _UnreadPulse(color: Colors.white),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          alert.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.unread,
    required this.onTap,
    required this.onMarkRead,
  });
  final _CampusAlert alert;
  final bool unread;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final color = alert.color;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      label:
          '${unread ? 'Unread' : 'Read'} ${alert.urgencyLabel} alert from ${alert.source}. ${alert.title}',
      child: AnimatedScale(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
        scale: 1,
        child: _GlassSurface(
          padding: EdgeInsets.zero,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppStyles.bentoRadius,
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(alert.icon, color: color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 7,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _UrgencyPill(alert: alert),
                              if (alert.pinned)
                                const _SmallPill(
                                  icon: Icons.push_pin_rounded,
                                  label: 'PINNED',
                                ),
                              if (unread) _UnreadPulse(color: color),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Text(
                            alert.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: unread ? FontWeight.w800 : FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            alert.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.verified_outlined, size: 16, color: color),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  alert.source,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _relativeTime(alert.createdAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (unread)
                      IconButton(
                        tooltip: 'Mark as read',
                        onPressed: onMarkRead,
                        icon: Icon(Icons.mark_email_read_outlined, color: color),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.success,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertDetails extends StatelessWidget {
  const _AlertDetails({required this.alert});
  final _CampusAlert alert;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            4,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: alert.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(alert.icon, color: alert.color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _UrgencyPill(alert: alert),
                          const SizedBox(height: 5),
                          Text(
                            alert.source,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(alert.title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(
                  alert.body,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
                ),
                const SizedBox(height: 22),
                const Divider(),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _DetailMeta(
                      icon: Icons.schedule_rounded,
                      label: DateFormat('d MMM yyyy · HH:mm').format(alert.createdAt),
                    ),
                    const _DetailMeta(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Marked as read',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _UnreadPulse extends StatefulWidget {
  const _UnreadPulse({required this.color});
  final Color color;

  @override
  State<_UnreadPulse> createState() => _UnreadPulseState();
}

class _UnreadPulseState extends State<_UnreadPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    lowerBound: 0.86,
    upperBound: 1.14,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: _controller,
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.38),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      );
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.vibeBlue,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.15,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.vibeBlue.withValues(alpha: 0.10),
              borderRadius: AppStyles.pillRadius,
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: AppColors.vibeBlue,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider()),
        ],
      );
}

class _UrgencyPill extends StatelessWidget {
  const _UrgencyPill({required this.alert});
  final _CampusAlert alert;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: alert.color.withValues(alpha: 0.11),
          borderRadius: AppStyles.pillRadius,
        ),
        child: Text(
          alert.urgencyLabel.toUpperCase(),
          style: TextStyle(
            color: alert.color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
          ),
        ),
      );
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.ogGold.withValues(alpha: 0.16),
          borderRadius: AppStyles.pillRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: const Color(0xFF9C7300)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9C7300),
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: 'You are offline. Showing the most recently loaded alerts.',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
          ),
          child: const Row(
            children: [
              Icon(Icons.cloud_off_outlined, color: AppColors.warning),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You’re offline. Showing the latest alerts available on this device.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _GlassSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.danger),
                const SizedBox(height: 14),
                Text('Alerts are unavailable', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
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
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching, required this.onClear});
  final bool searching;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.vibeBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  searching ? Icons.search_off_rounded : Icons.notifications_none_rounded,
                  color: AppColors.vibeBlue,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                searching ? 'No matching alerts' : 'No alerts right now',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                searching
                    ? 'Try another title, message, or campus office.'
                    : 'Official campus updates will appear here as they are published.',
                textAlign: TextAlign.center,
              ),
              if (searching) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Clear search'),
                ),
              ],
            ],
          ),
        ),
      );
}

class _LoadingSliver extends StatelessWidget {
  const _LoadingSliver({required this.horizontalPadding});
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      sliver: SliverList.separated(
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => Shimmer.fromColors(
          baseColor: dark ? const Color(0xFF172944) : Colors.grey.shade300,
          highlightColor: dark ? const Color(0xFF263B59) : Colors.grey.shade100,
          child: Container(
            height: 156,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppStyles.bentoRadius,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: dark
                ? const Color(0xCC172944)
                : Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: dark
                  ? const Color(0xFF304663)
                  : Colors.white.withValues(alpha: 0.92),
            ),
            boxShadow: AppStyles.glassShadow,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _DetailMeta extends StatelessWidget {
  const _DetailMeta({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _CampusAlert {
  const _CampusAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.source,
    required this.urgency,
    required this.pinned,
    required this.createdAt,
  });

  factory _CampusAlert.fromRow(Map<String, dynamic> row) {
    final data = row['data'] is Map
        ? Map<String, dynamic>.from(row['data'] as Map)
        : <String, dynamic>{};
    return _CampusAlert(
      id: row['id'].toString(),
      title: _text(row['title'], fallback: 'Campus alert'),
      body: _text(data['body'], fallback: _text(row['subtitle'])),
      source: _text(
        data['role'],
        fallback: _text(row['subtitle'], fallback: 'OG Vibes Campus'),
      ),
      urgency: _text(data['urgency'], fallback: 'info').toLowerCase(),
      pinned: data['isPinned'] == true || data['is_pinned'] == true,
      createdAt: _date(row['created_at']),
    );
  }

  final String id;
  final String title;
  final String body;
  final String source;
  final String urgency;
  final bool pinned;
  final DateTime createdAt;

  bool get isCritical => urgency == 'critical' || urgency == 'emergency';
  String get urgencyLabel => switch (urgency) {
        'critical' || 'emergency' => 'Critical',
        'warning' => 'Important',
        _ => 'Update',
      };
  Color get color => switch (urgency) {
        'critical' || 'emergency' => AppColors.danger,
        'warning' => AppColors.warning,
        _ => AppColors.vibeBlue,
      };
  IconData get icon => switch (urgency) {
        'critical' || 'emergency' => Icons.campaign_rounded,
        'warning' => Icons.warning_amber_rounded,
        _ => Icons.notifications_none_rounded,
      };
}

String _text(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

DateTime _date(dynamic value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toLocal() ?? DateTime.now();

String _dateGroup(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final days = today.difference(target).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return 'This week';
  return 'Earlier';
}

String _relativeTime(DateTime date) {
  final difference = DateTime.now().difference(date);
  if (difference.isNegative || difference.inMinutes < 1) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays == 1) return 'Yesterday';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return DateFormat('d MMM').format(date);
}
