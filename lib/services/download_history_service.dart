/// Download history synchronization is disabled in the offline build.
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
  }) async {}
}
