import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice routes and shared actions use canonical surfaces', () {
    final router = File('lib/shared/routes/app_router.dart').readAsStringSync();
    final form = File('lib/modules/sales/pages/invoice_form_page.dart')
        .readAsStringSync();
    final editor = File('lib/modules/sales/widgets/sales_invoice_editor.dart')
        .readAsStringSync();
    final listPreview = File('lib/modules/sales/pages/invoice_list_page.dart')
        .readAsStringSync();

    expect(router, contains("path: '/sales/invoices/:id'"));
    expect(router, contains('erp.InvoiceFormPage('));
    expect(form, contains('SalesCorrectionsMenu('));
    expect(editor, contains('SalesCorrectionsMenu('));
    expect(listPreview, contains('SalesCorrectionsMenu('));
    expect(
      File('lib/modules/sales/pages/invoice_detail_page.dart').existsSync(),
      isFalse,
      reason: 'Do not reintroduce a competing, unrouted invoice detail page.',
    );

    expect(router, contains("path: '/purchases/:id'"));
    expect(router, contains('erp.PurchaseInvoiceFormPage('));
    expect(
      File('lib/modules/purchases/pages/purchase_invoice_detail_page.dart')
          .existsSync(),
      isFalse,
      reason:
          'Do not reintroduce a competing, unrouted purchase invoice detail page.',
    );
    expect(
      File('lib/modules/purchases/pages/purchase_invoice_list_page_old.dart')
          .existsSync(),
      isFalse,
      reason: 'Do not retain a competing legacy purchase invoice list.',
    );
  });
}
