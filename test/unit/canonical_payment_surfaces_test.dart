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
  test('router exposes canonical payment master, detail, and edit routes', () {
    final router = _read('lib/shared/routes/app_router.dart');

    expect(router, contains("path: '/sales/payments',"));
    expect(router, contains("state.uri.queryParameters['paymentId']"));
    expect(
      router,
      contains('erp.PaymentsPage(highlightPaymentId: paymentId)'),
    );
    expect(router, contains("path: '/sales/payments/:id',"));
    expect(router, contains('erp.PaymentDetailPage(paymentId: id)'));
    expect(router, contains("path: '/sales/payments/:id/edit',"));
    expect(router, contains('erp.PaymentEditPage(paymentId: id)'));
  });

  test(
    'payment full-width master matches the configurable sales-invoice table',
    () {
      final master = _read(
        'lib/modules/sales/pages/payment_form_page.dart',
      );

      expect(master, contains('static const double _tableHeaderHeight = 38;'));
      expect(master, contains('static const double _tableRowHeight = 38;'));
      expect(master, contains('Widget _buildPaymentsTable('));
      expect(master, contains('ListView.builder('));
      expect(master, contains('onTap: () => _changeSort(column.id)'));
      expect(master, contains('bool _matchesSmartSearch('));
      expect(master, contains('.every((token)'));
      expect(master, contains('Widget _buildDateFilter('));
      expect(master, contains('Widget _buildMethodFilter('));
      expect(master, contains('Widget _buildSourceFilter('));
      expect(master, contains('int get _activeFilterCount'));

      for (final preferenceKey in [
        'sales_payments_list_pane_width_v1',
        'sales_payments_column_order_v1',
        'sales_payments_visible_columns_v1',
        'sales_payments_column_widths_v1',
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
      expect(master, contains("ValueKey('payments-full-table')"));

      for (final columnId in [
        'code',
        'date',
        'customer',
        'invoice',
        'method',
        'reference',
        'amount',
        'net',
        'iva',
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

      final tableHeader = _section(
        master,
        'Widget _buildTableHeader(',
        'Widget _buildHeaderCell(',
      );
      expect(tableHeader, contains('Colors.grey[50]'));
      expect(tableHeader, contains('Colors.grey[300]'));
      expect(tableHeader, contains('width: 48'));
      expect(tableHeader, contains('Checkbox('));

      final tableRow = _section(
        master,
        'Widget _buildTableRow(',
        'Widget _buildTableCell(',
      );
      expect(tableRow, contains('onTap: () => _selectRow(row)'));
      expect(tableRow, contains('Colors.grey[50]'));
      expect(tableRow, contains('Colors.blue[50]'));
      expect(tableRow, contains('width: 48'));
      expect(tableRow, contains('PopupMenuButton<String>('));
      expect(tableRow, isNot(contains('/sales/invoices/')));
      final outerTableTap = _section(
        tableRow,
        'child: InkWell(',
        'child: Container(',
      );
      expect(outerTableTap, contains('onTap: () => _selectRow(row)'));
      expect(outerTableTap, isNot(contains('_openInvoice(row)')));

      final tableCell = _section(
        master,
        'Widget _buildTableCell(',
        'String? _cellTooltip(',
      );
      expect(tableCell, contains('fontSize: 13'));
      expect(
        _section(tableCell, "case 'method':", "case 'reference':"),
        contains('_buildPaymentMethodChip(row)'),
      );
      expect(
        tableCell,
        contains('padding: const EdgeInsets.symmetric(horizontal: 12)'),
      );
      expect(tableCell, isNot(contains('BorderSide(')));

      final methodChip = _section(
        master,
        'Widget _buildPaymentMethodChip(',
        'Widget _buildToolbar(',
      );
      expect(methodChip, contains('Colors.green'));
      expect(methodChip, contains('Colors.blue'));
      expect(methodChip, contains('Colors.purple'));
      expect(methodChip, contains('Colors.teal'));
      expect(methodChip, contains('Colors.orange'));
      expect(methodChip, contains('Colors.grey'));
      expect(methodChip, contains('tone[100]'));
      expect(methodChip, contains('lightBackgroundShade = 200'));
      expect(methodChip, contains('lightForegroundShade = 700'));
      expect(methodChip, contains('BorderRadius.circular(3)'));
      expect(methodChip, contains('fontSize: 10.5'));
      expect(methodChip, contains('fontWeight: FontWeight.w600'));

      final mobileCard = _section(
        master,
        'Widget _buildMobilePaymentCard(',
        'Widget _buildErrorState(',
      );
      expect(
        mobileCard,
        contains(r"context.push('/sales/payments/${row.id}')"),
      );

      final rowSelection = _section(
        master,
        'void _selectRow(',
        'void _openInvoice(',
      );
      expect(
        rowSelection,
        contains(r"context.push('/sales/payments/${row.id}')"),
      );
      expect(rowSelection, isNot(contains('/sales/invoices/')));

      final invoiceCell = _section(
        master,
        "case 'invoice':",
        "case 'method':",
      );
      expect(invoiceCell, contains('onTap: () => _openInvoice(row)'));
    },
  );

  test('payment split replaces the table with sales-invoice-style cards', () {
    final master = _read(
      'lib/modules/sales/pages/payment_form_page.dart',
    );

    final split = _section(
      master,
      'Widget _buildSplitView(',
      'Widget _buildPaymentCardsList(',
    );
    expect(split, contains('_buildPaymentCardsList(visibleRows)'));
    expect(split, contains('PaymentDetailView('));
    expect(split, contains('Ajustar ancho de la lista de pagos'));
    expect(split, isNot(contains('_buildPaymentsTable(')));
    expect(split, isNot(contains('_buildTableHeader(')));
    expect(split, isNot(contains('_buildSummaryStrip(')));
    expect(split, isNot(contains('_showColumnCustomizer')));

    final cards = _section(
      master,
      'Widget _buildPaymentCardsList(',
      'Widget _buildPaymentMethodChip(',
    );
    expect(cards, contains("ValueKey('payments-split-card-list')"));
    expect(cards, contains("ValueKey('payment-card-\${row.id}')"));
    expect(cards, contains('Colors.blue[50]'));
    expect(cards, contains('width: 3'));
    expect(cards, contains('bottom: BorderSide('));
    expect(cards, contains('_selectRow(row)'));
    expect(cards, contains('row.customerName'));
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

  test('split and routed detail share real payment receipt actions', () {
    final master = _read(
      'lib/modules/sales/pages/payment_form_page.dart',
    );
    final detailPage = _read(
      'lib/modules/sales/pages/payment_detail_page.dart',
    );
    final detailView = _read(
      'lib/modules/sales/widgets/payment_detail_view.dart',
    );
    final pdfGenerator = _read(
      'lib/shared/utils/payment_receipt_pdf_generator.dart',
    );

    final split = _section(
      master,
      'Widget _buildSplitView(',
      'Widget _buildToolbar(',
    );
    expect(split, contains('PaymentDetailView('));
    expect(
      detailPage,
      contains("import '../widgets/payment_detail_view.dart';"),
    );
    expect(detailPage, contains('class PaymentDetailPage'));
    expect(detailPage, contains('PaymentDetailView('));
    expect(detailView, contains('class PaymentDetailView'));
    expect(
      detailView,
      contains(r"context.push('/sales/payments/$id/edit')"),
    );

    expect(detailView, contains('PaymentReceiptPdfGenerator.generate('));
    expect(detailView, contains('PaymentReceiptPdfGenerator.fileName('));
    expect(detailView, contains('await downloadFile('));
    expect(detailView, contains('await Printing.sharePdf('));
    expect(detailView, contains('await Printing.layoutPdf('));
    expect(detailView, contains("label: 'Compartir'"));
    expect(detailView, contains("label: 'Descargar PDF'"));
    expect(detailView, contains("label: 'Imprimir'"));

    expect(pdfGenerator, contains('class PaymentReceiptPdfGenerator'));
    expect(pdfGenerator, contains('static Future<pw.Document> generate('));
    expect(pdfGenerator, contains('final document = pw.Document('));
    expect(pdfGenerator, contains('document.addPage('));
    expect(pdfGenerator, contains('_nonFiscalNotice()'));
    expect(pdfGenerator, contains('No constituye factura ni DTE'));
  });

  test('payment edit saves only through the audited correction command', () {
    final editPage = _read(
      'lib/modules/sales/pages/payment_edit_page.dart',
    );
    final service = _read(
      'lib/modules/sales/services/sales_service.dart',
    );

    final save = _section(
      editPage,
      'Future<void> _save() async {',
      ' @override',
    );
    expect(save, contains('.correctSalesPayment('));
    expect(save, contains('reason: _reasonController.text'));
    expect(save, isNot(contains('.registerPayment(')));
    expect(save, isNot(contains(".from('sales_payments')")));
    expect(save, isNot(contains('.update(')));
    expect(save, isNot(contains('.insert(')));

    final correction = _section(
      service,
      'Future<SalesPaymentCorrectionResult> correctSalesPayment({',
      'Future<List<SalesPaymentEditEvent>> loadPaymentEditEvents(',
    );
    expect(correction, contains("'correct_sales_payment'"));
    expect(correction, contains("'get_sales_payment_edit_operation'"));
    expect(correction, contains("'p_payment_id': paymentId"));
    expect(correction, contains("'p_expected_updated_at'"));
    expect(correction, contains("'p_operation_key': key"));
    expect(correction, contains("'p_reason': reason.trim()"));
    expect(correction, contains('const Uuid().v4()'));
    expect(correction, contains('_isOutcomeAmbiguous(error)'));
    expect(
      correction,
      contains('fetchInvoice(result.payment.invoiceId, refresh: true)'),
    );
    expect(correction, contains('loadPayments(forceRefresh: true)'));
    expect(correction, isNot(contains(".from('sales_payments')")));
    expect(correction, isNot(contains('.update(')));
    expect(correction, isNot(contains('.insert(')));
  });

  test('managed payment sources stay locked in the correction form', () {
    final editPage = _read(
      'lib/modules/sales/pages/payment_edit_page.dart',
    );
    final policy = _read(
      'lib/modules/sales/utils/payment_edit_policy.dart',
    );

    expect(
      editPage,
      contains('SalesPaymentEditPolicy.canEditFinancialFields('),
    );
    expect(
      editPage,
      contains('SalesPaymentEditPolicy.canEditReference(invoice)'),
    );
    expect(editPage, contains('enabled: canEditFinancial'));
    expect(editPage, contains('enabled: canEditReference'));
    expect(editPage, contains('SalesPaymentEditPolicy.lockedMessage('));

    for (final source in [
      'pos',
      'quick_sale',
      'ecommerce',
      'online_order',
      'online_orders',
      'mercado_pago',
      'webpay',
    ]) {
      expect(policy, contains("'$source'"));
    }
    expect(policy, contains('if (isSourceManaged(invoice)) return false;'));
    expect(
      policy,
      contains(
        'static bool canEditReference(Invoice invoice) => '
        '!isSourceManaged(invoice);',
      ),
    );
    expect(policy, contains('aquí solo puedes agregar'));
    expect(policy, contains('notas sin alterar la contabilidad'));
  });

  test('notification and accounting entry points preserve payment identity',
      () {
    final notifications = _read(
      'lib/shared/widgets/notifications_panel.dart',
    );
    final accounting = _read(
      'lib/modules/accounting/widgets/accounting_dashboard_section.dart',
    );

    expect(
      notifications,
      contains("final entityId = row['entity_id']?.toString().trim();"),
    );
    expect(
      notifications,
      contains("storedRoute == '/sales/payments'"),
    );
    expect(
      notifications,
      contains(
        r"'/sales/payments?paymentId=${Uri.encodeComponent(entityId)}'",
      ),
    );

    final paymentBranch = _section(
      accounting,
      "if (item.sourceType == 'sales_payment') {",
      'final detailKey = _detailKeyFor(item);',
    );
    expect(
      paymentBranch,
      contains(r"context.push('/sales/payments/${item.id}')"),
    );
    expect(paymentBranch, contains('return;'));
    expect(paymentBranch, isNot(contains('/sales/invoices/')));
  });

  test('canonical registry locks both received-payment surfaces', () {
    final registry = _read(
      'docs/architecture/canonical-ui-surfaces.md',
    );

    expect(registry, contains('| Received-payment master/detail |'));
    expect(registry, contains('exact `?paymentId=` links'));
    expect(registry, contains('desktop split preview'));
    expect(registry, contains('mobile `/sales/payments/:id`'));
    expect(
      registry,
      contains(
        '`payment_form_page.dart` + shared `PaymentDetailView` + '
        '`payment_detail_page.dart`',
      ),
    );
    expect(
      registry,
      contains(
        'Rows and card bodies never use the parent invoice as their implicit '
        'destination.',
      ),
    );
    expect(registry, contains('sales-invoice-style compact payment-card rail'));
    expect(registry, contains('never squeeze the table into the split pane'));
    expect(registry, contains('`PaymentReceiptPdfGenerator`'));

    expect(registry, contains('| Received-payment correction form |'));
    expect(registry, contains('`/sales/payments/:id/edit`'));
    expect(
      registry,
      contains(
        '`payment_edit_page.dart` + `SalesService.correctSalesPayment` + '
        '`correct_sales_payment`',
      ),
    );
    expect(registry, contains('optimistic version'));
    expect(registry, contains('exact lost-ack readback'));
  });
}
