import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:vinabike_public_core/public_store/documents/quote_offer_pdf.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/customer_quote.dart';

/// Comandos de las cotizaciones de clientes. Cada uno es una función de la
/// base (20261102041700): aquí sólo se nombran el taller de la sesión y la
/// llave de operación que hace idempotente un reintento.
class CustomerQuoteService {
  CustomerQuoteService({SupabaseClient? client, TenantService? tenantService})
      : _client = client ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService();

  final SupabaseClient _client;
  final TenantService _tenantService;
  static const _uuid = Uuid();

  Future<String> _tenantId() async {
    final tenantId =
        _tenantService.currentTenantId ?? await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No hay una tienda activa en la sesión.');
    }
    return tenantId;
  }

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<CustomerQuoteInbox> fetchInbox({CustomerQuoteStatus? status}) async {
    final result = await _client.rpc('customer_quote_inbox_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_status': status?.code,
      'p_limit': 200,
      'p_offset': 0,
    });
    return CustomerQuoteInbox.fromJson(_map(result));
  }

  Future<CustomerQuoteDetail> fetchDetail(String quoteId) async {
    final result = await _client.rpc('customer_quote_detail_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_quote_id': quoteId,
    });
    return CustomerQuoteDetail.fromJson(_map(result));
  }

  Future<CustomerQuoteDetail> confirmLine(
    String offerLineId,
    QuoteLineConfirmation confirmation,
  ) async {
    final result = await _client.rpc('customer_quote_confirm_line_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_offer_line_id': offerLineId,
      'p_line': confirmation.toJson(),
    });
    return CustomerQuoteDetail.fromJson(_map(result));
  }

  Future<CustomerQuoteDetail> addLine(
    String quoteId, {
    required String productId,
    required int quantity,
  }) async {
    final result = await _client.rpc('customer_quote_add_line_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_quote_id': quoteId,
      'p_product_id': productId,
      'p_quantity': quantity,
    });
    return CustomerQuoteDetail.fromJson(_map(result));
  }

  /// Envía el borrador. [operationKey] se crea una vez por intento del
  /// operador: si la red se corta y reintenta, la base no envía dos veces.
  Future<CustomerQuoteDetail> sendOffer(
    String quoteId, {
    required String operationKey,
    String? notesToCustomer,
  }) async {
    final result = await _client.rpc('customer_quote_send_offer_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_quote_id': quoteId,
      'p_operation_key': operationKey,
      'p_notes_to_customer': notesToCustomer,
    });
    return CustomerQuoteDetail.fromJson(_map(result));
  }

  Future<CustomerQuoteDetail> reviseOffer(
    String quoteId, {
    required String operationKey,
  }) async {
    final result = await _client.rpc('customer_quote_revise_offer_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_quote_id': quoteId,
      'p_operation_key': operationKey,
    });
    return CustomerQuoteDetail.fromJson(_map(result));
  }

  Future<CustomerQuoteDetail> cancel(
    String quoteId, {
    required String operationKey,
    required String reason,
  }) async {
    final result = await _client.rpc('customer_quote_cancel_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_quote_id': quoteId,
      'p_operation_key': operationKey,
      'p_reason': reason,
    });
    return CustomerQuoteDetail.fromJson(_map(result));
  }

  /// Un enlace nuevo de la cotización para mandarlo a mano (60 días).
  Future<String> issueLink(String quoteId) async {
    final result = await _client.rpc('customer_quote_issue_link_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_quote_id': quoteId,
    });
    final url = _map(result)['url']?.toString() ?? '';
    if (url.isEmpty) throw StateError('No se pudo crear el enlace.');
    return url;
  }

  /// El equipo mandó por WhatsApp un mensaje que esperaba por él.
  Future<CustomerQuoteDetail> markMessageSent(String messageId) async {
    final result =
        await _client.rpc('customer_quote_mark_message_sent_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_message_id': messageId,
    });
    return CustomerQuoteDetail.fromJson(_map(result));
  }

  /// Revisa si llegó lo que el pedido de la cotización espera: aparta lo que
  /// ya tiene stock y, con todo apartado, emite la venta (20261103010000).
  /// La base lo hace sola cada 10 minutos; esto es para no esperar.
  Future<QuoteOrderArrivals> checkOrderArrivals(String quoteId) async {
    final result =
        await _client.rpc('customer_quote_order_check_arrivals_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_quote_id': quoteId,
    });
    return QuoteOrderArrivals.fromJson(_map(result));
  }

  /// Anula un pedido de cotización pagado que todavía no tiene venta, después
  /// de que el equipo devolvió la plata (20261103030000): libera lo apartado,
  /// anula los borradores de compra que nadie mandó y deja el reembolso
  /// registrado con su referencia.
  Future<CustomerQuoteDetail> cancelOrder(
    String quoteId, {
    required String operationKey,
    required String reason,
    required String refundReference,
    required DateTime refundedAt,
  }) async {
    final result = await _client.rpc('customer_quote_order_cancel_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_quote_id': quoteId,
      'p_request': {
        'operation_key': operationKey,
        'reason': reason,
        'refund_reference': refundReference,
        'refunded_at': refundedAt.toUtc().toIso8601String(),
      },
    });
    return CustomerQuoteDetail.fromJson(_map(result));
  }

  /// La oferta enviada tal como la ve el cliente, con el membrete de la
  /// tienda (20261103050000): el ERP dibuja el PDF desde aquí y la tienda
  /// desde el enlace, el mismo documento. Null sin una oferta enviada.
  Future<QuoteOfferPdfInput?> fetchOfferDocument(String quoteId) async {
    final result =
        await _client.rpc('customer_quote_offer_document_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_quote_id': quoteId,
    });
    return QuoteOfferPdfInput.fromPublicQuote(result);
  }

  static String newOperationKey() => _uuid.v4();

  /// El mensaje que entiende el operador para un error de la base.
  static String describeError(Object error) {
    final text = error is PostgrestException
        ? '${error.message} ${error.details ?? ''}'
        : error.toString();
    if (text.contains('quote_lines_pending')) {
      return 'Quedan líneas por confirmar.';
    }
    if (text.contains('quote_offer_empty')) {
      return 'La oferta no tiene ningún producto disponible.';
    }
    if (text.contains('quote_offer_not_draft') ||
        text.contains('quote_not_confirming')) {
      return 'La cotización cambió mientras la mirabas. Se recargó.';
    }
    if (text.contains('quote_not_open') ||
        text.contains('quote_not_revisable')) {
      return 'La cotización ya está cerrada.';
    }
    if (text.contains('quote_line_price_required')) {
      return 'Falta el precio.';
    }
    if (text.contains('quote_refund_not_allowed')) {
      return 'Sólo administración o contabilidad registra una devolución.';
    }
    if (text.contains('quote_order_has_sale')) {
      return 'Este pedido ya tiene venta: la devolución se hace en Correcciones, '
          'desde la venta.';
    }
    if (text.contains('quote_order_already_cancelled')) {
      return 'El pedido ya estaba anulado.';
    }
    if (text.contains('quote_refund_reference_required')) {
      return 'Falta la referencia de la devolución.';
    }
    if (text.contains('quote_refund_date_in_future') ||
        text.contains('quote_refund_date_before_payment')) {
      return 'Revisa la fecha de la devolución.';
    }
    if (text.contains('42501')) {
      return 'No tienes acceso a esta cotización.';
    }
    return 'No se pudo completar. Revisa la conexión e inténtalo de nuevo.';
  }
}

