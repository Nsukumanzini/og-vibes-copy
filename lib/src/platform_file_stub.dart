// Stub implementation for platforms without `dart:io` (web).
import 'dart:typed_data';

Future<Uint8List?> readFileBytesFromPath(String? path) async {
  return null;
}

dynamic fileFromPath(String? path) => null;
