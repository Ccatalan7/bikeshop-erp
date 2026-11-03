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

  // 20261103010000: a quote order whose on-order lines have not arrived keeps
  // its validated Mercado Pago payment in `action_required` with
  // `awaiting_on_order_stock` until the arrival issues the sale. That is the
  // plan working, not an incident: no «Revisar pago», no manual retry.
  test('a payment waiting for what comes on order is a wait, not an incident',
      () {
    final order = OnlineOrder.fromJson({
      ..._orderJson(
        processingState: 'action_required',
        requiresRefundReview: false,
      ),
      'payment_processing_error_code': 'awaiting_on_order_stock',
      'online_order_items': [
        {
          'id': 'item-1',
          'order_id': '00000000-0000-4000-8000-000000000001',
          'product_name': 'Neumático 29 x 2.40',
          'quantity': 1,
          'unit_price': 45000,
          'subtotal': 45000,
          'fulfillment': 'on_order',
          'lead_days_min': 3,
          'lead_days_max': 5,
        },
        {
          'id': 'item-2',
          'order_id': '00000000-0000-4000-8000-000000000001',
          'product_name': 'Neumático 29 x 2.25',
          'quantity': 1,
          'unit_price': 30000,
          'subtotal': 30000,
        },
      ],
    });

    expect(order.isPaymentAwaitingOnOrderStock, isTrue);
    expect(order.hasPaymentProcessingAttention, isFalse);
    expect(order.canRetryPaymentProcessing, isFalse);
    expect(order.isWaitingOnOrder, isTrue);
    expect(order.items.first.leadDaysMax, 5);
    expect(order.items.last.isOnOrder, isFalse);

    final arrived = order.copyWith(items: [
      OnlineOrderItem.fromJson({
        ...order.items.first.toJson(),
        'arrived_at': '2026-11-04T15:00:00.000Z',
      }),
      order.items.last,
    ]);
    expect(arrived.items.first.isOnOrder, isTrue);
    expect(arrived.isWaitingOnOrder, isFalse);
  });
}
