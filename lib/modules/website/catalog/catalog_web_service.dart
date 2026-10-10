import 'package:supabase_flutter/supabase_flutter.dart';

import 'catalog_web_models.dart';

/// What `catalog_set_web_sale_v1` reports: how many changed and why the
/// others did not.
class CatalogWebSaleResult {
  const CatalogWebSaleResult({
    required this.changed,
    required this.skippedConsumables,
    required this.skippedInactive,
    required this.skippedUntaxed,
  });

  factory CatalogWebSaleResult.fromJson(Map<String, dynamic> json) {
    int read(String key) => int.tryParse(json[key]?.toString() ?? '') ?? 0;
    return CatalogWebSaleResult(
      changed: read('changed'),
      skippedConsumables: read('skipped_consumables'),
      skippedInactive: read('skipped_inactive'),
      skippedUntaxed: read('skipped_untaxed'),
    );
  }

  final int changed;
  final int skippedConsumables;
  final int skippedInactive;
  final int skippedUntaxed;

  /// One sentence for the operator.
  String describe({required bool on}) {
    final verb = on ? 'a la venta' : 'fuera de la web';
    final parts = <String>[
      changed == 1
          ? '1 producto quedó $verb.'
          : '$changed productos quedaron $verb.',
      if (skippedConsumables > 0)
        '$skippedConsumables consumible${skippedConsumables == 1 ? '' : 's'} del taller no se ${skippedConsumables == 1 ? 'vende' : 'venden'} online.',
      if (skippedInactive > 0)
        '$skippedInactive inactivo${skippedInactive == 1 ? '' : 's'} omitido${skippedInactive == 1 ? '' : 's'}.',
      if (skippedUntaxed > 0)
        '$skippedUntaxed sin clasificación de IVA: clasifícalos en «Por resolver».',
    ];
    return parts.join(' ');
  }
}

/// The ERP side of the catalog rule: every read and write goes through the
/// `catalog_*` RPCs, which check the tenant and the editor permission.
class CatalogWebService {
  CatalogWebService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<CatalogWebItem>> loadItems(String tenantId) async {
    final rows = await _client.rpc(
      'catalog_web_items_v1',
      params: {'p_tenant_id': tenantId},
    );
    return [
      for (final row in rows as List)
        CatalogWebItem.fromRow(Map<String, dynamic>.from(row as Map)),
    ];
  }

  /// The services' «qué incluye» and the categories' texts, which the
  /// /servicios preview draws (the catalog rows do not carry long text).
  Future<({Map<String, String> services, Map<String, String> categories})>
      loadServiceTexts(String tenantId) async {
    final results = await Future.wait<Object?>([
      _client
          .from('products')
          .select('id,website_description,description')
          .eq('tenant_id', tenantId)
          .eq('product_type', 'service'),
      _client
          .from('product_categories')
          .select('id,description')
          .eq('tenant_id', tenantId)
          .eq('is_active', true),
    ]);
    String text(Map row, String a, [String? b]) {
      for (final key in [a, if (b != null) b]) {
        final value = row[key]?.toString() ?? '';
        if (value.trim().isNotEmpty) return value;
      }
      return '';
    }

    return (
      services: {
        for (final row in results[0] as List)
          (row as Map)['id'].toString():
              text(row, 'website_description', 'description'),
      },
      categories: {
        for (final row in results[1] as List)
          (row as Map)['id'].toString(): text(row, 'description'),
      },
    );
  }

  Future<CatalogRules> loadRules(String tenantId) async {
    final rows = await _client
        .from('website_settings')
        .select('key,value')
        .eq('tenant_id', tenantId)
        .inFilter('key', CatalogRules.keys);
    final settings = <String, String>{
      for (final row in rows as List)
        (row as Map)['key'].toString(): row['value']?.toString() ?? '',
    };
    return CatalogRules.fromSettings(settings);
  }