/// Lo que encontró «Revisar si llegó».
class QuoteOrderArrivals {
  const QuoteOrderArrivals({
    required this.waiting,
    required this.arrived,
    this.invoiceId,
    this.error,
  });

  final bool waiting;

  /// Líneas que se apartaron ahora; null si el pedido no estaba para revisar
  /// (sin pagar, anulado o con la venta ya emitida).
  final int? arrived;
  final String? invoiceId;
  final String? error;

  factory QuoteOrderArrivals.fromJson(Map<String, dynamic> json) {
    return QuoteOrderArrivals(
      waiting: json['waiting'] == true,
      arrived: (json['arrived'] as num?)?.toInt(),
      invoiceId: json['invoice_id']?.toString(),
      error: json['error']?.toString(),
    );
  }

  String get message {
    if (error != null) {
      return 'Llegó todo, pero la venta no se emitió: $error';
    }
    final count = arrived;
    if (count == null) {
      return invoiceId != null
          ? 'La venta ya estaba emitida.'
          : 'El pedido todavía no está pagado.';
    }
    if (!waiting) return 'Llegó todo: la venta quedó emitida.';
    if (count == 0) {
      return 'Todavía no llega: no hay stock libre de lo que falta.';
    }
    return count == 1
        ? 'Llegó un producto y quedó apartado. Falta el resto.'
        : 'Llegaron $count productos y quedaron apartados. Falta el resto.';
  }
}

/// Lo que el operador confirma de una línea del borrador.
class QuoteLineConfirmation {
  const QuoteLineConfirmation({
    required this.availability,
    this.quantityOffered,
    this.unitPrice,
    this.leadDaysMin,
    this.leadDaysMax,
    this.unitCostNet,
    this.customerNote,
    this.staffNote,
  });

  final QuoteLineAvailability availability;
  final int? quantityOffered;
  final num? unitPrice;
  final int? leadDaysMin;
  final int? leadDaysMax;
  final num? unitCostNet;
  final String? customerNote;
  final String? staffNote;

  Map<String, dynamic> toJson() => {
        'availability': availability.code,
        if (quantityOffered != null) 'quantity_offered': quantityOffered,
        if (unitPrice != null) 'unit_price': unitPrice,
        if (leadDaysMin != null) 'lead_days_min': leadDaysMin,
        if (leadDaysMax != null) 'lead_days_max': leadDaysMax,
        if (unitCostNet != null) 'unit_cost_net': unitCostNet,
        'customer_note': customerNote ?? '',
        'staff_note': staffNote ?? '',
      };
}
