import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_receipt.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_receiving_service.dart';

void main() {
  group('PurchaseReceiptLineDraft', () {
    const base = PurchaseReceiptLineDraft(
      lineIndex: 0,
      productName: 'Cadena',
      productImageUrl: 'https://example.test/cadena.webp',
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

    test('keeps presentation-only product image out of the command payload',
        () {
      expect(base.productImageUrl, 'https://example.test/cadena.webp');
      expect(base.copyWith(acceptedQuantity: 4).productImageUrl,
          base.productImageUrl);
      expect(base.toRpcJson(), isNot(contains('product_image_url')));
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

    test('subtracts non-physical resolutions from the receivable balance', () {
      const line = PurchaseReceiptLineDraft(
        lineIndex: 0,
        productName: 'Cadena',
        expectedQuantity: 10,
        previouslyReceivedQuantity: 7,
        previouslyResolvedQuantity: 2,
        acceptedQuantity: 1,
      );

      expect(line.remainingBefore, 1);
      expect(line.remainingAfter, 0);
      expect(line.validate(), isNull);
      expect(
          line.copyWith(acceptedQuantity: 2).validate(), contains('superan'));
    });
  });

  group('PurchaseReceiptFulfillment', () {
    test('keeps payment-independent receipt state empty without evidence', () {
      final fulfillment = PurchaseReceiptFulfillment.derive(
        expectedQuantities: const [10, 1],
        acceptedByLine: const {},
      );

      expect(fulfillment.state, PurchaseReceiptFulfillmentState.none);
      expect(fulfillment.expectedQuantity, 11);
      expect(fulfillment.remainingQuantity, 11);
      expect(fulfillment.hasReceiptEvidence, isFalse);
    });

    test('marks a fully accepted posted receipt complete', () {
      final fulfillment = PurchaseReceiptFulfillment.derive(
        expectedQuantities: const [10, 1, 1],
        acceptedByLine: const {0: 10, 1: 1, 2: 1},
        receiptCount: 1,
        latestReceivedAt: DateTime.utc(2026, 7, 23),
      );

      expect(fulfillment.state, PurchaseReceiptFulfillmentState.complete);
      expect(fulfillment.acceptedQuantity, 12);
      expect(fulfillment.remainingQuantity, 0);
      expect(fulfillment.receiptCount, 1);
    });

    test('reports a partial receipt without assuming another delivery', () {
      final fulfillment = PurchaseReceiptFulfillment.derive(
        expectedQuantities: const [10],
        acceptedByLine: const {0: 7},
        differencesByLine: const {0: 3},
        receiptCount: 1,
      );

      expect(fulfillment.state, PurchaseReceiptFulfillmentState.open);
      expect(fulfillment.acceptedQuantity, 7);
      expect(fulfillment.reportedDifferenceQuantity, 3);
      expect(fulfillment.remainingQuantity, 3);
      expect(fulfillment.hasReportedDifferences, isTrue);
    });

    test('closes commercially without falsifying physical receipt', () {
      final fulfillment = PurchaseReceiptFulfillment.derive(
        expectedQuantities: const [10],
        acceptedByLine: const {0: 7},
        differencesByLine: const {0: 3},
        resolvedDifferencesByLine: const {0: 3},
        nonPhysicalResolutionsByLine: const {0: 3},
        receiptCount: 1,
      );

      expect(
        fulfillment.state,
        PurchaseReceiptFulfillmentState.closedWithDifference,
      );
      expect(fulfillment.acceptedQuantity, 7);
      expect(fulfillment.physicalRemainingQuantity, 3);
      expect(fulfillment.resolvedDifferenceQuantity, 3);
      expect(fulfillment.unresolvedDifferenceQuantity, 0);
      expect(fulfillment.remainingQuantity, 0);
      expect(fulfillment.isComplete, isFalse);
      expect(fulfillment.isClosed, isTrue);
    });

    test('later delivery resolves the case through physical receipt only', () {
      final fulfillment = PurchaseReceiptFulfillment.derive(
        expectedQuantities: const [10],
        acceptedByLine: const {0: 10},
        differencesByLine: const {0: 3},
        resolvedDifferencesByLine: const {0: 3},
        receiptCount: 2,
      );

      expect(fulfillment.state, PurchaseReceiptFulfillmentState.complete);
      expect(fulfillment.resolvedDifferenceQuantity, 3);
      expect(fulfillment.nonPhysicalResolutionQuantity, 0);
      expect(fulfillment.unresolvedDifferenceQuantity, 0);
    });

    test('supports legacy received invoices without receipt rows', () {
      final fulfillment = PurchaseReceiptFulfillment.derive(
        expectedQuantities: const [4],
        acceptedByLine: const {},
        legacyReceived: true,
      );

      expect(fulfillment.state, PurchaseReceiptFulfillmentState.complete);
      expect(fulfillment.acceptedQuantity, 4);
      expect(fulfillment.remainingQuantity, 0);
      expect(fulfillment.legacyReceived, isTrue);
    });

    test('hydrates the canonical list read-model snapshot', () {
      final fulfillment = PurchaseReceiptFulfillment.fromListReadModel({
        'receipt_state': 'closed_with_difference',
        'receipt_expected_quantity': 10,
        'receipt_accepted_quantity': 7,
        'receipt_reported_difference_quantity': 3,
        'receipt_resolved_difference_quantity': 3,
        'receipt_nonphysical_resolution_quantity': 3,
        'receipt_unresolved_difference_quantity': 0,
        'receipt_physical_remaining_quantity': 3,
        'receipt_remaining_quantity': 0,
        'receipt_count': 1,
        'receipt_latest_received_at': '2026-07-24T08:30:00Z',
        'receipt_legacy_received': false,
      });

      expect(
        fulfillment.state,
        PurchaseReceiptFulfillmentState.closedWithDifference,
      );
      expect(fulfillment.expectedQuantity, 10);
      expect(fulfillment.acceptedQuantity, 7);
      expect(fulfillment.physicalRemainingQuantity, 3);
      expect(fulfillment.remainingQuantity, 0);
      expect(fulfillment.latestReceivedAt, DateTime.utc(2026, 7, 24, 8, 30));
    });
  });

  test('control mode enables commands only in enforce mode', () {
    expect(PurchaseReceiptControlMode.enforce.acceptsCommands, isTrue);
    expect(PurchaseReceiptControlMode.shadow.acceptsCommands, isFalse);
    expect(PurchaseReceiptControlModeX.fromDatabase('unknown'),
        PurchaseReceiptControlMode.disabled);
  });

  test('purchase invoice parses fulfillment in the same list snapshot', () {
    final invoice = PurchaseInvoice.fromJson({
      'id': 'invoice-1',
      'tenant_id': 'tenant-1',
      'invoice_number': 'REC-READ-MODEL',
      'date': '2026-07-24',
      'status': 'paid',
      'items': const [
        {
          'product_name': 'Cadena',
          'quantity': 2,
          'unit_price': 1000,
        },
      ],
      'receipt_state': 'complete',
      'receipt_expected_quantity': 2,
      'receipt_accepted_quantity': 2,
      'receipt_reported_difference_quantity': 0,
      'receipt_resolved_difference_quantity': 0,
      'receipt_nonphysical_resolution_quantity': 0,
      'receipt_unresolved_difference_quantity': 0,
      'receipt_physical_remaining_quantity': 0,
      'receipt_remaining_quantity': 0,
      'receipt_count': 1,
      'receipt_latest_received_at': '2026-07-24T08:30:00Z',
      'receipt_legacy_received': false,
    });

    expect(invoice.status, PurchaseInvoiceStatus.paid);
    expect(invoice.receiptFulfillment?.state,
        PurchaseReceiptFulfillmentState.complete);
    expect(invoice.receiptFulfillment?.acceptedQuantity, 2);
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
    expect(
      PurchaseReceivingBackendCompatibility.isResolutionSchemaUnavailable(
        const PostgrestException(
          message:
              'permission denied for purchase_receipt_resolution_case_view',
          code: '42501',
        ),
      ),
      isFalse,
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
