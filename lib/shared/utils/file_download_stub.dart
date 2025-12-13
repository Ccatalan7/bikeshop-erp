// Stub implementation for non-web platforms
// This file is used when dart:html is not available

import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<void> downloadFile({
  required List<int> bytes,
  required String fileName,
  required String mimeType,
}) async {
  // On desktop/mobile, save to downloads directory
  final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes);
}
