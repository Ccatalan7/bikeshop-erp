// Cotizaciones de clientes: productos en stock y a pedido en la misma lista.
//
// La base es la dueña de todo (20261102041700_customer_quotes_foundation):
// estas clases sólo leen lo que devuelven `customer_quote_inbox_v1` y
// `customer_quote_detail_v1`. Ningún total ni estado se calcula aquí salvo el
// subtotal del borrador, que la base congela recién al enviar la oferta.

import '../../../shared/widgets/vb_money_text.dart';
import '../../../shared/widgets/vb_status_badge.dart';

enum CustomerQuoteStatus {
  confirming('confirming', 'Por confirmar', VbStatusTone.warning),
  offered('offered', 'Oferta enviada', VbStatusTone.info),
  accepted('accepted', 'Aceptada', VbStatusTone.success),
  rejected('rejected', 'Rechazada', VbStatusTone.danger),
  expired('expired', 'Vencida', VbStatusTone.neutral),
  cancelled('cancelled', 'Anulada', VbStatusTone.neutral);

  const CustomerQuoteStatus(this.code, this.label, this.tone);

  final String code;
  final String label;
  final VbStatusTone tone;

  bool get isOpen => this == confirming || this == offered;

  static CustomerQuoteStatus parse(Object? value) {
    final code = value?.toString();
    return CustomerQuoteStatus.values.firstWhere(
      (status) => status.code == code,
      orElse: () => CustomerQuoteStatus.confirming,
    );
  }
}

/// Lo que dice una línea de la oferta sobre el producto.
enum QuoteLineAvailability {
  pending('pending', 'Por confirmar', VbStatusTone.warning),
  inStock('in_stock', 'En stock', VbStatusTone.success),
  onOrder('on_order', 'A pedido', VbStatusTone.info),
  unavailable('unavailable', 'No disponible', VbStatusTone.danger);

  const QuoteLineAvailability(this.code, this.label, this.tone);

  final String code;
  final String label;
  final VbStatusTone tone;

  static QuoteLineAvailability parse(Object? value) {
    final code = value?.toString();
    return QuoteLineAvailability.values.firstWhere(
      (availability) => availability.code == code,
      orElse: () => QuoteLineAvailability.pending,
    );
  }
}

enum QuoteChannel {
  email('email', 'Correo'),
  whatsapp('whatsapp', 'WhatsApp');

  const QuoteChannel(this.code, this.label);

  final String code;
  final String label;

  static QuoteChannel parse(Object? value) =>
      value?.toString() == 'email' ? QuoteChannel.email : QuoteChannel.whatsapp;

  /// Los avisos que eligió el cliente (20261102175500): correo, WhatsApp o
  /// los dos, en ese orden.
  static List<QuoteChannel> chosen(
          {required bool email, required bool whatsapp}) =>
      [if (email) QuoteChannel.email, if (whatsapp) QuoteChannel.whatsapp];

  /// «Correo», «WhatsApp» o «Correo y WhatsApp».
  static String labelOf(List<QuoteChannel> channels) =>
      channels.map((channel) => channel.label).join(' y ');

  /// Lo mismo dentro de una frase: «correo», «WhatsApp», «correo y WhatsApp».
  static String inSentence(List<QuoteChannel> channels) => channels
      .map(
          (channel) => channel == QuoteChannel.email ? 'correo' : channel.label)
      .join(' y ');
}

