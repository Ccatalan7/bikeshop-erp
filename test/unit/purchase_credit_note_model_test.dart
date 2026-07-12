import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_credit_note.dart';

void main() {
  const balance = PurchaseCreditNoteLineBalance(
    lineIndex: 0,
    sourceLineKey: 'line-1',
    productName: 'Cadena',
    purchaseTreatment: 'inventory',
    originalQuantity: 10,
    originalNet: 10000,
    originalTax: 1900,
    creditedQuantity: 2,
    creditedNet: 2000,
    creditedTax: 380,
    remainingQuantity: 8,
    remainingNet: 8000,
    remainingTax: 1520,
  );

  test('quantity selection derives the server allocation proportions', () {
    final line =
        const PurchaseCreditNoteLineDraft(balance: balance).withQuantity(3);
    expect(line.netAmount, 3000);
    expect(line.taxAmount, 570);
    expect(line.totalAmount, 3570);
    expect(line.validate(), isNull);
  });

  test('financial credit payload explicitly declares zero stock ownership', () {
    final line =
        const PurchaseCreditNoteLineDraft(balance: balance).withQuantity(2);
    expect(line.toRpcJson(), {
      'line_index': 0,
      'credited_quantity': 2,
      'net_amount': 2000,
      'tax_amount': 380,
      'disposition': 'financial_only',
    });
  });

  test('supplier-return credit requires and respects a physical return link',
      () {
    final line = const PurchaseCreditNoteLineDraft(balance: balance)
        .withQuantity(3)
        .copyWith(
          disposition: PurchaseCreditDisposition.supplierReturn,
          supplierReturnLineId: 'return-line-1',
        );
    const option = PurchaseCreditReturnOption(
      id: 'return-line-1',
      sourceLineKey: 'line-1',
      returnNumber: 'DVP-00001',
      returnedQuantity: 4,
      creditedQuantity: 2,
    );
    expect(line.validate(returnOption: option), contains('supera'));
  });

  test('credit cannot exceed server-provided remaining amount', () {
    final line = const PurchaseCreditNoteLineDraft(balance: balance)
        .copyWith(quantity: 1, netAmount: 8001, taxAmount: 0);
    expect(line.validate(), contains('supera'));
  });

  test('issued records cannot use an internal void action', () {
    final record = PurchaseCreditNoteRecord.fromJson({
      'id': 'credit-1',
      'credit_note_number': 'NCC-00001',
      'status': 'posted',
      'official_dte_status': 'issued',
      'issue_date': '2026-07-11T12:00:00Z',
      'reason': 'Return',
      'total_amount': 1190,
    });
    expect(record.canVoid, isFalse);
  });

  test('supplier refund balance uses both note and invoice limits', () {
    final record = PurchaseCreditNoteRecord.fromJson({
      'id': 'credit-1',
      'credit_note_number': 'NCC-00001',
      'status': 'posted',
      'official_dte_status': 'internal',
      'issue_date': '2026-07-11T12:00:00Z',
      'reason': 'Return',
      'total_amount': 5000,
      'refunded_amount': 1000,
      'remaining_refundable': 4000,
      'invoice_credit_balance': 3000,
    });
    expect(record.availableToRefund, 3000);
    expect(record.canRefund, isTrue);
    expect(record.canVoid, isFalse);
  });

  test('supplier refund evidence deserializes external reference', () {
    final refund = PurchaseSupplierRefundRecord.fromJson({
      'id': 'refund-1',
      'purchase_credit_note_id': 'credit-1',
      'refund_number': 'RP-1',
      'status': 'posted',
      'refunded_at': '2026-07-11T12:00:00Z',
      'amount': 2200,
      'reference': 'DEP-22',
      'reason': 'Abono proveedor',
      'payment_methods': {'name': 'Banco'},
    });
    expect(refund.paymentMethodName, 'Banco');
    expect(refund.reference, 'DEP-22');
    expect(refund.canVoid, isTrue);
  });
}
