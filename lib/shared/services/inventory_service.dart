import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import '../models/supplier_product_identity.dart';
import 'database_service.dart';
import 'tenant_service.dart';

class InventoryService extends ChangeNotifier {
  final DatabaseService? _db;
  final TenantService _tenantService = TenantService();
  final List<Product> _products = [];
  final Set<int> _loadedPreviewPages = <int>{};
  final Map<String, _CachedSetAvailability> _setAvailabilityCache = {};

  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isLoadingPreviewPage = false;
  bool _hasMorePreviewPages = true;
  Future<void>? _loadProductsFuture;

  RealtimeChannel? _stockMovementsChannel;

  InventoryService({DatabaseService? db}) : _db = db {
    // Don't await - fire and forget to avoid blocking constructor
    _setupStockMovementsRealtime();
  }

  @override
  void notifyListeners() {
    debugPrint(
        '🔔 [InventoryService] notifyListeners() — ${_products.length} products, isLoading=$_isLoading');
    super.notifyListeners();
  }

  List<Product> get products => List.unmodifiable(_products);
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  bool get isLoadingPreviewPage => _isLoadingPreviewPage;
  bool get hasMorePreviewPages => _hasMorePreviewPages;
  int get loadedPreviewPageCount => _loadedPreviewPages.length;

  void _resetPreviewPaginationState() {
    _loadedPreviewPages.clear();
    _hasMorePreviewPages = true;
    _isLoadingPreviewPage = false;
  }

  Future<List<Product>> loadProductPreviewPage({
    required int page,
    int pageSize = 80,
    bool reset = false,
  }) async {
    if (page < 0) return const [];

    if (_hasLoaded) {
      final from = page * pageSize;
      final slice = _products.skip(from).take(pageSize).toList(growable: false);
      _hasMorePreviewPages = _products.length > (from + slice.length);
      return slice;
    }

    if (_db == null) {
      await getProducts();
      final from = page * pageSize;
      final slice = _products.skip(from).take(pageSize).toList(growable: false);
      _hasMorePreviewPages = _products.length > (from + slice.length);
      return slice;
    }

    if (reset) {
      _products.clear();
      _resetPreviewPaginationState();
      notifyListeners();
    }

    if (_loadedPreviewPages.contains(page)) {
      final from = page * pageSize;
      return _products.skip(from).take(pageSize).toList(growable: false);
    }

    if (_isLoadingPreviewPage) {
      while (_isLoadingPreviewPage) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_loadedPreviewPages.contains(page)) {
        final from = page * pageSize;
        return _products.skip(from).take(pageSize).toList(growable: false);
      }
    }

