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
          'Inicia la preparación cuando el pedido esté listo para operar.',
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
      'confirmed' => const ['processing', 'cancelled'],
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
