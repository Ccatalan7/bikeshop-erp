import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/stock_movement.dart';

const receiptId = 'b1c29fc9-56b3-4e02-8055-7afa6c3b7ef0';
const unrelatedProjectionId = 'cf11dfdf-c3b8-44d0-a963-5df154153dc0';

StockMovement purchaseReceiptMovement({
  required String source,
  required String sourceDocumentType,
  String? notes,
  String referenceNumber = 'purchase_receipt:$receiptId',
}) {
  return StockMovement.fromJson({
    'id': '2dd860cb-98dd-4404-a263-5a24af5aa1f7',
    'product_id': '37c0ed83-2433-48d7-8163-a692109c33ae',
    'product_name': 'Cámara',
    'transaction_date': '2026-07-24T07:34:00Z',
    // This is how the current audit projection describes receipt movements.
    'movement_type': 'adjustment',
    'source': source,
    'reference_id': unrelatedProjectionId,
    'reference_number': referenceNumber,
    'quantity': 1,
    'stock_before': 10,
    'stock_after': 11,
    'source_document_type': sourceDocumentType,
    'source_document_id': receiptId,
    'notes': notes,
    'created_at': '2026-07-24T07:34:00Z',
  });
}

void main() {
  group('purchase receipt stock movements', () {
    test('direct receipt is classified and linked to its formal REC document',
        () {
      final movement = purchaseReceiptMovement(
        source: 'purchase_receipt',
        sourceDocumentType: 'purchase_receipt',
        notes: 'Recepción REC-00003 de factura MOCK-REC-20260723-01',
      );

      expect(movement.category, StockMovementCategory.purchase);
      expect(movement.movementTypeDisplay, 'Recepción');
      expect(movement.sourceDisplay, 'Recepción de compra');
      expect(movement.referenceDisplay, 'REC-00003');
      expect(movement.navigableReferenceId, receiptId);
      expect(movement.navigableReferenceId, isNot(unrelatedProjectionId));
      expect(movement.hasNavigableReference, isTrue);
    });

    test('set component receipt uses the same purchase receipt contract', () {
      final movement = purchaseReceiptMovement(
        source: 'purchase_receipt_component',
        sourceDocumentType: 'purchase_receipt_component',
        notes: 'Componente de set recibido en REC-00004',
      );

      expect(movement.category, StockMovementCategory.purchase);
      expect(movement.movementTypeDisplay, 'Recepción');
      expect(movement.sourceDisplay, 'Recepción de compra');
      expect(movement.referenceDisplay, 'REC-00004');
      expect(movement.navigableReferenceId, receiptId);
    });

    test('raw technical prefix is never shown when no REC number is available',
        () {
      final movement = purchaseReceiptMovement(
        source: 'purchase_receipt',
        sourceDocumentType: 'purchase_receipt',
      );

      expect(movement.referenceDisplay, 'Recepción de compra');
      expect(movement.referenceDisplay, isNot(contains('purchase_receipt:')));
      expect(movement.referenceDisplay, isNot(contains(receiptId)));
      expect(movement.navigableReferenceId, receiptId);
      expect(movement.hasNavigableReference, isTrue);
    });

    test('receipt reversal remains linked to the original REC document', () {
      final movement = purchaseReceiptMovement(
        source: 'purchase_receipt_reversal',
        sourceDocumentType: 'purchase_receipt',
        referenceNumber: 'purchase_receipt:$receiptId:void',
        notes: 'Anulación de recepción REC-00003: prueba revertida',
      );

      expect(movement.category, StockMovementCategory.purchase);
      expect(movement.isPurchaseReceiptReversal, isTrue);
      expect(movement.movementTypeDisplay, 'Reversión de recepción');
      expect(movement.sourceDisplay, 'Reversión de recepción');
      expect(movement.referenceDisplay, 'REC-00003');
      expect(movement.navigableReferenceId, receiptId);
      expect(movement.hasNavigableReference, isTrue);
    });

    test('receipt is inspected before its formal document route opens', () {
      final source = File(
        'lib/modules/inventory/pages/stock_movements_page.dart',
      ).readAsStringSync();
      final inspection = source.substring(
        source.indexOf('Future<void> _navigateToReference'),
        source.indexOf('Future<void> _loadOperationTrace'),
      );
      final documentRoute = source.substring(
        source.indexOf('void _openLinkedDocumentRoute'),
        source.indexOf('Future<void> _navigateToReference'),
      );

      expect(inspection, contains('movement.navigableReferenceId'));
      expect(inspection, contains('_selectedLinkedMovement = movement'));
      expect(inspection, contains('_loadOperationTrace(movement)'));
      expect(documentRoute, contains('movement.isPurchaseReceiptMovement'));
      expect(
        documentRoute,
        contains("'/purchases/receipts/\${Uri.encodeComponent(referenceId)}'"),
      );
    });
  });
}