  Future<CatalogWebSaleResult> setWebSale({
    required String tenantId,
    required Iterable<String> productIds,
    required bool on,
  }) async {
    final result = await _client.rpc('catalog_set_web_sale_v1', params: {
      'p_tenant_id': tenantId,
      'p_product_ids': productIds.toSet().toList(),
      'p_on': on,
    });
    return CatalogWebSaleResult.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  /// Copies the real barcode in the SKU to the GTIN; null copies every
  /// candidate. Returns the products changed, for an undo.
  Future<List<String>> copySkuToGtin({
    required String tenantId,
    Iterable<String>? productIds,
  }) async {
    final result = await _client.rpc('catalog_copy_sku_to_gtin_v1', params: {
      'p_tenant_id': tenantId,
      'p_product_ids': productIds?.toSet().toList(),
    });
    final ids = (result as Map)['product_ids'] as List? ?? const [];
    return [for (final id in ids) id.toString()];
  }

  Future<void> undoSkuToGtin({
    required String tenantId,
    required Iterable<String> productIds,
  }) async {
    await _client.rpc('catalog_undo_sku_to_gtin_v1', params: {
      'p_tenant_id': tenantId,
      'p_product_ids': productIds.toSet().toList(),
    });
  }

  Future<void> setClearance({
    required String tenantId,
    required String productId,
    required DateTime? until,
  }) async {
    await _client.rpc('catalog_set_clearance_v1', params: {
      'p_tenant_id': tenantId,
      'p_product_id': productId,
      'p_until': until == null
          ? null
          : '${until.year.toString().padLeft(4, '0')}-'
              '${until.month.toString().padLeft(2, '0')}-'
              '${until.day.toString().padLeft(2, '0')}',
    });
  }

  Future<void> setPriceMode({
    required String tenantId,
    required String productId,
    required CatalogPriceMode mode,
  }) async {
    await _client.rpc('catalog_set_price_mode_v1', params: {
      'p_tenant_id': tenantId,
      'p_product_id': productId,
      'p_mode': mode.code,
    });
  }

  /// [rate] is 19 (afecto) or 0 (exento).
  Future<int> classifyTax({
    required String tenantId,
    required Iterable<String> productIds,
    required int rate,
  }) async {
    final result = await _client.rpc('catalog_classify_tax_v1', params: {
      'p_tenant_id': tenantId,
      'p_product_ids': productIds.toSet().toList(),
      'p_rate': rate,
    });
    return int.tryParse((result as Map)['classified']?.toString() ?? '') ?? 0;
  }

  /// [toConsumable] true makes it workshop supply; false, a product for sale.
  Future<void> convertItem({
    required String tenantId,
    required String productId,
    required bool toConsumable,
  }) async {
    await _client.rpc('catalog_convert_item_v1', params: {
      'p_tenant_id': tenantId,
      'p_product_id': productId,
      'p_target': toConsumable ? 'workshop_consumable' : 'inventory',
      'p_reason': null,
    });
  }

  Future<void> dismissIssue({
    required String tenantId,
    required String productId,
    required String issue,
    bool dismissed = true,
  }) async {
    await _client.rpc('catalog_dismiss_issue_v1', params: {
      'p_tenant_id': tenantId,
      'p_product_id': productId,
      'p_issue': issue,
      'p_dismissed': dismissed,
    });
  }

  Future<int> archiveEmptyRecords({
    required String tenantId,
    required Iterable<String> productIds,
  }) async {
    final result =
        await _client.rpc('catalog_archive_empty_records_v1', params: {
      'p_tenant_id': tenantId,
      'p_product_ids': productIds.toSet().toList(),
    });
    return int.tryParse((result as Map)['archived']?.toString() ?? '') ?? 0;
  }

  Future<List<CatalogCategoryCount>> loadCategoryCounts(String tenantId) async {
    final rows = await _client.rpc(
      'catalog_category_counts_v1',
      params: {'p_tenant_id': tenantId},
    );
    return [
      for (final row in rows as List)
        CatalogCategoryCount.fromRow(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<void> replaceCategoryVisibility({
    required String tenantId,
    required Iterable<String> visibleCategoryIds,
  }) async {
    await _client.rpc('replace_website_category_visibility', params: {
      'p_tenant_id': tenantId,
      'p_visible_category_ids': visibleCategoryIds.toSet().toList(),
    });
  }

  Future<List<CatalogFeaturedSuggestion>> loadFeaturedSuggestions(
    String tenantId, {
    int limit = 16,
    int minStock = 2,
  }) async {
    final rows = await _client.rpc('catalog_featured_suggestions_v1', params: {
      'p_tenant_id': tenantId,
      'p_limit': limit,
      'p_min_stock': minStock,
    });
    return [
      for (final row in rows as List)
        CatalogFeaturedSuggestion.fromRow(
          Map<String, dynamic>.from(row as Map),
        ),
    ];
  }

  /// The featured products in their order (`featured_products`).
  Future<List<String>> loadFeaturedIds(String tenantId) async {
    final rows = await _client
        .from('featured_products')
        .select('product_id,order_index,active')
        .eq('tenant_id', tenantId)
        .eq('active', true)
        .order('order_index', ascending: true);
    return [
      for (final row in rows as List) (row as Map)['product_id'].toString(),
    ];
  }

  /// How many products each visible «Productos» block that reads
  /// «Destacados» shows (its `maxProducts`, 8 when unset): the featured
  /// tab tells which picks are on the page and which wait in reserve.
  Future<List<int>> loadFeaturedBlockLimits(String tenantId) async {
    final rows = await _client
        .from('website_blocks')
        .select('block_data')
        .eq('tenant_id', tenantId)
        .eq('block_type', 'products')
        .eq('is_visible', true);
    return [
      for (final row in rows as List)
        if ((row as Map)['block_data'] case final Map data
            when data['productSource'] == 'featured')
          int.tryParse(data['maxProducts']?.toString() ?? '') ?? 8,
    ];
  }

  Future<void> replaceFeatured({
    required String tenantId,
    required List<String> productIds,
  }) async {
    await _client.rpc('catalog_replace_featured_v1', params: {
      'p_tenant_id': tenantId,
      'p_product_ids': productIds,
    });
  }
}
