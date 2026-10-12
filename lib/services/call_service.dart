import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_notification_service.dart';

class CallService {
  CallService._({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static final CallService instance = CallService._();
  factory CallService({SupabaseClient? client}) =>
      client == null ? instance : CallService._(client: client);

  final SupabaseClient _client;
  RealtimeChannel? _incomingChannel;

  Future<CallSession> startCall(String calleeId, {required String type}) async {
    final callerId = _requireUser();
    if (callerId == calleeId) throw StateError('You cannot call yourself.');
    final call = Map<String, dynamic>.from(
      await _client.from('calls').insert({
        'caller_id': callerId,
        'callee_id': calleeId,
        'type': type,
        'status': 'ringing',
        'started_at': DateTime.now().toUtc().toIso8601String(),
      }).select().single(),
    );
    final session = CallSession._(
      client: _client,
      call: call,
      currentUserId: callerId,
      isCaller: true,
      iceServers: await _iceServers(),
    );
    try {
      await session.initialise();
      await session.createOffer();
      try {
        await PushNotificationService.sendIncomingCall(session.callId);
      } catch (error) {
        // Realtime still rings an online in-app recipient when push is
        // temporarily unavailable or has not yet been configured server-side.
        debugPrint('Unable to send incoming-call push: $error');
      }
      return session;
    } catch (_) {
      await cancelCall(call['id'].toString());
      await session.disposeSession();
      rethrow;
    }
  }

  Future<CallSession> acceptIncomingCall(Map<String, dynamic> call) async {
    final userId = _requireUser();
    if (call['callee_id']?.toString() != userId) {
      throw StateError('This call belongs to another user.');
    }
    final session = CallSession._(
      client: _client,
      call: call,
      currentUserId: userId,
      isCaller: false,
      iceServers: await _iceServers(),
    );
    try {
      await session.initialise();
      await session.accept();
      return session;
    } catch (_) {
      await session.disposeSession();
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> pendingIncomingCalls() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _client.from('calls').select().eq(
      'callee_id', userId,
    ).eq('status', 'ringing').order('started_at', ascending: false).limit(1);
    return List<Map<String, dynamic>>.from(rows as List<dynamic>);
  }

  Future<void> declineCall(String callId) => _finish(callId, 'declined');
  Future<void> cancelCall(String callId) => _finish(callId, 'cancelled');
  Future<void> markMissed(String callId) =>
      _finish(callId, 'missed', ringingOnly: true);

  Future<void> _finish(
    String callId,
    String status, {
    bool ringingOnly = false,
  }) async {
    var query = _client.from('calls').update({
      'status': status,
      'ended_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', callId);
    if (ringingOnly) query = query.eq('status', 'ringing');
    await query;
  }

  RealtimeChannel listenForIncomingCalls({
    required String currentUserId,
    required void Function(Map<String, dynamic> call) onIncoming,
  }) {
    _incomingChannel?.unsubscribe();
    _incomingChannel = _client.channel('incoming-calls:$currentUserId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'calls',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'callee_id',
          value: currentUserId,
        ),
        callback: (payload) {
          if (payload.newRecord['status'] == 'ringing') {
            onIncoming(Map<String, dynamic>.from(payload.newRecord));
          }
        },
      )
      ..subscribe();
    return _incomingChannel!;
  }

  Future<List<dynamic>> _iceServers() async {
    const fallback = <Map<String, dynamic>>[
      {'urls': ['stun:stun.l.google.com:19302']},
      {'urls': ['stun:stun1.l.google.com:19302']},
    ];
    try {
      final response = await _client.functions.invoke('get-turn-credentials');
      final data = response.data;
      if (data is Map && data['iceServers'] is List) {
        final servers = List<dynamic>.from(data['iceServers'] as List);
        if (servers.isNotEmpty) return servers;
      }
    } catch (_) {}
    return fallback;
  }

  String _requireUser() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Sign in before starting a call.');
    return id;
  }

  void dispose() {
    _incomingChannel?.unsubscribe();
    _incomingChannel = null;
  }
}

class CallSession extends ChangeNotifier {
  CallSession._({
    required SupabaseClient client,
    required Map<String, dynamic> call,
    required String currentUserId,
    required bool isCaller,
    required List<dynamic> iceServers,
  })  : _client = client,
        _call = call,
        _currentUserId = currentUserId,
        _isCaller = isCaller,
        _iceServers = iceServers;

  final SupabaseClient _client;
  final Map<String, dynamic> _call;
  final String _currentUserId;
  final bool _isCaller;
  final List<dynamic> _iceServers;
  final Set<int> _handledSignals = {};
  final List<RTCIceCandidate> _pendingCandidates = [];
  RTCPeerConnection? _peerConnection;
  RealtimeChannel? _channel;
  bool _remoteDescriptionReady = false;
  bool _closed = false;

  MediaStream? localStream;
  MediaStream? remoteStream;
  String status = 'connecting';

  String get callId => _call['id'].toString();
  String get type => _call['type']?.toString() ?? 'audio';
  bool get isVideo => type == 'video';

  Future<void> initialise() async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
              'frameRate': {'ideal': 24, 'max': 30},
            }
          : false,
    });
    _peerConnection = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    });
    for (final track in localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, localStream!);
    }
    _peerConnection!
      ..onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteStream = event.streams.first;
          status = 'active';
          notifyListeners();
        }
      }
      ..onIceCandidate = (candidate) {
        if (candidate.candidate == null || _closed) return;
        unawaited(_sendSignal('ice', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }));
      }
      ..onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          status = 'active';
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          status = 'reconnecting';
        }
        notifyListeners();
      };
    _subscribe();
    await _loadSignals();
  }

  void _subscribe() {
    _channel = _client.channel('call:$callId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'call_signals',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'call_id',
          value: callId,
        ),
        callback: (payload) => unawaited(_handleSignal(payload.newRecord)),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'calls',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: callId,
        ),
        callback: (payload) {
          final next = payload.newRecord['status']?.toString();
          if (next == null) return;
          status = next;
          notifyListeners();
          if (const {'declined', 'cancelled', 'missed', 'ended'}.contains(next)) {
            unawaited(disposeSession());
          }
        },
      )
      ..subscribe();
  }

  Future<void> _loadSignals() async {
    final rows = await _client.from('call_signals').select().eq(
      'call_id', callId,
    ).order('id');
    for (final row in List<Map<String, dynamic>>.from(rows as List<dynamic>)) {
      await _handleSignal(row);
    }
  }

  Future<void> createOffer() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await _sendSignal('offer', {'sdp': offer.sdp, 'type': offer.type});
    status = 'ringing';
    notifyListeners();
  }

  Future<void> accept() async {
    await _loadSignals();
    if (!_remoteDescriptionReady) {
      throw StateError('The caller has not finished connecting. Try again.');
    }
    await _client.from('calls').update({
      'status': 'active',
      'answered_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', callId).eq('callee_id', _currentUserId);
  }

  Future<void> _handleSignal(Map<String, dynamic> signal) async {
    final id = int.tryParse(signal['id']?.toString() ?? '');
    if (id != null && !_handledSignals.add(id)) return;
    if (signal['sender_id']?.toString() == _currentUserId) return;
    final payload = Map<String, dynamic>.from(signal['payload'] as Map? ?? {});
    switch (signal['kind']?.toString()) {
      case 'offer':
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(payload['sdp']?.toString(), 'offer'),
        );
        _remoteDescriptionReady = true;
        await _flushCandidates();
        if (!_isCaller) {
          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          await _sendSignal('answer', {
            'sdp': answer.sdp,
            'type': answer.type,
          });
        }
        break;
      case 'answer':
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(payload['sdp']?.toString(), 'answer'),
        );
        _remoteDescriptionReady = true;
        await _flushCandidates();
        break;
      case 'ice':
        final candidate = RTCIceCandidate(
          payload['candidate']?.toString(),
          payload['sdpMid']?.toString(),
          payload['sdpMLineIndex'] as int?,
        );
        if (_remoteDescriptionReady) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _pendingCandidates.add(candidate);
        }
    }
  }

  Future<void> _flushCandidates() async {
    for (final candidate in _pendingCandidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  Future<void> _sendSignal(String kind, Map<String, dynamic> payload) async {
    await _client.from('call_signals').insert({
      'call_id': callId,
      'sender_id': _currentUserId,
      'kind': kind,
      'payload': payload,
    });
  }

  void setMuted(bool muted) {
    for (final track in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  void setCameraEnabled(bool enabled) {
    for (final track in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    final tracks = localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> end() async {
    if (!_closed) {
      await _client.from('calls').update({
        'status': 'ended',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', callId);
    }
    await disposeSession();
  }

  Future<void> disposeSession() async {
    if (_closed) return;
    _closed = true;
    for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await localStream?.dispose();
    await remoteStream?.dispose();
    await _peerConnection?.close();
    if (_channel != null) await _client.removeChannel(_channel!);
    status = 'ended';
    notifyListeners();
  }
}
