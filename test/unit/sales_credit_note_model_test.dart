import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/sales/models/sales_credit_note.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';

void main() {
  const balance = SalesCreditNoteLineBalance(
    lineIndex: 0,
    sourceLineKey: 'line-1',
    productName: 'Cadena',
    originalQuantity: 10,
    originalNet: 10000,
    originalTax: 1900,
    remainingQuantity: 8,
    remainingNet: 8000,
    remainingTax: 1520,
  );

  test('quantity derives exact whole-CLP financial allocation', () {
    final line =
        const SalesCreditNoteLineDraft(balance: balance).withQuantity(3);
    expect(line.netAmount, 3000);
    expect(line.taxAmount, 570);
    expect(line.totalAmount, 3570);
  });

  test('financial-only credit payload never claims stock ownership', () {
    final line =
        const SalesCreditNoteLineDraft(balance: balance).withQuantity(2);
    expect(line.toRpcJson(), {
      'line_index': 0,
      'credited_quantity': 2,
      'net_amount': 2000,
      'tax_amount': 380,
      'disposition': 'financial_only',
    });
  });

  test('return-backed credit requires enough linked physical quantity', () {
    final line = const SalesCreditNoteLineDraft(balance: balance)
        .withQuantity(3)
        .copyWith(
          disposition: SalesCreditDisposition.salesReturn,
          salesReturnLineId: 'return-line-1',
        );
    const option = SalesCreditReturnOption(
      id: 'return-line-1',
      sourceLineKey: 'line-1',
      returnNumber: 'DVC-00001',
      returnedQuantity: 3,
      creditedQuantity: 1,
    );
    expect(line.validate(returnOption: option), contains('supera'));
  });

  test('settlement fields deserialize but never write through invoice editor',
      () {
    final invoice = Invoice.fromJson({
      'id': 'invoice-1',
      'tenant_id': 'tenant-1',
      'invoice_number': 'FV-1',
      'date': '2026-07-11T12:00:00Z',
      'status': 'paid',
      'total': 11900,
      'paid_amount': 11900,
      'balance': 0,
      'credited_amount': 2380,
      'customer_credit_balance': 2380,
      'items': const [],
    });
    expect(invoice.creditedAmount, 2380);
    expect(invoice.customerCreditBalance, 2380);
    expect(invoice.toFirestoreMap(), isNot(contains('credited_amount')));
    expect(
        invoice.toFirestoreMap(), isNot(contains('customer_credit_balance')));
  });

  test('issued credit note cannot be internally voided', () {
    final record = SalesCreditNoteRecord.fromJson({
      'id': 'credit-1',
      'credit_note_number': 'NCV-1',
      'status': 'posted',
      'official_dte_status': 'issued',
      'issue_date': '2026-07-11T12:00:00Z',
      'reason': 'Devolución',
      'total_amount': 1190,
    });
    expect(record.canVoid, isFalse);
  });
}
