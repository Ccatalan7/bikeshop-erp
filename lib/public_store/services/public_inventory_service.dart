import 'package:flutter/foundation.dart' hide Category;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/product.dart';
import '../../shared/models/public_product_visibility_policy.dart';
import '../../modules/inventory/models/category_models.dart';

class PublicProductPage {
  final List<Product> products;
  final int totalCount;

  const PublicProductPage({
    required this.products,
    required this.totalCount,
  });
}

class PublicCategoryCountSnapshot {
  final Map<String, int> directCountsByCategoryId;
  final int totalCount;

  const PublicCategoryCountSnapshot({
    required this.directCountsByCategoryId,
    required this.totalCount,
  });
}

class PublicCatalogBrandFacet {
  final String id;
  final String label;
  final int itemCount;

  const PublicCatalogBrandFacet({
    required this.id,
    required this.label,
    required this.itemCount,
  });
}

class PublicCatalogFacetSnapshot {
  final List<PublicCatalogBrandFacet> brands;
  final Map<String, int> directCategoryCounts;
  final int? filteredTotalCount;
  final double? minPrice;
  final double? maxPrice;
  final bool isAvailable;

  const PublicCatalogFacetSnapshot({
    required this.brands,
    this.directCategoryCounts = const {},
    this.filteredTotalCount,
    required this.minPrice,
    required this.maxPrice,
    this.isAvailable = true,
  });

  const PublicCatalogFacetSnapshot.unavailable()
      : brands = const [],
        directCategoryCounts = const {},
        filteredTotalCount = null,
        minPrice = null,
        maxPrice = null,
        isAvailable = false;
}

