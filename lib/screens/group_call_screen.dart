import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/group_call_service.dart';
import '../utils/theme_constants.dart';

class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({super.key, required this.session});

  final GroupCallSession session;

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  bool _muted = false;
  bool _cameraEnabled = true;
  bool _ready = false;
  Timer? _timer;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
    unawaited(_prepareRenderers());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _duration += const Duration(seconds: 1));
    });
  }

  Future<void> _prepareRenderers() async {
    await _localRenderer.initialize();
    _localRenderer.srcObject = widget.session.localStream;
    await _syncRemoteRenderers();
    if (mounted) setState(() => _ready = true);
  }

  void _sessionChanged() {
    unawaited(_syncRemoteRenderers());
    if (mounted) setState(() {});
  }

  Future<void> _syncRemoteRenderers() async {
    for (final entry in widget.session.remoteStreams.entries) {
      final renderer = _remoteRenderers[entry.key] ?? RTCVideoRenderer();
      if (!_remoteRenderers.containsKey(entry.key)) {
        await renderer.initialize();
        _remoteRenderers[entry.key] = renderer;
      }
      renderer.srcObject = entry.value;
    }
    for (final id in _remoteRenderers.keys.toList()) {
      if (!widget.session.remoteStreams.containsKey(id)) {
        await _remoteRenderers.remove(id)?.dispose();
      }
    }
    if (mounted) setState(() {});
  }

  String _name(String userId) {
    if (userId == widget.session.currentUserId) return 'You';
    final nickname = widget.session.participantProfiles[userId]?['nickname']
        ?.toString()
        .trim();
    return nickname?.isNotEmpty == true ? nickname! : 'Student';
  }

  String? _photo(String userId) =>
      widget.session.participantProfiles[userId]?['photo_url']?.toString();

  Future<void> _leave() async {
    var endForEveryone = false;
    if (widget.session.isStarter) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Leave call'),
                subtitle: const Text('The other students can keep talking.'),
                onTap: () => Navigator.pop(context, 'leave'),
              ),
              ListTile(
                leading: const Icon(Icons.call_end_rounded, color: Colors.red),
                title: const Text('End call for everyone'),
                onTap: () => Navigator.pop(context, 'end'),
              ),
            ],
          ),
        ),
      );
      if (choice == null) return;
      endForEveryone = choice == 'end';
    }
    await widget.session.leave(endForEveryone: endForEveryone);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final joined = widget.session.participantStatuses.entries
        .where((entry) => entry.value == 'joined')
        .map((entry) => entry.key)
        .toList();
    if (!joined.contains(widget.session.currentUserId)) {
      joined.insert(0, widget.session.currentUserId);
    }
    final minutes = _duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (_duration.inSeconds % 60).toString().padLeft(2, '0');
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppColors.midnightInk,
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF06152D),
                  Color(0xFF123D78),
                  Color(0xFF075E76),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_rounded,
                          color: Colors.white70,
                          size: 17,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.session.groupName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              Text(
                                '$minutes:$seconds • ${joined.length}/5 connected',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            widget.session.isVideo ? 'VIDEO' : 'VOICE',
                            style: const TextStyle(
                              color: AppColors.electricCyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: widget.session.isVideo
                        ? _buildVideoGrid(joined)
                        : _buildVoiceStage(joined),
                  ),
                  _buildControls(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoGrid(List<String> joined) {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 800 ? 3 : 2;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: width >= 800 ? 1.35 : .78,
      ),
      itemCount: joined.length,
      itemBuilder: (_, index) {
        final id = joined[index];
        final renderer = id == widget.session.currentUserId
            ? _localRenderer
            : _remoteRenderers[id];
        return _VideoTile(
          name: _name(id),
          renderer: renderer,
          photoUrl: _photo(id),
          mirrored: id == widget.session.currentUserId,
        );
      },
    );
  }

  Widget _buildVoiceStage(List<String> joined) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 24,
          runSpacing: 26,
          children: joined.map((id) {
            final photo = _photo(id)?.trim() ?? '';
            return SizedBox(
              width: 124,
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppStyles.brandGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.electricCyan.withValues(alpha: .22),
                          blurRadius: 30,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      backgroundColor: Colors.white12,
                      backgroundImage: photo.isEmpty
                          ? null
                          : CachedNetworkImageProvider(photo),
                      child: photo.isEmpty
                          ? Text(
                              _name(id)[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _name(id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _RoundCallAction(
                  label: _muted ? 'Unmute' : 'Mute',
                  icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  selected: _muted,
                  onTap: () {
                    setState(() => _muted = !_muted);
                    widget.session.setMuted(_muted);
                  },
                ),
                if (widget.session.isVideo)
                  _RoundCallAction(
                    label: _cameraEnabled ? 'Camera' : 'Camera off',
                    icon: _cameraEnabled
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                    selected: !_cameraEnabled,
                    onTap: () {
                      setState(() => _cameraEnabled = !_cameraEnabled);
                      widget.session.setCameraEnabled(_cameraEnabled);
                    },
                  ),
                if (widget.session.isVideo)
                  _RoundCallAction(
                    label: 'Flip',
                    icon: Icons.cameraswitch_rounded,
                    onTap: widget.session.switchCamera,
                  ),
                _RoundCallAction(
                  label: 'Leave',
                  icon: Icons.call_end_rounded,
                  danger: true,
                  onTap: _leave,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.session.removeListener(_sessionChanged);
    _localRenderer.dispose();
    for (final renderer in _remoteRenderers.values) {
      renderer.dispose();
    }
    super.dispose();
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.name,
    required this.renderer,
    required this.photoUrl,
    required this.mirrored,
  });
  final String name;
  final RTCVideoRenderer? renderer;
  final String? photoUrl;
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    final hasVideo = renderer?.srcObject?.getVideoTracks().isNotEmpty == true;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black38),
          if (hasVideo)
            RTCVideoView(
              renderer!,
              mirror: mirrored,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            Center(
              child: CircleAvatar(
                radius: 38,
                backgroundImage: (photoUrl?.isNotEmpty ?? false)
                    ? CachedNetworkImageProvider(photoUrl!)
                    : null,
                child: (photoUrl?.isEmpty ?? true)
                    ? Text(
                        name[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : null,
              ),
            ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 9,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundCallAction extends StatelessWidget {
  const _RoundCallAction({
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
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: danger
                    ? Colors.red
                    : selected
                    ? Colors.white
                    : Colors.white12,
              ),
              child: Icon(
                icon,
                color: danger || !selected
                    ? Colors.white
                    : AppColors.midnightInk,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
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
