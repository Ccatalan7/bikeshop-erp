import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

bool get isPayrollStatementImageOcrSupported =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

const MethodChannel _macosPayrollOcrChannel =
    MethodChannel('com.vinabike.erp/payroll_statement_ocr');

Future<String> extractPayrollStatementImageText({
  required Uint8List bytes,
  required String filename,
  String? sourcePath,
}) async {
  if (!isPayrollStatementImageOcrSupported) {
    throw UnsupportedError(
      'El OCR local de imágenes no está disponible en esta plataforma.',
    );
  }
  if (Platform.isMacOS) {
    final text = await _macosPayrollOcrChannel.invokeMethod<String>(
      'recognizeText',
      bytes,
    );
    if (text == null || text.trim().isEmpty) {
      throw const FormatException(
        'No se reconoció texto en la imagen de la cartola.',
      );
    }
    return text;
  }

  Directory? temporaryDirectory;
  TextRecognizer? recognizer;
  try {
    var imagePath = sourcePath;
    if (imagePath == null) {
      final temporaryRoot = await getTemporaryDirectory();
      temporaryDirectory = await temporaryRoot.createTemp(
        'vinabike_payroll_ocr_',
      );
      final temporaryImage = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}'
        'statement.${_imageExtension(bytes)}',
      );
      await temporaryImage.writeAsBytes(bytes, flush: true);
      imagePath = temporaryImage.path;
    }

    recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final result = await recognizer.processImage(
      InputImage.fromFilePath(imagePath),
    );
    return result.text;
  } finally {
    try {
      await recognizer?.close();
    } finally {
      if (temporaryDirectory != null && await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }
}

String _imageExtension(Uint8List bytes) {
  final isJpeg = bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;
  if (isJpeg) return 'jpg';

  final isWebp = bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50;
  if (isWebp) return 'webp';

  return 'png';
}
