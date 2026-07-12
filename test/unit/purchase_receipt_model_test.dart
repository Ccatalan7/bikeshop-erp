import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_receipt.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_receiving_service.dart';

void main() {
  group('PurchaseReceiptLineDraft', () {
    const base = PurchaseReceiptLineDraft(
      lineIndex: 0,
      productName: 'Cadena',
      expectedQuantity: 10,
      previouslyReceivedQuantity: 3,
      acceptedQuantity: 5,
      damagedQuantity: 1,
      shortageQuantity: 1,
      discrepancyReason: 'Caja incompleta',
    );

    test('derives receipt totals without treating discrepancies as stock', () {
      expect(base.remainingBefore, 7);
      expect(base.reportedNow, 7);
      expect(base.remainingAfter, 2);
      expect(base.hasDiscrepancy, isTrue);
      expect(base.validate(), isNull);
    });

    test('serializes the exact database command payload', () {
      expect(base.toRpcJson(), {
        'line_index': 0,
        'accepted_quantity': 5,
        'damaged_quantity': 1,
        'rejected_quantity': 0,
        'shortage_quantity': 1,
        'discrepancy_reason': 'Caja incompleta',
      });
    });

    test('rejects a no-op line', () {
      expect(
        base
            .copyWith(
              acceptedQuantity: 0,
              damagedQuantity: 0,
              rejectedQuantity: 0,
              shortageQuantity: 0,
            )
            .validate(),
        contains('cantidad recibida'),
      );
    });

    test('rejects quantities above the remaining invoice quantity', () {
      expect(
        base.copyWith(acceptedQuantity: 6).validate(),
        contains('superan'),
      );
    });

    test('requires a discrepancy reason', () {
      const line = PurchaseReceiptLineDraft(
        lineIndex: 0,
        productName: 'Cadena',
        expectedQuantity: 2,
        previouslyReceivedQuantity: 0,
        acceptedQuantity: 1,
        damagedQuantity: 1,
      );
      expect(line.validate(), contains('Explica la diferencia'));
    });
  });

  test('control mode enables commands only in enforce mode', () {
    expect(PurchaseReceiptControlMode.enforce.acceptsCommands, isTrue);
    expect(PurchaseReceiptControlMode.shadow.acceptsCommands, isFalse);
    expect(PurchaseReceiptControlModeX.fromDatabase('unknown'),
        PurchaseReceiptControlMode.disabled);
  });

  test('old backend schema errors use the legacy-compatible path', () {
    expect(
      PurchaseReceivingBackendCompatibility.isSchemaUnavailable(
        const PostgrestException(message: 'missing relation', code: '42P01'),
      ),
      isTrue,
    );
    expect(
      PurchaseReceivingBackendCompatibility.isSchemaUnavailable(
        const PostgrestException(message: 'schema cache', code: 'PGRST205'),
      ),
      isTrue,
    );
  });

  test('auth and business errors never silently fall back', () {
    expect(
      PurchaseReceivingBackendCompatibility.isSchemaUnavailable(
        const PostgrestException(message: 'not authorized', code: '42501'),
      ),
      isFalse,
    );
  });
}
