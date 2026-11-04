import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';

/// Cómo se ofrece un producto cuando no tiene stock (20261103070000). El
/// dueño: «no es simplemente que si un producto está agotado,
/// automáticamente se puede agregar a una cotización».
enum SoldOutOffer {
  /// Lo decide su marca: se cotiza si está en «Marcas que se cotizan sin
  /// stock» de Ajustes de cotizaciones.
  byBrand,

  /// Se cotiza: el taller confirma con sus proveedores.
  quote,

  /// Se vende a pedido, con proveedor y plazo.
  onOrder,

  /// No se ofrece: la tienda lo muestra agotado y sólo se pregunta por él.
  none,
}

/// Lo que la ficha de un producto dice de él sin stock
/// (`product_on_order_terms`): «Se vende a pedido» (20261102041700) con su
/// proveedor y su plazo, o si se cotiza o no se ofrece (20261103070000); sin
/// decisión, manda su marca.
class ProductOnOrderTerms {
  const ProductOnOrderTerms({
    required this.isActive,
    required this.leadDaysMin,
    required this.leadDaysMax,
    this.supplierId,
    this.quoteWhenSoldOut,
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
      quoteWhenSoldOut: switch (json['quote_when_sold_out']) {
        final bool decided => decided,
        _ => null,
      },
    );
  }

  final bool isActive;
  final int leadDaysMin;
  final int leadDaysMax;
  final String? supplierId;

  /// true se cotiza, false no se ofrece, null lo decide su marca.
  final bool? quoteWhenSoldOut;

  SoldOutOffer get offer => isActive
      ? SoldOutOffer.onOrder
      : switch (quoteWhenSoldOut) {
          true => SoldOutOffer.quote,
          false => SoldOutOffer.none,
          null => SoldOutOffer.byBrand,
        };

  /// Los mismos términos con otra decisión; el proveedor y el plazo quedan
  /// para cuando vuelva a venderse a pedido.
  ProductOnOrderTerms withOffer(SoldOutOffer offer) => ProductOnOrderTerms(
        isActive: offer == SoldOutOffer.onOrder,
        leadDaysMin: leadDaysMin,
        leadDaysMax: leadDaysMax,
        supplierId: supplierId,
        quoteWhenSoldOut: switch (offer) {
          SoldOutOffer.quote => true,
          SoldOutOffer.none => false,
          SoldOutOffer.byBrand || SoldOutOffer.onOrder => null,
        },
      );

  /// Lo que hay que guardar para pasar de [saved] a [edited]; null si no
  /// cambió nada o si sólo cambió el plazo de algo que no se vende a pedido
  /// (sin decisión y nunca guardado no escribe).
  static ProductOnOrderTerms? changeBetween(
    ProductOnOrderTerms saved,
    ProductOnOrderTerms edited,
  ) {
    if (!edited.isActive &&
        !saved.isActive &&
        edited.quoteWhenSoldOut == saved.quoteWhenSoldOut) {
      return null;
    }
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
      other.supplierId == supplierId &&
      other.quoteWhenSoldOut == quoteWhenSoldOut;

  @override
  int get hashCode => Object.hash(
        isActive,
        leadDaysMin,
        leadDaysMax,
        supplierId,
        quoteWhenSoldOut,
      );
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
        .select(
          'supplier_id, lead_days_min, lead_days_max, is_active, '
          'quote_when_sold_out',
        )
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
        'quote_when_sold_out': terms.quoteWhenSoldOut,
      },
    });
    return result is Map
        ? ProductOnOrderTerms.fromJson(Map<String, dynamic>.from(result))
        : terms;
  }

  /// Las marcas que se cotizan sin stock (`customer_quote_sold_out_brands`):
  /// con ellas la ficha dice qué decide la marca de este producto.
  Future<Set<String>> fetchSoldOutBrandIds() async {
    final rows = await _client
        .from('customer_quote_sold_out_brands')
        .select('brand_id')
        .eq('tenant_id', await _tenantId());
    return {
      for (final row in rows)
        if (row['brand_id'] != null) row['brand_id'].toString(),
    };
  }
}
