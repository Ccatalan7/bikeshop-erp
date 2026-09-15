import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Editing a purchase document from the list, and coming back to it.
///
/// The owner's report: a sent document could not be edited, «Volver a
/// borrador» waited on unrelated work, «Editar artículo» opened an empty
/// product editor, the list kept the pre-edit document after saving, and the
/// preview printed a text brand while the PDF printed the logo. The pages have
/// no widget-test harness (eight providers), so these are source guards on the
/// seams that fixed each one.
void main() {
  final form = File(
    'lib/modules/purchases/pages/purchase_invoice_form_page.dart',
  ).readAsStringSync();
  final list = File(
    'lib/modules/purchases/pages/purchase_invoice_list_page.dart',
  ).readAsStringSync();
  final service = File(
    'lib/modules/purchases/services/purchase_service.dart',
  ).readAsStringSync();
  final router = File('lib/shared/routes/app_router.dart').readAsStringSync();

  group('a sent document is still the buyer\'s text', () {
    test('draft and sent both allow editing; confirmed does not', () {
      expect(
        form,
        contains(
          'bool get _statusAllowsEditing =>\n'
          '      _status == PurchaseInvoiceStatus.draft ||\n'
          '      _status == PurchaseInvoiceStatus.sent;',
        ),
      );
      expect(
        form,
        contains(
            'bool get _canEditFields => _statusAllowsEditing && _isEditing;'),
      );
      expect(
        form,
        isNot(contains(
          '_status == PurchaseInvoiceStatus.draft && _isEditing;',
        )),
        reason: 'The old draft-only gate must not survive next to the new one.',
      );
    });

    test('the sent header offers Editar like the draft header does', () {
      final sentBranch = form.substring(
        form.indexOf('} else if (_status == PurchaseInvoiceStatus.sent) {'),
        form.indexOf(
            '} else if (_status == PurchaseInvoiceStatus.confirmed) {'),
      );
      expect(sentBranch, contains("Key('purchase-invoice-edit-sent')"));
      expect(sentBranch, contains("label: const Text('Editar')"));
      expect(sentBranch, contains("label: const Text('Volver a borrador')"));
    });

    test('saving keeps the evidence the document already carries', () {
      final persist = form.substring(
        form.indexOf('Future<PurchaseInvoice?> _persistInvoiceChanges('),
        form.indexOf(
            'Future<bool> _persistDraftChangesBeforeStatusTransition()'),
      );
      for (final field in [
        'sentDate: _loadedInvoice?.sentDate',
        'confirmedDate: _loadedInvoice?.confirmedDate',
        'paidAmount: _loadedInvoice?.paidAmount ?? 0',
        'supplierInvoiceNumber: _loadedInvoice?.supplierInvoiceNumber',
      ]) {
        expect(persist, contains(field),
            reason: '$field is not the form\'s to erase.');
      }
    });

    test('a pending edit is saved before any status change, sent included', () {
      final update = form.substring(
        form.indexOf(
            'Future<void> _updateStatus(PurchaseInvoiceStatus newStatus)'),
      );
      expect(
        update.substring(
            0, update.indexOf('_purchaseService.updateInvoiceStatus(')),
        contains('if (_statusAllowsEditing && _isEditing) {'),
      );
    });
  });

  group('the list opens the editor with intent and re-reads on return', () {
    test('the route understands ?edit=true', () {
      final route = router.substring(
        router.indexOf("path: '/purchases/:id',"),
        router.indexOf("path: '/purchases/:id/detail',"),
      );
      expect(
        route,
        contains(
            "startInEditMode: state.uri.queryParameters['edit'] == 'true'"),
      );
    });

    test('Editar pushes the edit intent and awaits the return', () {
      final open = list.substring(
        list.indexOf('Future<void> _openDocumentPage('),
      );
      expect(
          open,
          contains(
              "await context.push('/purchases/\$id\${edit ? '?edit=true' : ''}');"));
      expect(
          open, contains('await _refreshSelectedInvoiceResolutionContext();'));
      expect(
        list,
        contains('onPressed: () => _openDocumentPage(invoice, edit: true),'),
        reason:
            'The preview\'s Editar must go through the return-aware opener.',
      );
      expect(
        list,
        isNot(contains("context.push('/purchases/\${invoice.id}');")),
        reason:
            'No fire-and-forget push may remain: it never refreshed the pane.',
      );
    });

    test('the service reads the saved row back and re-reads the list', () {
      final save = service.substring(
        service.indexOf('Future<PurchaseInvoice> savePurchaseInvoice('),
        service.indexOf('Future<void> deletePurchaseInvoice('),
      );
      expect(
        save,
        contains('await getPurchaseInvoice(invoice.id!, refresh: true);'),
        reason: 'Without refresh the cached pre-edit row came back as «saved».',
      );
      expect(save, contains('unawaited(_refreshListInvoicesQuietly());'));
      expect(
        save,
        isNot(contains('await getPurchaseInvoices(forceRefresh: true);')),
        reason: 'A save must not reload the whole table before returning.',
      );
    });
  });

  group('a status change does only its own work', () {
    test('the journal reloads only when the transition posts or unposts', () {
      final update = service.substring(
        service.indexOf('Future<PurchaseInvoice?> updateInvoiceStatus('),
        service.indexOf('static bool _postsAccounting('),
      );
      expect(update, contains('unawaited(_refreshAccountingProjection());'));
      expect(update, contains('_postsAccounting(status)'));
      expect(
        update,
        isNot(contains(
            'await _accountingService!.journalEntries.loadJournalEntries();')),
        reason:
            'Draft ↔ sent touches no journal entry; it must not wait on one.',
      );
    });

    test('realtime refreshes the changed row, not the whole table', () {
      final handler = service.substring(
        service.indexOf('Future<void> _handleInvoiceRealtimeChange('),
        service.indexOf(
            'Future<PurchaseDocumentSendOutcome> markDocumentSentAfterDispatch('),
      );
      expect(handler, contains('await getPurchaseInvoice(id, refresh: true);'));
      expect(
          handler, isNot(contains('getPurchaseInvoices(forceRefresh: true)')));
      expect(
        service,
        contains(
            'if (_realtimeTenantId == tenantId && _purchaseInvoicesChannel != null) {'),
        reason:
            'Channels are bound once per tenant, not rebuilt on every load.',
      );
    });
  });

  group('a sales status change does only its own work too', () {
    final sales = File('lib/modules/sales/services/sales_service.dart')
        .readAsStringSync();

    test('the journal reloads only when the transition posts or unposts', () {
      final update = sales.substring(
        sales.indexOf('Future<Invoice?> updateInvoiceStatus('),
        sales.indexOf('static bool _postsAccounting('),
      );
      expect(update, contains('unawaited(_refreshAccountingProjection());'));
      expect(update, contains('_postsAccounting(status)'));
      expect(
        update,
        isNot(contains(
          'await _accountingService.journalEntries.loadJournalEntries();',
        )),
        reason:
            'Draft ↔ sent touches no journal entry; it must not wait on one.',
      );
      expect(
        sales,
        contains(
          'status == InvoiceStatus.confirmed ||\n'
          '      status == InvoiceStatus.paid ||\n'
          '      status == InvoiceStatus.overdue;',
        ),
        reason: "The trigger's non-posted list is draft, sent and cancelled.",
      );
    });

    test('saving a draft does not wait on the journal either', () {
      final save = sales.substring(
        sales.indexOf('Future<Invoice> saveInvoice('),
        sales.indexOf('Future<Invoice> createAtomicCheckout('),
      );
      expect(save, contains('if (_postsAccounting(savedInvoice.status)) {'));
      expect(
        save,
        isNot(contains(
          'await _accountingService.journalEntries.loadJournalEntries();',
        )),
      );
    });

    test('channels are bound once per tenant and the form does not re-fetch',
        () {
      expect(
        sales,
        contains(
            'if (_realtimeTenantId == tenantId && _invoiceChannel != null) {'),
      );
      final form = File('lib/modules/sales/pages/invoice_form_page.dart')
          .readAsStringSync();
      final transition = form.substring(
        form.indexOf('Future<bool> _updateStatusInternal('),
        form.indexOf("'ensure_sales_invoice_journal_entry'"),
      );
      expect(
        transition,
        isNot(contains(
            '_applyInvoice(updated);\n        await _refreshInvoiceById(invoiceId);')),
        reason:
            'The service already read the row back; a second fetch was a wasted round trip.',
      );
    });
  });

  test('no payment path waits on the accounting book either', () {
    // The write is awaited and errors surface there; only the re-read of the
    // journal runs in the background. Each service keeps exactly one awaited
    // reload: the one inside its background helper.
    final sales = File('lib/modules/sales/services/sales_service.dart')
        .readAsStringSync();
    expect(
      'await _accountingService.journalEntries.loadJournalEntries();'
          .allMatches(sales)
          .length,
      1,
      reason: 'Sales: only _refreshAccountingProjection may await the book.',
    );
    final purchases =
        File('lib/modules/purchases/services/purchase_service.dart')
            .readAsStringSync();
    expect(
      RegExp(r'await [a-zA-Z_!.]*journalEntries\.loadJournalEntries\(\);')
          .allMatches(purchases)
          .length,
      1,
      reason:
          'Purchases: only _refreshAccountingProjection may await the book.',
    );
    for (final method in [
      'Future<Payment> registerPayment(',
      'Future<Payment> registerPaymentWithInvoiceTax(',
      'Future<void> deletePayment(',
    ]) {
      expect(sales, contains(method));
    }
  });

  test('the preview prints the same brand the PDF prints', () {
    final brand = list.substring(
      list.indexOf('Widget _buildPreviewBrand('),
      list.indexOf('Widget _buildTableCell('),
    );
    expect(brand, contains('context.read<AppearanceService>().companyLogoUrl'));
    expect(brand, contains("key: const Key('purchase-preview-logo')"));
    expect(brand, contains('width: 120 * scale'));
    expect(brand, contains('height: 40 * scale'));
    final pdf = File('lib/shared/utils/purchase_document_pdf_generator.dart')
        .readAsStringSync();
    expect(pdf, contains('width: 120, height: 40, fit: pw.BoxFit.contain'));
  });

  test('a sales line reaches the catalog through the same owners', () {
    final sales = File('lib/modules/sales/pages/invoice_form_page.dart')
        .readAsStringSync();
    expect(
      sales,
      contains("import '../../inventory/widgets/product_detail_sheet.dart';"),
    );
    expect(
      sales,
      contains("import '../../inventory/widgets/product_editor_dialog.dart';"),
    );
    expect(sales, contains('onShowProductDetails: _showProductDetails,'));
    expect(
      sales,
      isNot(contains("'Detalles del Producto'")),
      reason: 'The line-local pane listed five fields; the shared sheet is '
          'the inventory detail pane.',
    );
    expect(
      sales,
      isNot(contains(
          'ProductFormPage(productId: product.id, showInDialog: true)')),
    );
  });

  test('a purchase line reaches the catalog through the canonical owners', () {
    expect(
        form,
        contains(
            "import '../../inventory/widgets/product_detail_sheet.dart';"));
    expect(
        form,
        contains(
            "import '../../inventory/widgets/product_editor_dialog.dart';"));
    expect(
      form,
      isNot(contains(
          'ProductFormPage(productId: product.id, showInDialog: true)')),
      reason:
          'The line-local Dialog wrapper opened the editor with an empty id.',
    );
    expect(form, contains('onCreateCatalogProduct: _createCatalogProduct,'));
  });
}
