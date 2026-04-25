import 'package:flutter/foundation.dart' hide Category;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/product.dart';
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

  Future<PublicProductPage> getProductPageForTenant({
    required String tenantId,
    List<String>? categoryIds,
    List<String>? productIds,
    String? sku,
    String? searchQuery,
    ProductType? productType,
    bool onlyInStock = true,
    String sortBy = 'name',
    int limit = 20,
    int offset = 0,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final response = await _supabase.rpc(
        'get_public_products',
        params: _cleanRpcParams({
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
      final products = rows.map(Product.fromJson).toList();
      final totalCount = rows.isEmpty
          ? 0
          : (rows.first['total_count'] as num?)?.toInt() ?? products.length;

      debugPrint(
          '⏱️ [PublicInventory] Product page RPC: ${sw.elapsedMilliseconds}ms (${products.length}/$totalCount products)');
      return PublicProductPage(products: products, totalCount: totalCount);
    } catch (e) {
      debugPrint(
          '❌ PublicInventoryService: Error fetching product page: $e (${sw.elapsedMilliseconds}ms)');
      return const PublicProductPage(products: [], totalCount: 0);
    }
  }

  Future<PublicCategoryCountSnapshot> getCategoryCountsForTenant({
    required String tenantId,
    ProductType? productType,
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
      if (onlyInStock && (searchQuery == null || searchQuery.isEmpty)) {
        // Be resilient: some code paths historically updated only one of the
        // legacy/current stock columns.
        // IMPORTANT: services and non-stock-tracked items must NEVER be
        // filtered out by stock constraints.
        // PostgREST supports only one `or=` param, so we include all
        // “in-stock” conditions in a single OR group.
        query = query.or(
          'product_type.eq.service,track_stock.eq.false,inventory_qty.gt.0,stock_quantity.gt.0',
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

      final products =
          (response as List).map((json) => Product.fromJson(json)).toList();

      if (onlyInStock && searchQuery != null && searchQuery.isNotEmpty) {
        return products.where((p) {
          if (p.productType == ProductType.service) return true;
          if (!p.trackStock) return true;
          return p.stockQuantity > 0;
        }).toList();
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
            'id,tenant_id,name,full_path,parent_id,level,image_url,sort_order')
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
  }) async {
    try {
      debugPrint(
          '🔍 PublicInventoryService: Fetching product $productId for tenant $tenantId');

      final page = await getProductPageForTenant(
        tenantId: tenantId,
        productIds: [productId],
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
  }) async {
    try {
      debugPrint(
          '🔍 PublicInventoryService: Fetching product by SKU $sku for tenant $tenantId');

      final page = await getProductPageForTenant(
        tenantId: tenantId,
        sku: sku,
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
  }) async {
    try {
      debugPrint(
          '🔍 PublicInventoryService: Fetching featured products for tenant: $tenantId');

      final response = await _supabase.rpc(
        'get_public_featured_products',
        params: {
          'p_tenant_id': tenantId,
          'p_limit': limit,
        },
      );

      final products =
          (response as List).map((json) => Product.fromJson(json)).toList();

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
  }) async {
    try {
      final page = await getProductPageForTenant(
        tenantId: tenantId,
        categoryIds:
            categoryId == null || categoryId.isEmpty ? null : [categoryId],
        searchQuery: searchQuery,
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
  }) async {
    if (searchTerm.trim().isEmpty) return [];

    try {
      debugPrint('🔍 PublicInventoryService: Fuzzy search for "$searchTerm"');

      final response = await _supabase.rpc(
        'search_public_products',
        params: {
          'p_search_term': searchTerm,
          'p_tenant_id': tenantId,
          'p_limit': limit,
        },
      );

      final products =
          (response as List).map((json) => Product.fromJson(json)).toList();
      final visibleProducts = products.where(_isPubliclyVisible).toList();

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
        limit: limit,
      );
    }
  }

  bool _isPubliclyVisible(Product product) {
    return product.isActive && product.isPublished;
  }
}
