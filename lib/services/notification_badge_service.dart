import 'dart:async';

import 'package:flutter/foundation.dart';
import 'offline_data_adapter.dart';

class NotificationBadgeCounts {
  const NotificationBadgeCounts({
    this.notifications = 0,
    this.alerts = 0,
    this.messages = 0,
    this.groups = 0,
  });

  final int notifications;
  final int alerts;
  final int messages;
  final int groups;
  int get chats => messages + groups;
}

class NotificationBadgeService {
  NotificationBadgeService._();

  static final NotificationBadgeService instance = NotificationBadgeService._();
  final _controller = StreamController<NotificationBadgeCounts>.broadcast();
  final _incomingNotifications = StreamController<void>.broadcast();
  final List<OfflineRealtimeChannel> _channels = [];
  NotificationBadgeCounts _current = const NotificationBadgeCounts();
  bool _hasInitialSnapshot = false;
  Set<String> _knownNotificationIds = <String>{};
  Set<String> _knownAlertIds = <String>{};

  Stream<NotificationBadgeCounts> get stream async* {
    yield _current;
    yield* _controller.stream;
  }

  Stream<void> get incomingNotifications => _incomingNotifications.stream;

  Future<void> start() async {
    final client = OfflineData.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    await stop();
    await refresh();
    _hasInitialSnapshot = true;
    final notificationsChannel = client.channel('notification-badges:$userId')
      ..onPostgresChanges(
        event: OfflinePostgresChangeEvent.all,
        schema: 'public',
        table: 'student_notifications',
        filter: OfflinePostgresChangeFilter(
          type: OfflinePostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (_) => unawaited(refresh()),
      )
      ..subscribe();
    final alertReadsChannel = client.channel('alert-read-badges:$userId')
      ..onPostgresChanges(
        event: OfflinePostgresChangeEvent.all,
        schema: 'public',
        table: 'alert_reads',
        filter: OfflinePostgresChangeFilter(
          type: OfflinePostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (_) => unawaited(refresh()),
      )
      ..subscribe();
    final alertsChannel = client.channel('campus-alert-badges:$userId')
      ..onPostgresChanges(
        event: OfflinePostgresChangeEvent.all,
        schema: 'public',
        table: 'app_content',
        callback: (_) => unawaited(refresh()),
      )
      ..subscribe();
    _channels.addAll([notificationsChannel, alertReadsChannel, alertsChannel]);
  }

  Future<void> refresh() async {
    final client = OfflineData.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final results = await Future.wait<dynamic>([
        client
            .from('student_notifications')
            .select('id,category,route,metadata')
            .isFilter('read_at', null)
            .limit(500),
        client
            .from('app_content')
            .select('id')
            .eq('section', 'announcements')
            .eq('is_active', true),
        client.from('alert_reads').select('alert_id').eq('user_id', userId),
      ]);
      final rows = List<Map<String, dynamic>>.from(results[0] as List<dynamic>);
      final activeAlertIds = List<Map<String, dynamic>>.from(
        results[1] as List<dynamic>,
      ).map((row) => row['id']?.toString()).whereType<String>().toSet();
      final readAlertIds = List<Map<String, dynamic>>.from(
        results[2] as List<dynamic>,
      ).map((row) => row['alert_id']?.toString()).whereType<String>().toSet();
      final alerts = activeAlertIds.difference(readAlertIds).length;
      final notificationIds = rows
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toSet();
      final receivedNotification =
          (_hasInitialSnapshot &&
              (notificationIds.difference(_knownNotificationIds).isNotEmpty ||
                  rows.length > _current.notifications)) ||
          (_hasInitialSnapshot &&
              activeAlertIds.difference(_knownAlertIds).isNotEmpty);
      var messages = 0, groups = 0;
      for (final row in rows) {
        final route = row['route']?.toString() ?? '';
        final metadata = row['metadata'] is Map
            ? Map<String, dynamic>.from(row['metadata'] as Map)
            : const <String, dynamic>{};
        final kind = metadata['kind']?.toString() ?? '';
        if (route == 'group_chats' || kind == 'group_message') {
          groups++;
        } else if (route == 'chat' ||
            route == 'messages' ||
            kind == 'private_message') {
          messages++;
        }
      }
      _current = NotificationBadgeCounts(
        notifications: rows.length,
        alerts: alerts,
        messages: messages,
        groups: groups,
      );
      _knownNotificationIds = notificationIds;
      _knownAlertIds = activeAlertIds;
      _controller.add(_current);
      if (receivedNotification) _incomingNotifications.add(null);
    } catch (error) {
      debugPrint('Unable to refresh notification badges: $error');
    }
  }

  Future<void> stop() async {
    final channels = List<OfflineRealtimeChannel>.from(_channels);
    _channels.clear();
    for (final channel in channels) {
      await OfflineData.instance.client.removeChannel(channel);
    }
  }
}
