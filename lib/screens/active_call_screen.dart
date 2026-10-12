import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';
import '../utils/theme_constants.dart';

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({
    super.key,
    required this.session,
    required this.contactName,
  });

  final CallSession session;
  final String contactName;

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isMuted = false;
  bool _cameraEnabled = true;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
    _initializeRenderers();
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (!mounted) return;
    if (widget.session.localStream != null) {
      await _localRenderer.setSrcObject(stream: widget.session.localStream);
    }
    if (widget.session.remoteStream != null) {
      await _remoteRenderer.setSrcObject(stream: widget.session.remoteStream);
    }
    setState(() {});
  }

  void _sessionChanged() {
    if (!mounted) return;
    unawaited(_syncRenderers());
    if (widget.session.status == 'ended') {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  Future<void> _syncRenderers() async {
    await _localRenderer.setSrcObject(stream: widget.session.localStream);
    await _remoteRenderer.setSrcObject(stream: widget.session.remoteStream);
  }

  void _toggleMute() {
    HapticFeedback.selectionClick();
    final bool nextValue = !_isMuted;
    widget.session.setMuted(nextValue);
    setState(() => _isMuted = nextValue);
  }

  void _toggleCamera() {
    final next = !_cameraEnabled;
    widget.session.setCameraEnabled(next);
    setState(() => _cameraEnabled = next);
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool connected = widget.session.remoteStream != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.midnightInk,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (connected)
              RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              const _ConnectingState(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xB307172F),
                    Colors.transparent,
                    Color(0xE607172F),
                  ],
                  stops: [0, .46, 1],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                child: Column(
                  children: [
                    _CallHeader(connected: connected),
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 112,
                        height: 154,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.24),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black38,
                              blurRadius: 24,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: widget.session.localStream != null
                            ? RTCVideoView(
                                _localRenderer,
                                mirror: true,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              )
                            : const Center(
                                child: Icon(
                                  Icons.videocam_off_outlined,
                                  color: Colors.white54,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _CallControl(
                                label: _isMuted ? 'Unmute' : 'Mute',
                                icon: _isMuted
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                                selected: _isMuted,
                                onTap: _toggleMute,
                              ),
                              if (widget.session.isVideo) ...[
                                const SizedBox(width: 12),
                                _CallControl(
                                  label: _cameraEnabled ? 'Camera' : 'Camera off',
                                  icon: _cameraEnabled
                                      ? Icons.videocam_rounded
                                      : Icons.videocam_off_rounded,
                                  selected: !_cameraEnabled,
                                  onTap: _toggleCamera,
                                ),
                                const SizedBox(width: 12),
                                _CallControl(
                                  label: 'Flip',
                                  icon: Icons.cameraswitch_rounded,
                                  onTap: widget.session.switchCamera,
                                ),
                              ],
                              const SizedBox(width: 12),
                              _CallControl(
                                label: 'End',
                                icon: Icons.call_end_rounded,
                                danger: true,
                                onTap: () async {
                                  HapticFeedback.heavyImpact();
                                  await widget.session.end();
                                  if (context.mounted) Navigator.of(context).maybePop();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallHeader extends StatelessWidget {
  const _CallHeader({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: connected ? AppColors.success : AppColors.warning,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (connected ? AppColors.success : AppColors.warning)
                    .withValues(alpha: 0.55),
                blurRadius: 12,
              ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Text(
          connected ? 'Connected securely' : 'Connecting securely…',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        const Icon(Icons.lock_rounded, color: Colors.white70, size: 18),
      ],
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color color = danger
        ? AppColors.danger
        : selected
            ? Colors.white
            : Colors.white.withValues(alpha: 0.16);
    final Color foreground =
        danger || selected ? Colors.white : Colors.white.withValues(alpha: .9);

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectingState extends StatelessWidget {
  const _ConnectingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppStyles.brandGradient),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.electricCyan,
              ),
            ),
            SizedBox(height: 18),
            Text(
              'Setting up your call',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'This may take a moment',
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
