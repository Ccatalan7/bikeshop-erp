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
        ['shipped', 'processing', 'cancelled'],
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
          currentStatus: 'confirmed',
          deliveryType: 'pickup',
        ),
        ['processing', 'cancelled'],
      );
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

    test('each order falls in the list of what the shop has to do', () {
      OnlineOrderQueue queue(
        String status,
        String payment, {
        bool attention = false,
      }) =>
          OnlineOrderWorkflowPolicy.queueFor(
            status: status,
            paymentStatus: payment,
            paymentNeedsAttention: attention,
          );

      expect(queue('confirmed', 'paid'), OnlineOrderQueue.attend);
      expect(queue('processing', 'paid'), OnlineOrderQueue.attend);
      // Paid in Mercado Pago, sale still to create: the shop acts first.
      expect(
        queue('pending', 'paid', attention: true),
        OnlineOrderQueue.attend,
      );
      expect(queue('pending', 'pending'), OnlineOrderQueue.awaitingPayment);
      expect(queue('confirmed', 'pending'), OnlineOrderQueue.awaitingPayment);
      expect(queue('pending', 'failed'), OnlineOrderQueue.awaitingPayment);
      expect(queue('shipped', 'paid'), OnlineOrderQueue.onTheWay);
      expect(queue('ready_for_pickup', 'paid'), OnlineOrderQueue.onTheWay);
      expect(queue('delivered', 'paid'), OnlineOrderQueue.closed);
      expect(queue('cancelled', 'pending'), OnlineOrderQueue.closed);
      expect(queue('confirmed', 'refunded'), OnlineOrderQueue.closed);
    });

    // 2026-10-13: the page opens on what is still active, «Por atender» next.
    test('«Activos» is every order not closed, and it comes first', () {
      expect(OnlineOrderList.values.first, OnlineOrderList.active);
      expect(OnlineOrderList.values[1], OnlineOrderList.attend);
      expect(
        OnlineOrderQueue.values.where(OnlineOrderList.active.includes),
        [
          OnlineOrderQueue.attend,
          OnlineOrderQueue.awaitingPayment,
          OnlineOrderQueue.onTheWay,
        ],
      );
      expect(
          OnlineOrderQueue.values.every(OnlineOrderList.all.includes), isTrue);
      for (final queue in OnlineOrderQueue.values) {
        final lists = OnlineOrderList.values
            .where((list) =>
                list != OnlineOrderList.active &&
                list != OnlineOrderList.all &&
                list.includes(queue))
            .toList();
        expect(lists, hasLength(1), reason: '$queue is in one queue list');
        expect(lists.single.label, queue.label);
      }
    });

    group('progress steps', () {
      String read(List<OnlineOrderProgressStep> steps) => steps
          .map((step) => switch (step.state) {
                OnlineOrderProgressState.done => '✓${step.label}',
                OnlineOrderProgressState.current => '>${step.label}',
                OnlineOrderProgressState.upcoming => step.label,
              })
          .join(' ');

      test('a paid order waiting to be prepared stands on Preparar', () {
        expect(
          read(OnlineOrderWorkflowPolicy.progressSteps(
            status: 'confirmed',
            deliveryType: 'shipping',
            paymentStatus: 'paid',
          )),
          '✓Pagado >Preparar Despachar Entregado',
        );
      });

      test('an unpaid order stands on its payment', () {
        expect(
          read(OnlineOrderWorkflowPolicy.progressSteps(
            status: 'pending',
            deliveryType: 'pickup',
            paymentStatus: 'pending',
          )),
          '>Pago Preparar Por retirar Entregado',
        );
      });

      test('shipped and handed-over orders wait for the delivery', () {
        expect(
          read(OnlineOrderWorkflowPolicy.progressSteps(
            status: 'ready_for_pickup',
            deliveryType: 'pickup',
            paymentStatus: 'paid',
          )),
          '✓Pagado ✓Preparar ✓Por retirar >Entregado',
        );
        expect(
          read(OnlineOrderWorkflowPolicy.progressSteps(
            status: 'delivered',
            deliveryType: 'shipping',
            paymentStatus: 'paid',
          )),
          '✓Pagado ✓Preparar ✓Despachar ✓Entregado',
        );
      });

      test('a cancelled order has no steps', () {
        expect(
          OnlineOrderWorkflowPolicy.progressSteps(
            status: 'cancelled',
            deliveryType: 'shipping',
            paymentStatus: 'paid',
          ),
          isEmpty,
        );
      });
    });
  });
}