/// Una fila de la bandeja.
class CustomerQuoteSummary {
  const CustomerQuoteSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.source,
    required this.customerName,
    required this.notices,
    required this.requestedAt,
    required this.updatedAt,
    required this.lines,
    required this.openTasks,
    this.expiresAt,
    this.total,
    this.nextDueAt,
    this.converted = false,
    this.orderNumber,
    this.orderWaiting = false,
  });

  final String id;
  final String number;
  final CustomerQuoteStatus status;
  final String source;
  final String customerName;

  /// El pedido web que nació al aceptar, y si espera algo a pedido
  /// (20261103010000).
  final String? orderNumber;
  final bool orderWaiting;

  /// Por dónde pidió el cliente que le avisemos; una cotización del taller
  /// no lo dice (vacío).
  final List<QuoteChannel> notices;
  final DateTime requestedAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  final int lines;
  final num? total;
  final int openTasks;
  final DateTime? nextDueAt;

  /// Una cotización del taller ya aprobada que se convirtió en trabajo o
  /// venta (20261102100000).
  final bool converted;

  /// Un trabajo del taller con flujo de cotización y sin bicicleta recibida:
  /// sus líneas, su PDF y la decisión del cliente son de Trabajos.
  bool get isWorkshop => source == 'workshop';

  factory CustomerQuoteSummary.fromJson(Map<String, dynamic> json) {
    return CustomerQuoteSummary(
      id: json['id'].toString(),
      number: json['number']?.toString() ?? '',
      status: CustomerQuoteStatus.parse(json['status']),
      source: json['source']?.toString() ?? 'web',
      customerName: json['customerName']?.toString() ?? '',
      notices: QuoteChannel.chosen(
        email: json['notifyEmail'] == true,
        whatsapp: json['notifyWhatsapp'] == true,
      ),
      requestedAt: _date(json['requestedAt']) ?? DateTime.now(),
      updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
      expiresAt: _date(json['expiresAt']),
      lines: _int(json['lines']) ?? 0,
      total: json['total'] as num?,
      openTasks: _int(json['openTasks']) ?? 0,
      nextDueAt: _date(json['nextDueAt']),
      converted: json['converted'] == true,
      orderNumber: _text(json['orderNumber']),
      orderWaiting: json['orderWaiting'] == true,
    );
  }
}

class CustomerQuoteInbox {
  const CustomerQuoteInbox({required this.counts, required this.quotes});

  final Map<CustomerQuoteStatus, int> counts;
  final List<CustomerQuoteSummary> quotes;

  int count(CustomerQuoteStatus status) => counts[status] ?? 0;

  factory CustomerQuoteInbox.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['counts'] is Map
        ? Map<String, dynamic>.from(json['counts'] as Map)
        : const <String, dynamic>{};
    return CustomerQuoteInbox(
      counts: {
        for (final entry in rawCounts.entries)
          CustomerQuoteStatus.parse(entry.key): _int(entry.value) ?? 0,
      },
      quotes: _maps(json['quotes'])
          .map(CustomerQuoteSummary.fromJson)
          .toList(growable: false),
    );
  }
}

/// Lo que pidió el cliente, tal cual quedó.
class CustomerQuoteRequestedLine {
  const CustomerQuoteRequestedLine({
    required this.lineNo,
    required this.name,
    required this.quantity,
    required this.kind,
    this.sku,
    this.productId,
    this.stockAtRequest,
    this.unitPriceReference,
  });

  final int lineNo;
  final String name;
  final String? sku;
  final String? productId;
  final int quantity;
  final String kind;
  final num? stockAtRequest;
  final num? unitPriceReference;

  factory CustomerQuoteRequestedLine.fromJson(Map<String, dynamic> json) {
    return CustomerQuoteRequestedLine(
      lineNo: _int(json['line_no']) ?? 0,
      name: json['product_name']?.toString() ?? '',
      sku: _text(json['product_sku']),
      productId: _text(json['product_id']),
      quantity: _int(json['quantity']) ?? 0,
      kind: json['kind_at_request']?.toString() ?? 'to_confirm',
      stockAtRequest: json['stock_at_request'] as num?,
      unitPriceReference: json['unit_price_reference'] as num?,
    );
  }

  String get kindLabel => switch (kind) {
        'in_stock' => 'En stock al pedir',
        'on_order' => 'A pedido',
        _ => 'Por confirmar',
      };
}

class CustomerQuoteOfferLine {
  const CustomerQuoteOfferLine({
    required this.id,
    required this.lineNo,
    required this.name,
    required this.quantityRequested,
    required this.availability,
    required this.quantityOffered,
    required this.confirmedBySystem,
    this.sku,
    this.productId,
    this.unitPrice,
    this.taxRate,
    this.leadDaysMin,
    this.leadDaysMax,
    this.supplierId,
    this.supplierName,
    this.unitCostNet,
    this.staffNote,
    this.customerNote,
    this.confirmedAt,
    this.stockNow,
  });

  final String id;
  final int lineNo;
  final String name;
  final String? sku;
  final String? productId;
  final int quantityRequested;
  final QuoteLineAvailability availability;
  final int quantityOffered;
  final num? unitPrice;
  final num? taxRate;
  final int? leadDaysMin;
  final int? leadDaysMax;
  final String? supplierId;
  final String? supplierName;
  final num? unitCostNet;
  final String? staffNote;
  final String? customerNote;
  final DateTime? confirmedAt;
  final bool confirmedBySystem;
  final num? stockNow;

