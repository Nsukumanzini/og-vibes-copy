import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class CallService {
  CallService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  RealtimeChannel? _incomingChannel;

  Future<Map<String, dynamic>> startCall(String calleeId, {required String type}) async {
    final callerId = _client.auth.currentUser?.id;
    if (callerId == null) {
      throw Exception('No authenticated user found.');
    }

    final response = await _client.from('calls').insert({
      'caller_id': callerId,
      'callee_id': calleeId,
      'type': type,
      'status': 'ringing',
      'started_at': DateTime.now().toUtc().toIso8601String(),
    }).select().single();

    return Map<String, dynamic>.from(response);
  }

  Future<void> acceptCall(String callId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('calls').update({
      'status': 'active',
      'answered_at': now,
    }).eq('id', callId);
  }

  Future<void> declineCall(String callId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('calls').update({
      'status': 'declined',
      'ended_at': now,
    }).eq('id', callId);
  }

  Future<void> cancelCall(String callId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('calls').update({
      'status': 'cancelled',
      'ended_at': now,
    }).eq('id', callId);
  }

  Future<void> endCall(String callId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('calls').update({
      'status': 'ended',
      'ended_at': now,
    }).eq('id', callId);
  }

  Future<void> markMissed(String callId) async {
    await _client.from('calls').update({
      'status': 'missed',
      'ended_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', callId).eq('status', 'ringing');
  }

  RealtimeChannel? listenForIncomingCalls({
    required String currentUserId,
    required void Function(Map<String, dynamic> call) onIncoming,
  }) {
    _incomingChannel?.unsubscribe();

    _incomingChannel = _client.channel('calls:$currentUserId');
    _incomingChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'calls',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'callee_id',
        value: currentUserId,
      ),
      callback: (payload) {
        final data = payload.newRecord;
        if (data['status'] == 'ringing') {
          onIncoming(Map<String, dynamic>.from(data));
        }
      },
    );

    _incomingChannel!.subscribe();
    return _incomingChannel;
  }

  Future<List<Map<String, dynamic>>> getCallHistory(String userId) async {
    final response = await _client.from('calls').select().or('caller_id.eq.$userId,callee_id.eq.$userId').order('started_at', ascending: false);
    return (response as List).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  void dispose() {
    _incomingChannel?.unsubscribe();
    _incomingChannel = null;
  }
}
