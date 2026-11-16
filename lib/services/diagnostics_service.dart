import 'package:flutter/foundation.dart';

/// Diagnostics are kept on-device only in the offline build.
class DiagnosticsService {
  DiagnosticsService._();

  static Future<void> record(
    String event, {
    Map<String, Object?> metadata = const {},
  }) async {}

  static Future<void> recordFlutterError(FlutterErrorDetails details) async {}
}
