import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key, required this.localStream, required this.remoteStream, required this.onEnd});

  final MediaStream? localStream;
  final MediaStream? remoteStream;
  final VoidCallback onEnd;

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _initializeRenderers();
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (!mounted) return;
    if (widget.localStream != null) {
      await _localRenderer.setSrcObject(stream: widget.localStream);
    }
    if (widget.remoteStream != null) {
      await _remoteRenderer.setSrcObject(stream: widget.remoteStream);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Active call')),
      body: Stack(
        children: [
          if (widget.remoteStream != null)
            Positioned.fill(
              child: RTCVideoView(_remoteRenderer),
            )
          else
            const Center(child: Text('Connecting…')),
          Positioned(
            right: 16,
            top: 16,
            width: 120,
            height: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: widget.localStream != null
                  ? RTCVideoView(_localRenderer)
                  : Container(color: Colors.black54),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  heroTag: 'mute',
                  onPressed: () {},
                  child: const Icon(Icons.mic_off),
                ),
                const SizedBox(width: 16),
                FloatingActionButton(
                  heroTag: 'end',
                  onPressed: widget.onEnd,
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.call_end),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
