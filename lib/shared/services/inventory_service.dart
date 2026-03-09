import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import 'database_service.dart';
import 'tenant_service.dart';

class InventoryService extends ChangeNotifier {
  final DatabaseService? _db;
  final TenantService _tenantService = TenantService();
  final List<Product> _products = [];

  bool _isLoading = false;
  bool _hasLoaded = false;

  RealtimeChannel? _stockMovementsChannel;

  InventoryService({DatabaseService? db}) : _db = db {
    // Don't await - fire and forget to avoid blocking constructor
    _setupStockMovementsRealtime();
  }

  List<Product> get products => List.unmodifiable(_products);
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;

  Future<List<Product>> getProducts({bool forceRefresh = false}) async {
    if (!_hasLoaded || forceRefresh) {
      await _loadProducts(force: forceRefresh);
    }
    return _products;
  }

  /// Get products of a specific type from server with a limit
  Future<List<Product>> getProductsByType(ProductType type,
      {int limit = 100}) async {
    try {
      if (_db == null)
        return _products.where((p) => p.productType == type).toList();

      final data = await _db!.select('products',
          where: "product_type=${type.name.toLowerCase()}", limit: limit);

      final results = data.map(_productFromMap).toList();
      // Update local cache with these items
      for (var p in results) {
        _upsertLocalProduct(p);
      }
      return results;
    } catch (e) {
      debugPrint('⚠️ [InventoryService] Failed to fetch products by type: $e');
      return _products.where((p) => p.productType == type).toList();
    }
  }

  Future<void> refresh() => _loadProducts(force: true);

