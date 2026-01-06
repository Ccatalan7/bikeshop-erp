import 'package:flutter/foundation.dart' hide Category;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/product.dart';
import '../../modules/inventory/models/category_models.dart';

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
  /// - [limit]: Max number of results (default: 100)
  /// - [offset]: Pagination offset (default: 0)
  ///
  /// Returns list of products or empty list on error
  Future<List<Product>> getProductsForTenant({
    required String tenantId,
    String? categoryId,
    String? searchQuery,
    bool onlyInStock = true,
    double? minPrice,
    double? maxPrice,
    int? limit, // null = no limit (fetch all)
    int offset = 0,
  }) async {
    final sw = Stopwatch()..start();
    try {
      // Check cache first (only if no filters/pagination applied)
      final cacheKey = 'products_$tenantId';
      if (categoryId == null &&
          searchQuery == null &&
          onlyInStock &&
          minPrice == null &&
          maxPrice == null &&
          offset == 0 &&
          limit == null &&
          _isCacheValid(cacheKey)) {
        debugPrint(
            '⏱️ [PublicInventory] Products from cache: ${sw.elapsedMilliseconds}ms');
        return _productsCache[cacheKey] ?? [];
      }
      // Build base query
      var query = _supabase.from('products').select().eq('tenant_id', tenantId);

      // Filter by stock if requested (RLS only filters is_active=true)
      if (onlyInStock) {
        query = query.gt('inventory_qty', 0);
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

      debugPrint(
          '⏱️ [PublicInventory] Products total: ${sw.elapsedMilliseconds}ms (${products.length} products)');

      // Cache results if no filters (default view)
      if (categoryId == null &&
          searchQuery == null &&
          onlyInStock &&
          minPrice == null &&
          maxPrice == null &&
          offset == 0 &&
          limit == null) {
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

      final response = await _supabase
          .from('products')
          .select()
          .eq('id', productId)
          .eq('tenant_id', tenantId)
          .maybeSingle();

      if (response == null) {
        debugPrint('⚠️ PublicInventoryService: Product $productId not found');
        return null;
      }

      final product = Product.fromJson(response);
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

      // Try exact match first, then case-insensitive
      var response = await _supabase
          .from('products')
          .select()
          .eq('sku', sku)
          .eq('tenant_id', tenantId)
          .maybeSingle();

      // Try with uppercase if not found (common pattern: s56467 -> S56467)
      response ??= await _supabase
          .from('products')
          .select()
          .eq('sku', sku.toUpperCase())
          .eq('tenant_id', tenantId)
          .maybeSingle();

      if (response == null) {
        debugPrint(
            '⚠️ PublicInventoryService: Product with SKU $sku not found');
        return null;
      }

      final product = Product.fromJson(response);
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

      // Query featured_products table (schema uses `order_index`, not `display_order`)
      final featuredResponse = await _supabase
          .from('featured_products')
          .select('product_id')
          .eq('tenant_id', tenantId)
          .eq('active', true)
          .order('order_index', ascending: true)
          .limit(limit);

      final productIds =
          featuredResponse.map((item) => item['product_id'] as String).toList();

      if (productIds.isEmpty) {
        debugPrint('⚠️ PublicInventoryService: No featured products found');
        return [];
      }

      // Fetch actual product details
      final productsResponse = await _supabase
          .from('products')
          .select()
          .inFilter('id', productIds)
          .eq('tenant_id', tenantId);

      final products = (productsResponse as List)
          .map((json) => Product.fromJson(json))
          .toList();

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
      var query = _supabase.from('products').select().eq('tenant_id', tenantId);

      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.eq('category_id', categoryId);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('name.ilike.%$searchQuery%,'
            'sku.ilike.%$searchQuery%,'
            'description.ilike.%$searchQuery%');
      }

      final response = await query.count();
      final count = response.count;

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
}
