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
    // El renderizador compartido se empaqueta desde `assets/browser/`, copia
    // espejo de la extensión de Chrome: los assets del ERP viven bajo
    // `assets/` y `aliexpress_asset_mirror_test.dart` impide que deriven.
    expect(
      browser,
      contains('assets/browser/aliexpress_invoice.css'),
    );
    expect(
      browser,
      contains('assets/browser/aliexpress_invoice.js'),
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
    // Los assets se empaquetan desde `assets/browser/`; la extensión de Chrome
    // conserva los originales en `tools/` y el espejo se guarda en
    // `aliexpress_asset_mirror_test.dart`.
    expect(pubspec, contains('assets/browser/aliexpress_invoice_content.js'));
    expect(pubspec, contains('assets/browser/aliexpress_invoice.css'));
    expect(pubspec, contains('assets/browser/aliexpress_invoice.js'));
  });

  test('AliExpress OCR creation separates internal SKU from supplier code', () {
    final ocr =
        File('lib/shared/widgets/ocr_upload_widget.dart').readAsStringSync();

    expect(ocr, contains('reserveAliExpressSkus('));
    // La reserva dejó de ser un flag de lote: cada fila guarda el código que le
    // dio la base, y ese es el único que se puede crear.
    expect(ocr, contains('String? reservedSku;'));
    expect(
      ocr,
      contains('bool get hasReservedAliExpressSku =>'),
    );
    expect(ocr, contains('entry.supplierCode.isEmpty ? entry.sku'));
    expect(ocr, contains('final String supplierCode;'));
  });

  test('AliExpress marks purchase days inside the calendar before selection',
      () {
    final browser =
        File('lib/shared/widgets/webview_module_page.dart').readAsStringSync();
    final extractor = File(
      'tools/chrome-extensions/aliexpress-invoice-generator/content.js',
    ).readAsStringSync();

    final pickerStart = browser.indexOf(
      'Future<_AliExpressImportRequest?> _pickAliExpressImportRequest()',
    );
    final pickerEnd = browser.indexOf(
      'Future<void> _startAliExpressDailyImport()',
      pickerStart,
    );
    expect(pickerStart, greaterThan(-1));
    expect(pickerEnd, greaterThan(pickerStart));
    final picker = browser.substring(pickerStart, pickerEnd);

    expect(picker, contains('_refreshAliExpressOrderDateIndex()'));
    expect(picker, contains('showVbMarkedDatePicker('));
    expect(picker, contains('markers: _aliExpressDateMarkers()'));
    expect(
      picker.indexOf('_refreshAliExpressOrderDateIndex()'),
      lessThan(picker.indexOf('showDialog<_AliExpressImportRequest>')),
    );
    expect(picker, isNot(contains('showDatePicker(')));
    expect(browser, contains("'datesOnly': true"));
    expect(browser, contains('UserScriptInjectionTime.AT_DOCUMENT_START'));
    expect(
      browser,
      contains('AliExpressDailyInvoiceService.trustedRegistrableDomains'),
    );
    expect(browser, isNot(contains('Sin compras este día')));
    expect(
      browser,
      contains(
        'No consta una compra para esta fecha en el índice disponible.',
      ),
    );

    expect(extractor, contains('const datesOnly = options.datesOnly === true'));
    expect(extractor, contains("mode: datesOnly ? 'dates-only'"));
    expect(extractor, contains('coverageComplete: coverage.complete'));
  });
}