  bool get isPending => availability == QuoteLineAvailability.pending;
  bool get isPartial =>
      quantityOffered > 0 && quantityOffered < quantityRequested;

  num? get lineTotal => unitPrice == null || quantityOffered <= 0
      ? null
      : unitPrice! * quantityOffered;

  /// Margen sobre el precio neto, cuando se conoce el costo del proveedor.
  double? get marginPercent {
    final price = unitPrice;
    final cost = unitCostNet;
    if (price == null || cost == null || cost <= 0 || price <= 0) return null;
    final rate = taxRate == null
        ? 0.19
        : (taxRate! > 1 ? taxRate! / 100 : taxRate!.toDouble());
    final net = price / (1 + rate);
    return (net - cost) / net * 100;
  }

  String? get leadLabel {
    if (leadDaysMin == null) return null;
    if (leadDaysMax == null || leadDaysMax == leadDaysMin) {
      return '$leadDaysMin días hábiles';
    }
    return '$leadDaysMin a $leadDaysMax días hábiles';
  }

  factory CustomerQuoteOfferLine.fromJson(Map<String, dynamic> json) {
    return CustomerQuoteOfferLine(
      id: json['id'].toString(),
      lineNo: _int(json['line_no']) ?? 0,
      name: json['product_name']?.toString() ?? '',
      sku: _text(json['product_sku']),
      productId: _text(json['product_id']),
      quantityRequested: _int(json['quantity_requested']) ?? 0,
      availability: QuoteLineAvailability.parse(json['availability']),
      quantityOffered: _int(json['quantity_offered']) ?? 0,
      unitPrice: json['unit_price'] as num?,
      taxRate: json['tax_rate'] as num?,
      leadDaysMin: _int(json['lead_days_min']),
      leadDaysMax: _int(json['lead_days_max']),
      supplierId: _text(json['supplier_id']),
      supplierName: _text(json['supplier_name']),
      unitCostNet: json['unit_cost_net'] as num?,
      staffNote: _text(json['staff_note']),
      customerNote: _text(json['customer_note']),
      confirmedAt: _date(json['confirmed_at']),
      confirmedBySystem: json['confirmed_by_system'] == true,
      stockNow: json['stock_now'] as num?,
    );
  }
}

class CustomerQuoteOffer {
  const CustomerQuoteOffer({
    required this.id,
    required this.number,
    required this.status,
    required this.lines,
    this.validUntil,
    this.subtotal,
    this.taxAmount,
    this.total,
    this.notesToCustomer,
    this.sentAt,
    this.respondedAt,
  });

  final String id;
  final int number;
  final String status;
  final List<CustomerQuoteOfferLine> lines;
  final DateTime? validUntil;
  final num? subtotal;
  final num? taxAmount;
  final num? total;
  final String? notesToCustomer;
  final DateTime? sentAt;
  final DateTime? respondedAt;

  bool get isDraft => status == 'draft';
  int get pendingLines => lines.where((line) => line.isPending).length;
  bool get hasOfferedLine => lines.any((line) => line.quantityOffered > 0);

  /// El total que tendría la oferta si se enviara ahora (IVA incluido).
  num get draftTotal =>
      lines.fold<num>(0, (sum, line) => sum + (line.lineTotal ?? 0));

  String get statusLabel => switch (status) {
        'draft' => 'Borrador',
        'sent' => 'Enviada',
        'superseded' => 'Reemplazada',
        'accepted' => 'Aceptada',
        'rejected' => 'Rechazada',
        'expired' => 'Vencida',
        _ => 'Anulada',
      };

  factory CustomerQuoteOffer.fromJson(Map<String, dynamic> json) {
    return CustomerQuoteOffer(
      id: json['id'].toString(),
      number: _int(json['offer_no']) ?? 1,
      status: json['status']?.toString() ?? 'draft',
      lines: _maps(json['lines'])
          .map(CustomerQuoteOfferLine.fromJson)
          .toList(growable: false),
      validUntil: _date(json['valid_until']),
      subtotal: json['subtotal'] as num?,
      taxAmount: json['tax_amount'] as num?,
      total: json['total'] as num?,
      notesToCustomer: _text(json['notes_to_customer']),
      sentAt: _date(json['sent_at']),
      respondedAt: _date(json['responded_at']),
    );
  }
}

