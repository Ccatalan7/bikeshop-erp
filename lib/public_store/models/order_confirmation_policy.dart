import '../../modules/website/models/website_models.dart';

enum OrderConfirmationState {
  cancelled,
  paid,
  failed,
  pending,
  transferPending,
  orderReceived,
}

/// Pure precedence and action policy for the public order confirmation page.
///
/// Provider callback query parameters are informational only. The persisted
/// order is authoritative, so a terminal cancellation can never be presented
/// as a pending payment or expose a new payment instruction.
class OrderConfirmationPolicy {
  const OrderConfirmationPolicy._();

  static OrderConfirmationState resolve(
    OnlineOrder order, {
    String? callbackStatus,
  }) {
    final normalizedCallback = callbackStatus?.trim().toLowerCase() ?? '';
    final paymentStatus = order.paymentStatus.trim().toLowerCase();
    final paymentMethod = order.paymentMethod?.trim().toLowerCase() ?? '';

    if (order.isCancelled) {
      return OrderConfirmationState.cancelled;
    }

    if (order.hasRecordedPayment) {
      return OrderConfirmationState.paid;
    }

    if (normalizedCallback == 'failure' ||
        normalizedCallback == 'rejected' ||
        paymentStatus == 'failed' ||
        paymentStatus == 'refunded') {
      return OrderConfirmationState.failed;
    }

    if (normalizedCallback == 'pending' ||
        normalizedCallback == 'in_process' ||
        (paymentMethod == 'mercadopago' && paymentStatus == 'pending')) {
      return OrderConfirmationState.pending;
    }

    if (const {'transfer', 'transferencia', 'bank_transfer'}
        .contains(paymentMethod)) {
      return OrderConfirmationState.transferPending;
    }

    return OrderConfirmationState.orderReceived;
  }

  static bool allowsPaymentAction(OrderConfirmationState state) =>
      state == OrderConfirmationState.failed ||
      state == OrderConfirmationState.pending;

  static bool showsTransferInstructions(OrderConfirmationState state) =>
      state == OrderConfirmationState.transferPending;

  static bool acceptsCallbackMessage(OrderConfirmationState state) =>
      state != OrderConfirmationState.cancelled;
}
