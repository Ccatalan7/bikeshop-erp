/// Pure presentation policy for the employee-facing online-order lifecycle.
///
/// The database remains authoritative. This policy deliberately exposes only
/// the forward transitions that an employee may choose from the Orders table.
class OnlineOrderWorkflowPolicy {
  OnlineOrderWorkflowPolicy._();

  static const definitions = <OnlineOrderWorkflowDefinition>[
    OnlineOrderWorkflowDefinition(
      status: 'pending',
      label: 'Pendiente',
      meaning: 'La compra ingresó y todavía necesita revisión operativa.',
      owner: 'Sitio web',
      nextAction:
          'Verifica cliente, productos, modalidad de entrega y condición de pago.',
    ),
    OnlineOrderWorkflowDefinition(
      status: 'confirmed',
      label: 'Confirmado',
      meaning: 'La tienda aceptó el pedido y validó que puede atenderlo.',
      owner: 'Trabajador de Viñabike',
      nextAction:
          'Prepáralo y registra el despacho con la boleta, o márcalo listo para retiro.',
    ),
    OnlineOrderWorkflowDefinition(
      status: 'processing',
      label: 'En proceso',
      meaning: 'Los productos están siendo separados y preparados.',
      owner: 'Trabajador de Viñabike',
      nextAction:
          'Registra el despacho o marca el pedido listo para retiro, según corresponda.',
    ),
    OnlineOrderWorkflowDefinition(
      status: 'shipped',
      label: 'Enviado',
      meaning: 'El pedido de despacho salió de la tienda.',
      owner: 'Trabajador de Viñabike',
      nextAction:
          'Conserva transportista y seguimiento; confirma la entrega final.',
      deliveryType: 'shipping',
    ),
    OnlineOrderWorkflowDefinition(
      status: 'ready_for_pickup',
      label: 'Listo para retiro',
      meaning: 'El pedido está preparado y esperando al cliente en la tienda.',
      owner: 'Trabajador de Viñabike',
      nextAction: 'Entrega contra verificación del cliente y marca Entregado.',
      deliveryType: 'pickup',
    ),
    OnlineOrderWorkflowDefinition(
      status: 'delivered',
      label: 'Entregado',
      meaning: 'El cliente recibió el pedido; el flujo operativo está cerrado.',
      owner: 'Trabajador de Viñabike',
      nextAction: 'No requiere otra transición operativa.',
      terminal: true,
    ),
    OnlineOrderWorkflowDefinition(
      status: 'cancelled',
      label: 'Cancelado',
      meaning:
          'El pedido fue anulado y está cerrado; no se prepara ni se solicita un nuevo pago.',
      owner: 'Trabajador de Viñabike',
      nextAction:
          'Conserva el motivo y la evidencia. Si hubo pago, gestiona devolución y correcciones desde la factura.',
      terminal: true,
    ),
  ];

  static OnlineOrderWorkflowDefinition definitionFor(String status) {
    return definitions.firstWhere(
      (definition) => definition.status == status,
      orElse: () => OnlineOrderWorkflowDefinition(
        status: status,
        label: status,
        meaning: 'Estado operativo no reconocido por esta versión.',
        owner: 'Sistema',
        nextAction: 'Actualiza la aplicación antes de operar este pedido.',
        terminal: true,
      ),
    );
  }

  static List<String> legalNextStatuses({
    required String currentStatus,
    required String deliveryType,
    String? paymentStatus,
  }) {
    final List<String> candidates = switch (currentStatus) {
      'pending' => const ['confirmed', 'cancelled'],
      // A shipping order can go straight to «Despachado» with its receipt:
      // the receipt proves it was prepared, and «En preparación» first sent
      // the customer two emails in a row (2026-10-13).
      'confirmed' => deliveryType == 'pickup'
          ? const ['processing', 'cancelled']
          : const ['shipped', 'processing', 'cancelled'],
      'processing' => deliveryType == 'pickup'
          ? const ['ready_for_pickup', 'cancelled']
          : const ['shipped', 'cancelled'],
      'shipped' || 'ready_for_pickup' => const ['delivered'],
      _ => const [],
    };

    // A paid sale cannot be "cancelled" as if money had never moved. The
    // database correctly requires the linked sale correction/refund workflow;
    // hiding this invalid shortcut keeps the employee UI aligned with it.
    final normalizedPayment = paymentStatus?.trim().toLowerCase();
    if (normalizedPayment == 'paid' || normalizedPayment == 'refunded') {
      return candidates.where((status) => status != 'cancelled').toList();
    }
    return candidates;
  }

  static bool isTerminal(String status) => definitionFor(status).terminal;

  static bool isManualTransfer(String? paymentMethod) {
    final normalized = paymentMethod?.trim().toLowerCase();
    return const {'transfer', 'transferencia', 'bank_transfer'}
        .contains(normalized);
  }

  static bool isWebhookOwnedPayment(String? paymentMethod) {
    final normalized = paymentMethod?.trim().toLowerCase();
    return const {'mercadopago', 'mercado_pago'}.contains(normalized);
  }