  Future<Product?> getProductById(String id,
      {bool forceRefresh = false}) async {
    if (!_hasLoaded || forceRefresh) {
      await _loadProducts(force: forceRefresh);
    }

    try {
      return _products.firstWhere((product) => product.id == id);
    } catch (_) {
      if (_db == null) return null;
      try {
        final data = await _db!.selectById('products', id);
        if (data == null) return null;
        final product = _productFromMap(data);
        _upsertLocalProduct(product);
        notifyListeners();
        return product;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              'InventoryService: Error fetching product by id $id -> $e');
        }
        return null;
      }
    }
  }

  Future<Product?> getProductBySku(String sku) async {
    await getProducts();
    try {
      return _products.firstWhere(
          (product) => product.sku.toLowerCase() == sku.toLowerCase());
    } catch (_) {
      if (_db == null) return null;
      try {
        final records = await _db!.select('products', where: 'sku=$sku');
        if (records.isEmpty) return null;
        final product = _productFromMap(records.first);
        _upsertLocalProduct(product);
        notifyListeners();
        return product;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              'InventoryService: Error fetching product by SKU $sku -> $e');
        }
        return null;
      }
    }
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    await getProducts();
    try {
      return _products.firstWhere((product) => product.barcode == barcode);
    } catch (_) {
      return null;
    }
  }

  Future<Product?> getProductBySupplierCode(String supplierCode) async {
    debugPrint('🔎 Finding Product by supplierCode: "$supplierCode"');
    await getProducts();
    debugPrint('📦 Cache size: ${_products.length}');

    final cleanCode = supplierCode.trim();
    final lowerCode = cleanCode.toLowerCase();

    try {
      final match = _products.firstWhere(
        (product) => product.supplierCode?.trim().toLowerCase() == lowerCode,
      );
      debugPrint('✅ Memory Match: ${match.name} (ID: ${match.id})');
      return match;
    } catch (_) {
      debugPrint('⚠️ Not in memory. DB Fallback for cleanCode="$cleanCode"...');
      if (_db == null) return null;
      try {
        debugPrint('🔌 Executing DB Select: supplier_code=$cleanCode');
        final records =
            await _db!.select('products', where: "supplier_code=$cleanCode");
        debugPrint('🔌 DB returned ${records.length} records');

        if (records.isEmpty) {
          debugPrint('❌ DB Check: zero results.');
          return null;
        }

        debugPrint('🔨 Mapping record 0...');
        final product = _productFromMap(records.first);
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

  Future<List<Product>> searchProducts(String query, {int limit = 50}) async {
    if (query.trim().isEmpty) {
      return await getProducts();
    }

    final lowered = query.toLowerCase();

    // 1. Try DB search first if available for efficiency on large datasets
    if (_db != null) {
      try {
        // Search multiple columns and combine (Supabase doesn't have a simple multi-column ilike in the basic RPC yet)
        final nameResults = await _db!.searchRecords('products', 'name', query);
        final skuResults = await _db!.searchRecords('products', 'sku', query);
        final brandResults =
            await _db!.searchRecords('products', 'brand', query);

        final Set<String> seenIds = {};
        final List<Product> results = [];

        for (var map in [...nameResults, ...skuResults, ...brandResults]) {
          final id = map['id']?.toString();
          if (id != null && seenIds.add(id)) {
            final product = _productFromMap(map);
            _upsertLocalProduct(product);
            results.add(product);
          }
          if (results.length >= limit) break;
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
          final candidates = <String?>[
            product.name,
            product.sku,
            product.brand,
            product.model,
            product.barcode,
            product.categoryName,
          ];
          return candidates.any((value) =>
              value != null && value.toLowerCase().contains(lowered));
        })
        .take(limit)
        .toList();
  }

  Future<bool> updateStock(
    String productId,
    int newQuantity, {
    String reference = 'Ajuste manual',
  }) async {
    if (newQuantity < 0) return false;
    final product = await getProductById(productId);
    if (product == null) return false;

    final difference = newQuantity - product.stockQuantity;
    if (difference == 0) return true;

    final type = difference > 0 ? 'IN' : 'OUT';
    final quantity = difference.abs();

    if (_db != null) {
      try {
        await _db!.adjustStock(productId, quantity, type, reference);
        await getProducts(forceRefresh: true);
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
  }) async {
    if (quantity <= 0) return false;
    final product = await getProductById(productId);
    if (product == null) return false;

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
        await _db!.adjustStock(productId, quantity, 'OUT', reference);
        await getProducts(forceRefresh: true);
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
  }) async {
    if (quantity <= 0) return false;
    final product = await getProductById(productId);
    if (product == null) return false;

    if (_db != null) {
      try {
        await _db!.adjustStock(productId, quantity, 'IN', reference);
        await getProducts(forceRefresh: true);
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
    notifyListeners();
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

    if (_isLoading && !force) {
      return;
    }

    _isLoading = true;
    if (!_hasLoaded) {
      notifyListeners();
    }

    try {
      // Fetch ALL products (uses pagination internally to bypass 1000 row limit)
      final rawProducts = await _db!.select('products', fetchAll: true);
      final products = rawProducts.map(_productFromMap).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      _products
        ..clear()
        ..addAll(products);
      _hasLoaded = true;
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
        json['inventory_qty'] as int? ?? json['stock_quantity'] as int? ?? 0;
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
      specifications:
          Map<String, String>.from(json['specifications'] as Map? ?? {}),
      supplierId: json['supplier_id']?.toString(),
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
      productType: ProductType.values.firstWhere(
        (t) => t.name == productTypeValue,
        orElse: () => ProductType.product,
      ),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
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

              if (payload.newRecord != null && payload.newRecord!.isNotEmpty) {
                final updatedProduct = _productFromMap(payload.newRecord!);
                _upsertLocalProduct(updatedProduct);
                notifyListeners();
              } else if (payload.eventType == PostgresChangeEvent.delete &&
                  payload.oldRecord != null) {
                final id = payload.oldRecord!['id']?.toString();
                if (id != null) {
                  _products.removeWhere((p) => p.id == id);
                  notifyListeners();
                }
              }
            },
          )
          .subscribe();

      debugPrint('✅ [InventoryService] Realtime subscription active');
    } catch (e) {
      debugPrint('❌ [InventoryService] Failed to setup realtime: $e');
    }
  }

  void disposeRealtime() {
    _stockMovementsChannel?.unsubscribe();
  }
}
