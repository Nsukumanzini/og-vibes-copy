import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/theme_constants.dart';

class AppNoticeGate extends StatefulWidget {
  const AppNoticeGate({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<AppNoticeGate> createState() => _AppNoticeGateState();
}

class _AppNoticeGateState extends State<AppNoticeGate> {
  static const _cacheKey = 'og_vibes_last_app_notice';
  static const _dismissedKey = 'og_vibes_dismissed_app_notice';
  RealtimeChannel? _channel;
  Timer? _expiryTimer;
  Timer? _pollTimer;
  Map<String, dynamic>? _notice;
  String? _dismissedSignature;
  String? _accessUserId;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialise());
  }

  Future<void> _initialise() async {
    final preferences = await SharedPreferences.getInstance();
    _dismissedSignature = preferences.getString(_dismissedKey);
    final cached = preferences.getString(_cacheKey);
    if (cached != null) {
      try {
        final row = Map<String, dynamic>.from(jsonDecode(cached) as Map);
        if (_isCurrent(row) && mounted) setState(() => _notice = row);
      } catch (_) {
        await preferences.remove(_cacheKey);
      }
    }
    if (!widget.enabled) return;
    await _refresh();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_refresh()),
    );
    _channel = Supabase.instance.client
        .channel('app-takeover-notices')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_takeover_notices',
          callback: (_) => unawaited(_refresh()),
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null && widget.enabled) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    _expiryTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  bool _isCurrent(Map<String, dynamic> row) {
    if (row['is_active'] != true) return false;
    final now = DateTime.now().toUtc();
    final startsAt = DateTime.tryParse(row['starts_at']?.toString() ?? '');
    final endsAt = DateTime.tryParse(row['ends_at']?.toString() ?? '');
    return (startsAt == null || !startsAt.isAfter(now)) &&
        (endsAt == null || endsAt.isAfter(now));
  }

  String _signature(Map<String, dynamic> row) =>
      '${row['id']}:${row['updated_at']}';

  Future<void> _refresh() async {
    try {
      final rows = await Supabase.instance.client
          .from('app_takeover_notices')
          .select()
          .order('is_blocking', ascending: false)
          .order('starts_at', ascending: false)
          .limit(10);
      final currentRows = List<Map<String, dynamic>>.from(rows)
          .where(_isCurrent)
          .toList();
      final userId = Supabase.instance.client.auth.currentUser?.id;
      currentRows.sort((a, b) {
        final aTargeted = a['target_user_id'] == userId ? 1 : 0;
        final bTargeted = b['target_user_id'] == userId ? 1 : 0;
        return bTargeted.compareTo(aTargeted);
      });
      final current = currentRows.isEmpty ? null : currentRows.first;
      final preferences = await SharedPreferences.getInstance();
      if (current == null) {
        await preferences.remove(_cacheKey);
      } else {
        await preferences.setString(_cacheKey, jsonEncode(current));
      }
      _scheduleExpiry(current);
      if (mounted) setState(() => _notice = current);
      await _refreshAdminAccess();
    } catch (_) {
      // Keep the last valid cached notice when the device or service is offline.
    }
  }

  Future<void> _refreshAdminAccess() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (_accessUserId == userId) return;
    _accessUserId = userId;
    _isAdmin = false;
    if (userId == null) return;
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      _isAdmin = profile?['role'] == 'admin';
    } catch (_) {
      // A suspended account is intentionally denied profile access. Keep the
      // notice visible and do not treat it as an administrator session.
      _isAdmin = false;
    }
  }

  void _scheduleExpiry(Map<String, dynamic>? notice) {
    _expiryTimer?.cancel();
    final endsAt = DateTime.tryParse(notice?['ends_at']?.toString() ?? '');
    if (endsAt == null) return;
    final delay = endsAt.difference(DateTime.now().toUtc());
    if (delay.isNegative) return;
    _expiryTimer = Timer(delay, () => unawaited(_refresh()));
  }

  Future<void> _dismiss() async {
    final notice = _notice;
    if (notice == null || notice['is_blocking'] == true) return;
    final signature = _signature(notice);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_dismissedKey, signature);
    if (mounted) setState(() => _dismissedSignature = signature);
  }

  @override
  Widget build(BuildContext context) {
    final notice = _notice;
    final visible = !_isAdmin && notice != null &&
        (notice['is_blocking'] == true ||
            _dismissedSignature != _signature(notice));
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (visible) _AppNoticeTakeover(notice: notice, onDismiss: _dismiss),
      ],
    );
  }
}

class _AppNoticeTakeover extends StatelessWidget {
  const _AppNoticeTakeover({required this.notice, required this.onDismiss});

  final Map<String, dynamic> notice;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final blocking = notice['is_blocking'] == true;
    final accountBlocked = notice['notice_kind'] == 'account_block';
    return PopScope(
      canPop: !blocking,
      child: Material(
        color: const Color(0xFF07111F),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF102B4F), Color(0xFF0A1628)],
                    ),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white.withValues(alpha: .14)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 36, offset: Offset(0, 18)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          gradient: AppStyles.brandGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.vibeBlue.withValues(alpha: .36),
                              blurRadius: 28,
                            ),
                          ],
                        ),
                        child: Icon(
                          accountBlocked
                              ? Icons.lock_person_rounded
                              : blocking
                                  ? Icons.engineering_rounded
                                  : Icons.campaign_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        accountBlocked
                            ? 'OG VIBES ACCOUNT NOTICE'
                            : blocking
                                ? 'OG VIBES SERVICE NOTICE'
                                : 'OG VIBES UPDATE',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.electricCyan,
                          fontSize: 12,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        notice['title']?.toString() ?? 'Important update',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        notice['message']?.toString() ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (blocking)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.electricCyan),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                accountBlocked
                                    ? 'Access will return when an administrator restores this account.'
                                    : 'This screen will close automatically when service resumes.',
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ),
                          ],
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: onDismiss,
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: const Text('Continue to OG Vibes'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
