import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks authenticated OG Vibes users who currently have the app open.
///
/// Presence is intentionally separate from the `profiles.is_online` column so
/// stale database values never make a student appear online after disconnecting.
class PresenceService {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  final ValueNotifier<Set<String>> onlineUserIds = ValueNotifier<Set<String>>(
    <String>{},
  );

  RealtimeChannel? _channel;
  String? _trackedUserId;

  bool isOnline(String userId) => onlineUserIds.value.contains(userId);

  Future<void> start() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      await stop();
      return;
    }
    if (_trackedUserId == userId && _channel != null) return;

    await stop();
    _trackedUserId = userId;
    late final RealtimeChannel channel;
    channel = client
        .channel(
          'og-vibes-online-users',
          opts: RealtimeChannelConfig(key: userId, enabled: true),
        )
        .onPresenceSync((_) => _sync(channel))
        .onPresenceJoin((_) => _sync(channel))
        .onPresenceLeave((_) => _sync(channel))
        .subscribe((status, error) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await channel.track(<String, dynamic>{
              'user_id': userId,
              'online_at': DateTime.now().toUtc().toIso8601String(),
            });
          } else if (error != null) {
            debugPrint('Presence connection failed: $error');
          }
        });
    _channel = channel;
  }

  Future<void> pause() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      await channel.untrack();
    } catch (error) {
      debugPrint('Presence pause failed: $error');
    }
  }

  Future<void> resume() async {
    final channel = _channel;
    final userId = _trackedUserId;
    if (channel == null || userId == null) {
      await start();
      return;
    }
    try {
      await channel.track(<String, dynamic>{
        'user_id': userId,
        'online_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (error) {
      debugPrint('Presence resume failed: $error');
    }
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _trackedUserId = null;
    onlineUserIds.value = <String>{};
    if (channel == null) return;
    try {
      await channel.untrack();
      await Supabase.instance.client.removeChannel(channel);
    } catch (error) {
      debugPrint('Presence disconnect failed: $error');
    }
  }

  void _sync(RealtimeChannel channel) {
    final online = <String>{};
    for (final state in channel.presenceState()) {
      for (final presence in state.presences) {
        final userId = presence.payload['user_id']?.toString();
        if (userId?.isNotEmpty == true) online.add(userId!);
      }
    }
    onlineUserIds.value = online;
  }
}