/// Lo que hay que preguntarle a un proveedor para cerrar el borrador.
class CustomerQuoteSupplierTask {
  const CustomerQuoteSupplierTask({
    required this.id,
    required this.status,
    required this.dueAt,
    required this.messageDraft,
    this.supplierId,
    this.supplierName,
    this.salesRepName,
    this.salesRepPhone,
  });

  final String id;
  final String status;
  final DateTime dueAt;
  final String messageDraft;
  final String? supplierId;
  final String? supplierName;
  final String? salesRepName;
  final String? salesRepPhone;

  bool get isOpen => status == 'open';

  factory CustomerQuoteSupplierTask.fromJson(Map<String, dynamic> json) {
    return CustomerQuoteSupplierTask(
      id: json['id'].toString(),
      status: json['status']?.toString() ?? 'open',
      dueAt: _date(json['due_at']) ?? DateTime.now(),
      messageDraft: json['message_draft']?.toString() ?? '',
      supplierId: _text(json['supplier_id']),
      supplierName: _text(json['supplier_name']),
      salesRepName: _text(json['sales_rep_name']),
      salesRepPhone: _text(json['sales_rep_phone']),
    );
  }
}

/// Un mensaje al cliente de la cotización (20261102063700): el correo lo
/// manda el worker; el WhatsApp, mientras no haya plantilla aprobada, lo
/// manda el equipo con un clic y lo marca.
class CustomerQuoteMessage {
  const CustomerQuoteMessage({
    required this.id,
    required this.kind,
    required this.channel,
    required this.recipient,
    required this.state,
    required this.createdAt,
    this.sentAt,
    this.lastError,
  });

  final String id;
  final String kind;
  final QuoteChannel channel;
  final String recipient;
  final String state;
  final DateTime createdAt;
  final DateTime? sentAt;
  final String? lastError;

  bool get needsStaff => state == 'needs_staff';

  String get kindLabel => switch (kind) {
        'received' => 'Recibimos tu cotización',
        'offer' => 'Oferta lista',
        'reminder' => 'Recordatorio',
        'order_paid' => 'Recibimos tu pago',
        'order_ready' => 'Listo para retiro',
        'order_shipped' => 'Va en camino',
        _ => 'Aceptación recibida',
      };

  /// Los hitos del pedido que nació de la cotización (20261103010000).
  bool get isOrderMilestone => kind.startsWith('order_');

  String get stateLabel => switch (state) {
        'sent' => 'Enviado',
        'needs_staff' => 'Por enviar',
        'failed' => 'No salió',
        'skipped' => 'Omitido',
        _ => 'En cola',
      };

  VbStatusTone get tone => switch (state) {
        'sent' => VbStatusTone.success,
        'needs_staff' => VbStatusTone.warning,
        'failed' => VbStatusTone.danger,
        _ => VbStatusTone.neutral,
      };

  factory CustomerQuoteMessage.fromJson(Map<String, dynamic> json) {
    return CustomerQuoteMessage(
      id: json['id'].toString(),
      kind: json['kind']?.toString() ?? 'offer',
      channel: QuoteChannel.parse(json['channel']),
      recipient: json['recipient']?.toString() ?? '',
      state: json['state']?.toString() ?? 'pending',
      createdAt: _date(json['created_at']) ?? DateTime.now(),
      sentAt: _date(json['sent_at']),
      lastError: _text(json['last_error']),
    );
  }
}

class CustomerQuoteEvent {
  const CustomerQuoteEvent({
    required this.type,
    required this.actorKind,
    required this.occurredAt,
    required this.detail,
    this.channel,
  });

  final String type;
  final String actorKind;
  final String? channel;
  final DateTime occurredAt;
  final Map<String, dynamic> detail;

