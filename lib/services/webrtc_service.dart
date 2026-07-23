import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ice_servers.dart';

class WebRtcService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  Future<MediaStream> createLocalMediaStream({bool video = true}) async {
    final cameraStatus = video ? await Permission.camera.request() : PermissionStatus.granted;
    final micStatus = await Permission.microphone.request();

    if (cameraStatus != PermissionStatus.granted || micStatus != PermissionStatus.granted) {
      throw Exception('Camera or microphone permission was denied.');
    }

    return await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
  }

  Future<RTCPeerConnection> createPeer({
    required void Function(RTCIceCandidate candidate) onIceCandidate,
    required void Function(MediaStream stream) onTrack,
    required void Function(String state) onConnectionStateChange,
  }) async {
    final configuration = await IceServers.fetch();

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (candidate) => onIceCandidate(candidate);
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        onTrack(_remoteStream!);
      }
    };
    _peerConnection!.onConnectionState = (state) => onConnectionStateChange(state.name);

    return _peerConnection!;
  }

  Future<RTCSessionDescription> createOffer() async {
    final pc = _peerConnection!;
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer({required RTCSessionDescription offer}) async {
    final pc = _peerConnection!;
    await pc.setRemoteDescription(offer);
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    await _peerConnection!.setRemoteDescription(description);
  }

  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await _peerConnection!.addCandidate(candidate);
  }

  Future<void> attachLocalStream(MediaStream stream) async {
    _localStream = stream;
    for (final track in stream.getTracks()) {
      await _peerConnection!.addTrack(track, stream);
    }
  }

  void dispose() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.close();
    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
  }
}
