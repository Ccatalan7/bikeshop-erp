import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../shared/models/stock_adjustment_origin.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/models/product.dart' show PurchaseTreatment;
import '../../ai_assistant/services/ai_service.dart';
import '../models/inventory_models.dart';
import '../models/stock_adjustment.dart';

class InventoryService extends ChangeNotifier {
  static final RegExp _aliExpressSkuPattern =
      RegExp(r'^AE(\d+)$', caseSensitive: false);

  final DatabaseService _db;
  final TenantService _tenantService;

  // ============================================================
  // CACHING - Avoid refetching on every page navigation
  // ============================================================
  List<Product>? _cachedProducts;
  DateTime? _productsCacheTime;
  List<Product>? _cachedListProducts;
  DateTime? _listProductsCacheTime;
  static const Duration _cacheMaxAge = Duration(minutes: 5);
  bool _isLoadingProducts = false;
  bool _isLoadingListProducts = false;

  // Public getters for cached data (instant access)
  List<Product> get cachedProducts => _cachedProducts ?? [];
  bool get hasProductsCache => _cachedProducts != null;
  List<Product> get cachedListProducts => _cachedListProducts ?? [];
  bool get hasListProductsCache => _cachedListProducts != null;

  // ============================================================
  // PRODUCT LIST PAGE STATE - Preserve across navigation
  // ============================================================
  bool _pendingStateRestore = false; // Only true when returning from edit
  DateTime? _lastListStateSavedAt;
  // Grace window: short enough that navigating to another module resets state,
  // but long enough to survive router rebuilds during within-module navigation
  static const Duration _listStateGraceWindow = Duration(seconds: 30);
  String? savedSearchTerm;
  int savedCurrentPage = 1;
  double savedScrollOffset = 0;
  String? savedCategoryId;
  String? savedSupplierId;
  int? savedProductTypeIndex; // Store index for ProductType enum
  int savedStockFilterIndex = 0; // Store index for StockFilter enum
  bool savedFilterWebPublished = false;
  bool savedFilterGoogleMerchant = false;
  bool savedShowInactive = false;
  int savedSortOptionIndex = 2; // Default: nameAsc (index 2)

  /// Returns true if we should restore state (returning from edit)
  bool get shouldRestoreState => _pendingStateRestore;
  bool get hasRecentSavedState {
    if (_pendingStateRestore) return true;
    if (_lastListStateSavedAt == null) return false;
    // Grace window to survive router/workspace rebuilds during navigation
    return DateTime.now().difference(_lastListStateSavedAt!) <
        _listStateGraceWindow;
  }

  // ============================================================
  // EXTERNAL EVENTS (e.g., from AI Assistant)
  // ============================================================
  final _externalSearchController = StreamController<String>.broadcast();
  Stream<String> get externalSearchStream => _externalSearchController.stream;

  /// SKUs matched by the AI assistant's semantic+keyword search.
  /// When set, the product list filters by these SKUs instead of keyword search.
  List<String>? aiMatchedSkus;
  int? aiStockFilterIndex;

  void applyExternalSearch(String term,
      {List<String>? matchedSkus, int? stockFilterIndex}) {
    aiMatchedSkus = matchedSkus;
    aiStockFilterIndex = stockFilterIndex;
    saveListState(searchTerm: term, stockFilterIndex: stockFilterIndex);
    _externalSearchController.add(term);
  }

  @override
  void dispose() {
    _externalSearchController.close();
    super.dispose();
  }

  void saveListState({
    String? searchTerm,
    int? currentPage,
    double? scrollOffset,
    String? categoryId,
    String? supplierId,
    int? productTypeIndex,
    int? stockFilterIndex,
    bool? filterWebPublished,
    bool? filterGoogleMerchant,
    bool? showInactive,
    int? sortOptionIndex,
  }) {
    _pendingStateRestore = true; // Mark that we should restore on next visit
    _lastListStateSavedAt = DateTime.now();
    savedSearchTerm = searchTerm;
    savedCurrentPage = currentPage ?? 1;
    savedScrollOffset = scrollOffset ?? 0;
    savedCategoryId = categoryId;
    savedSupplierId = supplierId;
    savedProductTypeIndex = productTypeIndex;
    savedStockFilterIndex = stockFilterIndex ?? 0;
    savedFilterWebPublished = filterWebPublished ?? false;
    savedFilterGoogleMerchant = filterGoogleMerchant ?? false;
    savedShowInactive = showInactive ?? false;
    savedSortOptionIndex = sortOptionIndex ?? 2;
  }