  /// La historia en palabras del taller.
  String get label => switch (type) {
        'requested' => actorKind == 'customer'
            ? 'El cliente pidió la cotización'
            : 'Cotización creada en el ERP',
        'offer_prepared' => 'Borrador ${detail['offer_no'] ?? ''} armado'
            '${_count(detail['confirmed'], ' confirmada', ' confirmadas')}'
            '${_count(detail['pending'], ' por confirmar', ' por confirmar')}',
        'offer_revised' => 'Oferta reabierta para corregir',
        'line_confirmed' => 'Línea ${detail['line_no'] ?? ''} confirmada',
        'line_added' => 'Línea ${detail['line_no'] ?? ''} agregada',
        'supplier_task_opened' => 'Consulta a proveedores abierta',
        'supplier_task_done' => 'Proveedor confirmado',
        'offer_sent' => 'Oferta ${detail['offer_no'] ?? ''} enviada',
        'viewed' => 'El cliente abrió la oferta',
        'accepted' => 'El cliente aceptó',
        'changes_requested' => 'El cliente pidió cambios',
        'rejected' => 'El cliente rechazó',
        'expired' => 'La oferta venció',
        'cancelled' => 'Cotización anulada',
        'reminder_sent' => 'Recordatorio programado',
        'message_queued' => 'Mensaje al cliente en cola',
        'notify_changed' => 'El cliente cambió sus avisos: ${_notices(detail)}',
        'contact_updated' => detail['whatsapp_dropped'] == true
            ? 'Su cuenta quedó sin teléfono: ahora avisa por correo'
            : 'Tomó los datos nuevos de su cuenta',
        'order_paid' => 'El cliente pagó el pedido',
        'order_waiting' => _purchases(detail),
        'order_line_arrived' => 'Llegó ${detail['product'] ?? 'un producto'}',
        'order_sale_issued' => detail['invoice_number'] == null
            ? 'Llegó todo: venta emitida'
            : 'Llegó todo: venta ${detail['invoice_number']} emitida',
        'order_attention' => 'La venta no se emitió: ${detail['error'] ?? ''}',
        'order_ready' => 'Pedido listo para retiro',
        'order_shipped' => 'Pedido despachado',
        'order_delivered' => 'Pedido entregado',
        'order_cancelled' => 'Pedido anulado',
        'order_refunded' => _refund(detail),
        _ => 'Nota',
      };

  String? get note {
    final value = detail['note'] ?? detail['reason'];
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String _refund(Map<String, dynamic> detail) {
    final amount = detail['amount'];
    final reference = detail['reference']?.toString();
    return [
      'Se devolvió el pago',
      if (amount is num) VbMoneyText.formatClp(amount),
      if (reference != null && reference.isNotEmpty) 'ref. $reference',
    ].join(' · ');
  }

  static String _purchases(Map<String, dynamic> detail) {
    final purchases = _int(detail['purchases']) ?? 0;
    final missing = _int(detail['without_supplier']) ?? 0;
    final rest = missing == 0
        ? ''
        : ' · ${missing == 1 ? 'un producto' : '$missing productos'} sin proveedor';
    return switch (purchases) {
      0 when missing > 0 => 'Pagado: falta armar el pedido al proveedor$rest',
      0 => 'Pagado: espera lo que viene a pedido',
      1 => 'Pagado: el pedido al proveedor quedó en borrador$rest',
      _ => 'Pagado: $purchases pedidos a proveedores quedaron en borrador$rest',
    };
  }

  static String _notices(Map<String, dynamic> detail) =>
      QuoteChannel.inSentence(QuoteChannel.chosen(
        email: detail['notify_email'] == true,
        whatsapp: detail['notify_whatsapp'] == true,
      ));

  static String _count(Object? value, String one, String many) {
    final n = _int(value) ?? 0;
    if (n == 0) return '';
    return ' · $n${n == 1 ? one : many}';
  }

  factory CustomerQuoteEvent.fromJson(Map<String, dynamic> json) {
    return CustomerQuoteEvent(
      type: json['event_type']?.toString() ?? 'note',
      actorKind: json['actor_kind']?.toString() ?? 'system',
      channel: _text(json['channel']),
      occurredAt: _date(json['occurred_at']) ?? DateTime.now(),
      detail: json['detail'] is Map
          ? Map<String, dynamic>.from(json['detail'] as Map)
          : const <String, dynamic>{},
    );
  }
}

class CustomerQuoteDetail {
  const CustomerQuoteDetail({
    required this.id,
    required this.number,
    required this.status,
    required this.source,
    required this.customerName,
    required this.notices,
    required this.requestedAt,
    required this.version,
    required this.requested,
    required this.offers,
    required this.tasks,
    required this.events,
    required this.messages,
    required this.offerValidityHours,
    required this.onOrderPrepayPercent,
    this.customerId,
    this.customerEmail,
    this.customerPhone,
    this.customerNotes,
    this.conversationId,
    this.currentOfferId,
    this.draftOfferId,
    this.expiresAt,
    this.closedReason,
    this.order,
  });

  final String id;
  final String number;
  final CustomerQuoteStatus status;
  final String source;
  final String customerName;

  /// El pedido web que nació al aceptar (20261103010000).
  final CustomerQuoteOrder? order;

