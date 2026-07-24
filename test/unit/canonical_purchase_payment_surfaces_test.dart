import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(
      path,
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

String _section(
  String source,
  String startMarker,
  String endMarker,
) {
  final start = source.indexOf(startMarker);
  expect(
    start,
    isNot(-1),
    reason: 'Missing section start: $startMarker',
  );
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(
    end,
    isNot(-1),
    reason: 'Missing section end after $startMarker: $endMarker',
  );
  return source.substring(start, end);
}

void main() {
  test(
    'router exposes supplier-payment master, detail and audited edit',
    () {
      final router = _read('lib/shared/routes/app_router.dart');
      final barrel = _read('lib/shared/routes/erp_routes_barrel.dart');

      expect(router, contains("path: '/purchases/payments',"));
      expect(router, contains("state.uri.queryParameters['paymentId']"));
      expect(router, contains('erp.PurchasePaymentsListPage('));
      expect(router, contains('highlightPaymentId: paymentId'));
      expect(router, contains("path: '/purchases/payments/:id',"));
      expect(router, contains("path: '/purchases/payments/:id/edit',"));
      expect(
        router,
        contains('erp.PurchasePaymentDetailPage(paymentId: id)'),
      );
      expect(
        router,
        contains('erp.PurchasePaymentEditPage(paymentId: id)'),
      );

      final editRoute = router.indexOf("path: '/purchases/payments/:id/edit',");
      final detailRoute = router.indexOf("path: '/purchases/payments/:id',");
      final invoiceRoute = router.indexOf("path: '/purchases/:id',");
      expect(editRoute, greaterThanOrEqualTo(0));
      expect(detailRoute, greaterThanOrEqualTo(0));
      expect(editRoute, lessThan(detailRoute));
      expect(invoiceRoute, greaterThan(detailRoute));

      expect(
        barrel,
        contains(
          "export '../../modules/purchases/pages/"
          "purchase_payment_detail_page.dart';",
        ),
      );
      expect(
        barrel,
        contains(
          "export '../../modules/purchases/pages/"
          "purchase_payment_edit_page.dart';",
        ),
      );
    },
  );

  test(
    'supplier-payment full master is the configurable invoice-style table',
    () {
      final master = _read(
        'lib/modules/purchases/pages/purchase_payments_list_page.dart',
      );

      expect(master, contains('static const double _tableHeaderHeight = 38;'));
      expect(master, contains('static const double _tableRowHeight = 38;'));
      expect(master, contains('Widget _buildPaymentsTable('));
      expect(master, contains("ValueKey('purchase-payments-full-table')"));
      expect(master, contains('onTap: () => _changeSort(column.id)'));
      expect(master, contains('bool _matchesSmartSearch('));
      expect(master, contains('.every((token)'));
      expect(master, contains('Widget _buildDateFilter('));
      expect(master, contains('Widget _buildMethodFilter('));
      expect(master, contains('Widget _buildSupplierFilter('));
      expect(master, contains('int get _activeFilterCount'));

      for (final preferenceKey in [
        'purchase_payments_list_pane_width_v1',
        'purchase_payments_column_order_v1',
        'purchase_payments_visible_columns_v1',
        'purchase_payments_column_widths_v1',
      ]) {
        expect(master, contains(preferenceKey));
      }
      expect(master, contains('ReorderableListView.builder('));
      expect(master, contains('Draggable<String>('));
      expect(master, contains('DragTarget<String>('));
      expect(master, contains('void _reorderColumn('));
      expect(master, contains('void _resizeColumn('));
      expect(master, contains('SystemMouseCursors.resizeColumn'));
      expect(master, contains('_saveColumnPreferences()'));
      expect(master, contains('_syncHeaderToBody'));
      expect(master, contains('_syncBodyToHeader'));

      for (final columnId in [
        'code',
        'date',
        'supplier',
        'invoice',
        'method',
        'reference',
        'amount',
        'notes',
      ]) {
        expect(master, contains("id: '$columnId'"));
      }

      final fullView = _section(
        master,
        'Widget _buildFullTableView(',
        'Widget _buildSplitView(',
      );
      expect(fullView, contains('_buildSummaryCards(visibleRows)'));
      expect(fullView, contains('_buildPaymentsTable(visibleRows)'));
      expect(fullView, isNot(contains('_buildPaymentCardsList(')));

      final tableRow = _section(
        master,
        'Widget _buildTableRow(',
        'Widget _buildTableCell(',
      );
      expect(tableRow, contains('onTap: () => _selectRow(row)'));
      expect(tableRow, contains('Colors.grey[50]'));
      expect(tableRow, contains('Colors.blue[50]'));
      expect(tableRow, contains('width: 48'));
      final outerTableTap = _section(
        tableRow,
        'child: InkWell(',
        'child: Container(',
      );
      expect(outerTableTap, contains('onTap: () => _selectRow(row)'));
      expect(outerTableTap, isNot(contains('_openInvoice(row)')));

      final methodCell = _section(
        master,
        "case 'method':",
        "case 'reference':",
      );
      expect(methodCell, contains('_buildPaymentMethodChip(row)'));
      final invoiceCell = _section(
        master,
        "case 'invoice':",
        "case 'method':",
      );
      expect(invoiceCell, contains('onTap: () => _openInvoice(row)'));

      expect(master, contains('loadReferencedPaymentMethods('));
    },
  );

  test('supplier-payment split replaces the table with compact cards', () {
    final master = _read(
      'lib/modules/purchases/pages/purchase_payments_list_page.dart',
    );

    final split = _section(
      master,
      'Widget _buildSplitView(',
      'Widget _buildPaymentCardsList(',
    );
    expect(split, contains('_buildPaymentCardsList(visibleRows)'));
    expect(split, contains('PurchasePaymentDetailView('));
    expect(split, contains('Ajustar ancho de la lista de pagos'));
    expect(split, isNot(contains('_buildPaymentsTable(')));
    expect(split, isNot(contains('_buildTableHeader(')));
    expect(split, isNot(contains('_buildSummaryCards(')));
    expect(split, isNot(contains('_showColumnCustomizer')));
    expect(
      split,
      contains("ValueKey('purchase-payment-detail-\${selectedRow.id}')"),
    );

    final cards = _section(
      master,
      'Widget _buildPaymentCardsList(',
      'Widget _buildPaymentMethodChip(',
    );
    expect(
      cards,
      contains("ValueKey('purchase-payments-split-card-list')"),
    );
    expect(
      cards,
      contains("ValueKey('purchase-payment-card-\${row.id}')"),
    );
    expect(cards, contains('Colors.blue[50]'));
    expect(cards, contains('width: 3'));
    expect(cards, contains('bottom: BorderSide('));
    expect(cards, contains('_selectRow(row)'));
    expect(cards, contains('row.supplierName'));
    expect(cards, contains('row.payment.amount'));
    expect(cards, contains('row.code'));
    expect(cards, contains('_buildPaymentMethodChip(row)'));

    final outerTap = _section(
      cards,
      'onTap: () {',
      'child: Container(',
    );
    expect(outerTap, contains('_selectRow(row)'));
    expect(outerTap, isNot(contains('_openInvoice(row)')));
  });

  test('split and routed detail share supplier-payment-owned evidence', () {
    final master = _read(
      'lib/modules/purchases/pages/purchase_payments_list_page.dart',
    );
    final detailPage = _read(
      'lib/modules/purchases/pages/purchase_payment_detail_page.dart',
    );
    final detailView = _read(
      'lib/modules/purchases/widgets/purchase_payment_detail_view.dart',
    );
    final pdfGenerator = _read(
      'lib/shared/utils/purchase_payment_receipt_pdf_generator.dart',
    );
    final accounting = _read(
      'lib/shared/services/document_accounting_context_service.dart',
    );

    expect(master, contains('PurchasePaymentDetailView('));
    expect(
      detailPage,
      contains("import '../widgets/purchase_payment_detail_view.dart';"),
    );
    expect(detailPage, contains('class PurchasePaymentDetailPage'));
    expect(detailPage, contains('PurchasePaymentDetailView('));

    expect(
      detailView,
      contains('PurchasePaymentReceiptPdfGenerator.generate('),
    );
    expect(
      detailView,
      contains('PurchasePaymentReceiptPdfGenerator.fileName('),
    );
    expect(detailView, contains('await downloadFile('));
    expect(detailView, contains('await Printing.sharePdf('));
    expect(detailView, contains('await Printing.layoutPdf('));
    expect(detailView, contains("label: 'Compartir'"));
    expect(detailView, contains("label: 'Descargar PDF'"));
    expect(detailView, contains("label: 'Imprimir'"));
    expect(detailView, contains("label: 'Abrir factura'"));
    expect(detailView, contains("context.push('/purchases/\$invoiceId')"));
    expect(detailView, contains("label: 'Editar'"));
    expect(detailView, contains('/purchases/payments/\$id/edit'));
    expect(detailView, contains('loadPurchasePaymentEditEvents(paymentId)'));
    expect(detailView, contains('Historial de correcciones'));
    expect(detailView, contains('PurchasePaymentEditEvent event'));

    expect(pdfGenerator, contains('class PurchasePaymentReceiptPdfGenerator'));
    expect(pdfGenerator, contains('static Future<pw.Document> generate('));
    expect(pdfGenerator, contains('document.addPage('));
    expect(pdfGenerator, contains('No constituye factura ni DTE'));

    final paymentAccounting = _section(
      accounting,
      'Future<DocumentAccountingContext> loadPurchasePayment({',
      'Future<List<DocumentPaymentRecord>> _loadPayments({',
    );
    expect(paymentAccounting, contains("sourceModule: 'purchase_payments'"));
    expect(paymentAccounting, contains('sourceReferences: [paymentId]'));
    expect(paymentAccounting, isNot(contains("'purchase_invoices'")));
    expect(detailView, contains('.loadPurchasePayment('));
  });

  test('supplier-payment edit uses only the audited correction command', () {
    final edit = _read(
      'lib/modules/purchases/pages/purchase_payment_edit_page.dart',
    );
    final service = _read(
      'lib/modules/purchases/services/purchase_service.dart',
    );

    expect(edit, contains('class PurchasePaymentEditPage'));
    expect(edit, contains("ValueKey('purchase-payment-edit-form')"));
    expect(edit, contains('PurchasePaymentReceiptPdfGenerator.paymentNumber('));
    expect(edit, contains('fetchPurchasePayment('));
    expect(edit, contains('fetchPurchaseInvoice('));
    expect(edit, contains('getPaymentsForInvoice(payment.invoiceId)'));
    expect(edit, contains('item.id != payment.id'));
    expect(edit, contains('invoice.total - _otherActivePaidAmount'));

    expect(edit, contains("labelText: 'Medio de pago'"));
    expect(edit, contains("labelText: 'Importe pagado'"));
    expect(edit, contains("labelText: 'Fecha de pago'"));
    expect(edit, contains("labelText: 'Referencia externa'"));
    expect(edit, contains("labelText: 'Notas internas'"));
    expect(edit, contains("labelText: 'Motivo de la corrección *'"));
    expect(edit, contains('reason.length < 8'));
    expect(edit, contains('selected?.requiresReference'));

    expect(edit, contains("const ['admin', 'manager', 'accountant']"));
    expect(edit, contains("hasPermission('access_accounting')"));
    expect(
      edit,
      contains(
        "const ['admin', 'manager', 'cashier', 'accountant']",
      ),
    );
    expect(edit, contains("hasPermission('create_invoices')"));
    expect(edit, contains('method.isActive ||'));
    expect(edit, contains("'\${method.name} (inactivo)'"));

    expect(edit, contains('.correctPurchasePayment('));
    expect(edit, contains('current: payment'));
    expect(edit, contains('operationKey: _operationKey'));
    expect(edit, contains("_operationKey = const Uuid().v4()"));
    expect(edit, contains('_operationPayload != operationPayload'));
    expect(edit, contains("text.contains('40001')"));
    expect(edit, contains("label: const Text('Recargar pago')"));
    expect(edit, isNot(contains('_db.update(')));
    expect(edit, isNot(contains('_db.insert(')));
    expect(edit, isNot(contains('_db.delete(')));
    expect(edit, isNot(contains(".from('purchase_payments')")));
    expect(edit, isNot(contains(".from('journal_entries')")));

    final correction = _section(
      service,
      'Future<PurchasePaymentCorrectionResult> correctPurchasePayment({',
      'Future<List<PurchasePaymentEditEvent>> loadPurchasePaymentEditEvents(',
    );
    expect(correction, contains("'correct_purchase_payment'"));
    expect(correction, contains("'get_purchase_payment_edit_operation'"));
    expect(correction, contains("'p_expected_updated_at'"));
    expect(correction, contains("'p_operation_key'"));
    expect(correction, contains("'p_reason'"));
    expect(correction, isNot(contains("_db.update('purchase_payments'")));
  });

  test('deep links and registry preserve supplier-payment identity', () {
    final master = _read(
      'lib/modules/purchases/pages/purchase_payments_list_page.dart',
    );
    final purchaseInvoices = _read(
      'lib/modules/purchases/pages/purchase_invoice_list_page.dart',
    );
    final registry = _read(
      'docs/architecture/canonical-ui-surfaces.md',
    );

    expect(master, contains('widget.highlightPaymentId'));
    expect(master, contains('_selectedPaymentId'));
    expect(
      purchaseInvoices,
      contains(
        r"'/purchases/payments?paymentId=${Uri.encodeComponent(payment.id)}'",
      ),
    );

    expect(registry, contains('| Supplier-payment master/detail |'));
    expect(registry, contains('exact `?paymentId=` links'));
    expect(registry, contains('desktop split preview'));
    expect(registry, contains('mobile `/purchases/payments/:id`'));
    expect(
      registry,
      contains(
        '`purchase_payments_list_page.dart` + shared '
        '`PurchasePaymentDetailView` + `purchase_payment_detail_page.dart`',
      ),
    );
    expect(
      registry,
      contains(
        'Rows and card bodies never use the purchase invoice as their '
        'implicit destination',
      ),
    );
    expect(registry, contains('never squeeze the table into the split pane'));
    expect(registry, contains('`PurchasePaymentReceiptPdfGenerator`'));
    expect(registry, contains('`source_module=purchase_payments`'));
    expect(
      registry,
      contains('purchase invoice remains the sole owner of the purchase'),
    );
    expect(registry, contains('| Supplier-payment correction form |'));
    expect(registry, contains('`PurchaseService.correctPurchasePayment`'));
    expect(registry, contains('`correct_purchase_payment`'));
    expect(registry, contains('invoice total minus all other active payments'));
    expect(registry, contains('no client surface writes payment or journal'));
  });
}
