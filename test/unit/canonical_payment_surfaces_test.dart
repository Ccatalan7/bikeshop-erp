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
      contains('highlightPaymentId: paymentId'),
    );
    expect(
      router,
      contains("state.uri.queryParameters['openRequest']"),
    );
    expect(router, contains("path: '/sales/payments/:id',"));
    expect(router, contains('erp.PaymentDetailPage(paymentId: id)'));
    expect(router, contains("path: '/sales/payments/:id/edit',"));
    expect(router, contains('erp.PaymentEditPage(paymentId: id)'));
  });

  test(
    'payment master preserves configurable operations and payment identity',
    () {
      final master = _read(
        'lib/modules/sales/pages/payment_form_page.dart',
      );

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

  test('payment and linked-invoice navigation remain separate commands', () {
    final master = _read(
      'lib/modules/sales/pages/payment_form_page.dart',
    );

    final rowSelection = _section(
      master,
      'void _selectRow(',
      'void _openInvoice(',
    );
    final invoiceNavigation = _section(
      master,
      'void _openInvoice(',
      'bool get _isEditableTextFocused',
    );
    expect(
      rowSelection,
      contains(r"context.push('/sales/payments/${row.id}')"),
    );
    expect(rowSelection, contains('_selectedPaymentId = row.id'));
    expect(rowSelection, isNot(contains('/sales/invoices/')));
    expect(
      invoiceNavigation,
      contains(r"context.push('/sales/invoices/$invoiceId')"),
    );
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
      'lib/shared/utils/notification_deep_link.dart',
    );
    final accounting = _read(
      'lib/modules/accounting/widgets/accounting_dashboard_section.dart',
    );

    expect(
      notifications,
      contains("'sales_payment_received' => data['payment_id']"),
    );
    expect(
      notifications,
      contains("entityType == 'sales_payment'"),
    );
    expect(
      notifications,
      contains("queryParameters: {'paymentId': entityId}"),
    );
    expect(
      notifications,
      contains("if (type == 'sales_payment_voided')"),
    );
    expect(
      notifications,
      contains("'/sales/invoices/\${Uri.encodeComponent(invoiceId)}'"),
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
