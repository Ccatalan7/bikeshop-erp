import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_models.dart';
import 'package:vinabike_erp/public_store/models/order_confirmation_policy.dart';

void main() {
  group('OrderConfirmationPolicy', () {
    test('cancelled order wins over pending provider state and callback', () {
      final order = _order(
        status: 'cancelled',
        paymentStatus: 'pending',
        paymentMethod: 'mercadopago',
      );

      final presentation = OrderConfirmationPolicy.resolve(
        order,
        callbackStatus: 'pending',
      );

      expect(order.isCancelled, isTrue);
      expect(presentation, OrderConfirmationState.cancelled);
      expect(
        OrderConfirmationPolicy.acceptsCallbackMessage(presentation),
        isFalse,
      );
      expect(
        OrderConfirmationPolicy.allowsPaymentAction(presentation),
        isFalse,
      );
      expect(
        OrderConfirmationPolicy.showsTransferInstructions(presentation),
        isFalse,
      );
    });

    test('cancelled order also wins over paid data and success callback', () {
      final order = _order(
        status: ' CANCELLED ',
        paymentStatus: 'paid',
        paymentMethod: 'mercadopago',
        paidAt: DateTime.utc(2026, 7, 18, 20),
      );

      expect(order.isCancelled, isTrue);
      expect(order.hasRecordedPayment, isTrue);
      expect(
        OrderConfirmationPolicy.resolve(order, callbackStatus: 'success'),
        OrderConfirmationState.cancelled,
      );
    });

    test('pending Mercado Pago state does not invite a duplicate payment', () {
      final presentation = OrderConfirmationPolicy.resolve(
        _order(
          status: 'pending',
          paymentStatus: 'pending',
          paymentMethod: 'mercadopago',
        ),
      );

      expect(presentation, OrderConfirmationState.pending);
      expect(
        OrderConfirmationPolicy.allowsPaymentAction(presentation),
        isFalse,
      );
    });

    test('only a failed Mercado Pago outcome can expose retry', () {
      final presentation = OrderConfirmationPolicy.resolve(
        _order(
          status: 'pending',
          paymentStatus: 'pending',
          paymentMethod: 'mercadopago',
        ),
        callbackStatus: 'failure',
      );

      expect(presentation, OrderConfirmationState.failed);
      expect(
        OrderConfirmationPolicy.allowsPaymentAction(presentation),
        isTrue,
      );
    });

    test('manual transfer instructions remain limited to an active order', () {
      final active = OrderConfirmationPolicy.resolve(
        _order(
          status: 'pending',
          paymentStatus: 'pending',
          paymentMethod: 'bank_transfer',
        ),
      );
      final cancelled = OrderConfirmationPolicy.resolve(
        _order(
          status: 'cancelled',
          paymentStatus: 'pending',
          paymentMethod: 'bank_transfer',
        ),
      );

      expect(active, OrderConfirmationState.transferPending);
      expect(
        OrderConfirmationPolicy.showsTransferInstructions(active),
        isTrue,
      );
      expect(cancelled, OrderConfirmationState.cancelled);
      expect(
        OrderConfirmationPolicy.showsTransferInstructions(cancelled),
        isFalse,
      );
    });
  });
}

OnlineOrder _order({
  required String status,
  required String paymentStatus,
  required String paymentMethod,
  DateTime? paidAt,
}) {
  final createdAt = DateTime.utc(2026, 7, 18, 19);
  return OnlineOrder(
    id: 'order-1',
    tenantId: '',
    orderNumber: 'WEB-26-00019',
    customerEmail: '',
    customerName: '',
    subtotal: 10000,
    taxAmount: 1597,
    shippingCost: 0,
    discountAmount: 0,
    total: 10000,
    status: status,
    paymentStatus: paymentStatus,
    paymentMethod: paymentMethod,
    paidAt: paidAt,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}
