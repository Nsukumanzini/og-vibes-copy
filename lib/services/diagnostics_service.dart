import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DiagnosticsService {
  DiagnosticsService._();

  static Future<void> record(
    String event, {
    Map<String, Object?> metadata = const {},
  }) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      await client.from('client_diagnostics').insert({
        'user_id': user.id,
        'event': event,
        'platform': kIsWeb
            ? 'web'
            : defaultTargetPlatform == TargetPlatform.android
            ? 'android'
            : 'other',
        'metadata': metadata,
      });
    } catch (error) {
      debugPrint('Diagnostics event was not recorded: $error');
    }
  }

  static Future<void> recordFlutterError(FlutterErrorDetails details) {
    return record(
      'flutter_error',
      metadata: {
        'type': details.exception.runtimeType.toString(),
        'library': details.library,
        'context': details.context?.toDescription(),
      },
    );
  }
}
