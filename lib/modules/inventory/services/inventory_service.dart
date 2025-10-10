import 'package:flutter/foundation.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/inventory_models.dart';

class InventoryService extends ChangeNotifier {
  final DatabaseService _db;
  
  InventoryService(this._db);
  
  // Product operations
  Future<List<Product>> getProducts({
    String? searchTerm,
    String? categoryId,
    bool? lowStockOnly,
  }) async {
    try {
      List<Map<String, dynamic>> data;
      
      if (searchTerm != null && searchTerm.isNotEmpty) {
        // Search by name, SKU, or brand with JOIN to get category name
        final nameResults = await _db.searchRecords('products', 'name', searchTerm);
        final skuResults = await _db.searchRecords('products', 'sku', searchTerm);
        final brandResults = await _db.searchRecords('products', 'brand', searchTerm);
        
        // Combine and deduplicate results
        final Set<String> ids = {};
        data = [...nameResults, ...skuResults, ...brandResults]
            .where((item) {
              final id = item['id']?.toString();
              if (id == null) return true;
              return ids.add(id);
            })
            .toList();
      } else {
        // Select with JOIN to get category name
        data = await _db.select('products');
      }
      
      List<Product> products = data.map((json) => Product.fromJson(json)).toList();
      
      // Apply filters
      if (categoryId != null) {
        products = products.where((p) => p.categoryId == categoryId).toList();
      }
      
      if (lowStockOnly == true) {
        products = products.where((p) => p.isLowStock).toList();
      }
      
      return products..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      if (kDebugMode) print('Error fetching products: $e');
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
      
      final data = await _db.insert('products', product.toJson());
      
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
      final existingProducts = await _db.select('products', where: 'sku=${product.sku}');
      final duplicates = existingProducts.where((p) => p['id']?.toString() != product.id).toList();
      if (duplicates.isNotEmpty) {
        throw Exception('Ya existe otro producto con este SKU');
      }
      
      final updatedProduct = product.copyWith(updatedAt: DateTime.now());
      if (product.id == null) {
        throw Exception('ID de producto inválido');
      }

      final data = await _db.update('products', product.id!, updatedProduct.toJson());
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
        throw Exception('Stock insuficiente. Disponible: ${product.inventoryQty}');
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
      final movement = StockMovement(
        productId: productId,
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
      
      final data = await _db.select('stock_movements_with_products', where: whereClause);
      List<StockMovement> movements = data.map((json) => StockMovement.fromJson(json)).toList();
      
      // Apply date filters
      if (startDate != null) {
        movements = movements.where((m) => m.date.isAfter(startDate.subtract(const Duration(days: 1)))).toList();
      }
      if (endDate != null) {
        movements = movements.where((m) => m.date.isBefore(endDate.add(const Duration(days: 1)))).toList();
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
      final totalValue = products.fold(0.0, (sum, product) => sum + product.inventoryValue);
      
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
        print('Credit Accounts Payable: ${ChileanUtils.formatCurrency(totalCost + ivaAmount)}');
      }
    } catch (e) {
      if (kDebugMode) print('Error posting purchase accounting entry: $e');
      // Don't rethrow as this is supplementary
    }
  }
}
