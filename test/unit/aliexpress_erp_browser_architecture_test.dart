import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('embedded browser previews or hands off AliExpress in a fresh tab', () {
    final browser =
        File('lib/shared/widgets/webview_module_page.dart').readAsStringSync();
    final extractor = File(
      'tools/chrome-extensions/aliexpress-invoice-generator/content.js',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(browser, contains("label: const Text('Compras del día')"));
    expect(browser, contains('extractOrdersList'));
    expect(browser, contains('extractOrder'));
    expect(
      browser,
      contains('OcrFileHandoffTarget.purchaseInvoice'),
    );
    expect(browser, contains("mimeType: 'application/pdf'"));
    expect(browser, contains('structuredInvoiceData: invoice'));
    expect(browser, contains('Printing.convertHtml'));
    expect(browser, isNot(contains('_buildAliExpressFallbackInvoicePdf')));
    expect(
      browser,
      contains(
          'No se usó una vista simplificada para evitar un preview engañoso'),
    );
    expect(
      browser,
      contains(
        'tools/chrome-extensions/aliexpress-invoice-generator/invoice.css',
      ),
    );
    expect(
      browser,
      contains(
        'tools/chrome-extensions/aliexpress-invoice-generator/invoice.js',
      ),
    );
    expect(browser, contains("label: const Text('Generar preview')"));
    expect(browser, contains("'Preview de factura AliExpress'"));
    expect(browser, contains("label: const Text('Enviar al OCR')"));
    expect(browser, contains("initialRoute: '/purchases/new'"));
    expect(
        browser, isNot(contains("navigateActiveWorkspace('/purchases/new')")));
    final previewGate = browser.indexOf(
      'if (request.mode == _AliExpressImportMode.preview)',
    );
    final ocrHandoff = browser.indexOf(
      'context.read<OcrFileHandoffService>().queue(',
    );
    final freshWorkspace = browser.indexOf('workspaceManager.addWorkspace(');
    expect(previewGate, greaterThan(-1));
    expect(freshWorkspace, greaterThan(previewGate));
    expect(ocrHandoff, greaterThan(previewGate));
    expect(ocrHandoff, greaterThan(freshWorkspace));
    expect(
      browser,
      contains('AliExpressDailyInvoiceService.isTrustedUri'),
    );
    expect(extractor, contains('const extensionRuntime ='));
    final invoiceRenderer = File(
      'tools/chrome-extensions/aliexpress-invoice-generator/invoice.js',
    ).readAsStringSync();
    expect(
      invoiceRenderer,
      contains('globalThis.__ALIEXPRESS_INVOICE_DATA__'),
    );
    expect(invoiceRenderer, contains('buildInvoiceMarkup'));
    expect(
      pubspec,
      contains(
        'tools/chrome-extensions/aliexpress-invoice-generator/content.js',
      ),
    );
    expect(
      pubspec,
      contains(
        'tools/chrome-extensions/aliexpress-invoice-generator/invoice.css',
      ),
    );
    expect(
      pubspec,
      contains(
        'tools/chrome-extensions/aliexpress-invoice-generator/invoice.js',
      ),
    );
  });

  test('AliExpress OCR creation separates internal SKU from supplier code', () {
    final ocr =
        File('lib/shared/widgets/ocr_upload_widget.dart').readAsStringSync();

    expect(ocr, contains("'AE\${(firstSequence + index)"));
    expect(ocr, contains('entry.supplierCode.isEmpty ? entry.sku'));
    expect(ocr, contains('final String supplierCode;'));
  });
}
