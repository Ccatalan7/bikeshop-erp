import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/pdf_parser_service.dart';

void main() {
  test('probe Mercado Libre PDF extraction', () async {
    final bytes = await File(
      '/Users/Claudio/Library/Containers/com.vinabike.vinabikeErp/Data/'
      'Documents/Downloads/invoice-2000017575800098.pdf',
    ).readAsBytes();
    final parsed = await PDFParserService().parseInvoiceFromBytes(
      bytes,
      filename: 'invoice-2000017575800098.pdf',
    );
    // ignore: avoid_print
    print('PROBE_RESULT: $parsed');
    // ignore: avoid_print
    print('PROBE_TEXT:\n${parsed?.rawText}');
  });
}
