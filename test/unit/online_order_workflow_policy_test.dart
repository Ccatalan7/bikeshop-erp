import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/online_order_workflow_policy.dart';

void main() {
  group('OnlineOrderWorkflowPolicy', () {
    test('offers only forward shipping transitions', () {
      expect(
        OnlineOrderWorkflowPolicy.legalNextStatuses(
          currentStatus: 'pending',
          deliveryType: 'shipping',
        ),
        ['confirmed', 'cancelled'],
      );
      expect(
        OnlineOrderWorkflowPolicy.legalNextStatuses(
          currentStatus: 'confirmed',
          deliveryType: 'shipping',
        ),
        ['processing', 'cancelled'],
      );
      expect(
        OnlineOrderWorkflowPolicy.legalNextStatuses(
          currentStatus: 'processing',
          deliveryType: 'shipping',
        ),
        ['shipped', 'cancelled'],
      );
      expect(
        OnlineOrderWorkflowPolicy.legalNextStatuses(
          currentStatus: 'shipped',
          deliveryType: 'shipping',
        ),
        ['delivered'],
      );
    });

    test('branches pickup orders through ready for pickup', () {
      expect(
        OnlineOrderWorkflowPolicy.legalNextStatuses(
          currentStatus: 'processing',
          deliveryType: 'pickup',
        ),
        ['ready_for_pickup', 'cancelled'],
      );
      expect(
        OnlineOrderWorkflowPolicy.legalNextStatuses(
          currentStatus: 'ready_for_pickup',
          deliveryType: 'pickup',
        ),
        ['delivered'],
      );
    });

    test('paid orders never offer the destructive cancellation shortcut', () {
      expect(
        OnlineOrderWorkflowPolicy.legalNextStatuses(
          currentStatus: 'pending',
          deliveryType: 'shipping',
          paymentStatus: 'paid',
        ),
        ['confirmed'],
      );
      expect(
        OnlineOrderWorkflowPolicy.legalNextStatuses(
          currentStatus: 'processing',
          deliveryType: 'shipping',
          paymentStatus: 'refunded',
        ),
        ['shipped'],
      );
    });

    test('delivered and cancelled orders are terminal', () {
      for (final status in ['delivered', 'cancelled']) {
        expect(OnlineOrderWorkflowPolicy.isTerminal(status), isTrue);
        expect(
          OnlineOrderWorkflowPolicy.legalNextStatuses(
            currentStatus: status,
            deliveryType: 'shipping',
          ),
          isEmpty,
        );
      }

      final cancelled = OnlineOrderWorkflowPolicy.definitionFor('cancelled');
      expect(cancelled.meaning, contains('no se prepara'));
      expect(cancelled.meaning, contains('solicita un nuevo pago'));
    });

    test('manual payment is restricted to pending bank transfers with invoice',
        () {
      expect(
        OnlineOrderWorkflowPolicy.canConfirmManualPayment(
          orderStatus: 'confirmed',
          paymentStatus: 'pending',
          paymentMethod: 'transferencia',
          hasInvoice: true,
        ),
        isTrue,
      );
      expect(
        OnlineOrderWorkflowPolicy.canConfirmManualPayment(
          orderStatus: 'confirmed',
          paymentStatus: 'pending',
          paymentMethod: 'mercadopago',
          hasInvoice: true,
        ),
        isFalse,
      );
      expect(
        OnlineOrderWorkflowPolicy.canConfirmManualPayment(
          orderStatus: 'cancelled',
          paymentStatus: 'pending',
          paymentMethod: 'bank_transfer',
          hasInvoice: true,
        ),
        isFalse,
      );
      expect(
        OnlineOrderWorkflowPolicy.canConfirmManualPayment(
          orderStatus: 'confirmed',
          paymentStatus: 'pending',
          paymentMethod: 'bank_transfer',
          hasInvoice: false,
        ),
        isFalse,
      );
    });

    test('guide definitions include both delivery branches and ownership', () {
      final statuses = OnlineOrderWorkflowPolicy.definitions
          .map((definition) => definition.status)
          .toSet();
      expect(statuses, containsAll(['shipped', 'ready_for_pickup']));
      expect(
        OnlineOrderWorkflowPolicy.definitionFor('confirmed').owner,
        'Trabajador de Viñabike',
      );
      expect(
        OnlineOrderWorkflowPolicy.isWebhookOwnedPayment('mercado_pago'),
        isTrue,
      );
    });
  });
}
