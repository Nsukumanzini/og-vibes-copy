import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Uses the platform save dialog (or a browser download), never a popup tab.
class AcademicFileService {
  static Future<bool> download(String url, String fileName) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !['https', 'http'].contains(uri.scheme)) {
      throw const FormatException('Invalid file link');
    }
    final response = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) throw StateError('Empty document');
    final name = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: 'Save document',
      fileName: name,
      bytes: Uint8List.fromList(bytes),
    );
    return kIsWeb || saved != null;
  }
}
