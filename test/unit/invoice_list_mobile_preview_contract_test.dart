import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/modules/sales/pages/invoice_list_page.dart',
    ).readAsStringSync();
  });

  test('compact viewport wins over a requested desktop split preview', () {
    expect(
      source,
      contains(
        'final usesCompactLayout = ResponsiveViewport.usesCompactShell(context);',
      ),
    );
    expect(
      source,
      contains('if (usesCompactLayout && selectedInvoice != null)'),
    );
    expect(source, isNot(contains('final forceSplitPreview')));
    expect(source, isNot(contains('final isMobile = !forceSplitPreview')));
  });

  test('selected mobile invoice has a dedicated full-width document surface',
      () {
    expect(source, contains('MainLayoutCompactHeader('));
    expect(source, contains('_buildCompactInvoicePreview(selectedInvoice)'));
    expect(
      source,
      contains("'sales-invoice-compact-preview-scroll'"),
    );
    expect(
      source,
      contains(
        '(constraints.maxWidth - 16).clamp(280.0, 920.0).toDouble()',
      ),
    );
    expect(source, contains("tooltip: 'Acciones de la factura'"));
    expect(source, contains('width: 48'));
    expect(source, contains('height: 48'));
  });
}
