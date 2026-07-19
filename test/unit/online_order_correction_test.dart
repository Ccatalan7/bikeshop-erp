import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/online_order_correction.dart';

void main() {
  test('preview preserves exact service and product correction boundaries', () {
    final preview = OnlineOrderCorrectionPreview.fromJson({
      'order_id': 'order-1',
      'order_number': 'WEB-26-00001',
      'order_version': 4,
      'payment_method': 'mercadopago',
      'controls_ready': true,
      'control_modes': {
        'sales_return': 'enforce',
        'sales_credit_note': 'enforce',
        'sales_customer_refund': 'enforce',
      },
      'lines': [
        {
          'line_index': 0,
          'product_name': 'Repuesto',
          'remaining_quantity': 2,
          'remaining_net': 10001,
          'remaining_tax': 1899,
          'remaining_total': 11900,
          'is_service': false,
          'physical_return_allowed': true,
        },
        {
          'line_index': 1,
          'product_name': 'Instalación',
          'remaining_quantity': 1,
          'remaining_net': 5000,
          'remaining_tax': 0,
          'remaining_total': 5000,
          'is_service': true,
          'physical_return_allowed': false,
        },
      ],
    });

    expect(preview.isMercadoPago, isTrue);
    expect(preview.controlsReady, isTrue);
    expect(preview.orderVersion, 4);
    expect(preview.lines, hasLength(2));
    expect(preview.lines.first.physicalReturnAllowed, isTrue);
    expect(preview.lines.last.isService, isTrue);
    expect(preview.lines.last.physicalReturnAllowed, isFalse);
    expect(preview.lines.first.amountForQuantity(1), 5951);
  });

  test('correction state distinguishes manual evidence from applied effects',
      () {
    final pending = OnlineOrderCorrectionRecord.fromJson({
      'id': 'correction-1',
      'order_id': 'order-1',
      'requested_amount': 10000,
      'provider': 'manual',
      'provider_state': 'pending',
      'processing_state': 'provider_pending',
      'correction_intent': 'return',
    });
    final applied = OnlineOrderCorrectionRecord.fromJson({
      'correction_id': 'correction-2',
      'order_id': 'order-1',
      'requested_amount': 10000,
      'provider': 'mercadopago',
      'provider_state': 'succeeded',
      'processing_state': 'applied',
      'correction_intent': 'cancel_before_fulfillment',
    });

    expect(pending.needsManualEvidence, isTrue);
    expect(pending.isApplied, isFalse);
    expect(applied.needsManualEvidence, isFalse);
    expect(applied.isApplied, isTrue);
    expect(applied.correctionIntent, 'cancel_before_fulfillment');
  });
}
