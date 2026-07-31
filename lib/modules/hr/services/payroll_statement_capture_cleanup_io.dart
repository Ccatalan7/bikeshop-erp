import 'dart:io';

import 'package:flutter/foundation.dart';

/// Best-effort removal of the picker's camera artifact.
///
/// The capture's bytes are already in memory when this runs; a filesystem
/// failure here must never abort the picker/OCR flow that owns them. The
/// sensitive file is short-lived picker cache either way.
Future<void> cleanupPayrollStatementCameraCapture(String? sourcePath) async {
  final path = sourcePath?.trim();
  if (path == null || path.isEmpty) return;
  try {
    final capture = File(path);
    if (await capture.exists()) {
      await capture.delete();
    }
  } catch (error) {
    // Only the error TYPE: a FileSystemException message embeds the capture
    // path, which must never reach logs.
    debugPrint(
      '⚠️ [PayrollStatementCapture] No se pudo borrar la captura temporal '
      'de cámara; el flujo continúa con los bytes ya leídos '
      '(${error.runtimeType})',
    );
  }
}
