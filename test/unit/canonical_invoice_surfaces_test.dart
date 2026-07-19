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
    final purchaseForm =
        File('lib/modules/purchases/pages/purchase_invoice_form_page.dart')
            .readAsStringSync();
    final paymentForm =
        File('lib/modules/sales/widgets/payment_form.dart').readAsStringSync();
    final paymentPage =
        File('lib/modules/sales/pages/invoice_payment_page.dart')
            .readAsStringSync();
    final salesService = File('lib/modules/sales/services/sales_service.dart')
        .readAsStringSync();
    final correctionsMenu =
        File('lib/modules/sales/widgets/sales_corrections_menu.dart')
            .readAsStringSync();
    final voidService =
        File('lib/modules/sales/services/sales_invoice_void_service.dart')
            .readAsStringSync();
    final jobForm =
        File('lib/modules/bikeshop/pages/mechanic_job_form_page.dart')
            .readAsStringSync();

    expect(router, contains("path: '/sales/invoices/:id'"));
    expect(router, contains('erp.InvoiceFormPage('));
    expect(form, contains('SalesCorrectionsMenu('));
    expect(editor, contains('SalesCorrectionsMenu('));
    expect(listPreview, contains('SalesCorrectionsMenu('));
    expect(correctionsMenu, contains("value: 'void'"));
    expect(correctionsMenu, contains('Descartar factura'));
    expect(voidService, contains("'void_sales_invoice'"));
    expect(
      listPreview,
      contains('invoice.status != InvoiceStatus.cancelled'),
      reason:
          'The normal invoice list must hide cancelled audit evidence by default.',
    );
    expect(
      listPreview,
      contains("value: 'cancelled', child: Text('Anuladas')"),
      reason:
          'Cancelled invoices must remain reachable through an explicit filter.',
    );
    final summaryStart = listPreview.indexOf(
      'Widget _buildSummaryCards(List<Invoice> invoices)',
    );
    final summaryEnd = listPreview.indexOf(
      'Widget _buildSummaryCard(',
      summaryStart,
    );
    expect(summaryStart, greaterThanOrEqualTo(0));
    expect(summaryEnd, greaterThan(summaryStart));
    final summaryFlow = listPreview.substring(summaryStart, summaryEnd);
    expect(summaryFlow, contains('invoice.status != InvoiceStatus.draft'));
    expect(
      summaryFlow,
      contains('invoice.status != InvoiceStatus.cancelled'),
      reason:
          'Cancelled historical balances must not contaminate collection KPIs.',
    );
    expect(
      RegExp(r'if \(_canOfferInvoiceDelete\(invoice\)\)')
          .allMatches(listPreview)
          .length,
      2,
      reason:
          'Both list-row and selected-preview menus must hide physical deletion outside eligible drafts.',
    );
    expect(
      salesService,
      contains(".select('id, invoice_number, status')"),
      reason:
          'Deletion must re-read the authoritative server status before the destructive write.',
    );
    expect(paymentForm, contains('registerPaymentWithInvoiceTax('));
    expect(paymentForm, contains('_taxChoiceIsLocked'));
    expect(paymentForm, isNot(contains('value.defaultTaxTreatment ==')));
    expect(paymentPage, contains("'Factura pagada'"));
    expect(paymentPage, contains('if (isSettled)'));
    expect(
      salesService,
      contains("'register_sales_payment_with_invoice_tax'"),
    );
    final saveInvoiceStart = salesService.indexOf(
      'Future<Invoice> saveInvoice(Invoice invoice)',
    );
    final saveInvoiceEnd = salesService.indexOf(
      'Future<Invoice> createAtomicCheckout(',
      saveInvoiceStart,
    );
    expect(saveInvoiceStart, greaterThanOrEqualTo(0));
    expect(saveInvoiceEnd, greaterThan(saveInvoiceStart));
    expect(
      salesService.substring(saveInvoiceStart, saveInvoiceEnd),
      isNot(contains('sync_invoice_items_to_job')),
      reason:
          'The invoice transaction trigger is the sole normal save synchronizer.',
    );
    for (final invoiceSurface in <String, String>{
      'routed invoice form': form,
      'embedded invoice editor': editor,
    }.entries) {
      final saveStart = invoiceSurface.value.indexOf(
        'Future<void> _saveInvoice() async',
      );
      final saveEnd = invoiceSurface.value.indexOf(
        'Future<void> _downloadInvoicePDF',
        saveStart,
      );
      expect(saveStart, greaterThanOrEqualTo(0), reason: invoiceSurface.key);
      expect(saveEnd, greaterThan(saveStart), reason: invoiceSurface.key);
      final saveFlow = invoiceSurface.value.substring(saveStart, saveEnd);
      expect(
        saveFlow,
        contains('createInvoiceFromJob('),
        reason:
            '${invoiceSurface.key} must use the guarded atomic command for job-context creation.',
      );
      final canonicalCommand = saveFlow.indexOf('createInvoiceFromJob(');
      final manualValidation = saveFlow.indexOf(
        'if (_selectedCustomer == null)',
      );
      final genericSave = saveFlow.indexOf('_salesService.saveInvoice(');
      expect(
        canonicalCommand,
        lessThan(manualValidation),
        reason:
            '${invoiceSurface.key} must not require a second client-built invoice before invoking the job command.',
      );
      expect(
        canonicalCommand,
        lessThan(genericSave),
        reason:
            '${invoiceSurface.key} must choose the atomic job command before the generic invoice save.',
      );
      expect(
        saveFlow.substring(canonicalCommand, manualValidation),
        contains('return;'),
        reason:
            '${invoiceSurface.key} must leave the save flow after the job-context command.',
      );
      expect(
        saveFlow,
        isNot(contains(".from('mechanic_jobs')")),
        reason:
            '${invoiceSurface.key} must not create an invoice and then link the job client-side.',
      );
      expect(
        saveFlow,
        isNot(contains('triggerLinkedJobSync(')),
        reason:
            '${invoiceSurface.key} must not hide a best-effort post-save link/sync failure.',
      );
    }
    expect(
      form,
      contains('_loadedInvoice?.id == null && widget.invoiceId == null'),
      reason:
          'Existing linked invoices must remain editable through their normal invoice save.',
    );
    expect(
      editor,
      contains('_loadedInvoice?.id == null && widget.invoiceId == null'),
      reason:
          'Existing embedded invoices must not be mistaken for new job-context creation.',
    );
    expect(
      salesService,
      contains('Future<Invoice> saveInvoice(Invoice invoice)'),
      reason: 'Manual and existing invoices keep the normal save command.',
    );
    expect(jobForm, isNot(contains('_updateInvoiceTaxTreatment(')));
    expect(
      File('lib/modules/sales/pages/invoice_detail_page.dart').existsSync(),
      isFalse,
      reason: 'Do not reintroduce a competing, unrouted invoice detail page.',
    );

    expect(router, contains("path: '/purchases/:id'"));
    expect(router, contains('erp.PurchaseInvoiceFormPage('));
    expect(purchaseForm, contains('PurchaseReceiptHistoryPanel('));
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
