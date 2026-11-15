// IO implementation for platforms that support dart:io (mobile/desktop).
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readFileBytesFromPath(String? path) async {
  if (path == null) return null;
  final file = File(path);
  if (!await file.exists()) return null;
  return await file.readAsBytes();
}

File? fileFromPath(String? path) {
  if (path == null) return null;
  return File(path);
}
