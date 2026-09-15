import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice_draft_seed.dart';

void main() {
  test('server document kind declares direct purchase behavior', () {
    final kind = PurchaseSourceDocumentKind.fromJson({
      'code': 'receipt',
      'display_name': 'Boleta',
      'description': 'Compra directa',
      'workflow_kind': 'direct_purchase',
      'sort_order': 20,
      'is_active': true,
    });

    expect(kind.displayName, 'Boleta');
    expect(kind.isDirectPurchase, isTrue);
  });

  test('malformed workflow kinds fail closed', () {
    expect(
      () => PurchaseSourceDocumentKind.fromJson({
        'code': 'receipt',
        'display_name': 'Boleta',
        'description': 'Compra directa',
        'workflow_kind': 'skip_everything',
      }),
      throwsFormatException,
    );
  });

  test('purchase invoice preserves source kind without persisting read label',
      () {
    final invoice = PurchaseInvoice.fromJson({
      'id': 'invoice-a',
      'tenant_id': 'tenant-a',
      'invoice_number': 'FC-100',
      'source_document_kind': 'ticket',
      'source_document_kind_label': 'Ticket o vale',
      'supplier_id': 'supplier-a',
      'date': '2026-08-16T12:00:00Z',
      'status': 'draft',
      'items': const [],
    });

    expect(invoice.sourceDocumentKind, 'ticket');
    expect(invoice.sourceDocumentKindLabel, 'Ticket o vale');
    expect(invoice.toJson()['source_document_kind'], 'ticket');
    expect(invoice.toJson(), isNot(contains('source_document_kind_label')));
  });

  test('local purchase draft seed keeps decimal quantity', () {
    final seed = PurchaseInvoiceDraftSeed(
      sourceDocumentKind: 'receipt',
      lines: const [
        PurchaseInvoiceDraftLineSeed(
          sourceNeedId: 'need-a',
          productId: 'product-a',
          productName: 'Cable por metro',
          quantity: 2.5,
        ),
      ],
    );

    expect(seed.lines.single.toFormJson()['suggested_quantity'], 2.5);
    expect(seed.lines.single.toFormJson()['source_need_id'], 'need-a');
  });

  test('purchase lines preserve their typed supply-need provenance', () {
    final line = PurchaseInvoiceItem.fromJson({
      'line_id': 'line-a',
      'source_need_id': 'need-a',
      'product_id': 'product-a',
      'product_name': 'Piñón',
      'quantity': 1,
      'unit_cost': 8990,
    });

    expect(line.sourceNeedId, 'need-a');
    expect(line.toJson()['source_need_id'], 'need-a');
    expect(line.copyWith(quantity: 2).sourceNeedId, 'need-a');
  });
}
