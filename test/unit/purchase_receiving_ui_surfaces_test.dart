import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

void main() {
  test('split and routed purchase invoices share the inline workspace', () {
    final list = _read(
      'lib/modules/purchases/pages/purchase_invoice_list_page.dart',
    );
    final form = _read(
      'lib/modules/purchases/pages/purchase_invoice_form_page.dart',
    );
    final receiving = _read(
      'lib/modules/purchases/pages/purchase_receiving_page.dart',
    );
    final detail = _read(
      'lib/modules/purchases/widgets/purchase_receipt_detail_view.dart',
    );
    final dropdown = _read(
      'lib/modules/purchases/widgets/purchase_receipt_records_dropdown.dart',
    );
    final evidenceDropdown = _read(
      'lib/modules/purchases/widgets/purchase_invoice_evidence_dropdown.dart',
    );
    final router = _read('lib/shared/routes/app_router.dart');

    expect(list, contains('PurchaseReceivingWorkspace('));
    expect(list, contains('_receiptWorkspaceInvoice != null'));
    expect(form, contains('PurchaseReceivingWorkspace('));
    expect(
        form, contains('_showingReceiptWorkspace && _loadedInvoice != null'));
    expect(receiving, contains('class PurchaseReceivingWorkspace'));
    expect(receiving, contains('class _ReceiptGrid'));
    expect(receiving, contains('class _ProductThumbnail'));
    expect(receiving, contains('CachedNetworkImage'));
    expect(receiving, isNot(contains('class PurchaseReceivingPage')));
    expect(receiving, isNot(contains('return Scaffold(')));
    expect(receiving, isNot(contains('AppBar(')));
    expect(detail, contains('class PurchaseReceiptDetailView'));
    expect(dropdown, contains('class PurchaseReceiptRecordsDropdown'));
    expect(list, contains('PurchaseInvoiceEvidenceDropdown('));
    expect(list, isNot(contains('DocumentPaymentsDropdown(')));
    expect(list, isNot(contains('PurchaseReceiptRecordsDropdown(')));
    expect(evidenceDropdown, contains('DocumentPaymentRecordsTable('));
    expect(evidenceDropdown, contains('PurchaseReceiptRecordsTable('));
    expect(router, contains('/purchases/receipts/:receiptId'));

    expect(
      list,
      isNot(contains('MaterialPageRoute( builder: (_) => PurchaseReceiving')),
    );
    expect(
      form,
      isNot(contains('MaterialPageRoute( builder: (_) => PurchaseReceiving')),
    );
  });

  test('receipt evidence is independent from financial invoice status', () {
    final list = _read(
      'lib/modules/purchases/pages/purchase_invoice_list_page.dart',
    );
    final form = _read(
      'lib/modules/purchases/pages/purchase_invoice_form_page.dart',
    );
    final service = _read(
      'lib/modules/purchases/services/purchase_receiving_service.dart',
    );

    expect(
        service, contains('Future<PurchaseReceiptFulfillment> getFulfillment'));
    expect(
        service, contains('Future<Map<String, String>> getProductImageUrls'));
    expect(service, contains("'id,image_url,image_url_optimized'"));
    expect(service, contains('purchase_receipts!inner(id,status,received_at)'));
    expect(list, contains('PAGADA · RECIBIDA'));
    expect(list, contains('PAGADA · PARCIAL'));
    expect(form, contains('PAGADA · RECIBIDA'));
    expect(form, contains('PAGADA · RECEPCIÓN PARCIAL'));
    expect(form, contains('Recepciones y diferencias'));
    expect(
      _read('lib/modules/purchases/pages/purchase_receiving_page.dart'),
      contains('La recepción y la resolución son pasos separados'),
    );
    expect(
      list,
      contains('Inventario y resolución comercial se controlan por separado'),
    );
  });

  test('purchase list status presentation shares fulfillment derivation', () {
    final list = _read(
      'lib/modules/purchases/pages/purchase_invoice_list_page.dart',
    );

    expect(
        list, contains('final presentation = _statusPresentationFor(invoice)'));
    expect(
      list,
      contains(
        "label: isPaid ? 'PAGADA · RECIBIDA' : 'RECIBIDA'",
      ),
    );
    expect(
      list,
      contains(
        "label: isPaid ? 'PAGADA · PARCIAL' : 'RECEP. PARCIAL'",
      ),
    );
    expect(
      list,
      contains(
        "label: isPaid ? 'PAGADA · CERRADA CON DIF.' "
        ": 'CERRADA CON DIF.'",
      ),
    );
    expect(list, contains('color: presentation.background'));
    expect(list, contains('color: presentation.foreground'));
    expect(
      list,
      contains('presentation.foreground.withValues(alpha: 0.32)'),
    );
  });

  test('purchase list receives physical status in its first read model', () {
    final list = _read(
      'lib/modules/purchases/pages/purchase_invoice_list_page.dart',
    );
    final service = _read(
      'lib/modules/purchases/services/purchase_service.dart',
    );
    final invoice = _read(
      'lib/modules/purchases/models/purchase_invoice.dart',
    );

    expect(
      service,
      contains("'purchase_invoice_list_read_model'"),
      reason:
          'The first list query must combine invoice and physical fulfillment.',
    );
    expect(
      service,
      contains('PurchaseInvoice.listReadModelSelect'),
    );
    expect(
      invoice,
      contains("json.containsKey('receipt_state')"),
    );
    expect(
      list,
      contains('final readModelFulfillment = invoice.receiptFulfillment'),
      reason:
          'Rows must use fulfillment supplied by the same initial snapshot.',
    );
    expect(
      list,
      isNot(contains('_PurchaseInvoiceStatusPlaceholder')),
      reason: 'There is no per-row loading phase to mask with a placeholder.',
    );
    expect(
      list,
      isNot(contains('_queueMissingReceiptFulfillments')),
      reason:
          'The list must not hydrate physical status after its first render.',
    );
    expect(
      service,
      isNot(
        contains(
          '_listInvoiceCache =\n'
          '          _invoiceCache.map(_toListPreviewInvoice)',
        ),
      ),
      reason:
          'A full financial invoice read must not overwrite the authoritative '
          'list snapshot.',
    );
  });

  test('receipt workspace stays local to the existing purchase host', () {
    final receiving = _read(
      'lib/modules/purchases/pages/purchase_receiving_page.dart',
    );

    expect(receiving, contains('class PurchaseReceivingWorkspace'));
    expect(receiving, isNot(contains('return Scaffold(')));
    expect(receiving, isNot(contains('AppBar(')));
    expect(receiving, isNot(contains('AppTheme.')));
  });

  test('preview photos are bundled and receipt grid stays simple', () {
    final pubspec = _read('pubspec.yaml');
    final receiving = _read(
      'lib/modules/purchases/pages/purchase_receiving_page.dart',
    );

    expect(
      pubspec,
      contains(
        'assets/images/campaigns/products/10ten-butyl-26-cutout.png',
      ),
    );
    expect(
      pubspec,
      contains(
        'assets/images/campaigns/products/maxxis-welter-weight-29-cutout.png',
      ),
    );
    expect(
      pubspec,
      contains(
        'assets/images/campaigns/products/ridexc-butyl-29-cutout.png',
      ),
    );
    expect(receiving, contains("'RECIBIDO AHORA'"));
    expect(receiving, contains("'DIFERENCIA'"));
    expect(receiving, contains("_header('MOTIVO / EVIDENCIA'"));
    expect(receiving, contains('Detalle / evidencia (opcional)'));
    expect(
        receiving, contains("ValueKey('evidence-field-\${line.lineIndex}')"));
    expect(
      receiving,
      isNot(contains('static const double previouslyReceived')),
    );
    expect(
      receiving,
      isNot(contains('static const double previouslyResolved')),
    );
    expect(receiving, isNot(contains('static const double damaged')));
    expect(receiving, isNot(contains('static const double rejected')));
    expect(receiving, isNot(contains('static const double shortage')));
    expect(receiving, isNot(contains('static const double remaining')));
    expect(receiving, contains('Recibido antes:'));
    expect(receiving, contains('Saldo previo:'));
    expect(receiving, contains('Faltante / no llegó'));
    expect(receiving, contains('Rechazado / no conforme'));
    expect(receiving, contains('thumbVisibility: true'));
    expect(receiving, contains('highlightWhenPositive: false'));
  });

  test('linked credit notes open their exact document inside the host layout',
      () {
    final receiptDetail = _read(
      'lib/modules/purchases/pages/purchase_receipt_detail_page.dart',
    );
    final creditNote = _read(
      'lib/modules/purchases/pages/purchase_credit_note_page.dart',
    );
    final supplierReturn = _read(
      'lib/modules/purchases/pages/purchase_supplier_return_page.dart',
    );
    final register = _read(
      'lib/modules/purchases/widgets/purchase_receipt_resolution_register.dart',
    );
    final list = _read(
      'lib/modules/purchases/pages/purchase_invoice_list_page.dart',
    );

    expect(receiptDetail, contains('focusCreditNoteId: _focusedCreditNoteId'));
    expect(receiptDetail, contains('embedded: true'));
    expect(creditNote, contains('_buildFocusedDocument()'));
    expect(creditNote, contains('focusRefundId'));
    expect(supplierReturn, contains('focusReturnId'));
    expect(supplierReturn, contains('_buildFocusedReturn()'));
    expect(supplierReturn, contains('if (!widget.embedded)'));
    expect(
      register,
      contains('PurchaseReceiptResolutionDocumentKind.supplierRefund'),
    );
    expect(
      list,
      contains('onResolutionDocumentTap: _openResolutionDocument'),
    );
    expect(
      receiptDetail,
      contains('onResolutionDocumentTap: _openResolutionDocument'),
    );
    expect(
      receiptDetail,
      contains('focusRefundId: _focusedPurchaseRefundId'),
    );
    expect(
      receiptDetail,
      contains('focusReturnId: _focusedSupplierReturnId'),
    );
    expect(list, contains('_refreshSelectedInvoiceResolutionContext'));
    expect(creditNote, contains('volverá a quedar abierta'));
    expect(
      creditNote,
      contains('Esta nota resuelve una diferencia exacta'),
    );
  });

  test(
      'both invoice hosts keep receipt resolution explicit, deferrable and refreshable',
      () {
    final list = _read(
      'lib/modules/purchases/pages/purchase_invoice_list_page.dart',
    );
    final form = _read(
      'lib/modules/purchases/pages/purchase_invoice_form_page.dart',
    );

    for (final host in [list, form]) {
      expect(host, contains("title: const Text('Recepción registrada')"));
      expect(host, contains("child: const Text('Resolver ahora')"));
      expect(host, contains("child: const Text('Resolver después')"));
      expect(host, contains('barrierDismissible: false'));
      expect(host, contains('fulfillment.unresolvedDifferenceQuantity'));
      expect(host, contains('Registrar la recepción'));
      expect(host, contains('no genera automáticamente una nota de crédito'));
      expect(host, contains('getCasesForInvoice'));
      expect(host, isNot(contains('resolveWithDocumentedLoss(')));
      expect(host, isNot(contains('resolvePurchaseReceiptWithCreditNote')));
    }

    expect(list, contains('_openFirstPendingResolution(current)'));
    expect(form, contains('await _openFirstPendingResolution();'));
    expect(form, contains("'Resolver diferencias'"));
    expect(form, contains('Future<void> _openFirstPendingResolution()'));
    expect(
      form,
      contains('_openReceiptById(resolutionCase.purchaseReceiptId)'),
    );

    final firstPendingStart =
        form.indexOf('Future<void> _openFirstPendingResolution()');
    final supplierReturnStart =
        form.indexOf('Future<void> _openSupplierReturn()');
    final creditNoteStart =
        form.indexOf('Future<void> _openPurchaseCreditNote()');
    final cacheStart = form.indexOf('void _replaceProductCache(');
    expect(firstPendingStart, greaterThanOrEqualTo(0));
    expect(supplierReturnStart, greaterThan(firstPendingStart));
    expect(creditNoteStart, greaterThan(supplierReturnStart));
    expect(cacheStart, greaterThan(creditNoteStart));

    final firstPending = form.substring(firstPendingStart, supplierReturnStart);
    final supplierReturn = form.substring(supplierReturnStart, creditNoteStart);
    final creditNote = form.substring(creditNoteStart, cacheStart);
    expect(firstPending, isNot(contains('_receiveProducts')));
    expect(
      supplierReturn,
      contains('await _refreshAfterReceiptChange();'),
    );
    expect(
      creditNote,
      contains('await _refreshAfterReceiptChange();'),
    );
    expect(
      supplierReturn.indexOf('await _refreshAfterReceiptChange();'),
      lessThan(supplierReturn.indexOf('if (result != null && mounted)')),
    );
    expect(
      creditNote.indexOf('await _refreshAfterReceiptChange();'),
      lessThan(creditNote.indexOf('if (result != null && mounted)')),
    );
  });
}
