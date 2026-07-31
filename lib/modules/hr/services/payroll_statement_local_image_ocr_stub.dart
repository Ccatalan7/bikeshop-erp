import 'dart:typed_data';

const bool isPayrollStatementImageOcrSupported = false;

Future<String> extractPayrollStatementImageText({
  required Uint8List bytes,
  required String filename,
  String? sourcePath,
}) {
  throw UnsupportedError(
    'El OCR local de imágenes no está disponible en esta plataforma.',
  );
}
