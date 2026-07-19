import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_models.dart';

Map<String, dynamic> _orderJson({
  required String processingState,
  required bool requiresRefundReview,
  String validationOutcome = 'payment_validated',
}) {
  return {
    'id': '00000000-0000-4000-8000-000000000001',
    'tenant_id': '00000000-0000-4000-8000-000000000002',
    'order_number': 'WEB-26-00001',
    'customer_email': 'cliente@example.invalid',
    'customer_name': 'Cliente',
    'subtotal': 10000,
    'tax_amount': 1900,
    'shipping_cost': 0,
    'discount_amount': 0,
    'total': 11900,
    'status': 'confirmed',
    'payment_status': 'paid',
    'created_at': '2026-07-18T18:00:00.000Z',
    'updated_at': '2026-07-18T18:00:01.000Z',
    'payment_processing_event_id': 41,
    'payment_provider_status': 'approved',
    'payment_validation_outcome': validationOutcome,
    'payment_processing_state': processingState,
    'payment_processing_attempt_count': 2,
    'payment_processing_requires_refund_review': requiresRefundReview,
  };
}

void main() {
  test('validated provider payment exposes a safe idempotent retry', () {
    final order = OnlineOrder.fromJson(
      _orderJson(
        processingState: 'action_required',
        requiresRefundReview: false,
      ),
    );

    expect(order.hasPaymentProcessingAttention, isTrue);
    expect(order.canRetryPaymentProcessing, isTrue);
    expect(order.paymentProcessingEventId, 41);
    expect(order.paymentProcessingAttemptCount, 2);
  });

  test('refund-review payment never exposes automatic processing retry', () {
    final order = OnlineOrder.fromJson(
      _orderJson(
        processingState: 'action_required',
        requiresRefundReview: true,
      ),
    );

    expect(order.hasPaymentProcessingAttention, isTrue);
    expect(order.canRetryPaymentProcessing, isFalse);
  });

  test('processed observation is passive even when provider was approved', () {
    final order = OnlineOrder.fromJson(
      _orderJson(
        processingState: 'processed',
        requiresRefundReview: false,
      ),
    );

    expect(order.hasPaymentProcessingAttention, isFalse);
    expect(order.canRetryPaymentProcessing, isFalse);
  });
}
