import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';

/// «Se vende a pedido» de un producto (`product_on_order_terms`,
/// 20261102041700): sin stock, la tienda lo ofrece a pedido con este plazo,
/// una cotización lo confirma sola y, al pagar, se le pide a este proveedor.
class ProductOnOrderTerms {
  const ProductOnOrderTerms({
    required this.isActive,
    required this.leadDaysMin,
    required this.leadDaysMax,
    this.supplierId,
  });

  static const off = ProductOnOrderTerms(
    isActive: false,
    leadDaysMin: 3,
    leadDaysMax: 5,
  );

  /// Los límites que la base hace cumplir (`product_on_order_terms_lead`).
  static const maxLeadDaysMin = 120;
  static const maxLeadDaysMax = 180;

  factory ProductOnOrderTerms.fromJson(Map<String, dynamic> json) {
    int days(Object? raw, int fallback) =>
        raw is num ? raw.toInt() : int.tryParse('$raw') ?? fallback;
    final supplier = json['supplier_id']?.toString().trim() ?? '';
    return ProductOnOrderTerms(
      isActive: json['is_active'] == true,
      leadDaysMin: days(json['lead_days_min'], 3),
      leadDaysMax: days(json['lead_days_max'], 5),
      supplierId: supplier.isEmpty ? null : supplier,
    );
  }

  final bool isActive;
  final int leadDaysMin;
  final int leadDaysMax;
  final String? supplierId;

  /// Lo que hay que guardar para pasar de [saved] a [edited]; null si no
  /// cambió nada o si sigue apagado (apagado y nunca guardado no escribe).
  static ProductOnOrderTerms? changeBetween(
    ProductOnOrderTerms saved,
    ProductOnOrderTerms edited,
  ) {
    if (!edited.isActive && !saved.isActive) return null;
    return edited == saved ? null : edited;
  }

  /// Lo que dice la tienda: «llega en 3 a 5 días hábiles».
  String get leadLabel => leadDaysMin == leadDaysMax
      ? 'llega en $leadDaysMin días hábiles'
      : 'llega en $leadDaysMin a $leadDaysMax días hábiles';

  @override
  bool operator ==(Object other) =>
      other is ProductOnOrderTerms &&
      other.isActive == isActive &&
      other.leadDaysMin == leadDaysMin &&
      other.leadDaysMax == leadDaysMax &&
      other.supplierId == supplierId;

  @override
  int get hashCode =>
      Object.hash(isActive, leadDaysMin, leadDaysMax, supplierId);
}

class ProductOnOrderTermsService {
  ProductOnOrderTermsService({
    SupabaseClient? client,
    TenantService? tenantService,
  })  : _client = client ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService();

  final SupabaseClient _client;
  final TenantService _tenantService;

  Future<String> _tenantId() async {
    final tenantId =
        _tenantService.currentTenantId ?? await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No hay una tienda activa en la sesión.');
    }
    return tenantId;
  }

  /// Lo guardado; sin fila, [ProductOnOrderTerms.off].
  Future<ProductOnOrderTerms> fetch(String productId) async {
    final row = await _client
        .from('product_on_order_terms')
        .select('supplier_id, lead_days_min, lead_days_max, is_active')
        .eq('tenant_id', await _tenantId())
        .eq('product_id', productId)
        .maybeSingle();
    return row == null
        ? ProductOnOrderTerms.off
        : ProductOnOrderTerms.fromJson(Map<String, dynamic>.from(row));
  }

  Future<ProductOnOrderTerms> save(
    String productId,
    ProductOnOrderTerms terms,
  ) async {
    final result = await _client.rpc('set_product_on_order_terms_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_product_id': productId,
      'p_terms': {
        'is_active': terms.isActive,
        'supplier_id': terms.supplierId ?? '',
        'lead_days_min': terms.leadDaysMin,
        'lead_days_max': terms.leadDaysMax,
      },
    });
    return result is Map
        ? ProductOnOrderTerms.fromJson(Map<String, dynamic>.from(result))
        : terms;
  }
}