/// Public-facing inventory service for the storefront
///
/// This service does NOT require authentication - it works for anonymous users.
/// Instead of using the authenticated user's tenant_id, it accepts tenant_id
/// as a parameter (from subdomain detection).
///
/// Use this service ONLY in public store pages (product catalog, product detail).
/// For admin/authenticated pages, use the regular InventoryProvider.
///
/// Example usage:
/// ```dart
/// final tenantId = context.read<PublicStoreTenantProvider>().tenantId;
/// if (tenantId != null) {
///   final products = await publicInventoryService.getProductsForTenant(
///     tenantId: tenantId,
///   );
/// }
/// ```
class PublicInventoryService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Cache products and categories to reduce DB calls
  final Map<String, List<Product>> _productsCache = {};
  final Map<String, List<Category>> _categoriesCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};

  // Prevent duplicate concurrent fetches per tenant
  final Map<String, Future<List<Category>>> _categoriesInFlight = {};

  // Cache duration: 5 minutes
  static const _cacheDuration = Duration(minutes: 5);

  /// Check if cache is still valid
  bool _isCacheValid(String key) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < _cacheDuration;
  }

  /// Check if products cache exists and is valid for tenant
  bool hasProductsCache(String tenantId) {
    final cacheKey = 'products_$tenantId';
    return _isCacheValid(cacheKey) && _productsCache.containsKey(cacheKey);
  }

  List<Product> getCachedProductsForTenant(String tenantId) {
    final cacheKey = 'products_$tenantId';
    return List<Product>.unmodifiable(_productsCache[cacheKey] ?? const []);
  }

  Map<String, dynamic> _cleanRpcParams(Map<String, dynamic> params) {
    final cleaned = <String, dynamic>{};
    for (final entry in params.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is Iterable && value.isEmpty) continue;
      cleaned[entry.key] = value;
    }
    return cleaned;
  }

  /// The main public catalog RPC predates checkout tax classification and does
  /// not expose it. Hydrate only the requested public product IDs through the
  /// narrow allowlisted RPC; if that contract is unavailable, keep products
  /// visible but leave `taxRate` null so checkout fails closed.
  Future<List<Map<String, dynamic>>> _attachCheckoutTaxRates({
    required String tenantId,
    required List<Map<String, dynamic>> rows,
  }) async {
    if (rows.isEmpty) return rows;

    final productIds = rows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (productIds.isEmpty) return rows;

    try {
      final response = await _supabase.rpc(
        'get_public_product_tax_classifications',
        params: {
          'p_tenant_id': tenantId,
          'p_product_ids': productIds,
        },
      );
      final taxRatesById = <String, Object?>{};
      for (final raw in response as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        if (id != null && id.isNotEmpty) {
          taxRatesById[id] = row['tax_rate'];
        }
      }

      return rows.map((row) {
        final id = row['id']?.toString();
        if (id == null || !taxRatesById.containsKey(id)) return row;
        return <String, dynamic>{
          ...row,
          'tax_rate': taxRatesById[id],
        };
      }).toList();
    } catch (error) {
      debugPrint(
        '⚠️ PublicInventoryService: tax classification unavailable; '
        'checkout will stay blocked: $error',
      );
      return rows;
    }
  }

  /// Resolves the canonical catalog brand for the public product projection.
  ///
  /// The public product RPC still exposes the legacy denormalized `brand`
  /// column. Merchant and static SEO resolve `brand_id` through
  /// `product_brands`, so the live storefront must do the same before a
  /// [Product] reaches the detail page, cart or checkout.
  Future<List<Map<String, dynamic>>> _attachCanonicalBrandNames({
    required String tenantId,
    required List<Map<String, dynamic>> rows,
  }) async {
    if (rows.isEmpty) return rows;
    final brandIds = rows
        .map((row) => row['brand_id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (brandIds.isEmpty) return rows;

    try {
      final response = await _supabase
          .from('product_brands')
          .select('id,name,tenant_id,is_active')
          .inFilter('id', brandIds)
          .eq('is_active', true);
      final canonicalNames = canonicalPublicProductBrandNames(
        rows: (response as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false),
        tenantId: tenantId,
        requestedBrandIds: brandIds,
      );
      if (canonicalNames.isEmpty) return rows;

      return rows.map((row) {
        final brandId = row['brand_id']?.toString().trim() ?? '';
        final canonicalName = canonicalNames[brandId];
        return canonicalName == null
            ? row
            : <String, dynamic>{...row, 'brand': canonicalName};
      }).toList(growable: false);
    } catch (error) {
      debugPrint(
        '⚠️ PublicInventoryService: canonical brand unavailable; '
        'using the catalog fallback: $error',
      );
      return rows;
    }
  }

  Future<List<Map<String, dynamic>>> _attachSetIdentity({
    required String tenantId,
    required List<Map<String, dynamic>> rows,
    bool deriveAvailability = false,
  }) async {
    if (rows.isEmpty) return rows;
    final ids = rows
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return rows;

    try {
      final response = await _supabase
          .from('products')
          .select(
            'id,is_set,set_type,parent_set_id,component_label,component_position,'
            'website_name,website_price,website_description,'
            'website_seo_title,website_seo_description,'
            'website_merchant_title,website_merchant_description,'
            'website_merchant_brand,website_merchant_gtin,website_merchant_mpn,'
            'website_google_product_category,price_currency',
          )
          .eq('tenant_id', tenantId)
          .inFilter('id', ids);
      final identityById = <String, Map<String, dynamic>>{
        for (final raw in response as List)
          if (raw['id'] != null)
            raw['id'].toString(): Map<String, dynamic>.from(raw as Map),
      };
      final enriched = rows
          .map((row) => <String, dynamic>{
                ...row,
                ...?identityById[row['id']?.toString()],
              })
          .toList(growable: false);

      if (!deriveAvailability) return enriched;
      for (final row in enriched.where((row) => row['is_set'] == true)) {
        final preview = await _supabase.rpc(
          'preview_product_stock_impact',
          params: {
            'p_product_id': row['id'],
            'p_quantity': 1,
          },
        );
        final payload = preview is Map
            ? Map<String, dynamic>.from(preview)
            : preview is List && preview.length == 1 && preview.first is Map
                ? Map<String, dynamic>.from(preview.first as Map)
                : null;
        final available = (payload?['available_quantity'] as num?)?.toInt();
        if (available != null) {
          row['inventory_qty'] = available;
          row['stock_quantity'] = available;
          row['full_sets_available'] = available;
        }
      }
      return enriched;
    } catch (error) {
      debugPrint(
        '⚠️ PublicInventoryService: set identity unavailable: $error',
      );
      return rows;
    }
  }

  Future<PublicProductPage> getProductPageForTenant({
    required String tenantId,
    List<String>? categoryIds,
    List<String>? productIds,
    String? sku,
    String? searchQuery,
    ProductType? productType,
    PublicProductVisibilityPolicy? policy,
    bool onlyInStock = true,
    // `onlyInStock` is also a legacy canonical-policy input. Keep this
    // separate so a missing visitor filter does not accidentally become an
    // additional availability restriction in the faceted facade.
    bool applyAvailabilityFacet = false,
    List<String>? brandIds,
    double? minPrice,
    double? maxPrice,
    String sortBy = 'name',
    int limit = 20,
    int offset = 0,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final hasProfessionalFacets = applyAvailabilityFacet ||
          brandIds?.isNotEmpty == true ||
          minPrice != null ||
          maxPrice != null;
      final response = await _supabase.rpc(
        hasProfessionalFacets
            ? 'get_public_products_faceted_v1'
            : 'get_public_products',
        params: _cleanRpcParams(hasProfessionalFacets
            ? {
                'p_tenant_id': tenantId,
                'p_category_ids': categoryIds,
                'p_search_term': searchQuery?.trim(),
                'p_product_type': productType?.name,
                'p_only_in_stock': applyAvailabilityFacet && onlyInStock,
                'p_brand_ids': brandIds,
                'p_min_price': minPrice,
                'p_max_price': maxPrice,
                'p_sort_by': sortBy,
                'p_limit': limit,
                'p_offset': offset,
              }
            : {
                'p_tenant_id': tenantId,
                'p_category_ids': categoryIds,
                'p_product_ids': productIds,
                'p_sku': sku,
                'p_search_term': searchQuery?.trim(),
                'p_product_type': productType?.name,
                'p_only_in_stock': onlyInStock,
                'p_sort_by': sortBy,
                'p_limit': limit,
                'p_offset': offset,
              }),
      );

      final rows = (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final classifiedRows = await _attachCheckoutTaxRates(
        tenantId: tenantId,
        rows: rows,
      );
      final setAwareRows = await _attachSetIdentity(
        tenantId: tenantId,
        rows: classifiedRows,
      );
      final brandAwareRows = await _attachCanonicalBrandNames(
        tenantId: tenantId,
        rows: setAwareRows,
      );
      final products = brandAwareRows.map(Product.fromJson).toList();
      final totalCount = classifiedRows.isEmpty
          ? 0
          : (classifiedRows.first['total_count'] as num?)?.toInt() ??
              products.length;

      debugPrint(
          '⏱️ [PublicInventory] Product page RPC: ${sw.elapsedMilliseconds}ms (${products.length}/$totalCount products)');
      return PublicProductPage(products: products, totalCount: totalCount);
    } catch (e) {
      debugPrint(
          '❌ PublicInventoryService: Error fetching product page: $e (${sw.elapsedMilliseconds}ms)');
      // A transport/schema/RPC failure is not a legitimate zero-result page.
      // Let the storefront render an explicit retry state instead of telling
      // the visitor that no products match. This is especially important
      // during database-first rollout of the additive faceted RPC.
      rethrow;
    }
  }

  Future<PublicCatalogFacetSnapshot> getCatalogFacetsForTenant({
    required String tenantId,
    List<String>? categoryIds,
    String? searchQuery,
    ProductType? productType,
    bool onlyInStock = true,
    // True only when the visitor explicitly selected the availability facet.
    bool applyAvailabilityFacet = false,
    List<String>? brandIds,
    double? minPrice,
    double? maxPrice,
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_public_product_facets_v1',
        params: _cleanRpcParams({
          'p_tenant_id': tenantId,
          'p_category_ids': categoryIds,
          'p_search_term': searchQuery?.trim(),
          'p_product_type': productType?.name,
          'p_only_in_stock': applyAvailabilityFacet && onlyInStock,
          'p_brand_ids': brandIds,
          'p_min_price': minPrice,
          'p_max_price': maxPrice,
        }),
      );

      final brands = <PublicCatalogBrandFacet>[];
      final directCategoryCounts = <String, int>{};
      int? filteredTotalCount;
      double? rangeMin;
      double? rangeMax;
      for (final raw in response as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        switch (row['facet_key']?.toString()) {
          case 'brand':
            final id = row['value_id']?.toString().trim() ?? '';
            final label = row['value_label']?.toString().trim() ?? '';
            if (id.isNotEmpty && label.isNotEmpty) {
              brands.add(PublicCatalogBrandFacet(
                id: id,
                label: label,
                itemCount: (row['item_count'] as num?)?.toInt() ?? 0,
              ));
            }
            break;
          case 'price':
            rangeMin = (row['range_min'] as num?)?.toDouble();
            rangeMax = (row['range_max'] as num?)?.toDouble();
            break;
          case 'category':
            final id = row['value_id']?.toString().trim() ?? '';
            if (id.isNotEmpty) {
              directCategoryCounts[id] =
                  (row['item_count'] as num?)?.toInt() ?? 0;
            }
            break;
          case 'summary':
            filteredTotalCount = (row['item_count'] as num?)?.toInt() ?? 0;
            break;
        }
      }
      brands.sort((a, b) => a.label.toLowerCase().compareTo(
            b.label.toLowerCase(),
          ));
      return PublicCatalogFacetSnapshot(
        brands: List.unmodifiable(brands),
        directCategoryCounts: Map.unmodifiable(directCategoryCounts),
        filteredTotalCount: filteredTotalCount,
        minPrice: rangeMin,
        maxPrice: rangeMax,
      );
    } catch (error) {
      debugPrint(
        '⚠️ PublicInventoryService: professional catalog facets unavailable: '
        '$error',
      );
      return const PublicCatalogFacetSnapshot.unavailable();
    }
  }

  Future<PublicCategoryCountSnapshot> getCategoryCountsForTenant({
    required String tenantId,
    ProductType? productType,
    PublicProductVisibilityPolicy? policy,
    bool onlyInStock = true,
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_public_product_category_counts',
        params: _cleanRpcParams({
          'p_tenant_id': tenantId,
          'p_product_type': productType?.name,
          'p_only_in_stock': onlyInStock,
        }),
      );

      final counts = <String, int>{};
      var total = 0;
      for (final row in response as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final count = (map['product_count'] as num?)?.toInt() ?? 0;
        total += count;
        final categoryId = map['category_id']?.toString();
        if (categoryId != null && categoryId.isNotEmpty) {
          counts[categoryId] = count;
        }
      }

      return PublicCategoryCountSnapshot(
        directCountsByCategoryId: counts,
        totalCount: total,
      );
    } catch (e) {
      debugPrint('❌ PublicInventoryService: Error fetching counts: $e');
      return const PublicCategoryCountSnapshot(
        directCountsByCategoryId: {},
        totalCount: 0,
      );
    }
  }

  /// Check if categories cache exists and is valid for tenant
  bool hasCategoriesCache(String tenantId) {
    final cacheKey = 'categories_$tenantId';
    return _isCacheValid(cacheKey) && _categoriesCache.containsKey(cacheKey);
  }

  /// Get products for specific tenant (public access)
  ///
  /// Parameters:
  /// - [tenantId]: The tenant ID (from subdomain detection)
  /// - [categoryId]: Optional - filter by category
  /// - [searchQuery]: Optional - search by name or SKU
  /// - [onlyInStock]: Show only products with inventory_qty > 0 (default: true)
  /// - [minPrice]: Optional - filter products with price >= minPrice
  /// - [maxPrice]: Optional - filter products with price <= maxPrice
  /// - [limit]: Max number of results (null uses a bounded public fallback)
  /// - [offset]: Pagination offset (default: 0)
  /// - [includeUnpublished]: Admin/editor preview bypass for unpublished items
  ///
  /// Returns list of products or empty list on error
  Future<List<Product>> getProductsForTenant({
    required String tenantId,
    String? categoryId,
    String? searchQuery,
    bool onlyInStock = true,
    PublicProductVisibilityPolicy? policy,
    double? minPrice,
    double? maxPrice,
    int? limit,
    int offset = 0,
    bool includeUnpublished = false,
  }) async {
    final sw = Stopwatch()..start();
    try {
      if (!includeUnpublished) {
        final page = await getProductPageForTenant(
          tenantId: tenantId,
          categoryIds:
              categoryId == null || categoryId.isEmpty ? null : [categoryId],
          searchQuery: searchQuery,
          policy: policy,
          onlyInStock: onlyInStock,
          sortBy: 'name',
          limit: limit ?? 100,
          offset: offset,
        );
        var products = page.products;
        if (minPrice != null) {
          products = products.where((p) => p.price >= minPrice).toList();
        }
        if (maxPrice != null) {
          products = products.where((p) => p.price <= maxPrice).toList();
        }
        return products;
      }

      // Check cache first (only if no filters/pagination applied)
      final cacheKey = 'products_$tenantId';
      if (categoryId == null &&
          searchQuery == null &&
          onlyInStock &&
          minPrice == null &&
          maxPrice == null &&
          offset == 0 &&
          limit == null &&
          !includeUnpublished &&
          _isCacheValid(cacheKey)) {
        debugPrint(
            '⏱️ [PublicInventory] Products from cache: ${sw.elapsedMilliseconds}ms');
        return _productsCache[cacheKey] ?? [];
      }
      // Build base query
      var query = _supabase
          .from('products')
          .select(Product.storefrontPreviewSelect)
          .eq('tenant_id', tenantId);

      if (!includeUnpublished) {
        query = query
            .eq('is_active', true)
            .eq('is_published', true)
            .eq('show_on_website', true);
      }

      // Filter by stock if requested (RLS only filters is_active=true)
      // NOTE: We avoid applying a stock filter at the SQL level when
      // searchQuery is present due to PostgREST's single `or=` query param.
      // We'll filter in-memory after fetching to keep services/non-stock items
      // visible.
      if (onlyInStock &&
          !includeUnpublished &&
          (searchQuery == null || searchQuery.isEmpty)) {
        // IMPORTANT: services and non-stock-tracked items must NEVER be
        // filtered out by stock constraints.
        // PostgREST supports only one `or=` param, so we include all
        // “in-stock” conditions in a single OR group.
        query = query.or(
          'product_type.eq.service,track_stock.eq.false,stock_quantity.gt.0',
        );
      }

      // Apply additional filters

      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.eq('category_id', categoryId);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        // Search in name, SKU, or description
        query = query.or('name.ilike.%$searchQuery%,'
            'sku.ilike.%$searchQuery%,'
            'description.ilike.%$searchQuery%');
      }

      if (minPrice != null) {
        query = query.gte('price', minPrice);
      }

      if (maxPrice != null) {
        query = query.lte('price', maxPrice);
      }

      // Apply ordering and pagination last
      var orderedQuery = query.order('name', ascending: true);

      // Only apply range if limit is specified
      final response = limit != null
          ? await orderedQuery.range(offset, offset + limit - 1)
          : await orderedQuery;

      debugPrint(
          '⏱️ [PublicInventory] Products query: ${sw.elapsedMilliseconds}ms');

      final rows = (response as List)
          .map((json) => Map<String, dynamic>.from(json as Map))
          .toList();
      final setAwareRows = await _attachSetIdentity(
        tenantId: tenantId,
        rows: rows,
        deriveAvailability: true,
      );
      final brandAwareRows = await _attachCanonicalBrandNames(
        tenantId: tenantId,
        rows: setAwareRows,
      );
      var products = brandAwareRows.map(Product.fromJson).toList();
      if (onlyInStock) {
        products = products
            .where(
              (product) =>
                  !product.tracksInventory ||
                  product.availableStockQuantity > 0,
            )
            .toList(growable: false);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final effectivePolicy = policy ?? const PublicProductVisibilityPolicy();
        return products.where(effectivePolicy.allowsProduct).toList();
      }

      debugPrint(
          '⏱️ [PublicInventory] Products total: ${sw.elapsedMilliseconds}ms (${products.length} products)');

      // Cache results if no filters (default view)
      if (categoryId == null &&
          searchQuery == null &&
          onlyInStock &&
          minPrice == null &&
          maxPrice == null &&
          offset == 0 &&
          limit == null &&
          !includeUnpublished) {
        _productsCache[cacheKey] = products;
        _cacheTimestamps[cacheKey] = DateTime.now();
      }

      return products;
    } catch (e) {
      debugPrint(
          '⏱️ [PublicInventory] Products ERROR: ${sw.elapsedMilliseconds}ms - $e');
      return [];
    }
  }

  /// Get categories for specific tenant (public access)
  ///
  /// Parameters:
  /// - [tenantId]: The tenant ID (from subdomain detection)
  ///
  /// Returns list of categories or empty list on error
  Future<List<Category>> getCategoriesForTenant({
    required String tenantId,
  }) async {
    final sw = Stopwatch()..start();
    final cacheKey = 'categories_$tenantId';
    try {
      // Check cache first
      if (_isCacheValid(cacheKey)) {
        debugPrint(
            '⏱️ [PublicInventory] Categories from cache: ${sw.elapsedMilliseconds}ms');
        return _categoriesCache[cacheKey] ?? [];
      }

      // Avoid duplicate requests if multiple widgets trigger it on startup
      final inFlight = _categoriesInFlight[cacheKey];
      if (inFlight != null) {
        debugPrint(
            '⏳ [PublicInventory] Categories already loading; awaiting in-flight request');
        return await inFlight;
      }

      final future = _fetchCategoriesForTenant(tenantId: tenantId, sw: sw);
      _categoriesInFlight[cacheKey] = future;
      return await future;
    } catch (e) {
      debugPrint(
          '❌ PublicInventoryService: Error fetching categories: $e (${sw.elapsedMilliseconds}ms)');
      return [];
    } finally {
      _categoriesInFlight.remove(cacheKey);
    }
  }

  Future<List<Category>> _fetchCategoriesForTenant({
    required String tenantId,
    required Stopwatch sw,
  }) async {
    final response = await _supabase
        .from('product_categories')
        // Only fetch what the public store needs (smaller payload = faster).
        .select(
            'id,tenant_id,name,full_path,parent_id,level,description,image_url,show_on_website,sort_order')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('sort_order', ascending: true)
        .order('name', ascending: true);

    debugPrint(
        '⏱️ [PublicInventory] Categories query: ${sw.elapsedMilliseconds}ms');

    final categories = (response as List)
        .map(
            (json) => Category.fromJson(Map<String, dynamic>.from(json as Map)))
        .toList();

    debugPrint(
        '✅ PublicInventoryService: Found ${categories.length} categories (${sw.elapsedMilliseconds}ms)');

    // Cache results
    final cacheKey = 'categories_$tenantId';
    _categoriesCache[cacheKey] = categories;
    _cacheTimestamps[cacheKey] = DateTime.now();

    return categories;
  }

  /// Get single product by ID (public access)
  ///
  /// Parameters:
  /// - [productId]: The product ID
  /// - [tenantId]: The tenant ID (for verification)
  ///
  /// Returns product or null if not found/error
  Future<Product?> getProductById({
    required String productId,
    required String tenantId,
    PublicProductVisibilityPolicy? policy,
  }) async {
    try {
      debugPrint(
          '🔍 PublicInventoryService: Fetching product $productId for tenant $tenantId');

      final page = await getProductPageForTenant(
        tenantId: tenantId,
        productIds: [productId],
        policy: policy,
        onlyInStock: false,
        limit: 1,
      );

      if (page.products.isEmpty) {
        debugPrint('⚠️ PublicInventoryService: Product $productId not found');
        return null;
      }

      final product = page.products.first;
      debugPrint('✅ PublicInventoryService: Found product: ${product.name}');
      return product;
    } catch (e) {
      debugPrint('❌ PublicInventoryService: Error fetching product: $e');
      return null;
    }
  }

  /// Get single product by SKU (public access)
  ///
  /// Parameters:
  /// - [sku]: The product SKU (case-insensitive)
  /// - [tenantId]: The tenant ID (for verification)
  ///
  /// Returns product or null if not found/error
  Future<Product?> getProductBySku({
    required String sku,
    required String tenantId,
    PublicProductVisibilityPolicy? policy,
  }) async {
    try {
      debugPrint(
          '🔍 PublicInventoryService: Fetching product by SKU $sku for tenant $tenantId');

      final page = await getProductPageForTenant(
        tenantId: tenantId,
        sku: sku,
        policy: policy,
        onlyInStock: false,
        limit: 1,
      );

      if (page.products.isEmpty) {
        debugPrint(
            '⚠️ PublicInventoryService: Product with SKU $sku not found');
        return null;
      }

      final product = page.products.first;
      debugPrint(
          '✅ PublicInventoryService: Found product by SKU: ${product.name}');
      return product;
    } catch (e) {
      debugPrint('❌ PublicInventoryService: Error fetching product by SKU: $e');
      return null;
    }
  }

  /// Get featured products for specific tenant (public access)
  ///
  /// Parameters:
  /// - [tenantId]: The tenant ID (from subdomain detection)
  /// - [limit]: Max number of featured products (default: 10)
  ///
  /// Returns list of featured products or empty list on error
  Future<List<Product>> getFeaturedProductsForTenant({
    required String tenantId,
    int limit = 10,
    PublicProductVisibilityPolicy? policy,
  }) async {
    try {
      debugPrint(
          '🔍 PublicInventoryService: Fetching featured products for tenant: $tenantId');

      final response = await _supabase.rpc(
        'get_public_featured_products',
        params: _cleanRpcParams({
          'p_tenant_id': tenantId,
          'p_limit': limit,
        }),
      );

      final rows = (response as List)
          .map((json) => Map<String, dynamic>.from(json as Map))
          .toList();
      final classifiedRows = await _attachCheckoutTaxRates(
        tenantId: tenantId,
        rows: rows,
      );
      final setAwareRows = await _attachSetIdentity(
        tenantId: tenantId,
        rows: classifiedRows,
      );
      final brandAwareRows = await _attachCanonicalBrandNames(
        tenantId: tenantId,
        rows: setAwareRows,
      );
      final products = brandAwareRows.map(Product.fromJson).toList();

      debugPrint(
          '✅ PublicInventoryService: Found ${products.length} featured products');
      return products;
    } catch (e) {
      debugPrint(
          '❌ PublicInventoryService: Error fetching featured products: $e');
      return [];
    }
  }

  /// Get product count for specific tenant
  ///
  /// Useful for pagination
  Future<int> getProductCountForTenant({
    required String tenantId,
    String? categoryId,
    String? searchQuery,
    PublicProductVisibilityPolicy? policy,
  }) async {
    try {
      final page = await getProductPageForTenant(
        tenantId: tenantId,
        categoryIds:
            categoryId == null || categoryId.isEmpty ? null : [categoryId],
        searchQuery: searchQuery,
        policy: policy,
        limit: 1,
      );
      final count = page.totalCount;

      debugPrint('📊 PublicInventoryService: Product count = $count');
      return count;
    } catch (e) {
      debugPrint('❌ PublicInventoryService: Error counting products: $e');
      return 0;
    }
  }

  /// Clear cache for specific tenant
  ///
  /// Call this when products/categories are updated
  void clearCache({String? tenantId}) {
    if (tenantId != null) {
      _productsCache.remove('products_$tenantId');
      _categoriesCache.remove('categories_$tenantId');
      _cacheTimestamps.remove('products_$tenantId');
      _cacheTimestamps.remove('categories_$tenantId');
      debugPrint(
          '🗑️ PublicInventoryService: Cleared cache for tenant $tenantId');
    } else {
      _productsCache.clear();
      _categoriesCache.clear();
      _cacheTimestamps.clear();
      debugPrint('🗑️ PublicInventoryService: Cleared all cache');
    }
    notifyListeners();
  }

  /// Refresh products for specific tenant
  ///
  /// Forces a cache refresh
  Future<List<Product>> refreshProductsForTenant({
    required String tenantId,
  }) async {
    clearCache(tenantId: tenantId);
    return getProductsForTenant(tenantId: tenantId);
  }

  /// Refresh categories for specific tenant
  ///
  /// Forces a cache refresh
  Future<List<Category>> refreshCategoriesForTenant({
    required String tenantId,
  }) async {
    clearCache(tenantId: tenantId);
    return getCategoriesForTenant(tenantId: tenantId);
  }

  /// Search products using fuzzy matching (RPC) for live preview
  ///
  /// Uses server-side pg_trgm for typo tolerance
  Future<List<Product>> searchProductsFuzzy({
    required String tenantId,
    required String searchTerm,
    int limit = 10,
    PublicProductVisibilityPolicy? policy,
  }) async {
    if (searchTerm.trim().isEmpty) return [];

    try {
      debugPrint('🔍 PublicInventoryService: Fuzzy search for "$searchTerm"');

      final response = await _supabase.rpc(
        'search_public_products',
        params: _cleanRpcParams({
          'p_search_term': searchTerm,
          'p_tenant_id': tenantId,
          'p_limit': limit,
        }),
      );

      final rows = (response as List)
          .map((json) => Map<String, dynamic>.from(json as Map))
          .toList();
      final classifiedRows = await _attachCheckoutTaxRates(
        tenantId: tenantId,
        rows: rows,
      );
      final setAwareRows = await _attachSetIdentity(
        tenantId: tenantId,
        rows: classifiedRows,
      );
      final brandAwareRows = await _attachCanonicalBrandNames(
        tenantId: tenantId,
        rows: setAwareRows,
      );
      final products = brandAwareRows.map(Product.fromJson).toList();
      final visibleProducts = policy == null
          ? products
          : products.where(policy.allowsProduct).toList();

      debugPrint(
          '✅ PublicInventoryService: Found ${visibleProducts.length} matches for "$searchTerm"');
      return visibleProducts;
    } catch (e) {
      debugPrint('❌ PublicInventoryService: Error in fuzzy search: $e');
      // Fallback to the visibility-filtered storefront query if the public RPC
      // is not deployed yet.
      return getProductsForTenant(
        tenantId: tenantId,
        searchQuery: searchTerm,
        policy: policy,
        limit: limit,
      );
    }
  }
}

/// Builds the tenant-safe linked-brand map shared by public product consumers.
///
/// `product_brands` can contain tenant-owned and global (`tenant_id = null`)
/// rows. The caller may use a public client, so this defensive boundary also
/// rejects active rows from another tenant and rows that were not requested.
Map<String, String> canonicalPublicProductBrandNames({
  required List<Map<String, dynamic>> rows,
  required String tenantId,
  required Iterable<String> requestedBrandIds,
}) {
  final requested = requestedBrandIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  final normalizedTenantId = tenantId.trim();
  final namesById = <String, String>{};
  for (final row in rows) {
    final id = row['id']?.toString().trim() ?? '';
    final name = row['name']?.toString().trim() ?? '';
    final rowTenantId = row['tenant_id']?.toString().trim() ?? '';
    if (!requested.contains(id) ||
        name.isEmpty ||
        row['is_active'] != true ||
        (rowTenantId.isNotEmpty && rowTenantId != normalizedTenantId)) {
      continue;
    }
    namesById[id] = name;
  }
  return Map.unmodifiable(namesById);
}
