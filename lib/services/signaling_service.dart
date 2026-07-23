import 'package:supabase_flutter/supabase_flutter.dart';

class SignalingService {
  SignalingService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  RealtimeChannel? _channel;

  Future<void> joinChannel(String callId) async {
    _channel?.unsubscribe();
    _channel = _client.channel(
      'call-$callId',
      opts: RealtimeChannelConfig(
        private: true,
      ),
    );
    _channel!.subscribe();
  }

  Future<void> sendSignal(String callId, String type, Map<String, dynamic> payload) async {
    final channel = _channel ?? await _ensureChannel(callId);
    await channel.sendBroadcastMessage(
      event: 'webrtc',
      payload: {
        'callId': callId,
        'type': type,
        'payload': payload,
      },
    );
  }

  Future<void> listen(String callId, void Function(Map<String, dynamic> message) onMessage) async {
    final channel = _channel ?? await _ensureChannel(callId);
    channel.onBroadcast(
      event: 'webrtc',
      callback: (payload) {
        onMessage(Map<String, dynamic>.from(payload));
      },
    );
  }

  Future<RealtimeChannel> _ensureChannel(String callId) async {
    if (_channel == null) {
      await joinChannel(callId);
    }
    return _channel!;
  }

  void dispose() {
    _channel?.unsubscribe();
    _channel = null;
  }
}
