class OrderCommunication {
  const OrderCommunication({
    required this.id,
    required this.orderId,
    required this.messageKind,
    required this.templateVersion,
    required this.recipientEmail,
    required this.subject,
    required this.deliveryMode,
    required this.state,
    required this.attemptCount,
    required this.createdAt,
    this.provider,
    this.providerMessageId,
    this.lastErrorClass,
    this.lastErrorMessage,
    this.renderedAt,
    this.submittedAt,
    this.deliveredAt,
    this.bouncedAt,
    this.complainedAt,
    this.failedAt,
    this.providerEvents = const [],
  });

  final String id;
  final String orderId;
  final String messageKind;
  final int templateVersion;
  final String recipientEmail;
  final String subject;
  final String deliveryMode;
  final String state;
  final int attemptCount;
  final String? provider;
  final String? providerMessageId;
  final String? lastErrorClass;
  final String? lastErrorMessage;
  final DateTime createdAt;
  final DateTime? renderedAt;
  final DateTime? submittedAt;
  final DateTime? deliveredAt;
  final DateTime? bouncedAt;
  final DateTime? complainedAt;
  final DateTime? failedAt;
  final List<OrderCommunicationProviderEvent> providerEvents;

  String get messageLabel => switch (messageKind) {
        'order_received' => 'Pedido recibido',
        'payment_confirmed' => 'Pago confirmado',
        'processing' => 'Preparación iniciada',
        'ready_for_pickup' => 'Listo para retiro',
        'shipped' => 'Pedido enviado',
        'delivered' => 'Pedido entregado',
        'cancelled' => 'Pedido cancelado',
        'refund_completed' => 'Reembolso completado',
        'payment_voucher_available' => 'Voucher válido como boleta disponible',
        'mercadopago_payment_voucher_available' =>
          'Comprobante de pago Mercado Pago disponible',
        'tax_document_issued' => 'Documento tributario emitido',
        _ => messageKind,
      };

  bool get isDryRun => deliveryMode == 'dry_run';

  bool get needsAttention => const {
        'bounced',
        'complained',
        'failed',
        'dead_letter',
      }.contains(state);

  factory OrderCommunication.fromJson(
    Map<String, dynamic> json, {
    List<OrderCommunicationProviderEvent> providerEvents = const [],
  }) {
    return OrderCommunication(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      messageKind: json['message_kind'] as String,
      templateVersion: (json['template_version'] as num?)?.toInt() ?? 1,
      recipientEmail: json['recipient_email'] as String,
      subject: json['subject'] as String,
      deliveryMode: json['delivery_mode'] as String,
      state: json['state'] as String,
      attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
      provider: json['provider'] as String?,
      providerMessageId: json['provider_message_id'] as String?,
      lastErrorClass: json['last_error_class'] as String?,
      lastErrorMessage: json['last_error_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      renderedAt: _date(json['rendered_at']),
      submittedAt: _date(json['submitted_at']),
      deliveredAt: _date(json['delivered_at']),
      bouncedAt: _date(json['bounced_at']),
      complainedAt: _date(json['complained_at']),
      failedAt: _date(json['failed_at']),
      providerEvents: providerEvents,
    );
  }

  static DateTime? _date(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}

class OrderCommunicationProviderEvent {
  const OrderCommunicationProviderEvent({
    required this.id,
    required this.eventType,
    required this.occurredAt,
    required this.receivedAt,
  });

  final String id;
  final String eventType;
  final DateTime occurredAt;
  final DateTime receivedAt;

  factory OrderCommunicationProviderEvent.fromJson(Map<String, dynamic> json) {
    return OrderCommunicationProviderEvent(
      id: json['id'] as String,
      eventType: json['event_type'] as String,
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      receivedAt: DateTime.parse(json['received_at'] as String),
    );
  }
}
