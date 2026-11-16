import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/diagnostics_service.dart';
import '../services/push_notification_service.dart';
import '../utils/theme_constants.dart';

enum _AppPermission { notifications, microphone, camera }

extension on _AppPermission {
  String get title => switch (this) {
    _AppPermission.notifications => 'Allow notifications?',
    _AppPermission.microphone => 'Allow microphone access?',
    _AppPermission.camera => 'Allow camera access?',
  };

  String get description => switch (this) {
    _AppPermission.notifications =>
      'Get messages, assessments, campus alerts and incoming call notices.',
    _AppPermission.microphone =>
      'Make voice calls and be heard when you answer a video call.',
    _AppPermission.camera =>
      'Join video calls with your camera when you choose to turn it on.',
  };

  IconData get icon => switch (this) {
    _AppPermission.notifications => Icons.notifications_active_rounded,
    _AppPermission.microphone => Icons.mic_rounded,
    _AppPermission.camera => Icons.videocam_rounded,
  };
}

/// Shows one clear choice at a time. Allow invokes the operating-system or
/// browser dialog; Don't allow advances without redirecting to Settings.
class NotificationEnrollmentGate extends StatefulWidget {
  const NotificationEnrollmentGate({
    super.key,
    required this.child,
    required this.enabled,
  });

  final Widget child;
  final bool enabled;

  @override
  State<NotificationEnrollmentGate> createState() =>
      _NotificationEnrollmentGateState();
}

class _NotificationEnrollmentGateState
    extends State<NotificationEnrollmentGate> {
  StreamSubscription<AuthState>? _authSubscription;
  final Set<_AppPermission> _answeredThisSession = {};
  List<_AppPermission> _pending = const [];
  bool _busy = false;

  _AppPermission? get _current => _pending.isEmpty ? null : _pending.first;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) {
      _answeredThisSession.clear();
      unawaited(_refresh());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refresh()));
  }

  Future<bool> _isGranted(_AppPermission permission) async {
    if (permission == _AppPermission.notifications) {
      final status = await PushNotificationService.enrollmentStatus();
      if (status == PushEnrollmentStatus.enabled) {
        await PushNotificationService.registerCurrentDevice();
        return true;
      }
      return status == PushEnrollmentStatus.unsupported;
    }
    final status = switch (permission) {
      _AppPermission.microphone => await Permission.microphone.status,
      _AppPermission.camera => await Permission.camera.status,
      _AppPermission.notifications => throw StateError('Already handled'),
    };
    return status.isGranted || status.isLimited;
  }

  Future<void> _refresh() async {
    if (!widget.enabled || Supabase.instance.client.auth.currentUser == null) {
      if (mounted) setState(() => _pending = const []);
      return;
    }
    final missing = <_AppPermission>[];
    for (final permission in _AppPermission.values) {
      if (_answeredThisSession.contains(permission)) continue;
      try {
        if (!await _isGranted(permission)) missing.add(permission);
      } catch (_) {
        // Unsupported permissions are omitted instead of blocking the app.
      }
    }
    if (mounted) setState(() => _pending = missing);
  }

  Future<bool> _request(_AppPermission permission) async {
    if (permission == _AppPermission.notifications) {
      return PushNotificationService.requestAndRegisterCurrentDevice();
    }
    final status = switch (permission) {
      _AppPermission.microphone => await Permission.microphone.request(),
      _AppPermission.camera => await Permission.camera.request(),
      _AppPermission.notifications => throw StateError('Already handled'),
    };
    return status.isGranted || status.isLimited;
  }

  Future<void> _allow() async {
    final permission = _current;
    if (permission == null || _busy) return;
    setState(() => _busy = true);
    var granted = false;
    try {
      granted = await _request(permission);
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    _answeredThisSession.add(permission);
    setState(() {
      _busy = false;
      _pending = _pending.where((value) => value != permission).toList();
    });
    unawaited(
      DiagnosticsService.record(
        granted
            ? 'permission_enabled_${permission.name}'
            : 'permission_declined_${permission.name}',
      ),
    );
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${permission.title.replaceAll('?', '')} was not enabled. The app will keep working without it.',
          ),
        ),
      );
    }
  }

  void _decline() {
    final permission = _current;
    if (permission == null || _busy) return;
    _answeredThisSession.add(permission);
    setState(
      () => _pending = _pending.where((value) => value != permission).toList(),
    );
    unawaited(
      DiagnosticsService.record('permission_declined_${permission.name}'),
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permission = _current;
    return Stack(
      children: [
        widget.child,
        if (permission != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 18,
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF071A39), Color(0xFF164FBA)],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.vibeBlue.withValues(alpha: 0.3),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 21,
                            backgroundColor: Colors.white12,
                            child: Icon(
                              permission.icon,
                              color: AppColors.electricCyan,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  permission.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  permission.description,
                                  style: const TextStyle(
                                    color: Color(0xFFDCE8FF),
                                    height: 1.35,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton(
                                      onPressed: _busy ? null : _allow,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: const Color(
                                          0xFF1249A5,
                                        ),
                                      ),
                                      child: _busy
                                          ? const SizedBox.square(
                                              dimension: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Allow'),
                                    ),
                                    TextButton(
                                      onPressed: _busy ? null : _decline,
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text("Don't allow"),
                                    ),
                                  ],
                                ),
                              ],
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
      ],
    );
  }
}
