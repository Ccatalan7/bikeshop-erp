import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf/pdf.dart';

import 'package:vinabike_erp/shared/services/html_pdf_renderer_service.dart';
import 'package:vinabike_erp/shared/widgets/webview_module_page.dart';

/// Runs the real invoice pipeline on the device: the shared template is drawn
/// in a headless web view and converted by the platform's own PDF path. The
/// owner's phone hung on "Consolidando 7 pedidos y generando el PDF"
/// (2026-09-04); this exercises exactly that step, with no AliExpress session
/// and no network.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// A real product photo, not a 1x1 pixel: the owner's invoice embeds seven
  /// of them as data URIs, so the document the pipeline moves around is
  /// megabytes, not kilobytes.
  Future<Uint8List> photoBytes(int side) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final random = Random(7);
    for (var i = 0; i < 4000; i++) {
      canvas.drawRect(
        Rect.fromLTWH(random.nextDouble() * side, random.nextDouble() * side,
            random.nextDouble() * 24, random.nextDouble() * 24),
        Paint()
          ..color = Color.fromARGB(255, random.nextInt(256),
              random.nextInt(256), random.nextInt(256)),
      );
    }
    final image = await recorder.endRecording().toImage(side, side);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    debugPrint('🧪 [InvoicePdfTest] photo ${side}px = ${bytes.length} bytes');
    return bytes;
  }

  Future<String> buildInvoiceHtml(int lineCount, {String? photo}) async {
    final css =
        await rootBundle.loadString('assets/browser/aliexpress_invoice.css');
    final renderer =
        (await rootBundle.loadString('assets/browser/aliexpress_invoice.js'))
            .replaceAll(RegExp('</script', caseSensitive: false), r'<\/script');
    const pixel =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
        'AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    final invoice = <String, dynamic>{
      'orderNumber': 'AE-DEVICE-TEST',
      'supplierName': 'AliExpress Marketplace',
      'date': '2026-08-12',
      'currency': 'CLP',
      'total': 157898,
      'sourceOrders': <Map<String, dynamic>>[
        {'orderNumber': '3061234567890123'},
      ],
      'items': <Map<String, dynamic>>[
        for (var index = 0; index < lineCount; index++)
          <String, dynamic>{
            'description': 'Repuesto de prueba $index para medir el PDF',
            'sku': 'AE-TEST-$index',
            'quantity': 2,
            'unitPrice': 5000,
            'lineTotal': 10000,
            'embeddedImageUrl': photo ?? pixel,
          },
      ],
    };

    return '''<!doctype html>
<html lang="es">
  <head>
    <meta charset="utf-8">
    <title>AliExpress OCR Invoice</title>
    <style>$css</style>
    <style>
      .toolbar { display: none !important; }
      body { background: #fff !important; }
      .paper { margin: 0; box-shadow: none; }
    </style>
  </head>
  <body>
    <div class="toolbar"><div><span id="toolbarMeta"></span></div></div>
    <main id="invoiceRoot" class="paper" aria-live="polite"></main>
    <script>
      globalThis.__ALIEXPRESS_INVOICE_DATA__ = ${jsonEncode(invoice)};
      globalThis.__ALIEXPRESS_INVOICE_LOGO_URL__ = ${jsonEncode(pixel)};
    </script>
    <script>$renderer</script>
  </body>
</html>''';
  }

  testWidgets('a seven-photo invoice converts, repeatedly, once shrunk',
      (tester) async {
    // Measured 2026-09-04 on Android: seven 600px photos make a 1.34 MB
    // document and Printing.convertHtml never returns. shrinkInvoiceThumbnail
    // is what the app now applies before embedding, so this runs the real
    // path, several times in one process, to catch flakiness too.
    final original = await photoBytes(600);
    final shrunk = shrinkInvoiceThumbnail(original)!;
    debugPrint(
        '🧪 [InvoicePdfTest] photo ${original.length} -> ${shrunk.length} bytes');
    expect(shrunk.length, lessThan(original.length));

    final html = await buildInvoiceHtml(
      7,
      photo: 'data:image/jpeg;base64,${base64Encode(shrunk)}',
    );
    debugPrint('🧪 [InvoicePdfTest] document ${html.length} chars');

    for (var attempt = 1; attempt <= 6; attempt++) {
      final stopwatch = Stopwatch()..start();
      final bytes = await HtmlPdfRendererService().render(
        html: html,
        format: PdfPageFormat.letter,
        readySelector: '#invoiceRoot',
        readyFlag: '__ALIEXPRESS_INVOICE_READY__',
      );
      stopwatch.stop();
      debugPrint('🧪 [InvoicePdfTest] run $attempt OK pdf=${bytes.length} '
          'in ${stopwatch.elapsedMilliseconds}ms');
      expect(HtmlPdfRendererService.hasPdfHeader(bytes), isTrue);
      expect(bytes.length, greaterThan(20000),
          reason: 'the photos have to reach the page');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('the headless step returns the drawn document', (tester) async {
    final html = await buildInvoiceHtml(2);
    final printable = await HtmlPdfRendererService.prepareWithHeadlessWebView(
      html,
      readySelector: '#invoiceRoot',
      readyFlag: '__ALIEXPRESS_INVOICE_READY__',
    );
    debugPrint('🧪 [InvoicePdfTest] printable: ${printable.length} chars');
    expect(printable, contains('Repuesto de prueba 0'));
    expect(printable, isNot(contains('<script')));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
