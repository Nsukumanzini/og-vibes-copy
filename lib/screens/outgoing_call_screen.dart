import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/call_service.dart';
import '../utils/theme_constants.dart';
import 'active_call_screen.dart';

class OutgoingCallScreen extends StatefulWidget {
  const OutgoingCallScreen({
    super.key,
    required this.contactName,
    required this.callType,
    required this.calleeId,
  });

  final String contactName;
  final String callType;
  final String calleeId;

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  CallSession? _session;
  String? _error;
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final session = await CallService.instance.startCall(
        widget.calleeId,
        type: widget.callType,
      );
      if (!mounted) {
        await session.end();
        return;
      }
      _session = session..addListener(_sessionChanged);
      setState(() {});
      _sessionChanged();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  void _sessionChanged() {
    final session = _session;
    if (!mounted || session == null) return;
    if (session.status == 'active' && session.remoteStream != null && !_handedOff) {
      _handedOff = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ActiveCallScreen(
          session: session,
          contactName: widget.contactName,
        ),
      ));
      return;
    }
    if (const {'declined', 'cancelled', 'missed', 'ended'}.contains(session.status)) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  String _friendlyError(Object error) {
    final value = error.toString().toLowerCase();
    if (value.contains('permission') || value.contains('notallowed')) {
      return 'Allow camera and microphone access to start this call.';
    }
    return 'The call could not be started. Check your connection and try again.';
  }

  Future<void> _cancel() async {
    final session = _session;
    if (session != null) {
      await CallService.instance.cancelCall(session.callId);
      await session.disposeSession();
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _session?.removeListener(_sessionChanged);
    if (!_handedOff && _session != null) unawaited(_session!.disposeSession());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.midnightInk,
      body: Container(
        decoration: const BoxDecoration(gradient: AppStyles.brandGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 116,
                    height: 116,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: .12),
                      border: Border.all(color: Colors.white24),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 32)],
                    ),
                    child: Icon(
                      widget.callType == 'video' ? Icons.videocam_rounded : Icons.person_rounded,
                      size: 52,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.contactName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error ?? (_session == null ? 'Preparing secure call…' : 'Ringing…'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _error == null ? Colors.white70 : const Color(0xFFFFB4AB),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 54),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
                        ),
                        onPressed: _error == null ? _cancel : () => Navigator.pop(context),
                        icon: Icon(_error == null ? Icons.call_end_rounded : Icons.close_rounded),
                        label: Text(_error == null ? 'Cancel call' : 'Close'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