  static bool canConfirmManualPayment({
    required String orderStatus,
    required String paymentStatus,
    required String? paymentMethod,
    required bool hasInvoice,
  }) {
    return hasInvoice &&
        orderStatus != 'cancelled' &&
        paymentStatus == 'pending' &&
        isManualTransfer(paymentMethod);
  }

  /// The four steps the shop walks for one order, for the order's progress
  /// bar: paid, prepare, ship or hand over, delivered. [paymentStatus] is the
  /// payment as the shop sees it (`OnlineOrder.operationalPaymentStatus`). A
  /// cancelled order left the path, so it has no steps.
  static List<OnlineOrderProgressStep> progressSteps({
    required String status,
    required String deliveryType,
    required String paymentStatus,
  }) {
    if (status == 'cancelled') return const [];
    final paid = paymentStatus == 'paid' || paymentStatus == 'refunded';
    final reached = switch (status) {
      'delivered' => 4,
      'shipped' || 'ready_for_pickup' => 3,
      _ => paid ? 1 : 0,
    };
    final labels = [
      paid ? 'Pagado' : 'Pago',
      'Preparar',
      deliveryType == 'pickup' ? 'Por retirar' : 'Despachar',
      'Entregado',
    ];
    return [
      for (var index = 0; index < labels.length; index++)
        OnlineOrderProgressStep(
          label: labels[index],
          state: index < reached
              ? OnlineOrderProgressState.done
              : index == reached
                  ? OnlineOrderProgressState.current
                  : OnlineOrderProgressState.upcoming,
        ),
    ];
  }

  /// Which list an order belongs to, by what the shop has to do with it:
  /// paid and waiting for the shop (or a payment to sort out) is «Por
  /// atender»; not paid yet is «Esperando pago»; shipped or waiting at the
  /// counter is «En camino»; delivered, cancelled or refunded is «Cerrados».
  /// [paymentStatus] is `OnlineOrder.operationalPaymentStatus`.
  static OnlineOrderQueue queueFor({
    required String status,
    required String paymentStatus,
    bool paymentNeedsAttention = false,
  }) {
    if (status == 'cancelled' ||
        status == 'delivered' ||
        paymentStatus == 'refunded') {
      return OnlineOrderQueue.closed;
    }
    if (status == 'shipped' || status == 'ready_for_pickup') {
      return OnlineOrderQueue.onTheWay;
    }
    if (paymentNeedsAttention || paymentStatus == 'paid') {
      return OnlineOrderQueue.attend;
    }
    return OnlineOrderQueue.awaitingPayment;
  }

  static String actionLabel(String status) {
    return switch (status) {
      'confirmed' => 'Confirmar pedido',
      'processing' => 'Comenzar preparación',
      'ready_for_pickup' => 'Marcar listo para retiro',
      'shipped' => 'Registrar despacho',
      'delivered' => 'Marcar entregado',
      'cancelled' => 'Cancelar pedido',
      _ => definitionFor(status).label,
    };
  }
}

class OnlineOrderWorkflowDefinition {
  const OnlineOrderWorkflowDefinition({
    required this.status,
    required this.label,
    required this.meaning,
    required this.owner,
    required this.nextAction,
    this.deliveryType,
    this.terminal = false,
  });

  final String status;
  final String label;
  final String meaning;
  final String owner;
  final String nextAction;
  final String? deliveryType;
  final bool terminal;
}

enum OnlineOrderProgressState { done, current, upcoming }

enum OnlineOrderQueue {
  attend('Por atender'),
  awaitingPayment('Esperando pago'),
  onTheWay('En camino'),
  closed('Cerrados');

  const OnlineOrderQueue(this.label);

  final String label;
}

/// The lists the orders page offers, in this order. «Activos» opens it
/// (owner, 2026-10-13: «la principal debería ser de las órdenes activas…
/// las que aún no se hayan marcado como entregadas», with «Por atender»
/// right after): every order not closed — to attend, waiting for payment or
/// on its way. Then each queue, then «Todos».
enum OnlineOrderList {
  active('Activos'),
  attend('Por atender'),
  awaitingPayment('Esperando pago'),
  onTheWay('En camino'),
  closed('Cerrados'),
  all('Todos');

  const OnlineOrderList(this.label);

  final String label;

  /// Whether an order in [queue] shows in this list.
  bool includes(OnlineOrderQueue queue) => switch (this) {
        OnlineOrderList.active => queue != OnlineOrderQueue.closed,
        OnlineOrderList.attend => queue == OnlineOrderQueue.attend,
        OnlineOrderList.awaitingPayment =>
          queue == OnlineOrderQueue.awaitingPayment,
        OnlineOrderList.onTheWay => queue == OnlineOrderQueue.onTheWay,
        OnlineOrderList.closed => queue == OnlineOrderQueue.closed,
        OnlineOrderList.all => true,
      };
}

class OnlineOrderProgressStep {
  const OnlineOrderProgressStep({required this.label, required this.state});

  final String label;
  final OnlineOrderProgressState state;
}