  /// Por dónde pidió el cliente que le avisemos (20261102175500).
  final List<QuoteChannel> notices;
  final String? customerId;
  final String? customerEmail;
  final String? customerPhone;
  final String? customerNotes;
  final String? conversationId;
  final String? currentOfferId;
  final String? draftOfferId;
  final DateTime requestedAt;
  final DateTime? expiresAt;
  final String? closedReason;
  final int version;
  final List<CustomerQuoteRequestedLine> requested;
  final List<CustomerQuoteOffer> offers;
  final List<CustomerQuoteSupplierTask> tasks;
  final List<CustomerQuoteEvent> events;
  final List<CustomerQuoteMessage> messages;
  final int offerValidityHours;
  final int onOrderPrepayPercent;

  CustomerQuoteOffer? get draft {
    for (final offer in offers) {
      if (offer.id == draftOfferId) return offer;
    }
    return null;
  }

  CustomerQuoteOffer? get currentOffer {
    for (final offer in offers) {
      if (offer.id == currentOfferId) return offer;
    }
    return null;
  }

  List<CustomerQuoteSupplierTask> get openTasks =>
      tasks.where((task) => task.isOpen).toList(growable: false);

  bool get notifiesByEmail => notices.contains(QuoteChannel.email);
  bool get notifiesByWhatsapp => notices.contains(QuoteChannel.whatsapp);

  /// Desde el 2026-11-02 una cotización del sitio es de una cuenta: sus datos
  /// de contacto son los de esa cuenta y la siguen.
  bool get fromAccount => source == 'web' && customerId != null;

  String get sourceLabel => switch (source) {
        'web' => 'Desde el sitio',
        'whatsapp' => 'Desde WhatsApp',
        _ => 'En el mesón',
      };

