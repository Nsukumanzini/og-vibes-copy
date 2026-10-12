import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  group('production configuration', () {
    test(
      'friend discovery is student-only and old unfiltered caches are ignored',
      () {
        final friends = source('lib/screens/friend_requests_screen.dart');
        expect(friends, contains(".eq('role', 'student')"));
        expect(friends, contains("row['role'] == 'student'"));
        expect(friends, contains("'student_friends_v2'"));
        expect(friends, isNot(contains("readList('friends')")));
        expect(friends, contains('relatedIds'));
        expect(friends, contains('Load more students'));
      },
    );

    test('Android release builds never use the debug signing key', () {
      final gradle = source('android/app/build.gradle.kts');
      expect(gradle, contains('signingConfigs.getByName("release")'));
      expect(
        gradle,
        isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
      );
      expect(gradle, contains('setup_android_signing.ps1'));
    });

    test(
      'Android blocks cleartext and supports incoming-call presentation',
      () {
        final manifest = source('android/app/src/main/AndroidManifest.xml');
        expect(manifest, isNot(contains('usesCleartextTraffic="true"')));
        expect(manifest, contains('android:showWhenLocked="true"'));
        expect(manifest, contains('android:turnScreenOn="true"'));
        expect(manifest, contains('ActionBroadcastReceiver'));
      },
    );

    test('web users receive the OG Vibes installation experience', () {
      final index = source('web/index.html');
      expect(index, contains('id="app_install_prompt"'));
      expect(index, contains('Install OG Vibes'));
      expect(index, contains('beforeinstallprompt'));
      expect(index, contains("window.navigator.standalone"));
    });

    test('notification enrollment is permission-led and refresh-safe', () {
      final service = source('lib/services/push_notification_service.dart');
      expect(service, contains('requestAndRegisterCurrentDevice'));
      expect(service, contains('onTokenRefresh'));
      expect(service, contains('requestFullScreenIntentPermission'));
      expect(service, contains("'call-push'"));
    });

    test('alerts and the notification inbox remain separate destinations', () {
      final home = source('lib/screens/home_screen.dart');
      final alerts = source('lib/screens/announcements_screen.dart');
      final bell = source('lib/widgets/notification_bell_button.dart');
      expect(home, contains('const AnnouncementsScreen()'));
      expect(alerts, isNot(contains(".from('student_notifications')")));
      expect(bell, contains('const NotificationCenterScreen()'));
    });

    test('feed prioritises unseen posts and downloads keep their bucket', () {
      final home = source('lib/screens/home_screen.dart');
      final downloads = source('lib/services/download_history_service.dart');
      expect(home, contains(".from('post_views')"));
      expect(home, contains("'is_unseen'"));
      expect(downloads, contains("'storage_bucket': storageBucket"));
    });

    test('known mock screens are not shipped', () {
      const removed = [
        'bursary_screen.dart',
        'call_feature_screen.dart',
        'exam_timetable_screen.dart',
        'grade_appeal_screen.dart',
        'video_tutorials_screen.dart',
        'live_broadcast_screen.dart',
        'lesson_player_screen.dart',
        'phone_auth_screen.dart',
      ];
      for (final fileName in removed) {
        expect(
          File('lib/screens/$fileName').existsSync(),
          isFalse,
          reason: '$fileName must not return as an unconnected prototype',
        );
      }
    });
  });
}
