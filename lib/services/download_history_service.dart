import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DownloadHistoryService {
  DownloadHistoryService._();

  static Future<void> record({
    required String sourceType,
    required String title,
    String? sourceId,
    String? url,
    String? storagePath,
    String storageBucket = 'academic-content',
    int? fileSizeBytes,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('download_history').insert({
        'user_id': user.id,
        'source_type': sourceType,
        if (sourceId != null && sourceId.isNotEmpty) 'source_id': sourceId,
        'title': title,
        if (url != null && url.isNotEmpty) 'url': url,
        if (storagePath != null && storagePath.isNotEmpty)
          'storage_path': storagePath,
        'storage_bucket': storageBucket,
        if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      });
    } catch (error) {
      // A history failure must never make a completed download look failed.
      debugPrint('Unable to save download history: $error');
    }
  }
}