  factory CustomerQuoteDetail.fromJson(Map<String, dynamic> json) {
    final quote = json['quote'] is Map
        ? Map<String, dynamic>.from(json['quote'] as Map)
        : const <String, dynamic>{};
    final settings = json['settings'] is Map
        ? Map<String, dynamic>.from(json['settings'] as Map)
        : const <String, dynamic>{};
    return CustomerQuoteDetail(
      id: quote['id'].toString(),
      number: quote['quote_number']?.toString() ?? '',
      status: CustomerQuoteStatus.parse(quote['status']),
      source: quote['source']?.toString() ?? 'web',
      customerName: quote['customer_name']?.toString() ?? '',
      notices: QuoteChannel.chosen(
        email: quote['notify_email'] == true,
        whatsapp: quote['notify_whatsapp'] == true,
      ),
      customerId: _text(quote['customer_id']),
      customerEmail: _text(quote['customer_email']),
      customerPhone: _text(quote['customer_phone']),
      customerNotes: _text(quote['customer_notes']),
      conversationId: _text(quote['conversation_id']),
      currentOfferId: _text(quote['current_offer_id']),
      draftOfferId: _text(json['draftOfferId']),
      requestedAt: _date(quote['requested_at']) ?? DateTime.now(),
      expiresAt: _date(quote['expires_at']),
      closedReason: _text(quote['closed_reason']),
      version: _int(quote['version']) ?? 1,
      requested: _maps(json['requested'])
          .map(CustomerQuoteRequestedLine.fromJson)
          .toList(growable: false),
      offers: _maps(json['offers'])
          .map(CustomerQuoteOffer.fromJson)
          .toList(growable: false),
      tasks: _maps(json['tasks'])
          .map(CustomerQuoteSupplierTask.fromJson)
          .toList(growable: false),
      events: _maps(json['events'])
          .map(CustomerQuoteEvent.fromJson)
          .toList(growable: false),
      messages: _maps(json['messages'])
          .map(CustomerQuoteMessage.fromJson)
          .toList(growable: false),
      offerValidityHours: _int(settings['offer_validity_hours']) ?? 72,
      onOrderPrepayPercent: _int(settings['on_order_prepay_percent']) ?? 100,
      order: json['order'] is Map
          ? CustomerQuoteOrder.fromJson(
              Map<String, dynamic>.from(json['order'] as Map))
          : null,
    );
  }
}

/// El pedido web de una cotización aceptada (20261103010000): sus líneas
/// dicen si salieron del stock o vienen del proveedor, y si ya llegaron; los
/// pedidos a proveedores son los borradores de Compras que nacieron al pagar.
class CustomerQuoteOrder {
  const CustomerQuoteOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.deliveryType,
    required this.total,
    required this.shippingCost,
    required this.waiting,
    required this.items,
    required this.purchases,
    this.paidAt,
    this.trackingNumber,
    this.carrier,
    this.invoiceNumber,
    this.salesInvoiceId,
  });

  final String id;
  final String number;
  final String status;
  final String paymentStatus;
  final String paymentMethod;
  final String deliveryType;
  final num total;
  final num shippingCost;
  final bool waiting;
  final DateTime? paidAt;
  final String? trackingNumber;
  final String? carrier;
  final String? invoiceNumber;
  final String? salesInvoiceId;
  final List<CustomerQuoteOrderItem> items;
  final List<CustomerQuoteOrderPurchase> purchases;

  bool get isPaid => paymentStatus == 'paid';

  /// Pagado y sin venta: se anula devolviendo la plata (20261103030000).
  /// Con venta, la devolución es de Correcciones.
  bool get canCancelAndRefund => isPaid && !isCancelled && !hasSale;
  bool get hasSale => salesInvoiceId != null;

  /// Lo que viene a pedido y no tiene proveedor: no entra en ningún pedido al
  /// proveedor y hay que pedirlo a mano.
  int get missingSupplier =>
      items.where((item) => item.waiting && item.supplierId == null).length;
  bool get isCancelled => status == 'cancelled';

  /// Lo que el equipo tiene que saber: falta el pago, falta el proveedor, se
  /// puede preparar, o en qué va.
  String get stateLabel {
    if (isCancelled) {
      return paymentStatus == 'refunded' ? 'Anulado · devuelto' : 'Anulado';
    }
    if (!isPaid) {
      return paymentMethod == 'transfer'
          ? 'Esperando la transferencia'
          : 'Esperando el pago';
    }
    if (waiting) return 'Pagado · falta que llegue';
    return switch (status) {
      'ready_for_pickup' => 'Listo para retiro',
      'shipped' => 'Despachado',
      'delivered' => 'Entregado',
      'processing' => 'En preparación',
      _ => 'Pagado · listo para preparar',
    };
  }

  VbStatusTone get tone {
    if (isCancelled) return VbStatusTone.neutral;
    if (!isPaid || waiting) return VbStatusTone.warning;
    return VbStatusTone.success;
  }

  String get deliveryLabel => deliveryType == 'shipping'
      ? 'Despacho a domicilio'
      : 'Retiro en el taller';

  factory CustomerQuoteOrder.fromJson(Map<String, dynamic> json) {
    return CustomerQuoteOrder(
      id: json['id'].toString(),
      number: json['number']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      paymentStatus: json['payment_status']?.toString() ?? 'pending',
      paymentMethod: json['payment_method']?.toString() ?? 'transfer',
      deliveryType: json['delivery_type']?.toString() ?? 'pickup',
      total: json['total'] as num? ?? 0,
      shippingCost: json['shipping_cost'] as num? ?? 0,
      waiting: json['waiting'] == true,
      paidAt: _date(json['paid_at']),
      trackingNumber: _text(json['tracking_number']),
      carrier: _text(json['shipping_carrier']),
      invoiceNumber: _text(json['invoice_number']),
      salesInvoiceId: _text(json['sales_invoice_id']),
      items: _maps(json['items'])
          .map(CustomerQuoteOrderItem.fromJson)
          .toList(growable: false),
      purchases: _maps(json['purchases'])
          .map(CustomerQuoteOrderPurchase.fromJson)
          .toList(growable: false),
    );
  }
}

class CustomerQuoteOrderItem {
  const CustomerQuoteOrderItem({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.onOrder,
    this.productSku,
    this.arrivedAt,
    this.supplierId,
    this.supplierName,
    this.leadDaysMin,
    this.leadDaysMax,
    this.stockNow,
  });

  final String id;
  final String productName;
  final String? productSku;
  final int quantity;
  final bool onOrder;
  final DateTime? arrivedAt;
  final String? supplierId;
  final String? supplierName;
  final int? leadDaysMin;
  final int? leadDaysMax;
  final int? stockNow;

  bool get arrived => arrivedAt != null;
  bool get waiting => onOrder && !arrived;

  /// El plazo que prometió la oferta, en días hábiles.
  String? get leadLabel {
    final min = leadDaysMin;
    if (min == null) return null;
    final max = leadDaysMax ?? min;
    return min == max ? '$min días hábiles' : '$min a $max días hábiles';
  }

