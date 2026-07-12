import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_supplier_return.dart';

void main() {
  group('PurchaseSupplierReturnLineDraft', () {
    const line = PurchaseSupplierReturnLineDraft(
      receiptLineId: 'receipt-line-1',
      productName: 'Cadena',
      productSku: 'CHAIN-1',
      acceptedQuantity: 10,
      previouslyReturnedQuantity: 3,
      returnedQuantity: 4,
      reason: 'Modelo incorrecto',
    );

    test('derives the returnable receipt balance', () {
      expect(line.returnableQuantity, 7);
      expect(line.isSelected, isTrue);
      expect(line.validate(), isNull);
    });

    test('serializes only the physical return command fields', () {
      expect(line.toRpcJson(), {
        'receipt_line_id': 'receipt-line-1',
        'returned_quantity': 4,
        'reason': 'Modelo incorrecto',
      });
    });

    test('rejects quantities above the accepted unreturned balance', () {
      expect(
        line.copyWith(returnedQuantity: 8).validate(),
        contains('supera'),
      );
    });

    test('rejects zero-effect return lines', () {
      expect(
        line.copyWith(returnedQuantity: 0).validate(),
        contains('positiva'),
      );
    });
  });

  test('receipt aggregates returnable quantities across its lines', () {
    final receipt = PurchaseReturnableReceipt(
      id: 'receipt-1',
      receiptNumber: 'REC-00001',
      receivedAt: DateTime.utc(2026, 7, 11),
      lines: const [
        PurchaseSupplierReturnLineDraft(
          receiptLineId: 'line-1',
          productName: 'A',
          acceptedQuantity: 5,
          previouslyReturnedQuantity: 1,
        ),
        PurchaseSupplierReturnLineDraft(
          receiptLineId: 'line-2',
          productName: 'B',
          acceptedQuantity: 3,
          previouslyReturnedQuantity: 0,
        ),
      ],
    );
    expect(receipt.returnableQuantity, 7);
  });

  test('return history aggregates commercial quantities and void state', () {
    final record = PurchaseSupplierReturnRecord.fromJson({
      'id': 'return-1',
      'return_number': 'DVP-00001',
      'status': 'posted',
      'returned_at': '2026-07-11T12:00:00Z',
      'reason': 'Modelo incorrecto',
      'purchase_supplier_return_lines': [
        {'returned_quantity': 2},
        {'returned_quantity': 3},
      ],
    });
    expect(record.quantity, 5);
    expect(record.canVoid, isTrue);
  });
}
