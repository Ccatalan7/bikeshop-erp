import 'dart:typed_data';

import 'payroll_statement_local_image_ocr_stub.dart'
    if (dart.library.io) 'payroll_statement_local_image_ocr_io.dart'
    as platform;

/// On-device image OCR boundary for payroll statements.
///
/// It is intentionally unavailable on web/desktop until a payroll-authorized
/// and privacy-reviewed processor exists. PDF text extraction remains local on
/// every platform.
class PayrollStatementLocalImageOcr {
  const PayrollStatementLocalImageOcr();

  bool get isSupported => platform.isPayrollStatementImageOcrSupported;

  Future<String> extractText({
    required Uint8List bytes,
    required String filename,
    String? sourcePath,
  }) {
    return platform.extractPayrollStatementImageText(
      bytes: bytes,
      filename: filename,
      sourcePath: sourcePath,
    );
  }
}
