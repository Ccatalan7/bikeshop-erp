import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/stock_movement.dart';

StockMovement movement({
  required String integrityStatus,
  int rawQuantity = -10,
  int actualStockDelta = -9,
  int reconciledQuantity = -9,
}) {
  return StockMovement.fromJson({
    'id': '99000000-0000-4000-8000-000000000001',
    'product_id': '99000000-0000-4000-8000-000000000002',
    'product_name': 'Regression product',
    'transaction_date': '2026-07-11T12:00:00Z',
    'movement_type': 'purchase_invoice_reversal',
    'source': 'purchase_invoice_reversal',
    'stock_before': 9,
    'quantity': rawQuantity,
    'stock_after': 0,
    'raw_quantity': rawQuantity,
    'actual_stock_delta': actualStockDelta,
    'reconciled_quantity': reconciledQuantity,
    'balance_provenance': 'current_stock_reconciled_ledger',
    'integrity_status': integrityStatus,
    'is_summary_excluded': false,
    'evidence_stock_before': 9,
    'evidence_stock_after': 0,
    'evidence_balance_provenance': 'stock_adjustment',
    'evidence_integrity_status': integrityStatus,
    'created_at': '2026-07-11T12:00:00Z',
  });
}

void main() {
  group('stock movement integrity classification', () {
    test('legacy reconstructed history is not presented as an anomaly', () {
      final historical = movement(integrityStatus: 'legacy_reconstructed');

      expect(historical.hasIntegrityWarning, isFalse);
      expect(historical.integrityLabel, 'Historial encadenado');
    });

    test('known duplicate and reversal collisions remain review cases', () {
      expect(
        movement(integrityStatus: 'legacy_duplicate_footprint')
            .hasIntegrityWarning,
        isTrue,
      );
      expect(
        movement(integrityStatus: 'legacy_purchase_reversal_collision')
            .hasIntegrityWarning,
        isTrue,
      );
    });

    test('the visible and summarized change use the reconciled quantity', () {
      final reconciled = movement(
        integrityStatus: 'legacy_purchase_reversal_collision',
      );

      expect(reconciled.displayQuantity, -9);
      expect(reconciled.summaryQuantity, -9);
      expect(reconciled.rawQuantity, -10);
    });
  });
}