    _isLoadingPreviewPage = true;
    try {
      final from = page * pageSize;
      final rawBatch = await _db.selectWithPagination(
        'products',
        from: from,
        to: from + pageSize - 1,
        selectColumns: Product.listPreviewSelect,
        orderBy: 'name',
      );

      final mappedBatch = await _hydrateSetAvailabilityBatch(
        rawBatch.map(_productFromMap).toList(growable: false),
      );
      for (final product in mappedBatch) {
        _upsertLocalProduct(product);
      }

      _loadedPreviewPages.add(page);
      _hasMorePreviewPages = rawBatch.length == pageSize;
      notifyListeners();
      return mappedBatch;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            'InventoryService: Error loading product preview page -> $e');
      }
      rethrow;
    } finally {
      _isLoadingPreviewPage = false;
    }
  }

  Future<List<Product>> getProducts({bool forceRefresh = false}) async {
    if (!_hasLoaded || forceRefresh) {
      await _loadProducts(force: forceRefresh);
    }
    return _hydrateSetAvailabilityBatch(
      _products,
      forceRefresh: forceRefresh,
    );
  }

  /// Get products of a specific type from server with a limit
  Future<List<Product>> getProductsByType(ProductType type,
      {int limit = 100}) async {
    try {
      if (_db == null) {
        return _hydrateSetAvailabilityBatch(
          _products.where((p) => p.productType == type),
        );
      }

      final data = await _db.select('products',
          where: "product_type=${type.name.toLowerCase()}", limit: limit);

      final results = await _hydrateSetAvailabilityBatch(
        data.map(_productFromMap).toList(growable: false),
      );
      // Update local cache with these items
      for (var p in results) {
        _upsertLocalProduct(p);
      }
      return results;
    } catch (e) {
      debugPrint('⚠️ [InventoryService] Failed to fetch products by type: $e');
      return _hydrateSetAvailabilityBatch(
        _products.where((p) => p.productType == type),
      );
    }
  }

  Future<void> refresh() => _loadProducts(force: true);

  Future<Product?> getProductById(String id,
      {bool forceRefresh = false}) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return null;

    try {
      if (!forceRefresh) {
        final product =
            _products.firstWhere((product) => product.id == normalizedId);
        return _hydrateSetAvailability(product);
      }
    } catch (_) {}

    if (_db != null) {
      try {
        final data = await _db.selectById(
          'products',
          normalizedId,
          selectColumns: Product.listPreviewSelect,
        );
        if (data == null) return null;
        final product = await _hydrateSetAvailability(
          _productFromMap(data),
          forceRefresh: forceRefresh,
        );
        _upsertLocalProduct(product);
        notifyListeners();
        return product;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              'InventoryService: Error fetching product by id $normalizedId -> $e');
        }
      }
    }

    if (!_hasLoaded || forceRefresh) {
      await _loadProducts(force: forceRefresh);
    }

    try {
      final product =
          _products.firstWhere((product) => product.id == normalizedId);
      return _hydrateSetAvailability(
        product,
        forceRefresh: forceRefresh,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Product?> getProductBySku(String sku) async {
    final normalizedSku = sku.trim();
    if (normalizedSku.isEmpty) return null;

    try {
      final product = _products.firstWhere((product) =>
          product.sku.toLowerCase() == normalizedSku.toLowerCase());
      return _hydrateSetAvailability(product);
    } catch (_) {
      if (_db != null) {
        try {
          final records = await _db.select(
            'products',
            selectColumns: Product.listPreviewSelect,
            where: 'sku=$normalizedSku',
            limit: 1,
          );
          if (records.isEmpty) return null;
          final product =
              await _hydrateSetAvailability(_productFromMap(records.first));
          _upsertLocalProduct(product);
          notifyListeners();
          return product;
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                'InventoryService: Error fetching product by SKU $normalizedSku -> $e');
          }
        }
      }

      if (_db == null && !_hasLoaded) {
        await getProducts();
        try {
          final product = _products.firstWhere((product) =>
              product.sku.toLowerCase() == normalizedSku.toLowerCase());
          return _hydrateSetAvailability(product);
        } catch (_) {
          return null;
        }
      }

      return null;
    }
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    final normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) return null;

    try {
      final product = _products.firstWhere((product) =>
          product.barcode?.toLowerCase() == normalizedBarcode.toLowerCase());
      return _hydrateSetAvailability(product);
    } catch (_) {
      try {
        if (_db != null) {
          final records = await _db.select(
            'products',
            selectColumns: Product.listPreviewSelect,
            where: 'barcode=$normalizedBarcode',
            limit: 1,
          );
          if (records.isEmpty) return null;
          final product =
              await _hydrateSetAvailability(_productFromMap(records.first));
          _upsertLocalProduct(product);
          notifyListeners();
          return product;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              'InventoryService: Error fetching product by barcode $normalizedBarcode -> $e');
        }
      }

      if (_db == null && !_hasLoaded) {
        await getProducts();
        try {
          final product = _products
              .firstWhere((product) => product.barcode == normalizedBarcode);
          return _hydrateSetAvailability(product);
        } catch (_) {
          return null;
        }
      }

      return null;
    }
  }

  Future<Product?> getProductBySupplierCode(String supplierCode) async {
    final cleanCode = supplierCode.trim();
    if (cleanCode.isEmpty) return null;

    debugPrint('🔎 Finding Product by supplierCode: "$cleanCode"');
    debugPrint('📦 Cache size: ${_products.length}');

    final lowerCode = cleanCode.toLowerCase();

    try {
      final match = _products.firstWhere(
        (product) => product.supplierCode?.trim().toLowerCase() == lowerCode,
      );
      debugPrint('✅ Memory Match: ${match.name} (ID: ${match.id})');
      return _hydrateSetAvailability(match);
    } catch (_) {
      debugPrint('⚠️ Not in memory. DB Fallback for cleanCode="$cleanCode"...');
      if (_db == null) {
        if (!_hasLoaded) {
          await getProducts();
          try {
            final product = _products.firstWhere((product) =>
                product.supplierCode?.trim().toLowerCase() == lowerCode);
            return _hydrateSetAvailability(product);
          } catch (_) {
            return null;
          }
        }
        return null;
      }
      try {
        debugPrint('🔌 Executing DB Select: supplier_code=$cleanCode');
        final records = await _db.select(
          'products',
          selectColumns: Product.listPreviewSelect,
          where: "supplier_code=$cleanCode",
          limit: 1,
        );
        debugPrint('🔌 DB returned ${records.length} records');

        if (records.isEmpty) {
          debugPrint('❌ DB Check: zero results.');
          return null;
        }

        debugPrint('🔨 Mapping record 0...');
        final product =
            await _hydrateSetAvailability(_productFromMap(records.first));
        debugPrint('✅ Mapped: ${product.name}');

        _upsertLocalProduct(product);
        notifyListeners();
        return product;
      } catch (e, stack) {
        debugPrint('❌ DB/Mapping Exception: $e');
        debugPrint(stack.toString());
        return null;
      }
    }
  }

  /// Resolves an exact supplier code without allowing the same code from a
  /// different supplier (or tenant) to match.
  ///
  /// This is the supplier-aware API for OCR/purchase workflows. The legacy
  /// [getProductBySupplierCode] remains only for callers that have not yet
  /// collected an explicit supplier identity.
  Future<Product?> getProductBySupplierCodeForSupplier({
    required String supplierId,
    required String supplierCode,
  }) async {
    final cleanSupplierId = supplierId.trim();
    final cleanCode = supplierCode.trim();
    if (cleanSupplierId.isEmpty || cleanCode.isEmpty) return null;

    if (_db == null) {
      final matches = _products
          .where(
            (product) =>
                product.supplierId == cleanSupplierId &&
                product.supplierCode?.trim().toLowerCase() ==
                    cleanCode.toLowerCase(),
          )
          .take(2)
          .toList(growable: false);
      if (matches.length > 1) {
        throw StateError(
          'Supplier code is ambiguous for the selected supplier.',
        );
      }
      return matches.isEmpty ? null : matches.single;
    }

    final response = await _db.rpc(
      'resolve_product_by_supplier_code',
      params: {
        'p_supplier_id': cleanSupplierId,
        'p_supplier_code': cleanCode,
      },
    );
    final payload = _rpcJsonMap(response);
    if (payload == null) return null;

    final productId = payload['product_id']?.toString().trim() ?? '';
    if (productId.isEmpty) {
      throw const FormatException(
        'Supplier-code lookup response has no product ID.',
      );
    }
    return getProductById(productId, forceRefresh: true);
  }

  /// Resolves a previously confirmed supplier listing variant to its ERP
  /// product. A listing ID without an explicit variant identity never matches.
  Future<Product?> resolveSupplierProductAlias({
    required String supplierId,
    required String variantKey,
    String? productUrl,
    String? itemId,
  }) async {
    final cleanSupplierId = supplierId.trim();
    final cleanVariantKey = variantKey.trim();
    if (cleanSupplierId.isEmpty) {
      throw ArgumentError.value(supplierId, 'supplierId', 'Cannot be empty.');
    }
    if (cleanVariantKey.isEmpty) {
      throw ArgumentError.value(variantKey, 'variantKey', 'Cannot be empty.');
    }
    if (cleanVariantKey.length > 512) {
      throw ArgumentError.value(
        variantKey,
        'variantKey',
        'Cannot exceed 512 characters.',
      );
    }
    _requireListingIdentity(productUrl: productUrl, itemId: itemId);

    final db = _requireDatabase();
    final response = await db.rpc(
      'resolve_supplier_product_alias',
      params: {
        'p_supplier_id': cleanSupplierId,
        'p_product_url': _nullIfBlank(productUrl),
        'p_item_id': _nullIfBlank(itemId),
        'p_variant_key': cleanVariantKey,
      },
    );
    final payload = _rpcJsonMap(response);
    if (payload == null) return null;

    final productId = payload['product_id']?.toString().trim() ?? '';
    if (productId.isEmpty) {
      throw const FormatException('Alias response has no product ID.');
    }
    return getProductById(productId, forceRefresh: true);
  }

  /// Persists an explicit supplier-listing-variant -> product decision.
  ///
  /// The database derives tenant ownership from the authenticated session,
  /// canonicalizes the listing ID, and deliberately preserves the product's
  /// existing primary supplier fields.
  Future<SupplierProductAliasRecord> rememberSupplierProductAlias({
    required String supplierId,
    required String productId,
    required String variantKey,
    String? productUrl,
    String? itemId,
    String? originalTitle,
    String? model,
    String? imageUrl,
    String? imageContentHash,
  }) async {
    final cleanSupplierId = supplierId.trim();
    final cleanProductId = productId.trim();
    final cleanVariantKey = variantKey.trim();
    if (cleanSupplierId.isEmpty) {
      throw ArgumentError.value(supplierId, 'supplierId', 'Cannot be empty.');
    }
    if (cleanProductId.isEmpty) {
      throw ArgumentError.value(productId, 'productId', 'Cannot be empty.');
    }
    if (cleanVariantKey.isEmpty) {
      throw ArgumentError.value(variantKey, 'variantKey', 'Cannot be empty.');
    }
    if (cleanVariantKey.length > 512) {
      throw ArgumentError.value(
        variantKey,
        'variantKey',
        'Cannot exceed 512 characters.',
      );
    }
    _requireListingIdentity(productUrl: productUrl, itemId: itemId);

    final db = _requireDatabase();
    final response = await db.rpc(
      'remember_supplier_product_alias',
      params: {
        'p_supplier_id': cleanSupplierId,
        'p_product_id': cleanProductId,
        'p_product_url': _nullIfBlank(productUrl),
        'p_item_id': _nullIfBlank(itemId),
        'p_variant_key': cleanVariantKey,
        'p_original_title': _nullIfBlank(originalTitle),
        'p_model': _nullIfBlank(model),
        'p_image_url': _nullIfBlank(imageUrl),
        'p_image_content_hash': _nullIfBlank(imageContentHash),
      },
    );
    final payload = _rpcJsonMap(response);
    if (payload == null) {
      throw const FormatException('Alias write returned no receipt.');
    }
    return SupplierProductAliasRecord.fromJson(payload);
  }

  /// Atomically reserves one or more globally unique `AE####` values.
  ///
  /// Reusing [operationKey] with the same supplier/count replays the committed
  /// receipt; reusing it for another request fails instead of allocating twice.
  Future<AliExpressSkuReservation> reserveAliExpressSkus({
    required int count,
    required String operationKey,
    required String supplierId,
    required String supplierName,
  }) async {
    final cleanOperationKey = operationKey.trim();
    final cleanSupplierId = supplierId.trim();
    final cleanSupplierName = supplierName.trim();
    if (count < 1 || count > 100) {
      throw RangeError.range(count, 1, 100, 'count');
    }
    if (cleanOperationKey.isEmpty) {
      throw ArgumentError.value(
        operationKey,
        'operationKey',
        'Cannot be empty.',
      );
    }
    if (cleanSupplierId.isEmpty) {
      throw ArgumentError.value(supplierId, 'supplierId', 'Cannot be empty.');
    }
    if (cleanSupplierName.isEmpty) {
      throw ArgumentError.value(
        supplierName,
        'supplierName',
        'Cannot be empty.',
      );
    }

    final db = _requireDatabase();
    final response = await db.rpc(
      'reserve_aliexpress_skus',
      params: {
        'p_count': count,
        'p_operation_key': cleanOperationKey,
        'p_supplier_id': cleanSupplierId,
        'p_supplier_name': cleanSupplierName,
      },
    );
    final payload = _rpcJsonMap(response);
    if (payload == null) {
      throw const FormatException('SKU reservation returned no receipt.');
    }
    return AliExpressSkuReservation.fromJson(payload);
  }

  DatabaseService _requireDatabase() {
    final db = _db;
    if (db == null) {
      throw StateError(
        'This inventory operation requires a database-backed service.',
      );
    }
    return db;
  }

  static void _requireListingIdentity({
    String? productUrl,
    String? itemId,
  }) {
    if (_nullIfBlank(productUrl) == null && _nullIfBlank(itemId) == null) {
      throw ArgumentError('A productUrl or itemId is required.');
    }
  }

  static String? _nullIfBlank(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static Map<String, dynamic>? _rpcJsonMap(dynamic response) {
    if (response == null) return null;
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    if (response is List && response.length == 1 && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    throw const FormatException('Unexpected database RPC response shape.');
  }

  Future<List<Product>> getProductsByIds(
    Iterable<String> productIds, {
    bool forceRefresh = false,
  }) async {
    final requestedIds = productIds
        .map((productId) => productId.trim())
        .where((productId) => productId.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (requestedIds.isEmpty) {
      return const [];
    }

    final missingIds = <String>[];

    for (final productId in requestedIds) {
      final localIndex =
          forceRefresh ? -1 : _products.indexWhere((p) => p.id == productId);
      if (localIndex != -1) {
        continue;
      } else {
        missingIds.add(productId);
      }
    }

    if (missingIds.isNotEmpty) {
      if (_db != null) {
        try {
          final rows = await _db.select(
            'products',
            selectColumns: Product.listPreviewSelect,
            where: 'id',
            whereIn: missingIds,
          );
          for (final row in rows) {
            final product = _productFromMap(row);
            _upsertLocalProduct(product);
          }

          if (rows.isNotEmpty) {
            notifyListeners();
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                'InventoryService: Error fetching products by ids $missingIds -> $e');
          }
        }
      } else if (!_hasLoaded) {
        await getProducts();
      }
    }

    final results = requestedIds
        .map(
          (productId) => _products.cast<Product?>().firstWhere(
                (product) => product?.id == productId,
                orElse: () => null,
              ),
        )
        .whereType<Product>()
        .toList(growable: false);
    return _hydrateSetAvailabilityBatch(
      results,
      forceRefresh: forceRefresh,
    );
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('ü', 'u');
  }

  Future<List<Product>> searchProducts(
    String query, {
    int limit = 200,
    ProductType? productType,
  }) async {
    if (query.trim().isEmpty) {
      if (_hasLoaded && _products.isNotEmpty) {
        final results = _products
            .where((product) =>
                productType == null || product.productType == productType)
            .take(limit)
            .toList();
        return _hydrateSetAvailabilityBatch(results);
      }

      if (_db != null) {
        try {
          final data = await _db.select(
            'products',
            selectColumns: Product.listPreviewSelect,
            where:
                productType == null ? null : 'product_type=${productType.name}',
            orderBy: 'updated_at',
            descending: true,
            limit: limit,
          );

          final results = await _hydrateSetAvailabilityBatch(
            data.map(_productFromMap).toList(growable: false),
          );
          for (final product in results) {
            _upsertLocalProduct(product);
          }
          return results;
        } catch (e) {
          debugPrint(
              '⚠️ [InventoryService] Empty-query preview fetch failed, falling back to full cache load: $e');
        }
      }

      final products = await getProducts();
      return products
          .where((product) =>
              productType == null || product.productType == productType)
          .take(limit)
          .toList();
    }

    final normalizedQuery = _normalize(query);
    final searchTerms = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    if (searchTerms.isEmpty) {
      return await searchProducts(
        '',
        limit: limit,
        productType: productType,
      );
    }

    // If products are already in local memory, use accent-insensitive filter
    // (avoids DB ILIKE which is accent-sensitive in PostgreSQL by default)
    if (_hasLoaded && _products.isNotEmpty) {
      final results = _products
          .where((product) {
            if (productType != null && product.productType != productType) {
              return false;
            }
            final searchableText = _normalize([
              product.name,
              product.sku,
              product.brand ?? '',
              product.model ?? '',
              product.barcode ?? '',
              product.categoryName ?? '',
              product.supplierCode ?? '',
            ].join(' '));
            return searchTerms.every((term) => searchableText.contains(term));
          })
          .take(limit)
          .toList();
      return _hydrateSetAvailabilityBatch(results);
    }

    // 1. Try DB search first if available for efficiency on large datasets
    if (_db != null) {
      try {
        final rawResults = await _db.searchRecordsMultiToken(
          'products',
          [
            'name',
            'sku',
            'brand',
            'model',
            'supplier_code',
            'barcode',
            'category_name'
          ],
          searchTerms,
          limit: limit,
          selectColumns: Product.listPreviewSelect,
          where:
              productType == null ? null : 'product_type=${productType.name}',
        );

        final List<Product> mappedResults = [];
        for (var map in rawResults) {
          final product = _productFromMap(map);
          mappedResults.add(product);
        }

        final results = await _hydrateSetAvailabilityBatch(mappedResults);
        for (final product in results) {
          _upsertLocalProduct(product);
        }

        if (results.isNotEmpty) return results;
      } catch (e) {
        debugPrint(
            '⚠️ [InventoryService] DB search failed, falling back to cache: $e');
      }
    }

    // 2. Fallback to local cache search
    final products = await getProducts();
    return products
        .where((product) {
          if (productType != null && product.productType != productType) {
            return false;
          }
          final searchableText = _normalize([
            product.name,
            product.sku,
            product.brand ?? '',
            product.model ?? '',
            product.barcode ?? '',
            product.categoryName ?? '',
            product.supplierCode ?? '',
          ].join(' '));

          return searchTerms.every((term) => searchableText.contains(term));
        })
        .take(limit)
        .toList();
  }

  Future<bool> updateStock(
    String productId,
    int newQuantity, {
    String reference = 'Ajuste manual',
    String? adjustmentOrigin,
  }) async {
    if (newQuantity < 0) return false;
    final product = await getProductById(productId);
    if (product == null) return false;
    if (product.isSet) {
      debugPrint(
        'InventoryService: refusing direct stock update for set parent $productId',
      );
      return false;
    }

    final difference = newQuantity - product.stockQuantity;
    if (difference == 0) return true;

    final type = difference > 0 ? 'IN' : 'OUT';
    final quantity = difference.abs();

    if (_db != null) {
      try {
        await _db.adjustStock(
          productId,
          quantity,
          type,
          reference,
          adjustmentOrigin: adjustmentOrigin,
        );
        await getProductById(productId, forceRefresh: true);
        notifyListeners();
        return true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('InventoryService: Error updating stock -> $e');
        }
        return false;
      }
    }

    _upsertLocalProduct(product.copyWith(
      stockQuantity: newQuantity,
      updatedAt: DateTime.now(),
    ));
    notifyListeners();
    return true;
  }

  Future<bool> deductStock(
    String productId,
    int quantity, {
    String reference = 'Venta POS',
    String? adjustmentOrigin,
  }) async {
    if (quantity <= 0) return false;
    final product = await getProductById(productId);
    if (product == null) return false;
    if (product.isSet) {
      debugPrint(
        'InventoryService: refusing direct stock deduction for set parent $productId',
      );
      return false;
    }

    if (product.trackStock && product.stockQuantity < quantity) {
      if (kDebugMode) {
        debugPrint(
          'InventoryService: Insufficient stock for $productId (requested $quantity, available ${product.stockQuantity})',
        );
      }
      return false;
    }

    if (_db != null) {
      try {
        await _db.adjustStock(
          productId,
          quantity,
          'OUT',
          reference,
          adjustmentOrigin: adjustmentOrigin,
        );
        await getProductById(productId, forceRefresh: true);
        notifyListeners();
        return true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('InventoryService: Error deducting stock -> $e');
        }
        return false;
      }
    }

    _upsertLocalProduct(product.copyWith(
      stockQuantity: product.stockQuantity - quantity,
      updatedAt: DateTime.now(),
    ));
    notifyListeners();
    return true;
  }

  Future<bool> addStock(
    String productId,
    int quantity, {
    String reference = 'Ingreso inventario',
    String? adjustmentOrigin,
  }) async {
    if (quantity <= 0) return false;
    final product = await getProductById(productId);
    if (product == null) return false;
    if (product.isSet) {
      debugPrint(
        'InventoryService: refusing direct stock addition for set parent $productId',
      );
      return false;
    }

    if (_db != null) {
      try {
        await _db.adjustStock(
          productId,
          quantity,
          'IN',
          reference,
          adjustmentOrigin: adjustmentOrigin,
        );
        await getProductById(productId, forceRefresh: true);
        notifyListeners();
        return true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('InventoryService: Error adding stock -> $e');
        }
        return false;
      }
    }

    _upsertLocalProduct(product.copyWith(
      stockQuantity: product.stockQuantity + quantity,
      updatedAt: DateTime.now(),
    ));
    notifyListeners();
    return true;
  }

  Future<void> removeProductFromCache(String productId) async {
    _products.removeWhere((product) => product.id == productId);
    _setAvailabilityCache.remove(productId);
    notifyListeners();
  }

  Future<List<Product>> _hydrateSetAvailabilityBatch(
    Iterable<Product> products, {
    bool forceRefresh = false,
  }) async {
    final hydrated = await Future.wait(
      products.map(
        (product) => _hydrateSetAvailability(
          product,
          forceRefresh: forceRefresh,
        ),
      ),
    );
    return hydrated;
  }

  Future<Product> _hydrateSetAvailability(
    Product product, {
    bool forceRefresh = false,
  }) async {
    final db = _db;
    if (!product.isSet || product.id.isEmpty || db == null) return product;

    final now = DateTime.now();
    final cached = _setAvailabilityCache[product.id];
    if (!forceRefresh &&
        cached != null &&
        now.difference(cached.fetchedAt) < const Duration(seconds: 15)) {
      return product.copyWith(
        fullSetsAvailable: cached.availableQuantity,
        isPartial: cached.isPartial,
      );
    }

    try {
      final response = await db.rpc(
        'preview_product_stock_impact',
        params: {
          'p_product_id': product.id,
          'p_quantity': 1,
        },
      );
      final payload = _rpcJsonMap(response);
      if (payload == null || payload['is_set'] != true) return product;

      final available = (payload['available_quantity'] as num?)?.toInt() ?? 0;
      final components = payload['components'] as List? ?? const [];
      final isPartial = components.any((rawComponent) {
        if (rawComponent is! Map) return false;
        final component = Map<String, dynamic>.from(rawComponent);
        final stock = (component['stock_quantity'] as num?)?.toInt() ?? 0;
        final quantityInSet =
            ((component['quantity_in_set'] as num?)?.toInt() ?? 1)
                .clamp(1, 1 << 31)
                .toInt();
        return stock < 0 || stock != available * quantityInSet;
      });
      final availability = _CachedSetAvailability(
        availableQuantity: available,
        isPartial: isPartial,
        fetchedAt: now,
      );
      _setAvailabilityCache[product.id] = availability;
      return product.copyWith(
        fullSetsAvailable: availability.availableQuantity,
        isPartial: availability.isPartial,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'InventoryService: could not derive availability for set ${product.id} -> $error',
        );
      }
      return product;
    }
  }

  void _refreshSetAvailabilityInBackground(String? setProductId) {
    final normalizedId = setProductId?.trim() ?? '';
    if (normalizedId.isEmpty) return;
    final index = _products.indexWhere(
      (product) => product.id == normalizedId && product.isSet,
    );
    if (index == -1) return;
    final parent = _products[index];
    _hydrateSetAvailability(parent, forceRefresh: true).then((hydrated) {
      _upsertLocalProduct(hydrated);
      notifyListeners();
    });
  }

  Future<void> _loadProducts({bool force = false}) async {
    if (_db == null) {
      if (_products.isEmpty) {
        _products
          ..clear()
          ..addAll(_getMockProducts());
        _hasLoaded = true;
        notifyListeners();
      }
      return;
    }

    final activeLoad = _loadProductsFuture;
    if (activeLoad != null) {
      await activeLoad;
      return;
    }

    final loadFuture = _loadProductsProgressively(force: force);
    _loadProductsFuture = loadFuture;

    try {
      await loadFuture;
    } finally {
      if (identical(_loadProductsFuture, loadFuture)) {
        _loadProductsFuture = null;
      }
    }
  }

  Future<void> _loadProductsProgressively({bool force = false}) async {
    _isLoading = true;
    _resetPreviewPaginationState();
    if (!_hasLoaded && _products.isEmpty) {
      notifyListeners();
    }

    try {
      const batchSize = 80;
      const batchesPerNotify = 4;
      var offset = 0;
      var pendingBatches = 0;
      var notifiedDuringLoad = false;

      while (true) {
        final rawBatch = await _db!.selectWithPagination(
          'products',
          from: offset,
          to: offset + batchSize - 1,
          orderBy: 'name',
        );

        if (rawBatch.isEmpty) {
          break;
        }

        final mappedBatch = await _hydrateSetAvailabilityBatch(
          rawBatch.map(_productFromMap).toList(growable: false),
          forceRefresh: force,
        );

        if (offset == 0) {
          _products
            ..clear()
            ..addAll(mappedBatch);
          notifyListeners();
          notifiedDuringLoad = true;
          pendingBatches = 0;
        } else {
          _products.addAll(mappedBatch);
          pendingBatches += 1;

          if (pendingBatches >= batchesPerNotify) {
            notifyListeners();
            notifiedDuringLoad = true;
            pendingBatches = 0;
          }
        }

        if (rawBatch.length < batchSize) {
          break;
        }

        offset += batchSize;
      }

      if (force && _products.isEmpty) {
        _products.clear();
      }

      _hasLoaded = true;
      _hasMorePreviewPages = false;

      if (!notifiedDuringLoad || pendingBatches > 0) {
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InventoryService: Error loading products -> $e');
      }
      if (_products.isEmpty) {
        _products
          ..clear()
          ..addAll(_getMockProducts());
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _upsertLocalProduct(Product product) {
    final index = _products.indexWhere((existing) => existing.id == product.id);
    if (index == -1) {
      _products.add(product);
      _products
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      _products[index] = product;
    }
  }

  Product _productFromMap(Map<String, dynamic> json) {
    final price = (json['price'] as num?)?.toDouble() ?? 0.0;
    final cost = (json['cost'] as num?)?.toDouble() ?? 0.0;
    final stockQuantity =
        json['stock_quantity'] as int? ?? json['inventory_qty'] as int? ?? 0;
    final minStock =
        json['min_stock_level'] as int? ?? json['min_stock'] as int? ?? 0;
    final maxStock =
        json['max_stock_level'] as int? ?? json['max_stock'] as int? ?? 0;
    final categoryValue = json['category'] as String? ?? 'other';

    final productTypeValue = (json['product_type'] as String?)?.toLowerCase();

    return Product(
      id: json['id']?.toString() ?? '',
      name: (json['name'] as String?) ?? 'Sin nombre',
      sku: (json['sku'] as String?) ?? '',
      barcode: json['barcode'] as String?,
      price: price,
      cost: cost,
      stockQuantity: stockQuantity,
      minStockLevel: minStock,
      maxStockLevel: maxStock > 0 ? maxStock : 100,
      imageUrl: json['image_url'] as String?,
      imageUrlOptimized: json['image_url_optimized'] as String?,
      imageUrls: (json['image_urls'] as List?)?.cast<String>() ?? const [],
      description: json['description'] as String?,
      category: ProductCategory.values.firstWhere(
        (c) => c.name == categoryValue,
        orElse: () => ProductCategory.other,
      ),
      categoryId: json['category_id']?.toString(),
      categoryName: json['category_name'] as String?,
      brandId: json['brand_id']?.toString(),
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      specifications: (json['specifications'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
          ) ??
          const {},
      supplierId: json['supplier_id']?.toString(),
      supplierName: json['supplier_name'] as String?,
      supplierReference: json['supplier_reference'] as String?,
      supplierCode: json['supplier_code']?.toString(),
      manufacturer: json['manufacturer'] as String?,
      manufacturerSku: json['manufacturer_sku'] as String?,
      gtin: json['gtin'] as String?,
      hsCode: json['hs_code'] as String?,
      countryOfOrigin: json['country_of_origin'] as String?,
      color: json['color'] as String?,
      size: json['size'] as String?,
      material: json['material'] as String?,
      dimensions:
          null, // Could add ProductDimensions.fromJsonNullable(json['dimensions']) if needed
      warrantyMonths: json['warranty_months'] as int? ?? 0,
      lifecycleStatus: json['lifecycle_status'] as String? ?? 'active',
      serialized: json['serialized'] as bool? ?? false,
      lotTracking: json['lot_tracking'] as bool? ?? false,
      expirationTracking: json['expiration_tracking'] as bool? ?? false,
      expiryDays: json['expiry_days'] as int?,
      leadTimeDays: json['lead_time_days'] as int? ?? 0,
      reorderQuantity: json['reorder_quantity'] as int? ?? 0,
      warehouseLocation: json['warehouse_location'] as String?,
      priceCurrency: (json['price_currency'] as String? ?? 'CLP').toUpperCase(),
      costCurrency: (json['cost_currency'] as String? ?? 'CLP').toUpperCase(),
      taxRate: (json['tax_rate'] as num?)?.toDouble(),
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      unit: ProductUnit.values.firstWhere(
        (u) => u.name == json['unit'],
        orElse: () => ProductUnit.unit,
      ),
      weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
      trackStock: json['track_stock'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      isPublished: json['is_published'] as bool? ??
          json['show_on_website'] as bool? ??
          true,
      purchaseTreatment: parsePurchaseTreatment(
        json['purchase_treatment'],
        productType: productTypeValue,
        trackStock: json['track_stock'] as bool?,
      ),
      productType: ProductType.values.firstWhere(
        (t) => t.name == productTypeValue,
        orElse: () => ProductType.product,
      ),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      isSet: json['is_set'] as bool? ?? false,
      setType: _parseSharedSetType(json['set_type']),
      parentSetId: json['parent_set_id']?.toString(),
      componentLabel: json['component_label']?.toString(),
      componentPosition: (json['component_position'] as num?)?.toInt(),
      fullSetsAvailable: (json['full_sets_available'] as num?)?.toInt(),
      isPartial: json['is_partial'] as bool?,
    );
  }

  List<Product> _getMockProducts() {
    final now = DateTime.now();
    return [
      Product(
        id: 'prd-demo-1',
        name: 'Bicicleta MTB Trek Marlin 7 29"',
        sku: 'MTB-TREK-M7',
        price: 549000,
        cost: 385000,
        stockQuantity: 4,
        minStockLevel: 1,
        maxStockLevel: 10,
        category: ProductCategory.bicycles,
        brand: 'Trek',
        model: 'Marlin 7',
        imageUrl: null,
        description: 'Cuadro aluminio, frenos hidráulicos, transmisión 1x10.',
        createdAt: now.subtract(const Duration(days: 12)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
      Product(
        id: 'prd-demo-2',
        name: 'Casco Giro Fixture MIPS',
        sku: 'ACC-GIRO-CAS',
        price: 74990,
        cost: 42000,
        stockQuantity: 18,
        minStockLevel: 5,
        maxStockLevel: 30,
        category: ProductCategory.accessories,
        brand: 'Giro',
        model: 'Fixture MIPS',
        imageUrl: null,
        description: 'Seguridad MIPS, talla ajustable, ventilación optimizada.',
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(hours: 12)),
      ),
      Product(
        id: 'prd-demo-3',
        name: 'Luz Trasera Bontrager Flare RT',
        sku: 'ELE-BON-FLARE',
        price: 59990,
        cost: 31000,
        stockQuantity: 25,
        minStockLevel: 8,
        maxStockLevel: 40,
        category: ProductCategory.electronics,
        brand: 'Bontrager',
        model: 'Flare RT',
        imageUrl: null,
        description: 'USB recargable, 90 lúmenes, visible hasta 2 km.',
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now,
      ),
    ];
  }
}

SetType? _parseSharedSetType(dynamic value) {
  return switch (value?.toString()) {
    null || '' => null,
    'pair' => SetType.pair,
    'frontRear' || 'front_rear' => SetType.frontRear,
    'leftRight' || 'left_right' => SetType.leftRight,
    _ => SetType.custom,
  };
}

class _CachedSetAvailability {
  const _CachedSetAvailability({
    required this.availableQuantity,
    required this.isPartial,
    required this.fetchedAt,
  });

  final int availableQuantity;
  final bool isPartial;
  final DateTime fetchedAt;
}

DateTime _parseDate(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  try {
    final dynamic dynamicValue = value;
    final result = dynamicValue.toDate();
    if (result is DateTime) {
      return result;
    }
  } catch (_) {
    // Ignore conversion errors and fallback below.
  }
  return DateTime.now();
}

// Extension for _setupStockMovementsRealtime
extension _InventoryServiceRealtime on InventoryService {
  Future<void> _setupStockMovementsRealtime() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        debugPrint('⚠️ [InventoryService] Cannot setup realtime: no tenant_id');
        return;
      }

      await _stockMovementsChannel?.unsubscribe();

      _stockMovementsChannel = Supabase.instance.client
          .channel('inventory_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'products',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              debugPrint(
                  '🔔 [InventoryService] Product changed: ${payload.eventType}');
              // Any component balance change can alter a parent set's derived
              // availability. Force the next read to re-evaluate it.
              _setAvailabilityCache.clear();

              if (payload.newRecord.isNotEmpty) {
                final updatedProduct = _productFromMap(payload.newRecord);
                _upsertLocalProduct(updatedProduct);
                notifyListeners();
                _refreshSetAvailabilityInBackground(
                  updatedProduct.isSet
                      ? updatedProduct.id
                      : updatedProduct.parentSetId,
                );
              } else if (payload.eventType == PostgresChangeEvent.delete) {
                final id = payload.oldRecord['id']?.toString();
                final parentSetId =
                    payload.oldRecord['parent_set_id']?.toString();
                if (id != null) {
                  _products.removeWhere((p) => p.id == id);
                  notifyListeners();
                }
                _refreshSetAvailabilityInBackground(parentSetId);
              }
            },
          )
          .subscribe();

      debugPrint('✅ [InventoryService] Realtime subscription active');
    } catch (e) {
      debugPrint('❌ [InventoryService] Failed to setup realtime: $e');
    }
  }
}
