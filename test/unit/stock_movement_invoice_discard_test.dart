import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/stock_movement.dart';

void main() {
  test('invoice void movement is labelled as a discard, not a mystery reversal',
      () {
    final movement = StockMovement.fromJson({
      'id': 'movement-1',
      'product_id': 'product-1',
      'product_name': 'Cámara',
      'transaction_date': '2026-07-18T12:00:00Z',
      'movement_type': 'sale',
      'source': 'sales_invoice_reversal',
      'reference_number': 'FV-00878',
      'quantity': 2,
      'stock_before': 4,
      'stock_after': 6,
      'created_at': '2026-07-18T12:00:00Z',
      'trigger_action': 'void',
      'trigger_reason': 'Factura de prueba; la venta no ocurrió',
    });

    expect(movement.sourceDisplay, 'Descarte de factura');
    expect(movement.referenceDisplay, 'FV-00878');
    expect(movement.triggerReason, 'Factura de prueba; la venta no ocurrió');
    expect(movement.quantity, 2);
  });
}
