import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'push_notification_service.dart';
import 'feature_flag_service.dart';

class GroupCallInvite {
  const GroupCallInvite({
    required this.call,
    required this.groupName,
    required this.callerName,
    this.callerPhotoUrl,
  });

  final Map<String, dynamic> call;
  final String groupName;
  final String callerName;
  final String? callerPhotoUrl;
  String get callId => call['id'].toString();
  String get callType => call['call_type']?.toString() ?? 'audio';
}

class GroupCallService {
  GroupCallService._({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static final GroupCallService instance = GroupCallService._();
  final SupabaseClient _client;
  RealtimeChannel? _incomingChannel;

  Future<List<Map<String, dynamic>>> availableCallPeople({
    required String excludingUserId,
  }) async {
    final userId = _requireUser();
    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('friendships')
              .select('user_id,friend_id')
              .or('user_id.eq.$userId,friend_id.eq.$userId')
          as List<dynamic>,
    );
    final ids = rows
        .map(
          (row) => row['user_id']?.toString() == userId
              ? row['friend_id']?.toString()
              : row['user_id']?.toString(),
        )
        .whereType<String>()
        .where((id) => id.isNotEmpty && id != excludingUserId)
        .toSet()
        .toList();
    if (ids.isEmpty) return const [];
    final profiles = List<Map<String, dynamic>>.from(
      await _client
              .from('profiles')
              .select('id,nickname,photo_url')
              .inFilter('id', ids)
          as List<dynamic>,
    );
    profiles.sort(
      (a, b) => (a['nickname']?.toString() ?? '').compareTo(
        b['nickname']?.toString() ?? '',
      ),
    );
    return profiles;
  }

  Future<GroupCallSession> upgradePrivateCall({
    required String privateCallId,
    required String type,
    required List<String> inviteeIds,
  }) async {
    await _requireCallsEnabled();
    final userId = _requireUser();
    if (inviteeIds.isEmpty || inviteeIds.length > 3) {
      throw StateError('Choose between one and three friends.');
    }
    final response = await _client.rpc(
      'upgrade_private_call_to_group',
      params: {'target_call_id': privateCallId, 'invitee_ids': inviteeIds},
    );
    final call = Map<String, dynamic>.from(response as Map);
    final session = GroupCallSession._(
      client: _client,
      call: call,
      currentUserId: userId,
      isStarter: true,
      groupName: call['room_name']?.toString() ?? 'Group call',
      iceServers: await _iceServers(),
    );
    try {
      await session.initialise();
      unawaited(
        PushNotificationService.sendIncomingGroupCall(call['id'].toString()),
      );
      return session;
    } catch (_) {
      await _client.rpc(
        'end_group_call',
        params: {'target_call_id': call['id'].toString()},
      );
      await session.disposeSession();
      rethrow;
    }
  }

  Future<GroupCallSession> startCall({
    required String groupId,
    required String groupName,
    required String type,
    required List<String> inviteeIds,
  }) async {
    await _requireCallsEnabled();
    final userId = _requireUser();
    if (inviteeIds.isEmpty || inviteeIds.length > 4) {
      throw StateError('Choose between one and four people.');
    }
    final response = await _client.rpc(
      'start_group_call',
      params: {
        'target_group_id': groupId,
        'target_call_type': type,
        'invitee_ids': inviteeIds,
      },
    );
    final call = Map<String, dynamic>.from(response as Map);
    final session = GroupCallSession._(
      client: _client,
      call: call,
      currentUserId: userId,
      isStarter: true,
      groupName: groupName,
      iceServers: await _iceServers(),
    );
    try {
      await session.initialise();
      unawaited(
        PushNotificationService.sendIncomingGroupCall(call['id'].toString()),
      );
      return session;
    } catch (_) {
      await _client.rpc(
        'end_group_call',
        params: {'target_call_id': call['id'].toString()},
      );
      await session.disposeSession();
      rethrow;
    }
  }

  Future<void> _requireCallsEnabled() async {
    final availability = await FeatureFlagService.availability(
      'calls',
      client: _client,
      forceRefresh: true,
    );
    if (!availability.enabled) throw StateError(availability.message);
  }

  Future<GroupCallSession> accept(GroupCallInvite invite) async {
    final userId = _requireUser();
    final session = GroupCallSession._(
      client: _client,
      call: invite.call,
      currentUserId: userId,
      isStarter: invite.call['started_by']?.toString() == userId,
      groupName: invite.groupName,
      iceServers: await _iceServers(),
    );
    try {
      await session.prepareMedia();
      final response = await _client.rpc(
        'join_group_call',
        params: {'target_call_id': invite.callId},
      );
      session.replaceCall(Map<String, dynamic>.from(response as Map));
      await session.connect();
      return session;
    } catch (_) {
      await session.disposeSession();
      rethrow;
    }
  }

  Future<void> decline(String callId) =>
      _client.rpc('decline_group_call', params: {'target_call_id': callId});

  Future<List<GroupCallInvite>> pendingInvites() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('group_call_participants')
              .select('call_id')
              .eq('user_id', userId)
              .eq('status', 'invited')
              .order('invited_at', ascending: false)
              .limit(5)
          as List<dynamic>,
    );
    final invites = <GroupCallInvite>[];
    for (final row in rows) {
      final invite = await inviteById(row['call_id'].toString());
      if (invite != null &&
          const {'ringing', 'active'}.contains(invite.call['status'])) {
        invites.add(invite);
      }
    }
    return invites;
  }

  Future<GroupCallInvite?> inviteById(String callId) async {
    final call = await _client
        .from('group_calls')
        .select()
        .eq('id', callId)
        .maybeSingle();
    if (call == null) return null;
    final groupId = call['group_id']?.toString();
    final responses = await Future.wait<dynamic>([
      groupId == null || groupId.isEmpty
          ? Future<Map<String, dynamic>?>.value(null)
          : _client
                .from('group_chats')
                .select('name')
                .eq('id', groupId)
                .maybeSingle(),
      _client
          .from('profiles')
          .select('nickname, photo_url')
          .eq('id', call['started_by'])
          .maybeSingle(),
    ]);
    final group = responses[0] as Map<String, dynamic>?;
    final profile = responses[1] as Map<String, dynamic>?;
    return GroupCallInvite(
      call: Map<String, dynamic>.from(call),
      groupName:
          group?['name']?.toString() ??
          call['room_name']?.toString() ??
          'Group call',
      callerName: profile?['nickname']?.toString().trim().isNotEmpty == true
          ? profile!['nickname'].toString().trim()
          : 'OG Vibes student',
      callerPhotoUrl: profile?['photo_url']?.toString(),
    );
  }

  void listenForInvites({
    required String currentUserId,
    required void Function(GroupCallInvite invite) onIncoming,
  }) {
    _incomingChannel?.unsubscribe();
    _incomingChannel = _client.channel('group-call-invites:$currentUserId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'group_call_participants',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: currentUserId,
        ),
        callback: (payload) async {
          if (payload.newRecord['status'] != 'invited') return;
          final invite = await inviteById(
            payload.newRecord['call_id'].toString(),
          );
          if (invite != null) onIncoming(invite);
        },
      )
      ..subscribe();
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
      if (response.data is Map &&
          (response.data as Map)['iceServers'] is List) {
        final servers = List<dynamic>.from(
          (response.data as Map)['iceServers'] as List,
        );
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

class GroupCallSession extends ChangeNotifier {
  GroupCallSession._({
    required SupabaseClient client,
    required Map<String, dynamic> call,
    required this.currentUserId,
    required this.isStarter,
    required this.groupName,
    required List<dynamic> iceServers,
  }) : _client = client,
       _call = call,
       _iceServers = iceServers;

  final SupabaseClient _client;
  Map<String, dynamic> _call;
  final String currentUserId;
  final bool isStarter;
  final String groupName;
  final List<dynamic> _iceServers;
  final Map<String, RTCPeerConnection> _peers = {};
  final Set<String> _creatingPeers = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Set<int> _handledSignals = {};
  RealtimeChannel? _channel;
  bool _closed = false;

  MediaStream? localStream;
  final Map<String, MediaStream> remoteStreams = {};
  final Map<String, Map<String, dynamic>> participantProfiles = {};
  final Map<String, String> participantStatuses = {};
  String status = 'connecting';

  String get callId => _call['id'].toString();
  String? get groupId => _call['group_id']?.toString();
  String get type => _call['call_type']?.toString() ?? 'audio';
  bool get isVideo => type == 'video';
  int get joinedCount =>
      participantStatuses.values.where((value) => value == 'joined').length;

  void replaceCall(Map<String, dynamic> call) => _call = call;

  Future<void> initialise() async {
    await WakelockPlus.enable();
    await prepareMedia();
    await connect();
  }

  Future<void> prepareMedia() async {
    if (localStream != null) return;
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
  }

  Future<void> connect() async {
    _subscribe();
    await _refreshParticipants();
    await _loadSignals();
    status = 'active';
    notifyListeners();
  }

  void _subscribe() {
    _channel = _client.channel('group-call:$callId:$currentUserId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'group_call_participants',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'call_id',
          value: callId,
        ),
        callback: (_) => unawaited(_refreshParticipants()),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'group_call_signals',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'recipient_id',
          value: currentUserId,
        ),
        callback: (payload) => unawaited(_handleSignal(payload.newRecord)),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'group_calls',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: callId,
        ),
        callback: (payload) {
          status = payload.newRecord['status']?.toString() ?? status;
          notifyListeners();
          if (const {'ended', 'cancelled'}.contains(status)) {
            unawaited(disposeSession());
          }
        },
      )
      ..subscribe();
  }

  Future<void> _refreshParticipants() async {
    if (_closed) return;
    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('group_call_participants')
              .select('user_id,status')
              .eq('call_id', callId)
          as List<dynamic>,
    );
    participantStatuses
      ..clear()
      ..addEntries(
        rows.map(
          (row) =>
              MapEntry(row['user_id'].toString(), row['status'].toString()),
        ),
      );
    final ids = rows.map((row) => row['user_id'].toString()).toList();
    if (ids.isNotEmpty) {
      final profiles = List<Map<String, dynamic>>.from(
        await _client
                .from('profiles')
                .select('id,nickname,photo_url')
                .inFilter('id', ids)
            as List<dynamic>,
      );
      participantProfiles
        ..clear()
        ..addEntries(
          profiles.map(
            (profile) => MapEntry(profile['id'].toString(), profile),
          ),
        );
    }
    final joinedPeers = participantStatuses.entries
        .where((entry) => entry.value == 'joined' && entry.key != currentUserId)
        .map((entry) => entry.key)
        .toSet();
    for (final remoteId in joinedPeers) {
      await _ensurePeer(remoteId, offerIfLeader: true);
    }
    for (final remoteId in _peers.keys.toList()) {
      if (!joinedPeers.contains(remoteId)) await _removePeer(remoteId);
    }
    notifyListeners();
  }

  Future<void> _ensurePeer(
    String remoteId, {
    required bool offerIfLeader,
  }) async {
    if (_closed ||
        _peers.containsKey(remoteId) ||
        !_creatingPeers.add(remoteId)) {
      return;
    }
    try {
      final peer = await createPeerConnection({
        'iceServers': _iceServers,
        'sdpSemantics': 'unified-plan',
      });
      _peers[remoteId] = peer;
      for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
        await peer.addTrack(track, localStream!);
      }
      peer.onTrack = (event) => unawaited(_attachRemoteTrack(remoteId, event));
      peer.onIceCandidate = (candidate) {
        if (candidate.candidate == null || _closed) return;
        unawaited(
          _sendSignal(remoteId, 'ice', {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }),
        );
      };
      if (offerIfLeader && currentUserId.compareTo(remoteId) < 0) {
        final offer = await peer.createOffer();
        await peer.setLocalDescription(offer);
        await _sendSignal(remoteId, 'offer', {
          'sdp': offer.sdp,
          'type': offer.type,
        });
      }
    } finally {
      _creatingPeers.remove(remoteId);
    }
  }

  Future<void> _attachRemoteTrack(String remoteId, RTCTrackEvent event) async {
    if (_closed) return;
    MediaStream stream;
    if (event.streams.isNotEmpty) {
      stream = event.streams.first;
    } else {
      stream =
          remoteStreams[remoteId] ??
          await createLocalMediaStream('group-$callId-$remoteId');
      final trackId = event.track.id;
      if (trackId == null || stream.getTrackById(trackId) == null) {
        await stream.addTrack(event.track);
      }
    }
    remoteStreams[remoteId] = stream;
    notifyListeners();
  }

  Future<void> _loadSignals() async {
    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('group_call_signals')
              .select()
              .eq('call_id', callId)
              .eq('recipient_id', currentUserId)
              .order('id')
          as List<dynamic>,
    );
    for (final row in rows) {
      await _handleSignal(row);
    }
  }

  Future<void> _handleSignal(Map<String, dynamic> signal) async {
    if (_closed || signal['call_id']?.toString() != callId) return;
    final id = int.tryParse(signal['id']?.toString() ?? '');
    if (id != null && !_handledSignals.add(id)) return;
    final remoteId = signal['sender_id']?.toString() ?? '';
    if (remoteId.isEmpty || remoteId == currentUserId) return;
    await _ensurePeer(remoteId, offerIfLeader: false);
    final peer = _peers[remoteId];
    if (peer == null) return;
    final payload = Map<String, dynamic>.from(signal['payload'] as Map? ?? {});
    switch (signal['kind']?.toString()) {
      case 'offer':
        await peer.setRemoteDescription(
          RTCSessionDescription(payload['sdp']?.toString(), 'offer'),
        );
        await _flushCandidates(remoteId, peer);
        final answer = await peer.createAnswer();
        await peer.setLocalDescription(answer);
        await _sendSignal(remoteId, 'answer', {
          'sdp': answer.sdp,
          'type': answer.type,
        });
        break;
      case 'answer':
        await peer.setRemoteDescription(
          RTCSessionDescription(payload['sdp']?.toString(), 'answer'),
        );
        await _flushCandidates(remoteId, peer);
        break;
      case 'ice':
        final candidate = RTCIceCandidate(
          payload['candidate']?.toString(),
          payload['sdpMid']?.toString(),
          payload['sdpMLineIndex'] as int?,
        );
        final description = await peer.getRemoteDescription();
        if (description == null) {
          (_pendingCandidates[remoteId] ??= []).add(candidate);
        } else {
          await peer.addCandidate(candidate);
        }
    }
  }

  Future<void> _flushCandidates(String remoteId, RTCPeerConnection peer) async {
    for (final candidate in _pendingCandidates.remove(remoteId) ?? const []) {
      await peer.addCandidate(candidate);
    }
  }

  Future<void> _sendSignal(
    String recipientId,
    String kind,
    Map<String, dynamic> payload,
  ) async {
    await _client.from('group_call_signals').insert({
      'call_id': callId,
      'sender_id': currentUserId,
      'recipient_id': recipientId,
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

  Future<void> leave({bool endForEveryone = false}) async {
    if (_closed) return;
    if (endForEveryone && isStarter) {
      await _client.rpc('end_group_call', params: {'target_call_id': callId});
    } else {
      await _client.rpc('leave_group_call', params: {'target_call_id': callId});
    }
    await disposeSession();
  }

  Future<void> _removePeer(String remoteId) async {
    final stream = remoteStreams.remove(remoteId);
    if (stream != null) await stream.dispose();
    await _peers.remove(remoteId)?.close();
    _pendingCandidates.remove(remoteId);
  }

  Future<void> disposeSession() async {
    if (_closed) return;
    _closed = true;
    await WakelockPlus.disable();
    await _channel?.unsubscribe();
    _channel = null;
    for (final id in _peers.keys.toList()) {
      await _removePeer(id);
    }
    for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await localStream?.dispose();
    localStream = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(disposeSession());
    super.dispose();
  }
}
