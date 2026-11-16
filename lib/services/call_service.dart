import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'offline_data_adapter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'push_notification_service.dart';
import 'feature_flag_service.dart';

class CallService {
  CallService._({OfflineDataClient? client})
    : _client = client ?? OfflineData.instance.client;

  static final CallService instance = CallService._();
  factory CallService({OfflineDataClient? client}) =>
      client == null ? instance : CallService._(client: client);

  final OfflineDataClient _client;
  OfflineRealtimeChannel? _incomingChannel;

  Future<CallSession> startCall(String calleeId, {required String type}) async {
    final availability = await FeatureFlagService.availability(
      'calls',
      client: _client,
      forceRefresh: true,
    );
    if (!availability.enabled) throw StateError(availability.message);
    final callerId = _requireUser();
    if (callerId == calleeId) throw StateError('You cannot call yourself.');
    final call = Map<String, dynamic>.from(
      await _client
          .from('calls')
          .insert({
            'caller_id': callerId,
            'callee_id': calleeId,
            'type': type,
            'status': 'ringing',
            'started_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select()
          .single(),
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
    final rows = await _client
        .from('calls')
        .select()
        .eq('callee_id', userId)
        .eq('status', 'ringing')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('started_at', ascending: false)
        .limit(1);
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
    var query = _client
        .from('calls')
        .update({
          'status': status,
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', callId);
    if (ringingOnly) query = query.eq('status', 'ringing');
    await query;
  }

  OfflineRealtimeChannel listenForIncomingCalls({
    required String currentUserId,
    required void Function(Map<String, dynamic> call) onIncoming,
  }) {
    _incomingChannel?.unsubscribe();
    _incomingChannel = _client.channel('incoming-calls:$currentUserId')
      ..onPostgresChanges(
        event: OfflinePostgresChangeEvent.insert,
        schema: 'public',
        table: 'calls',
        filter: OfflinePostgresChangeFilter(
          type: OfflinePostgresChangeFilterType.eq,
          column: 'callee_id',
          value: currentUserId,
        ),
        callback: (payload) {
          final expiresAt = DateTime.tryParse(
            payload.newRecord['expires_at']?.toString() ?? '',
          );
          if (payload.newRecord['status'] == 'ringing' &&
              (expiresAt == null || expiresAt.isAfter(DateTime.now()))) {
            onIncoming(Map<String, dynamic>.from(payload.newRecord));
          }
        },
      )
      ..subscribe();
    return _incomingChannel!;
  }

  Future<List<dynamic>> _iceServers() async {
    const fallback = <Map<String, dynamic>>[
      {
        'urls': ['stun:stun.l.google.com:19302'],
      },
      {
        'urls': ['stun:stun1.l.google.com:19302'],
      },
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
    required OfflineDataClient client,
    required Map<String, dynamic> call,
    required String currentUserId,
    required bool isCaller,
    required List<dynamic> iceServers,
  }) : _client = client,
       _call = call,
       _currentUserId = currentUserId,
       _isCaller = isCaller,
       _iceServers = iceServers;

  final OfflineDataClient _client;
  final Map<String, dynamic> _call;
  final String _currentUserId;
  final bool _isCaller;
  final List<dynamic> _iceServers;
  final Set<int> _handledSignals = {};
  final List<RTCIceCandidate> _pendingCandidates = [];
  RTCPeerConnection? _peerConnection;
  OfflineRealtimeChannel? _channel;
  bool _remoteDescriptionReady = false;
  bool _closed = false;
  bool _restartInProgress = false;
  Timer? _qualityTimer;
  Timer? _expiryTimer;
  int? _lastPacketsLost;
  int? _lastPacketsReceived;

  MediaStream? localStream;
  MediaStream? remoteStream;
  String status = 'connecting';
  String connectionQuality = 'Checking';
  DateTime? connectedAt;

  String get callId => _call['id'].toString();
  String get type => _call['type']?.toString() ?? 'audio';
  bool get isVideo => type == 'video';
  Duration get elapsed => connectedAt == null
      ? Duration.zero
      : DateTime.now().difference(connectedAt!);
  DateTime? get expiresAt =>
      DateTime.tryParse(_call['expires_at']?.toString() ?? '')?.toLocal();
  String get currentUserId => _currentUserId;
  String get otherUserId =>
      (_call['caller_id']?.toString() == _currentUserId
              ? _call['callee_id']
              : _call['caller_id'])
          .toString();

  String get stateLabel => switch (status) {
    'ringing' => 'Calling',
    'active' => 'Connected',
    'reconnecting' => 'Reconnecting',
    'declined' => 'Call declined',
    'cancelled' => 'Call cancelled',
    'missed' => 'Missed call',
    'ended' => 'Call ended',
    _ => 'Connecting',
  };

  Future<void> initialise() async {
    await WakelockPlus.enable();
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
    if (isVideo && localStream!.getVideoTracks().isEmpty) {
      throw StateError(
        'The camera did not provide a video track. Check camera permission and try again.',
      );
    }
    _peerConnection = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    });
    for (final track in localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, localStream!);
    }
    final peerConnection = _peerConnection!;
    peerConnection.onTrack = (event) => unawaited(_attachRemoteTrack(event));
    peerConnection.onIceCandidate = (candidate) {
      if (candidate.candidate == null || _closed) return;
      unawaited(
        _sendSignal('ice', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }),
      );
    };
    peerConnection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        status = 'active';
        connectedAt ??= DateTime.now();
        _restartInProgress = false;
        unawaited(_measureConnectionQuality());
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        status = 'reconnecting';
        connectionQuality = 'Poor';
        unawaited(_restartConnection());
      }
      notifyListeners();
    };
    _subscribe();
    await _loadSignals();
    _qualityTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_measureConnectionQuality()),
    );
    _scheduleExpiryTimer();
  }

  void _scheduleExpiryTimer() {
    _expiryTimer?.cancel();
    final expiry = expiresAt;
    if (expiry == null || status != 'ringing') return;
    final delay = expiry.difference(DateTime.now());
    if (delay <= Duration.zero) {
      unawaited(_expireIfStillRinging());
      return;
    }
    _expiryTimer = Timer(delay, () => unawaited(_expireIfStillRinging()));
  }

  Future<void> _expireIfStillRinging() async {
    if (_closed || status != 'ringing') return;
    try {
      await _client
          .from('calls')
          .update({
            'status': _isCaller ? 'cancelled' : 'missed',
            'ended_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', callId)
          .eq('status', 'ringing')
          .lte('expires_at', DateTime.now().toUtc().toIso8601String());
    } finally {
      if (!_closed) await disposeSession();
    }
  }

  Future<void> _restartConnection() async {
    if (_closed ||
        !_isCaller ||
        _restartInProgress ||
        _peerConnection == null) {
      return;
    }
    _restartInProgress = true;
    try {
      final offer = await _peerConnection!.createOffer({'iceRestart': true});
      await _peerConnection!.setLocalDescription(offer);
      await _sendSignal('offer', {'sdp': offer.sdp, 'type': offer.type});
    } catch (error) {
      debugPrint('Call reconnection attempt failed: $error');
    } finally {
      Future<void>.delayed(const Duration(seconds: 5), () {
        _restartInProgress = false;
      });
    }
  }

  Future<void> _measureConnectionQuality() async {
    if (_closed || status != 'active' || _peerConnection == null) return;
    try {
      final reports = await _peerConnection!.getStats();
      var packetsLost = 0;
      var packetsReceived = 0;
      var worstJitter = 0.0;
      var worstRtt = 0.0;
      for (final report in reports) {
        final values = report.values;
        if (report.type == 'inbound-rtp' && values['isRemote'] != true) {
          packetsLost += _asInt(values['packetsLost']);
          packetsReceived += _asInt(values['packetsReceived']);
          worstJitter = _max(worstJitter, _asDouble(values['jitter']));
        }
        if (report.type == 'candidate-pair' &&
            (values['selected'] == true || values['nominated'] == true)) {
          worstRtt = _max(worstRtt, _asDouble(values['currentRoundTripTime']));
        }
        if (report.type == 'remote-inbound-rtp') {
          worstRtt = _max(worstRtt, _asDouble(values['roundTripTime']));
        }
      }
      final lostDelta = _lastPacketsLost == null
          ? 0
          : (packetsLost - _lastPacketsLost!).clamp(0, 1 << 30);
      final receivedDelta = _lastPacketsReceived == null
          ? 0
          : (packetsReceived - _lastPacketsReceived!).clamp(0, 1 << 30);
      _lastPacketsLost = packetsLost;
      _lastPacketsReceived = packetsReceived;
      final totalDelta = lostDelta + receivedDelta;
      final lossRate = totalDelta == 0 ? 0.0 : lostDelta / totalDelta;
      final nextQuality =
          lossRate >= .08 || worstJitter >= .08 || worstRtt >= .7
          ? 'Poor'
          : lossRate >= .03 || worstJitter >= .04 || worstRtt >= .35
          ? 'Fair'
          : 'Good';
      if (connectionQuality != nextQuality) {
        connectionQuality = nextQuality;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Unable to read call quality: $error');
    }
  }

  static int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  static double _asDouble(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  static double _max(double first, double second) =>
      first > second ? first : second;

  Future<void> _attachRemoteTrack(RTCTrackEvent event) async {
    if (_closed) return;

    if (event.streams.isNotEmpty) {
      remoteStream = event.streams.first;
    } else {
      // Unified Plan is allowed to deliver a track without an associated
      // stream. Build one so RTCVideoRenderer receives both audio and video on
      // Android and web instead of silently discarding the track.
      final stream =
          remoteStream ?? await createLocalMediaStream('remote-$callId');
      final trackId = event.track.id;
      if (trackId == null || stream.getTrackById(trackId) == null) {
        await stream.addTrack(event.track);
      }
      remoteStream = stream;
    }

    status = 'active';
    connectedAt ??= DateTime.now();
    notifyListeners();
  }

  void _subscribe() {
    _channel = _client.channel('call:$callId')
      ..onPostgresChanges(
        event: OfflinePostgresChangeEvent.insert,
        schema: 'public',
        table: 'call_signals',
        filter: OfflinePostgresChangeFilter(
          type: OfflinePostgresChangeFilterType.eq,
          column: 'call_id',
          value: callId,
        ),
        callback: (payload) => unawaited(_handleSignal(payload.newRecord)),
      )
      ..onPostgresChanges(
        event: OfflinePostgresChangeEvent.update,
        schema: 'public',
        table: 'calls',
        filter: OfflinePostgresChangeFilter(
          type: OfflinePostgresChangeFilterType.eq,
          column: 'id',
          value: callId,
        ),
        callback: (payload) {
          final next = payload.newRecord['status']?.toString();
          if (next == null) return;
          status = next;
          notifyListeners();
          if (const {
            'declined',
            'cancelled',
            'missed',
            'ended',
          }.contains(next)) {
            unawaited(disposeSession());
          } else if (next == 'active') {
            _expiryTimer?.cancel();
          }
        },
      )
      ..subscribe();
  }

  Future<void> _loadSignals() async {
    final rows = await _client
        .from('call_signals')
        .select()
        .eq('call_id', callId)
        .order('id');
    for (final row in List<Map<String, dynamic>>.from(rows as List<dynamic>)) {
      await _handleSignal(row);
    }
  }

  Future<void> createOffer() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await _sendSignal('offer', {'sdp': offer.sdp, 'type': offer.type});
    status = 'ringing';
    _scheduleExpiryTimer();
    notifyListeners();
  }

  Future<void> accept() async {
    await _loadSignals();
    if (!_remoteDescriptionReady) {
      throw StateError('The caller has not finished connecting. Try again.');
    }
    final accepted = await _client
        .from('calls')
        .update({
          'status': 'active',
          'answered_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', callId)
        .eq('callee_id', _currentUserId)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .select('id')
        .maybeSingle();
    if (accepted == null) {
      throw StateError('This call invitation has expired.');
    }
    _expiryTimer?.cancel();
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
          await _sendSignal('answer', {'sdp': answer.sdp, 'type': answer.type});
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

  Future<void> setSpeakerEnabled(bool enabled) =>
      Helper.setSpeakerphoneOn(enabled);

  Future<void> end() async {
    if (!_closed) {
      await _client
          .from('calls')
          .update({
            'status': 'ended',
            'ended_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', callId);
    }
    await disposeSession();
  }

  Future<void> disposeSession() async {
    if (_closed) return;
    _closed = true;
    _qualityTimer?.cancel();
    _expiryTimer?.cancel();
    await WakelockPlus.disable();
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
