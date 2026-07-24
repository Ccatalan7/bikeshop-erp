import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_receipt_resolution.dart';

void main() {
  test('partially resolved cases remain actionable', () {
    final resolutionCase = PurchaseReceiptResolutionCase(
      id: 'case-1',
      number: 'CR-00001',
      purchaseInvoiceId: 'invoice-1',
      purchaseReceiptId: 'receipt-1',
      purchaseReceiptLineId: 'receipt-line-1',
      sourceLineIndex: 0,
      sourceLineKey: 'source-line-1',
      productName: 'Cadena',
      purchaseTreatment: 'inventory',
      kind: PurchaseReceiptDiscrepancyKind.shortage,
      reportedQuantity: 3,
      resolvedQuantity: 1,
      openQuantity: 2,
      effectiveStatus: 'partially_resolved',
      createdAt: DateTime.utc(2026, 7, 23),
      allocations: const [],
    );

    expect(resolutionCase.isOpen, isTrue);
    expect(resolutionCase.isResolved, isFalse);
  });

  test('unknown outcomes never masquerade as documented loss', () {
    expect(
      PurchaseReceiptResolutionOutcomeX.fromDatabase('future_outcome'),
      PurchaseReceiptResolutionOutcome.unknown,
    );
    expect(
      PurchaseReceiptResolutionOutcome.unknown.label,
      'Resolución desconocida',
    );
  });

  test('loss reversal evidence is not treated as an active resolution', () {
    final allocation = PurchaseReceiptResolutionAllocation(
      id: 'allocation-reversal',
      caseId: 'case-1',
      resolutionGroupId: 'group-reversal',
      outcome: PurchaseReceiptResolutionOutcome.documentedLossReversal,
      quantity: 2,
      effectiveStatus: 'reversal',
      isEffective: false,
      createdAt: DateTime.utc(2026, 7, 23),
    );

    expect(allocation.isActive, isFalse);
  });
}
