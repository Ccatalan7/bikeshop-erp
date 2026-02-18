import 'package:flutter/foundation.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/inventory_models.dart';

class InventoryService extends ChangeNotifier {
  final DatabaseService _db;
  final TenantService _tenantService;

  // ============================================================
  // CACHING - Avoid refetching on every page navigation
  // ============================================================
  List<Product>? _cachedProducts;
  DateTime? _productsCacheTime;
  static const Duration _cacheMaxAge = Duration(minutes: 5);
  bool _isLoadingProducts = false;

  // Public getters for cached data (instant access)
  List<Product> get cachedProducts => _cachedProducts ?? [];
  bool get hasProductsCache => _cachedProducts != null;

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
  }

  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheMaxAge;
  }

  void invalidateProductsCache() {
    _cachedProducts = null;
    _productsCacheTime = null;
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
        if (_cachedProducts != null && !isFilteredQuery)
          return _cachedProducts!;
      }

      if (!isFilteredQuery) _isLoadingProducts = true;

      List<Map<String, dynamic>> data;

      if (searchTerm != null && searchTerm.isNotEmpty) {
        // 1. Fetch all products (leveraging existing pagination/caching)
        data = await _db.select('products', fetchAll: true);

        // 2. Client-side fuzzy search for better flexibility
        // This is acceptable because product count is usually < 5000 for a bike shop
        // and we want to match "Cassette Shimano" even if name is "Shimano Cassette"
        final searchTerms =
            searchTerm.toLowerCase().trim().split(RegExp(r'\s+'));

        List<Map<String, dynamic>> filteredData = [];

        for (final item in data) {
          final name = (item['name'] as String? ?? '').toLowerCase();
          final sku = (item['sku'] as String? ?? '').toLowerCase();
          final brand = (item['brand'] as String? ?? '').toLowerCase();
          final category =
              (item['category_name'] as String? ?? '').toLowerCase();
          final model = (item['model'] as String? ?? '').toLowerCase();
          final tags = (item['tags'] as List?)?.join(' ').toLowerCase() ?? '';

          final searchableText = '$name $sku $brand $category $model $tags';

          // Check if ALL keywords exist in the searchable text
          bool matchesAll = true;
          for (final term in searchTerms) {
            if (!searchableText.contains(term)) {
              matchesAll = false;
              break;
            }
          }

          if (matchesAll) {
            filteredData.add(item);
          }
        }
        data = filteredData;
      } else {
        // Select with JOIN to get category name - fetch ALL products with pagination
        data = await _db.select('products', fetchAll: true);
      }

      List<Product> products =
          data.map((json) => Product.fromJson(json)).toList();

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

  Future<Product?> getProductById(String id) async {
    try {
      final data = await _db.selectById('products', id);
      return data != null ? Product.fromJson(data) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching product: $e');
      rethrow;
    }
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

  Future<Product> createProduct(Product product) async {
    try {
      // Check if SKU already exists
      final existingProduct = await getProductBySku(product.sku);
      if (existingProduct != null) {
        throw Exception('Ya existe un producto con este SKU');
      }

      // Add tenant_id to product data
      final productData = _tenantService.addTenantId(product.toJson());
      final data = await _db.insert('products', productData);

      // Create initial stock movement if inventory > 0
      if (product.inventoryQty > 0) {
        await _createStockMovement(
          productId: data['id'],
          quantity: product.inventoryQty,
          type: StockMovementType.adjustment,
          reference: 'Inventario inicial',
          unitCost: product.cost,
        );
      }

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

      // Check if stock quantity changed - if so, create stock_adjustments record
      final existingProduct = await getProductById(product.id!);
      if (existingProduct != null &&
          existingProduct.inventoryQty != product.inventoryQty) {
        final difference = product.inventoryQty - existingProduct.inventoryQty;

        // Create stock_adjustments record (NOT stock_movements)
        final tenantId = await _tenantService.getTenantId();
        if (tenantId != null) {
          try {
            await _db.insert('stock_adjustments', {
              'product_id': product.id!,
              'adjustment_type': 'manual',
              'quantity': difference,
              'stock_before': existingProduct.inventoryQty,
              'stock_after': product.inventoryQty,
              'reason': 'Ajuste manual desde formulario de producto',
            });
          } catch (e) {
            if (kDebugMode)
              print('⚠️ Error creating stock adjustment record: $e');
            // Don't fail the whole update if adjustment logging fails
          }
        }
      }

      final data =
          await _db.update('products', product.id!, updatedProduct.toJson());
      invalidateProductsCache();
      notifyListeners();
      return Product.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error updating product: $e');
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

      // Update product inventory
      await _db.update('products', productId, {
        'inventory_qty': newQuantity,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Create stock movement
      await _createStockMovement(
        productId: productId,
        quantity: difference.abs(),
        type: StockMovementType.adjustment,
        reference: reason,
        unitCost: unitCost ?? product.cost,
      );

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error adjusting stock: $e');
      rethrow;
    }
  }

  Future<void> recordSale({
    required String productId,
    required int quantity,
    required String reference,
    double? salePrice,
  }) async {
    try {
      final product = await getProductById(productId);
      if (product == null) {
        throw Exception('Producto no encontrado');
      }

      if (product.inventoryQty < quantity) {
        throw Exception(
            'Stock insuficiente. Disponible: ${product.inventoryQty}');
      }

      // Update product inventory
      final newQuantity = product.inventoryQty - quantity;
      await _db.update('products', productId, {
        'inventory_qty': newQuantity,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Create stock movement
      await _createStockMovement(
        productId: productId,
        quantity: quantity,
        type: StockMovementType.sale,
        reference: reference,
        unitCost: product.cost,
      );

      // Post accounting entry for sale
      await _postSaleAccountingEntry(
        productId: productId,
        quantity: quantity,
        costPerUnit: product.cost,
        salePrice: salePrice ?? product.price,
        reference: reference,
      );

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error recording sale: $e');
      rethrow;
    }
  }

  Future<void> recordPurchase({
    required String productId,
    required int quantity,
    required String reference,
    required double unitCost,
  }) async {
    try {
      final product = await getProductById(productId);
      if (product == null) {
        throw Exception('Producto no encontrado');
      }

      // Update product inventory and cost
      final newQuantity = product.inventoryQty + quantity;

      // Calculate weighted average cost
      final totalCurrentValue = product.cost * product.inventoryQty;
      final totalNewValue = unitCost * quantity;
      final newAverageCost = (totalCurrentValue + totalNewValue) / newQuantity;

      await _db.update('products', productId, {
        'inventory_qty': newQuantity,
        'cost': newAverageCost,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Create stock movement
      await _createStockMovement(
        productId: productId,
        quantity: quantity,
        type: StockMovementType.purchase,
        reference: reference,
        unitCost: unitCost,
      );

      // Post accounting entry for purchase
      await _postPurchaseAccountingEntry(
        productId: productId,
        quantity: quantity,
        unitCost: unitCost,
        reference: reference,
      );

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error recording purchase: $e');
      rethrow;
    }
  }

  Future<void> _createStockMovement({
    required String productId,
    required int quantity,
    required StockMovementType type,
    required String reference,
    double? unitCost,
    String? notes,
  }) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('User does not have a tenant_id. Cannot proceed.');
      }

      final movement = StockMovement(
        productId: productId,
        tenantId: tenantId,
        quantity: quantity,
        type: type,
        reference: reference,
        unitCost: unitCost,
        notes: notes,
      );

      await _db.insert('stock_movements', movement.toJson());
    } catch (e) {
      if (kDebugMode) print('Error creating stock movement: $e');
      // Don't rethrow as this is supplementary data
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

  // Accounting integration
  Future<void> _postSaleAccountingEntry({
    required String productId,
    required int quantity,
    required double costPerUnit,
    required double salePrice,
    required String reference,
  }) async {
    try {
      final totalCost = costPerUnit * quantity;
      final totalSale = salePrice * quantity;

      // This would integrate with the accounting service
      // For now, we'll just log the entry that should be created
      if (kDebugMode) {
        print('Accounting Entry for Sale:');
        print('Reference: $reference');
        print('Debit COGS: ${ChileanUtils.formatCurrency(totalCost)}');
        print('Credit Inventory: ${ChileanUtils.formatCurrency(totalCost)}');
        print('Debit Cash/AR: ${ChileanUtils.formatCurrency(totalSale)}');
        print('Credit Sales: ${ChileanUtils.formatCurrency(totalSale)}');
      }
    } catch (e) {
      if (kDebugMode) print('Error posting sale accounting entry: $e');
      // Don't rethrow as this is supplementary
    }
  }

  Future<void> _postPurchaseAccountingEntry({
    required String productId,
    required int quantity,
    required double unitCost,
    required String reference,
  }) async {
    try {
      final totalCost = unitCost * quantity;
      final ivaAmount = ChileanUtils.calculateIva(totalCost);

      // This would integrate with the accounting service
      // For now, we'll just log the entry that should be created
      if (kDebugMode) {
        print('Accounting Entry for Purchase:');
        print('Reference: $reference');
        print('Debit Inventory: ${ChileanUtils.formatCurrency(totalCost)}');
        print('Debit IVA Credit: ${ChileanUtils.formatCurrency(ivaAmount)}');
        print(
            'Credit Accounts Payable: ${ChileanUtils.formatCurrency(totalCost + ivaAmount)}');
      }
    } catch (e) {
      if (kDebugMode) print('Error posting purchase accounting entry: $e');
      // Don't rethrow as this is supplementary
    }
  }
}
