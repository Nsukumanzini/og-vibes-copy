import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';
import '../services/group_call_service.dart';
import '../utils/theme_constants.dart';
import 'group_call_screen.dart';

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({
    super.key,
    required this.session,
    required this.contactName,
    this.contactPhotoUrl,
  });
  final CallSession session;
  final String contactName;
  final String? contactPhotoUrl;

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  static OverlayEntry? _minimisedEntry;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isMuted = false;
  bool _cameraEnabled = true;
  bool _speakerEnabled = false;
  bool _controlsVisible = true;
  bool _upgrading = false;
  Timer? _durationTimer;
  Timer? _controlsTimer;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _removeMinimisedEntry();
    widget.session.addListener(_sessionChanged);
    unawaited(_initializeRenderers());
    _duration = widget.session.elapsed;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.session.status == 'active') {
        setState(() => _duration = widget.session.elapsed);
      }
    });
    if (widget.session.isVideo) _scheduleControlsHide();
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (!mounted) return;
    await _syncRenderers();
    if (mounted) setState(() {});
  }

  void _sessionChanged() {
    if (!mounted) return;
    unawaited(_syncRenderers());
    if (widget.session.status == 'ended' && !_upgrading) {
      _removeMinimisedEntry();
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
    final next = !_isMuted;
    widget.session.setMuted(next);
    setState(() => _isMuted = next);
  }

  void _toggleCamera() {
    final next = !_cameraEnabled;
    widget.session.setCameraEnabled(next);
    setState(() => _cameraEnabled = next);
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerEnabled;
    await widget.session.setSpeakerEnabled(next);
    if (mounted) setState(() => _speakerEnabled = next);
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && widget.session.status == 'active') {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleVideoControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleControlsHide();
  }

  String get _durationLabel {
    final hours = _duration.inHours;
    final minutes = (_duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (_duration.inSeconds % 60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Future<void> _endCall() async {
    await widget.session.end();
    if (mounted) Navigator.of(context).maybePop();
  }

  void _minimise() {
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay;
    if (overlay == null) return;
    _removeMinimisedEntry();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _MinimisedCallBubble(
        session: widget.session,
        name: widget.contactName,
        photoUrl: widget.contactPhotoUrl,
        onRemove: () {
          if (entry.mounted) entry.remove();
          if (identical(_minimisedEntry, entry)) _minimisedEntry = null;
        },
        onOpen: () {
          if (entry.mounted) entry.remove();
          if (identical(_minimisedEntry, entry)) _minimisedEntry = null;
          navigator.push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => ActiveCallScreen(
                session: widget.session,
                contactName: widget.contactName,
                contactPhotoUrl: widget.contactPhotoUrl,
              ),
            ),
          );
        },
      ),
    );
    _minimisedEntry = entry;
    overlay.insert(entry);
    navigator.pop();
  }

  static void _removeMinimisedEntry() {
    final entry = _minimisedEntry;
    if (entry?.mounted == true) entry!.remove();
    _minimisedEntry = null;
  }

  Future<void> _addParticipants() async {
    if (_upgrading) return;
    try {
      final people = await GroupCallService.instance.availableCallPeople(
        excludingUserId: widget.session.otherUserId,
      );
      if (!mounted) return;
      if (people.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Add friends before starting a group call.'),
          ),
        );
        return;
      }
      final chosen = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _CallPeoplePicker(people: people),
      );
      if (chosen == null || chosen.isEmpty || !mounted) return;
      setState(() => _upgrading = true);
      final groupSession = await GroupCallService.instance.upgradePrivateCall(
        privateCallId: widget.session.callId,
        type: widget.session.type,
        inviteeIds: chosen,
      );
      if (!mounted) {
        await groupSession.leave(endForEveryone: true);
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => GroupCallScreen(session: groupSession),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _upgrading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add people to this call. $error')),
      );
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    _durationTimer?.cancel();
    _controlsTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.session.isVideo ? _buildVideoCall() : _buildVoiceCall();

  Widget _buildVideoCall() {
    final connected = widget.session.remoteStream != null;
    final remoteCameraOn =
        widget.session.remoteStream?.getVideoTracks().any((track) => track.enabled) ??
        false;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.midnightInk,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleVideoControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (connected)
                RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                _ConnectingState(name: widget.contactName),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xC807172F),
                      Colors.transparent,
                      Color(0xEA07172F),
                    ],
                    stops: [0, .48, 1],
                  ),
                ),
              ),
              SafeArea(
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
                      child: Column(
                        children: [
                          _CallHeader(
                            name: widget.contactName,
                            state: widget.session.stateLabel,
                            quality: widget.session.connectionQuality,
                            duration: widget.session.status == 'active'
                                ? _durationLabel
                                : null,
                            onMinimise: _minimise,
                          ),
                          if (widget.session.status == 'reconnecting')
                            const _ReconnectingBanner(),
                          const Spacer(),
                          Align(
                            alignment: Alignment.centerRight,
                            child: AnimatedContainer(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              width: _cameraEnabled ? 112 : 78,
                              height: _cameraEnabled ? 154 : 78,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: const Color(0xCC132544),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white24),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black38,
                                    blurRadius: 24,
                                    offset: Offset(0, 12),
                                  ),
                                ],
                              ),
                              child:
                                  _cameraEnabled &&
                                      widget.session.localStream != null
                                  ? RTCVideoView(
                                      _localRenderer,
                                      mirror: true,
                                      objectFit: RTCVideoViewObjectFit
                                          .RTCVideoViewObjectFitCover,
                                    )
                                  : const Center(
                                      child: Icon(
                                        Icons.videocam_off_rounded,
                                        color: Colors.white70,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _ControlsPanel(
                            children: [
                              _CallControl(
                                label: _isMuted ? 'Unmute' : 'Mute',
                                icon: _isMuted
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                                selected: _isMuted,
                                onTap: _toggleMute,
                              ),
                              _CallControl(
                                label: _cameraEnabled ? 'Camera' : 'Camera off',
                                icon: _cameraEnabled
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded,
                                selected: !_cameraEnabled,
                                onTap: _toggleCamera,
                              ),
                              _CallControl(
                                label: 'Flip',
                                icon: Icons.cameraswitch_rounded,
                                onTap: widget.session.switchCamera,
                              ),
                          _CallControl(
                                label: 'Add 2/5',
                                icon: Icons.person_add_alt_1_rounded,
                                loading: _upgrading,
                                onTap: _addParticipants,
                              ),
                              _CallControl(
                                label: 'End',
                                icon: Icons.call_end_rounded,
                                danger: true,
                                onTap: _endCall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (connected && !remoteCameraOn)
                const Center(child: _RemoteCameraOffNotice()),
              if (!_controlsVisible)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 52,
                  child: IgnorePointer(child: _TapForControlsHint()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceCall() {
    final connected = widget.session.status == 'active';
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.midnightInk,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF07172F), Color(0xFF0D47A1), Color(0xFF2457F5)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              child: Column(
                children: [
                  _CallHeader(
                    name: widget.contactName,
                    state: widget.session.stateLabel,
                    quality: widget.session.connectionQuality,
                    showName: false,
                    onMinimise: _minimise,
                  ),
                  if (widget.session.status == 'reconnecting')
                    const _ReconnectingBanner(),
                  const Spacer(),
                  _ProfileAvatar(
                    name: widget.contactName,
                    photoUrl: widget.contactPhotoUrl,
                    size: 160,
                    glowing: connected,
                  ),
                  const SizedBox(height: 26),
                  Text(
                    widget.contactName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    connected ? _durationLabel : widget.session.stateLabel,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 17,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  _ControlsPanel(
                    children: [
                      _CallControl(
                        label: _isMuted ? 'Unmute' : 'Mute',
                        icon: _isMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        selected: _isMuted,
                        onTap: _toggleMute,
                      ),
                      _CallControl(
                        label: _speakerEnabled ? 'Speaker on' : 'Speaker',
                        icon: _speakerEnabled
                            ? Icons.volume_up_rounded
                            : Icons.volume_down_rounded,
                        selected: _speakerEnabled,
                        onTap: () => unawaited(_toggleSpeaker()),
                      ),
                      _CallControl(
                        label: 'Add 2/5',
                        icon: Icons.person_add_alt_1_rounded,
                        loading: _upgrading,
                        onTap: _addParticipants,
                      ),
                      _CallControl(
                        label: 'End',
                        icon: Icons.call_end_rounded,
                        danger: true,
                        onTap: _endCall,
                      ),
                    ],
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

class _CallHeader extends StatelessWidget {
  const _CallHeader({
    required this.name,
    required this.state,
    required this.quality,
    required this.onMinimise,
    this.duration,
    this.showName = true,
  });
  final String name;
  final String state;
  final String quality;
  final VoidCallback onMinimise;
  final String? duration;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final qualityColor = quality == 'Good'
        ? AppColors.success
        : quality == 'Fair'
        ? AppColors.warning
        : quality == 'Poor'
        ? AppColors.danger
        : Colors.white54;
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: qualityColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: qualityColor.withValues(alpha: .45),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showName)
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              Text(
                '${showName ? state : 'Voice call'}${duration == null ? '' : ' • $duration'} • $quality connection',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Minimise call',
          onPressed: onMinimise,
          icon: const Icon(
            Icons.picture_in_picture_alt_rounded,
            color: Colors.white,
          ),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white12,
            minimumSize: const Size(48, 48),
          ),
        ),
      ],
    );
  }
}

class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: .18),
      border: Border.all(color: AppColors.warning.withValues(alpha: .45)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.warning,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Connection interrupted. Reconnecting automatically…',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RemoteCameraOffNotice extends StatelessWidget {
  const _RemoteCameraOffNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xDE0A1D38),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white24),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.videocam_off_rounded, color: Colors.white70),
        SizedBox(width: 8),
        Text(
          'Their camera is off',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _TapForControlsHint extends StatelessWidget {
  const _TapForControlsHint();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Tap anywhere for call controls',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _ControlsPanel extends StatelessWidget {
  const _ControlsPanel({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(30),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .12),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceEvenly,
          runAlignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 8,
          children: children,
        ),
      ),
    ),
  );
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.danger = false,
    this.loading = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final bool danger;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final background = danger
        ? AppColors.danger
        : selected
        ? Colors.white
        : Colors.white.withValues(alpha: .14);
    final foreground = selected && !danger
        ? AppColors.midnightInk
        : Colors.white;
    return Semantics(
      button: true,
      toggled: selected,
      label: label,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: 66,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(icon, color: foreground),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
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

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.name,
    this.photoUrl,
    required this.size,
    this.glowing = false,
  });
  final String name;
  final String? photoUrl;
  final double size;
  final bool glowing;

  @override
  Widget build(BuildContext context) {
    final photo = photoUrl?.trim() ?? '';
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final initials = words.take(2).map((word) => word[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppStyles.brandGradient,
        boxShadow: glowing
            ? [
                BoxShadow(
                  color: AppColors.electricCyan.withValues(alpha: .28),
                  blurRadius: 42,
                  spreadRadius: 8,
                ),
              ]
            : null,
      ),
      child: CircleAvatar(
        backgroundColor: const Color(0xFF0D47A1),
        backgroundImage: photo.isEmpty
            ? null
            : CachedNetworkImageProvider(photo),
        child: photo.isEmpty
            ? Text(
                initials.isEmpty ? 'OG' : initials,
                style: TextStyle(
                  fontSize: size * .3,
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              )
            : null,
      ),
    );
  }
}

class _ConnectingState extends StatelessWidget {
  const _ConnectingState({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(gradient: AppStyles.brandGradient),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProfileAvatar(name: name, size: 118),
          const SizedBox(height: 22),
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          const Text(
            'Connecting video…',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class _MinimisedCallBubble extends StatefulWidget {
  const _MinimisedCallBubble({
    required this.session,
    required this.name,
    required this.photoUrl,
    required this.onOpen,
    required this.onRemove,
  });
  final CallSession session;
  final String name;
  final String? photoUrl;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  @override
  State<_MinimisedCallBubble> createState() => _MinimisedCallBubbleState();
}

class _MinimisedCallBubbleState extends State<_MinimisedCallBubble> {
  Offset? _position;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  void _changed() {
    if (widget.session.status == 'ended') {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onRemove());
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    super.dispose();
  }

  void _move(DragUpdateDetails details) {
    final size = MediaQuery.sizeOf(context);
    final current =
        _position ?? Offset(size.width - 222, MediaQuery.paddingOf(context).top + 14);
    setState(() {
      _position = Offset(
        (current.dx + details.delta.dx).clamp(8.0, size.width - 112.0).toDouble(),
        (current.dy + details.delta.dy)
            .clamp(MediaQuery.paddingOf(context).top + 8, size.height - 100)
            .toDouble(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final defaultPosition = Offset(
      size.width - 222,
      MediaQuery.paddingOf(context).top + 14,
    );
    final position = _position ?? defaultPosition;
    return Positioned(
      left: position.dx.clamp(8.0, size.width - 112.0).toDouble(),
      top: position.dy
          .clamp(MediaQuery.paddingOf(context).top + 8, size.height - 100)
          .toDouble(),
      child: Material(
      color: Colors.transparent,
      child: Semantics(
        button: true,
        label: 'Return to call with ${widget.name}',
        child: GestureDetector(
          onTap: widget.onOpen,
          onPanUpdate: _move,
          child: Container(
            padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
            decoration: BoxDecoration(
              color: const Color(0xF20A1D38),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: AppColors.electricCyan.withValues(alpha: .55),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ProfileAvatar(
                  name: widget.name,
                  photoUrl: widget.photoUrl,
                  size: 44,
                  glowing: true,
                ),
                const SizedBox(width: 9),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      widget.session.stateLabel,
                      style: const TextStyle(
                        color: AppColors.electricCyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
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

class _CallPeoplePicker extends StatefulWidget {
  const _CallPeoplePicker({required this.people});
  final List<Map<String, dynamic>> people;
  @override
  State<_CallPeoplePicker> createState() => _CallPeoplePickerState();
}

class _CallPeoplePickerState extends State<_CallPeoplePicker> {
  final Set<String> selected = {};
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Column(
        children: [
          const ListTile(
            title: Text(
              'Add people',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              'Choose up to 3 friends. This call can have 5 people in total.',
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.people.length,
              itemBuilder: (_, index) {
                final person = widget.people[index];
                final id = person['id'].toString();
                final name = person['nickname']?.toString().trim();
                final photo = person['photo_url']?.toString();
                final checked = selected.contains(id);
                return CheckboxListTile(
                  value: checked,
                  secondary: _ProfileAvatar(
                    name: name?.isNotEmpty == true ? name! : 'Student',
                    photoUrl: photo,
                    size: 46,
                  ),
                  title: Text(
                    name?.isNotEmpty == true ? name! : 'Student',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(checked ? 'Selected' : 'Tap to add'),
                  onChanged: (value) {
                    if (value == true && selected.length >= 3) return;
                    setState(
                      () => value == true
                          ? selected.add(id)
                          : selected.remove(id),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected.toList()),
              icon: const Icon(Icons.group_add_rounded),
              label: Text('Start group call (${selected.length + 2}/5)'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
