// Stub implementation for non-web platforms
// This file is used when dart:html is not available

import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<void> downloadFile({
  required List<int> bytes,
  required String fileName,
  required String mimeType,
}) async {
  final safeName = _safeFileName(fileName);
  final downloadsDirectory = await getDownloadsDirectory();
  final documentsDirectory = await getApplicationDocumentsDirectory();
  final candidates = <Directory>[
    if (downloadsDirectory != null) downloadsDirectory,
    Directory('${documentsDirectory.path}/Downloads'),
    documentsDirectory,
  ];

  Object? lastError;
  StackTrace? lastStackTrace;

  for (final directory in candidates) {
    try {
      await directory.create(recursive: true);
      final file = File('${directory.path}/$safeName');
      await file.writeAsBytes(bytes, flush: true);
      return;
    } catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
    }
  }

  Error.throwWithStackTrace(
    FileSystemException(
      'No se pudo guardar la descarga localmente',
      safeName,
      lastError is OSError ? lastError : null,
    ),
    lastStackTrace ?? StackTrace.current,
  );
}

String _safeFileName(String value) {
  final cleaned = value
      .trim()
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  return cleaned.isEmpty ? 'descarga' : cleaned;
}
