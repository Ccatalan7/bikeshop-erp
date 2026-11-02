import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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
    if (text.contains('42501')) {
      return 'No tienes acceso a esta cotización.';
    }
    return 'No se pudo completar. Revisa la conexión e inténtalo de nuevo.';
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
