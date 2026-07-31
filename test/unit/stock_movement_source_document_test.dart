import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/stock_movement.dart';

const _sourceDocumentId = '92000000-0000-4000-8000-000000000001';
const _legacyReferenceId = '92000000-0000-4000-8000-000000000002';

void main() {
  test('every typed source document takes precedence over legacy reference_id',
      () {
    const sourceTypes = <String>[
      'sales_invoice',
      'purchase_invoice',
      'purchase_receipt',
      'stock_adjustment',
      'sales_return',
      'purchase_supplier_return',
      'mechanic_job',
      'online_order',
    ];

    for (final sourceType in sourceTypes) {
      final movement = _movement(
        sourceDocumentType: sourceType,
        sourceDocumentId: '  $_sourceDocumentId  ',
      );

      expect(
        movement.sourceDocumentId,
        _sourceDocumentId,
        reason: '$sourceType must retain its normalized stable identity.',
      );
      expect(
        movement.navigableReferenceId,
        _sourceDocumentId,
        reason: '$sourceType must not navigate through legacy reference_id.',
      );
      expect(movement.toJson()['source_document_id'], _sourceDocumentId);
    }
  });

  test('missing typed identity keeps the legacy reference fallback', () {
    final movement = _movement(
      sourceDocumentType: 'sales_invoice',
      sourceDocumentId: '   ',
    );

    expect(movement.sourceDocumentId, isNull);
    expect(movement.navigableReferenceId, _legacyReferenceId);
  });

  test('typed ownership never routes an id through the wrong module', () {
    final mechanicJob = _movement(
      sourceDocumentType: 'mechanic_job',
      sourceDocumentId: _sourceDocumentId,
    );
    final salesReturn = _movement(
      sourceDocumentType: 'sales_return',
      sourceDocumentId: _sourceDocumentId,
    );
    final supplierReturn = _movement(
      sourceDocumentType: 'purchase_supplier_return',
      sourceDocumentId: _sourceDocumentId,
    );

    expect(mechanicJob.isMechanicJobSourceDocument, isTrue);
    expect(mechanicJob.hasNavigableReference, isTrue);
    expect(salesReturn.hasNavigableReference, isFalse);
    expect(supplierReturn.hasNavigableReference, isFalse);
    expect(salesReturn.sourceDocumentDisplay, 'devolución de venta');
    expect(supplierReturn.sourceDocumentDisplay, 'devolución a proveedor');
  });

  test('commercial corrections stay in their sale or purchase facets', () {
    const salesTypes = <String>[
      'sales_return_restock',
      'sales_return_reversal',
      'sales_return_quarantine_release',
      'sales_return_quarantine_release_reversal',
    ];
    for (final movementType in salesTypes) {
      final movement = _movementWithType(
        movementType: movementType,
        source: movementType,
      );
      expect(
        movement.category,
        StockMovementCategory.sale,
        reason: '$movementType corrects a sale, not generic inventory.',
      );
    }

    const purchaseTypes = <String>[
      'purchase_supplier_return',
      'purchase_supplier_return_reversal',
    ];
    for (final movementType in purchaseTypes) {
      final movement = _movementWithType(
        movementType: movementType,
        source: movementType,
      );
      expect(
        movement.category,
        StockMovementCategory.purchase,
        reason: '$movementType corrects a purchase, not generic inventory.',
      );
    }
  });

  test('typed correction owner wins over a legacy adjustment label', () {
    final salesReturn = _movementWithType(
      movementType: 'adjustment',
      source: 'legacy',
      sourceDocumentType: 'sales_return',
    );
    final supplierReturn = _movementWithType(
      movementType: 'adjustment',
      source: 'legacy',
      sourceDocumentType: 'purchase_supplier_return',
    );

    expect(salesReturn.category, StockMovementCategory.sale);
    expect(supplierReturn.category, StockMovementCategory.purchase);
  });
}

StockMovement _movement({
  required String sourceDocumentType,
  required String sourceDocumentId,
}) {
  return StockMovement.fromJson({
    'id': '92000000-0000-4000-8000-000000000003',
    'product_id': '92000000-0000-4000-8000-000000000004',
    'product_name': 'Producto de prueba',
    'transaction_date': '2026-07-15T12:00:00Z',
    'movement_type': 'sale',
    'source': sourceDocumentType,
    'reference_id': _legacyReferenceId,
    'quantity': -1,
    'stock_before': 3,
    'stock_after': 2,
    'source_document_type': sourceDocumentType,
    'source_document_id': sourceDocumentId,
    'created_at': '2026-07-15T12:00:00Z',
  });
}

StockMovement _movementWithType({
  required String movementType,
  required String source,
  String? sourceDocumentType,
}) {
  return StockMovement.fromJson({
    'id': '92000000-0000-4000-8000-000000000003',
    'product_id': '92000000-0000-4000-8000-000000000004',
    'product_name': 'Producto de prueba',
    'transaction_date': '2026-07-15T12:00:00Z',
    'movement_type': movementType,
    'source': source,
    'quantity': 1,
    'stock_before': 2,
    'stock_after': 3,
    if (sourceDocumentType != null) 'source_document_type': sourceDocumentType,
    'created_at': '2026-07-15T12:00:00Z',
  });
}