  factory CustomerQuoteOrderItem.fromJson(Map<String, dynamic> json) {
    return CustomerQuoteOrderItem(
      id: json['id'].toString(),
      productName: json['product_name']?.toString() ?? '',
      productSku: _text(json['product_sku']),
      quantity: _int(json['quantity']) ?? 0,
      onOrder: json['fulfillment'] == 'on_order',
      arrivedAt: _date(json['arrived_at']),
      supplierId: _text(json['supplier_id']),
      supplierName: _text(json['supplier_name']),
      leadDaysMin: _int(json['lead_days_min']),
      leadDaysMax: _int(json['lead_days_max']),
      stockNow: _int(json['stock_now']),
    );
  }
}

/// Un pedido al proveedor: el documento de compra (PED-…) en Compras.
class CustomerQuoteOrderPurchase {
  const CustomerQuoteOrderPurchase({
    required this.id,
    required this.status,
    required this.total,
    this.purchaseInvoiceId,
    this.number,
    this.supplierId,
    this.supplierName,
    this.salesRepName,
    this.salesRepPhone,
  });

  final String id;
  final String? purchaseInvoiceId;
  final String? number;
  final String status;
  final num total;
  final String? supplierId;
  final String? supplierName;
  final String? salesRepName;
  final String? salesRepPhone;

  bool get isDraft => status == 'draft';

  String get statusLabel => switch (status) {
        'draft' => 'Por enviar',
        'sent' => 'Enviado',
        'confirmed' => 'Con factura',
        'received' => 'Recibido',
        'paid' => 'Pagado',
        'cancelled' => 'Anulado',
        _ => status,
      };

  VbStatusTone get tone => switch (status) {
        'draft' => VbStatusTone.warning,
        'received' || 'paid' => VbStatusTone.success,
        'cancelled' => VbStatusTone.neutral,
        _ => VbStatusTone.info,
      };

  factory CustomerQuoteOrderPurchase.fromJson(Map<String, dynamic> json) {
    return CustomerQuoteOrderPurchase(
      id: json['id'].toString(),
      purchaseInvoiceId: _text(json['purchase_invoice_id']),
      number: _text(json['number']),
      status: json['status']?.toString() ?? 'draft',
      total: json['total'] as num? ?? 0,
      supplierId: _text(json['supplier_id']),
      supplierName: _text(json['supplier_name']),
      salesRepName: _text(json['sales_rep_name']),
      salesRepPhone: _text(json['sales_rep_phone']),
    );
  }
}

/// Los valores de las cotizaciones del taller (`customer_quote_settings_v1`):
/// cuánto vale una oferta, cuándo se le recuerda al cliente, cuánto tiene un
/// proveedor para responder y cuánto sirve una disponibilidad ya confirmada.
class CustomerQuoteSettings {
  const CustomerQuoteSettings({
    required this.offerValidityHours,
    required this.reminderHoursBefore,
    required this.onOrderPrepayPercent,
    required this.supplierTaskDueHours,
    required this.supplierCheckFreshHours,
    required this.canEdit,
    this.updatedAt,
  });

  factory CustomerQuoteSettings.fromJson(Map<String, dynamic> json) {
    return CustomerQuoteSettings(
      offerValidityHours: _int(json['offer_validity_hours']) ?? 72,
      reminderHoursBefore: _int(json['reminder_hours_before']) ?? 24,
      onOrderPrepayPercent: _int(json['on_order_prepay_percent']) ?? 100,
      supplierTaskDueHours: _int(json['supplier_task_due_hours']) ?? 24,
      supplierCheckFreshHours: _int(json['supplier_check_fresh_hours']) ?? 48,
      canEdit: json['can_edit'] == true,
      updatedAt: _date(json['updated_at']),
    );
  }

  final int offerValidityHours;
  final int reminderHoursBefore;
  final int onOrderPrepayPercent;
  final int supplierTaskDueHours;
  final int supplierCheckFreshHours;

  /// Administración o el permiso de cambiar los ajustes del taller.
  final bool canEdit;
  final DateTime? updatedAt;

  /// Los límites que la base hace cumplir (20261103060000).
  static const validityRange = (min: 12, max: 720);
  static const reminderRange = (min: 0, max: 168);
  static const taskDueRange = (min: 1, max: 168);
  static const checkFreshRange = (min: 1, max: 720);
}

List<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

DateTime? _date(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text);
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