  /// Call after restoring state to prevent restoring on subsequent visits
  void markStateRestored() {
    _pendingStateRestore = false;
    // Don't update _lastListStateSavedAt - let the grace window expire naturally
    // so navigating to another module for 30+ seconds will clear state
  }

  void clearListState() {
    _pendingStateRestore = false;
    _lastListStateSavedAt = null;
    savedSearchTerm = null;
    savedCurrentPage = 1;
    savedScrollOffset = 0;
    savedCategoryId = null;
    savedSupplierId = null;
    savedProductTypeIndex = null;
    savedStockFilterIndex = 0;
    savedFilterWebPublished = false;
    savedFilterGoogleMerchant = false;
    savedShowInactive = false;
    savedSortOptionIndex = 2;
    aiMatchedSkus = null;
    aiStockFilterIndex = null;
  }

  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheMaxAge;
  }

  void invalidateProductsCache() {
    _cachedProducts = null;
    _productsCacheTime = null;
    _cachedListProducts = null;
    _listProductsCacheTime = null;
  }

  void _updateCachedProductStock(String productId, int stockAfter) {
    void updateCache(List<Product>? cache) {
      if (cache == null) return;
      final index = cache.indexWhere((product) => product.id == productId);
      if (index < 0) return;
      cache[index] = cache[index].copyWith(
        inventoryQty: stockAfter,
        updatedAt: DateTime.now(),
      );
    }

    updateCache(_cachedProducts);
    updateCache(_cachedListProducts);
  }

  void _updateCachedProductImageFingerprint(
    String productId,
    Map<String, dynamic>? imageFingerprint,
  ) {
    void updateCache(List<Product>? cache) {
      if (cache == null) return;
      final index = cache.indexWhere((product) => product.id == productId);
      if (index < 0) return;
      cache[index] = cache[index].copyWith(
        imageFingerprint: imageFingerprint,
        imageFingerprintHasValue: true,
      );
    }

    updateCache(_cachedProducts);
    updateCache(_cachedListProducts);
  }

  Future<void> storeProductImageFingerprint({
    required String productId,
    required Map<String, dynamic> imageFingerprint,
  }) async {
    try {
      await _db.update(
        'products',
        productId,
        {'image_fingerprint': imageFingerprint},
        applyTimestamps: false,
      );
      _updateCachedProductImageFingerprint(productId, imageFingerprint);
    } catch (e) {
      if (kDebugMode) {
        print('Error storing product image fingerprint: $e');
      }
    }
  }

  InventoryService(this._db, this._tenantService);

  // Product operations
  Future<List<Product>> getProducts({
    String? searchTerm,
    String? categoryId,
    bool? lowStockOnly,
    bool forceRefresh = false,
  }) async {
    try {
      // Check if this is a filtered query
      final isFilteredQuery = (searchTerm != null && searchTerm.isNotEmpty) ||
          categoryId != null ||
          lowStockOnly == true;

      // Return cached data if valid and not a filtered query
      if (!forceRefresh &&
          !isFilteredQuery &&
          _isCacheValid(_productsCacheTime) &&
          _cachedProducts != null) {
        debugPrint(
            '📦 [InventoryService] Using cached products (${_cachedProducts!.length} items)');
        return _cachedProducts!;
      }

      // Prevent concurrent fetches
      if (_isLoadingProducts && !isFilteredQuery) {
        debugPrint('⏳ [InventoryService] Already loading products, waiting...');
        while (_isLoadingProducts) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        if (_cachedProducts != null && !isFilteredQuery) {
          return _cachedProducts!;
        }
      }

      if (!isFilteredQuery) _isLoadingProducts = true;

      List<Map<String, dynamic>> data;

      if (searchTerm != null && searchTerm.isNotEmpty) {
        var products = await searchProductPreviews(searchTerm, limit: 200);
        if (categoryId != null) {
          products = products.where((p) => p.categoryId == categoryId).toList();
        }
        if (lowStockOnly == true) {
          products = products.where((p) => p.isLowStock).toList();
        }
        return products..sort((a, b) => a.name.compareTo(b.name));
      } else {
        // Select with JOIN to get category name - fetch ALL products with pagination
        data = await _db.select('products', fetchAll: true);
      }

      List<Product> products = await _hydrateSetAvailability(
        data.map((json) => Product.fromJson(json)).toList(),
      );

      // Apply filters
      if (categoryId != null) {
        products = products.where((p) => p.categoryId == categoryId).toList();
      }

      if (lowStockOnly == true) {
        products = products.where((p) => p.isLowStock).toList();
      }

      final sortedProducts = products..sort((a, b) => a.name.compareTo(b.name));

      // Cache only unfiltered results
      if (!isFilteredQuery) {
        _cachedProducts = sortedProducts;
        _productsCacheTime = DateTime.now();
        if (!kReleaseMode) {
          debugPrint(
              '✅ [InventoryService] Cached ${sortedProducts.length} products');
        }
        _isLoadingProducts = false;
      }

      return sortedProducts;
    } catch (e) {
      _isLoadingProducts = false;
      if (!kReleaseMode) {
        debugPrint('Error fetching products: $e');
      }
      rethrow;
    }
  }

  Future<List<Product>> searchProductPreviews(
    String searchTerm, {
    int limit = 50,
  }) async {
    final trimmed = searchTerm.trim();
    if (trimmed.isEmpty) {
      final products = await getProductsForList();
      return products.take(limit).toList(growable: false);
    }

    final searchTerms = _searchTermsFor(trimmed);
    if (searchTerms.isEmpty) return const [];

    final cachedSource = _isCacheValid(_productsCacheTime)
        ? _cachedProducts
        : _isCacheValid(_listProductsCacheTime)
            ? _cachedListProducts
            : null;
    if (cachedSource != null && cachedSource.isNotEmpty) {
      return _filterProductsByTerms(cachedSource, searchTerms, limit);
    }

    try {
      final rows = await _db.searchRecordsMultiToken(
        'products',
        const [
          'name',
          'sku',
          'brand',
          'model',
          'supplier_code',
          'barcode',
          'category_name',
        ],
        searchTerms,
        limit: limit,
        selectColumns: Product.listPreviewSelect,
      );

      final products = await _hydrateSetAvailability(
        rows.map((json) => Product.fromJson(json)).toList(),
      )
        ..sort((a, b) => a.name.compareTo(b.name));
      if (products.isNotEmpty) return products;
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [InventoryService] Product preview search failed: $e');
      }
    }

    // Accent-insensitive fallback: still preview-width, but local filtered.
    final products = await getProductsForList();
    return _filterProductsByTerms(products, searchTerms, limit);
  }

  Future<List<Product>> getProductsForList({
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh &&
          _isCacheValid(_listProductsCacheTime) &&
          _cachedListProducts != null) {
        debugPrint(
            '📦 [InventoryService] Using cached product list preview (${_cachedListProducts!.length} items)');
        return _cachedListProducts!;
      }

      if (_isLoadingListProducts) {
        debugPrint(
            '⏳ [InventoryService] Already loading product list preview, waiting...');
        while (_isLoadingListProducts) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        if (_cachedListProducts != null) {
          return _cachedListProducts!;
        }
      }

      _isLoadingListProducts = true;

      final data = await _db.select(
        'products',
        selectColumns: Product.listPreviewSelect,
        fetchAll: true,
      );

      final products = await _hydrateSetAvailability(
        data.map((json) => Product.fromJson(json)).toList(),
      )
        ..sort((a, b) => a.name.compareTo(b.name));

      _cachedListProducts = products;
      _listProductsCacheTime = DateTime.now();

      if (!kReleaseMode) {
        debugPrint(
            '✅ [InventoryService] Cached ${products.length} product list preview rows');
      }

      return products;
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('Error fetching product list preview: $e');
      }
      rethrow;
    } finally {
      _isLoadingListProducts = false;
    }
  }

  /// Semantic vector search via pgvector RPC.
  /// Returns raw maps with: name, sku, brand, price, inventory_qty, warehouse_location, similarity.
  Future<List<Map<String, dynamic>>> searchProductsSemantic(List<double> vector,
      {double threshold = 0.65, int limit = 10}) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant found');

      debugPrint(
          '🧠 [InventoryService] Calling match_products_semantic RPC...');

      final dynamic response =
          await _db.rpc('match_products_semantic', params: {
        'query_embedding': vector.toString(),
        'match_threshold': threshold,
        'match_count': limit,
        'match_tenant_id': tenantId,
      });

      if (response == null) return [];

      final results = (response as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      debugPrint(
          '🧠 [InventoryService] Semantic search returned ${results.length} results');
      return results;
    } catch (e) {
      debugPrint('❌ [InventoryService] Error in semantic search RPC: $e');
      rethrow;
    }
  }

  Future<Product?> getProductById(String id) async {
    try {
      final data = await _db.selectById('products', id);
      if (data == null) return null;
      final hydrated = await _hydrateSetAvailability([Product.fromJson(data)]);
      return hydrated.single;
    } catch (e) {
      if (kDebugMode) print('Error fetching product: $e');
      rethrow;
    }
  }

  Future<List<Product>> _hydrateSetAvailability(
    List<Product> products,
  ) async {
    return Future.wait(products.map((product) async {
      if (!product.isSet || product.id == null) return product;
      try {
        final composition = await getProductSetComposition(product.id!);
        return product.copyWith(
          fullSetsAvailable: composition.fullSetsAvailable,
        );
      } catch (error) {
        if (!kReleaseMode) {
          debugPrint(
            'No se pudo proyectar disponibilidad del juego ${product.id}: $error',
          );
        }
        return product;
      }
    }));
  }

  Future<Product?> getProductBySku(String sku) async {
    try {
      final data = await _db.select('products', where: 'sku=$sku');
      return data.isNotEmpty ? Product.fromJson(data.first) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching product by SKU: $e');
      rethrow;
    }
  }

  bool isAliExpressSupplierName(String? supplierName) {
    final normalized = supplierName?.trim().toLowerCase() ?? '';
    return normalized.contains('aliexpress');
  }

  Future<String> getNextAliExpressSku({
    String? supplierId,
    String? supplierName,
    bool forceRefresh = true,
  }) async {
    if (!isAliExpressSupplierName(supplierName)) {
      throw Exception('El proveedor seleccionado no usa la secuencia AE');
    }

    final products = await getProducts(forceRefresh: forceRefresh);
    var maxSequence = 0;

    void collectSequence(Product product) {
      final match = _aliExpressSkuPattern.firstMatch(product.sku.trim());
      if (match == null) return;

      final sequence = int.tryParse(match.group(1) ?? '0') ?? 0;
      if (sequence > maxSequence) {
        maxSequence = sequence;
      }
    }

    for (final product in products) {
      final matchesSupplier = supplierId != null &&
          supplierId.isNotEmpty &&
          product.supplierId == supplierId;
      final matchesAliExpressName =
          isAliExpressSupplierName(product.supplierName);

      if (matchesSupplier || matchesAliExpressName) {
        collectSequence(product);
      }
    }

    if (maxSequence == 0) {
      for (final product in products) {
        collectSequence(product);
      }
    }

    return 'AE${(maxSequence + 1).toString().padLeft(4, '0')}';
  }

  /// Reserves the canonical AE namespace in the database. Every creation
  /// surface must reserve immediately before insert; previewing the next SKU
  /// alone is intentionally not an allocation.
  Future<List<String>> reserveAliExpressSkus({
    required int count,
    required String operationKey,
    required String supplierId,
    required String supplierName,
  }) async {
    final response = await _db.rpc(
      'reserve_aliexpress_skus',
      params: {
        'p_count': count,
        'p_operation_key': operationKey.trim(),
        'p_supplier_id': supplierId.trim(),
        'p_supplier_name': supplierName.trim(),
      },
    );
    if (response is! Map) {
      throw const FormatException(
          'La reserva AE devolvió una respuesta inválida.');
    }
    final rawSkus = response['skus'];
    if (rawSkus is! List) {
      throw const FormatException('La reserva AE no devolvió SKUs.');
    }
    final skus = rawSkus
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (skus.length != count) {
      throw const FormatException('La cantidad reservada de SKUs no coincide.');
    }
    return skus;
  }

  Future<Product> createProduct(Product product) async {
    try {
      // Check if SKU already exists
      final existingProduct = await getProductBySku(product.sku);
      if (existingProduct != null) {
        throw Exception('Ya existe un producto con este SKU');
      }

      // Add tenant_id to product data
      final productData = _tenantService.addTenantId(product.toJson());

      // Generate embedding BEFORE insert
      try {
        final aiService = AIAssistantService();
        final embeddingContent =
            '${product.name} ${product.brand ?? ""} ${product.categoryName ?? ""} ${product.description ?? ""}';
        final vector = await aiService.generateEmbedding(embeddingContent);
        if (vector != null) {
          productData['embedding'] = vector.toString();
        }
      } catch (e) {
        debugPrint('⚠️ [InventoryService] Failed to generate embedding: $e');
      }

      final data = await _db.insert('products', productData);

      invalidateProductsCache();
      notifyListeners();
      return Product.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating product: $e');
      rethrow;
    }
  }

  Future<Product> updateProduct(Product product) async {
    try {
      // Check if SKU already exists (excluding current product)
      final existingProducts =
          await _db.select('products', where: 'sku=${product.sku}');
      final duplicates = existingProducts
          .where((p) => p['id']?.toString() != product.id)
          .toList();
      if (duplicates.isNotEmpty) {
        throw Exception('Ya existe otro producto con este SKU');
      }

      final updatedProduct = product.copyWith(updatedAt: DateTime.now());
      if (product.id == null) {
        throw Exception('ID de producto inválido');
      }

      final productData = updatedProduct.toJson(includeNulls: true);

      // Stock must change only through explicit stock-adjustment workflows.
      productData.remove('inventory_qty');
      productData.remove('stock_quantity');

      // Generate/Refresh embedding on update
      try {
        final aiService = AIAssistantService();
        final embeddingContent =
            '${product.name} ${product.brand ?? ""} ${product.categoryName ?? ""} ${product.description ?? ""}';
        final vector = await aiService.generateEmbedding(embeddingContent);
        if (vector != null) {
          productData['embedding'] = vector.toString();
        }
      } catch (e) {
        debugPrint('⚠️ [InventoryService] Failed to update embedding: $e');
      }

      final data = await _db.update('products', product.id!, productData);
      invalidateProductsCache();
      notifyListeners();
      return Product.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating product: $e');
      rethrow;
    }
  }

  Future<ProductSetAggregateSaveResult> saveProductSetAggregate({
    required Map<String, dynamic> parent,
    required List<Map<String, dynamic>> components,
    required String operationKey,
  }) async {
    final cleanOperationKey = operationKey.trim();
    if (cleanOperationKey.isEmpty) {
      throw ArgumentError.value(
        operationKey,
        'operationKey',
        'No puede estar vacío.',
      );
    }
    if (components.isEmpty) {
      throw ArgumentError.value(
        components,
        'components',
        'Un juego debe tener al menos un componente.',
      );
    }

    final response = await _db.rpc(
      'save_product_set_aggregate',
      params: {
        'p_parent': parent,
        'p_components': components,
        'p_operation_key': cleanOperationKey,
      },
    );
    final result = ProductSetAggregateSaveResult.fromJson(
      _rpcJsonMap(response),
    );
    invalidateProductsCache();
    notifyListeners();
    return result;
  }

  Future<ProductSetCompositionSnapshot> getProductSetComposition(
    String setProductId,
  ) async {
    final normalizedId = setProductId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(
        setProductId,
        'setProductId',
        'No puede estar vacío.',
      );
    }
    final response = await _db.rpc(
      'get_product_set_composition',
      params: {'p_set_product_id': normalizedId},
    );
    return ProductSetCompositionSnapshot.fromJson(_rpcJsonMap(response));
  }

  Future<Map<String, int>> getProductSetComponentQuantities() async {
    final rows = await _db.select(
      'product_set_components',
      selectColumns: 'component_product_id,quantity_in_set',
      fetchAll: true,
    );
    final quantities = <String, int>{};
    for (final row in rows) {
      final componentId = row['component_product_id']?.toString() ?? '';
      final quantity = (row['quantity_in_set'] as num?)?.round() ?? 1;
      if (componentId.isEmpty || quantity < 1) continue;
      quantities[componentId] = quantity;
    }
    return quantities;
  }

  static Map<String, dynamic> _rpcJsonMap(dynamic response) {
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    if (response is List && response.length == 1 && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    throw const FormatException(
      'La base de datos devolvió una respuesta inválida.',
    );
  }

  Future<StockAdjustmentDetail> applyStockAdjustment({
    required String productId,
    required int quantity,
    required String type,
    required String reasonType,
    String? note,
    DateTime? effectiveAt,
    String? adjustmentOrigin,
  }) async {
    try {
      final response = await _db.rpc(
        'apply_inventory_stock_adjustment',
        params: {
          'p_product_id': productId,
          'p_quantity': quantity,
          'p_type': type.trim().toUpperCase(),
          'p_reason_type': reasonType,
          'p_note': note,
          'p_effective_at': (effectiveAt ?? DateTime.now()).toIso8601String(),
          'p_adjustment_origin':
              adjustmentOrigin ?? StockAdjustmentOrigin.productForm.value,
        },
      );

      final result = Map<String, dynamic>.from(response as Map);
      final adjustmentId = result['adjustment_id']?.toString();
      if (adjustmentId == null || adjustmentId.isEmpty) {
        throw Exception(
            'La respuesta del ajuste no incluyó un identificador válido.');
      }

      final loadedDetail = await getStockAdjustmentDetails(adjustmentId);
      final detail = StockAdjustmentDetail.fromJson({
        'id': loadedDetail.id,
        'operation_id': result['operation_id'],
        'product_id': loadedDetail.productId,
        'product_name': loadedDetail.productName,
        'product_sku': loadedDetail.productSku,
        'adjustment_type': loadedDetail.adjustmentType,
        'reference_number': loadedDetail.referenceNumber,
        'quantity': loadedDetail.quantity,
        'stock_before': loadedDetail.stockBefore,
        'stock_after': loadedDetail.stockAfter,
        'reason': loadedDetail.reason,
        'adjustment_origin': loadedDetail.adjustmentOrigin,
        'adjustment_date': loadedDetail.adjustmentDate.toIso8601String(),
        'created_at': loadedDetail.createdAt.toIso8601String(),
        'created_by': loadedDetail.createdBy,
        'created_by_email': loadedDetail.createdByEmail,
        'unit_cost': loadedDetail.unitCost,
        'inventory_value': loadedDetail.inventoryValue,
        'journal_entry_id': loadedDetail.journalEntryId,
        'journal_entry_number': loadedDetail.journalEntryNumber,
        'journal_entry_date': loadedDetail.journalEntryDate?.toIso8601String(),
        'journal_entry_description': loadedDetail.journalEntryDescription,
        'counterpart_account_code': loadedDetail.counterpartAccountCode,
        'counterpart_account_name': loadedDetail.counterpartAccountName,
        'counterpart_debit': loadedDetail.counterpartDebit,
        'counterpart_credit': loadedDetail.counterpartCredit,
      });
      _updateCachedProductStock(productId, detail.stockAfter);
      notifyListeners();
      return detail;
    } catch (e) {
      if (kDebugMode) {
        print('Error applying stock adjustment: $e');
      }
      rethrow;
    }
  }

  Future<StockAdjustmentDetail> getStockAdjustmentDetails(
    String adjustmentId,
  ) async {
    try {
      final response = await _db.rpc(
        'get_stock_adjustment_details',
        params: {'p_adjustment_id': adjustmentId},
      );

      return StockAdjustmentDetail.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching stock adjustment details: $e');
      }
      rethrow;
    }
  }

  Future<Product> convertProductInventoryToNonStock({
    required String productId,
    required PurchaseTreatment targetPurchaseTreatment,
    required ProductType targetProductType,
    required String reason,
  }) async {
    try {
      final dynamic result = await _db.rpc(
        'convert_product_inventory_to_non_stock',
        params: {
          'p_product_id': productId,
          'p_target_purchase_treatment': targetPurchaseTreatment.dbValue,
          'p_target_product_type': targetProductType.name,
          'p_reason': reason,
        },
      );

      Map<String, dynamic> productJson;
      if (result is Map && result['product'] is Map) {
        productJson = Map<String, dynamic>.from(result['product'] as Map);
      } else if (result is Map) {
        productJson = Map<String, dynamic>.from(result);
      } else {
        throw Exception('Respuesta inválida al convertir el producto');
      }

      invalidateProductsCache();
      notifyListeners();
      return Product.fromJson(productJson);
    } catch (e) {
      if (kDebugMode) {
        print('Error converting product inventory to non-stock: $e');
      }
      rethrow;
    }
  }

  Future<Product> restoreProductConversionState({
    required String productId,
    required String reason,
    required bool restoreInventory,
    String? conversionReference,
  }) async {
    try {
      final dynamic result = await _db.rpc(
        'restore_product_conversion_state',
        params: {
          'p_product_id': productId,
          'p_reason': reason,
          'p_restore_inventory': restoreInventory,
          'p_conversion_reference': conversionReference,
        },
      );

      Map<String, dynamic> productJson;
      if (result is Map && result['product'] is Map) {
        productJson = Map<String, dynamic>.from(result['product'] as Map);
      } else if (result is Map) {
        productJson = Map<String, dynamic>.from(result);
      } else {
        throw Exception('Respuesta inválida al restaurar el producto');
      }

      invalidateProductsCache();
      notifyListeners();
      return Product.fromJson(productJson);
    } catch (e) {
      if (kDebugMode) {
        print('Error restoring product conversion state: $e');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getProductConversionStatus({
    required String productId,
  }) async {
    try {
      final dynamic result = await _db.rpc(
        'get_product_conversion_status',
        params: {'p_product_id': productId},
      );

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }

      throw Exception('Respuesta inválida al consultar estado de conversión');
    } catch (e) {
      if (kDebugMode) {
        print('Error loading product conversion status: $e');
      }
      rethrow;
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      if (id.isEmpty) {
        throw Exception('ID de producto inválido');
      }
      await _db.delete('products', id);
      invalidateProductsCache();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error deleting product: $e');
      rethrow;
    }
  }

  // Stock operations
  Future<void> adjustStock({
    required String productId,
    required int newQuantity,
    required String reason,
    double? unitCost,
  }) async {
    try {
      final product = await getProductById(productId);
      if (product == null) {
        throw Exception('Producto no encontrado');
      }

      final difference = newQuantity - product.inventoryQty;
      if (difference == 0) return; // No change needed

      await _db.adjustStock(
        productId,
        difference.abs(),
        difference > 0 ? 'IN' : 'OUT',
        reason,
      );

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error adjusting stock: $e');
      rethrow;
    }
  }

  // Stock movement history
  Future<List<StockMovement>> getStockMovements({
    String? productId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      String? whereClause;
      if (productId != null && productId.isNotEmpty) {
        whereClause = 'product_id=$productId';
      }

      final data =
          await _db.select('stock_movements_with_products', where: whereClause);
      List<StockMovement> movements =
          data.map((json) => StockMovement.fromJson(json)).toList();

      // Apply date filters
      if (startDate != null) {
        movements = movements
            .where((m) =>
                m.date.isAfter(startDate.subtract(const Duration(days: 1))))
            .toList();
      }
      if (endDate != null) {
        movements = movements
            .where((m) => m.date.isBefore(endDate.add(const Duration(days: 1))))
            .toList();
      }

      return movements..sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      if (kDebugMode) print('Error fetching stock movements: $e');
      // Fallback to basic stock movements if view doesn't exist
      try {
        final data = await _db.select('stock_movements');
        return data.map((json) => StockMovement.fromJson(json)).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
      } catch (e2) {
        if (kDebugMode) print('Error fetching basic stock movements: $e2');
        return [];
      }
    }
  }

  // Analytics and reports
  Future<Map<String, dynamic>> getInventoryAnalytics() async {
    try {
      final products = await getProducts();
      final totalProducts = products.length;
      final lowStockProducts = products.where((p) => p.isLowStock).length;
      final outOfStockProducts = products.where((p) => p.isOutOfStock).length;

      // Calculate total inventory value
      final totalValue =
          products.fold(0.0, (sum, product) => sum + product.inventoryValue);

      // Category distribution (now by category ID)
      final categoryDistribution = <String, int>{};
      for (final product in products) {
        if (product.categoryId != null) {
          categoryDistribution[product.categoryId!] =
              (categoryDistribution[product.categoryId!] ?? 0) + 1;
        }
      }

      return {
        'total_products': totalProducts,
        'low_stock_count': lowStockProducts,
        'out_of_stock_count': outOfStockProducts,
        'total_inventory_value': totalValue,
        'category_distribution': categoryDistribution,
      };
    } catch (e) {
      if (kDebugMode) print('Error getting inventory analytics: $e');
      return {};
    }
  }

  Future<List<Product>> getLowStockProducts() async {
    try {
      return await getProducts(lowStockOnly: true);
    } catch (e) {
      if (kDebugMode) print('Error fetching low stock products: $e');
      return [];
    }
  }

  bool _embeddingBackfillDone = false;

  /// Backfills embeddings for all products that don't have one yet.
  /// Runs in the background and does not block the UI. Only runs once per session.
  /// Skips products that already have embeddings and retries on rate limit errors.
  Future<void> backfillEmbeddings() async {
    if (_embeddingBackfillDone) return;
    _embeddingBackfillDone = true;
    try {
      // Fetch only product IDs that are missing embeddings via raw RPC
      final List<dynamic> missingRows = await _db.rpc(
        'get_products_missing_embeddings',
        params: {'batch_limit': 1500},
      );

      if (missingRows.isEmpty) {
        debugPrint('✅ [Embedding] All products already have embeddings');
        return;
      }

      final missingIds =
          missingRows.map((r) => (r as Map)['id'].toString()).toSet();

      // Get full product data for those IDs
      final allProducts = await getProducts(forceRefresh: true);
      final productsToProcess = allProducts
          .where((p) => p.id != null && missingIds.contains(p.id))
          .toList();

      debugPrint(
          '🧠 [Embedding] Backfilling ${productsToProcess.length} products missing embeddings...');

      int generated = 0;
      int errors = 0;

      for (final product in productsToProcess) {
        try {
          // Try up to 2 times per product (retry once on rate limit)
          List<double>? embedding;
          for (int attempt = 0; attempt < 2; attempt++) {
            embedding = await _generateProductEmbedding(product);
            if (embedding != null) break;

            // Wait longer on retry (likely rate limited)
            if (attempt == 0) {
              debugPrint(
                  '⏳ [Embedding] Rate limited, waiting 5s before retry...');
              await Future.delayed(const Duration(seconds: 5));
            }
          }

          if (embedding == null) {
            errors++;
            continue;
          }

          await _db.update(
              'products',
              product.id!,
              {
                'embedding': embedding.toString(),
              },
              applyTimestamps: false);
          generated++;
        } catch (e) {
          errors++;
          debugPrint(
              '⚠️ [Embedding] Skipping product ${product.id} (${product.name}): $e');
        }

        // Rate limit: pause every 5 products
        if (generated % 5 == 0 && generated > 0) {
          debugPrint(
              '🧠 [Embedding] Progress: $generated/${productsToProcess.length} (errors: $errors)');
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      debugPrint(
          '✅ [Embedding] Backfill complete: $generated generated, $errors errors out of ${productsToProcess.length}');
    } catch (e) {
      debugPrint('⚠️ [Embedding] Backfill failed: $e');
      // Allow retry next session
      _embeddingBackfillDone = false;
    }
  }

  /// Generates a vector embedding for a product using the shared AIAssistantService.
  /// Returns null if the call fails (non-blocking).
  Future<List<double>?> _generateProductEmbedding(Product product) async {
    try {
      final text =
          '${product.name} ${product.brand ?? ''} ${product.categoryName ?? ''} ${product.description ?? ''}'
              .trim();

      if (text.isEmpty) return null;

      final aiService = AIAssistantService();
      final vector = await aiService.generateEmbedding(text);
      if (vector != null) {
        debugPrint(
            '✅ [Embedding] Generated ${vector.length}-dim vector for "${product.name}"');
      }
      return vector;
    } catch (e) {
      debugPrint('⚠️ [Embedding] Failed to generate embedding: $e');
      return null;
    }
  }

  /// Normalizes text by removing diacritics and converting to lowercase
  String _normalizeText(String text) {
    if (text.isEmpty) return text;

    // Convert to lowercase first
    String normalized = text.toLowerCase();

    // Replace accented characters
    normalized = normalized.replaceAll(RegExp(r'[áàäâ]'), 'a');
    normalized = normalized.replaceAll(RegExp(r'[éèëê]'), 'e');
    normalized = normalized.replaceAll(RegExp(r'[íìïî]'), 'i');
    normalized = normalized.replaceAll(RegExp(r'[óòöô]'), 'o');
    normalized = normalized.replaceAll(RegExp(r'[úùüû]'), 'u');
    normalized = normalized.replaceAll(RegExp(r'[ñ]'), 'n');
    normalized = normalized.replaceAll(RegExp(r'[ç]'), 'c');

    return normalized;
  }

  List<String> _searchTermsFor(String searchTerm) {
    return searchTerm
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .map((term) => _stemSearchTerm(_normalizeText(term)))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
  }

  List<Product> _filterProductsByTerms(
    Iterable<Product> products,
    List<String> searchTerms,
    int limit,
  ) {
    final filtered = products.where((product) {
      final searchableText = _normalizeText([
        product.name,
        product.sku,
        product.brand ?? '',
        product.model ?? '',
        product.barcode ?? '',
        product.categoryName ?? '',
        product.supplierCode ?? '',
        product.tags.join(' '),
      ].join(' '));

      for (final term in searchTerms) {
        if (RegExp(r'^\d+$').hasMatch(term)) {
          final pattern =
              RegExp('(?:^|\\s|[^0-9])${RegExp.escape(term)}(?:\$|\\s|[^0-9])');
          if (!pattern.hasMatch(searchableText)) return false;
        } else if (!searchableText.contains(term)) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return filtered.take(limit).toList(growable: false);
  }

  /// Naive Spanish stemming for search queries
  /// Removes trailing 's' or 'es' to match singular products
  String _stemSearchTerm(String term) {
    if (term.length <= 3) return term; // Too short to stem safely

    // If it ends in 'es' (e.g. pedales -> pedal, cassettes (wait, cassette ends in e))
    if (term.endsWith('es')) {
      // Exceptions where removing 'es' is wrong
      if (term == 'mes' || term == 'tres') return term;

      // Let's strip 's' first, which is the most common plural.
      // If the word ends in a consonant + 'es' (like l, d, r, n), removing 'es' might be better.
      final beforeEs = term.substring(0, term.length - 2);
      if (beforeEs.isNotEmpty) {
        final lastChar = beforeEs[beforeEs.length - 1];
        if ('ldrn'.contains(lastChar)) {
          return beforeEs; // pedales -> pedal
        }
      }
    }

    // Most common: just remove trailing 's'
    if (term.endsWith('s')) {
      if (term == 'cas' ||
          term == 'dos' ||
          term == 'mas' ||
          term == 'las' ||
          term == 'los' ||
          term == 'sus') {
        return term;
      }
      return term.substring(0, term.length - 1);
    }

    return term;
  }
}
