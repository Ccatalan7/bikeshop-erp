import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/smart_purchase_list_item.dart';

/// Result of scanning for low stock products
class ScanResult {
  final int added;
  final int removed;
  
  ScanResult({required this.added, required this.removed});
  
  int get total => added + removed;
}

class SmartPurchaseListService extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final TenantService _tenantService = TenantService();
  final SupabaseClient _client = Supabase.instance.client;

  List<SmartPurchaseListItem> _items = [];
  bool _isLoading = false;
  String? _error;

  List<SmartPurchaseListItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Dashboard KPIs
  int get totalPendingItems => _items.where((i) => i.isPending).length;
  int get urgentItemsCount => _items.where((i) => i.isUrgent).length;
  int get outOfStockCount => _items.where((i) => i.isOutOfStock).length;
  
  Map<String, int> get itemsBySupplier {
    final Map<String, int> result = {};
    for (var item in _items.where((i) => i.isPending)) {
      final supplier = item.supplierName ?? 'Sin proveedor';
      result[supplier] = (result[supplier] ?? 0) + 1;
    }
    return result;
  }
  
  String? get topSupplier {
    if (itemsBySupplier.isEmpty) return null;
    return itemsBySupplier.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Load all purchase list items
  Future<void> loadItems({
    String? statusFilter,
    String? supplierFilter,
    String searchQuery = '',
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant ID found');
      }

      // First, get the purchase list items
      PostgrestFilterBuilder<PostgrestList> query = _client
          .from('smart_purchase_list')
          .select('*')
          .eq('tenant_id', tenantId);

      // Apply status filter only (supplier filter will be applied after enrichment)
      if (statusFilter != null && statusFilter != 'all') {
        query = query.eq('status', statusFilter);
      }

      final response = await query
          .order('priority', ascending: false)
          .order('added_date', ascending: false);
      
      final items = response as List<dynamic>;
      
      // Now enrich each item with fresh product and supplier data
      final enrichedItems = <Map<String, dynamic>>[];
      
      for (final item in items) {
        final itemMap = Map<String, dynamic>.from(item);
        final productId = itemMap['product_id'];
        
        if (productId != null) {
          try {
            // Fetch fresh product data with supplier and stock levels
            final productData = await _client
                .from('products')
                .select('''
                  id,
                  name,
                  sku,
                  stock_quantity,
                  min_stock_level,
                  supplier_id,
                  suppliers(id, name)
                ''')
                .eq('id', productId)
                .maybeSingle();
            
            if (productData != null) {
              // Update with fresh product data
              itemMap['product_name'] = productData['name'] ?? itemMap['product_name'];
              itemMap['product_sku'] = productData['sku'] ?? itemMap['product_sku'];
              
              // Update stock levels with LIVE data from products table
              itemMap['current_stock'] = productData['stock_quantity'] ?? itemMap['current_stock'];
              itemMap['min_stock_level'] = productData['min_stock_level'] ?? itemMap['min_stock_level'];
              
              // Update supplier from product
              if (productData['supplier_id'] != null) {
                itemMap['supplier_id'] = productData['supplier_id'];
                
                final supplier = productData['suppliers'] as Map<String, dynamic>?;
                if (supplier != null) {
                  itemMap['supplier_name'] = supplier['name'];
                }
              } else {
                // Product has no supplier
                itemMap['supplier_id'] = null;
                itemMap['supplier_name'] = null;
              }
            }
          } catch (e) {
            debugPrint('⚠️ Error fetching product $productId: $e');
            // Keep the cached data from smart_purchase_list
          }
        }
        
        enrichedItems.add(itemMap);
      }
      
      _items = enrichedItems
          .map((json) => SmartPurchaseListItem.fromJson(json))
          .toList();

      // Apply supplier filter in memory (after enrichment with fresh data)
      if (supplierFilter != null && supplierFilter != 'all') {
        if (supplierFilter == 'none' || supplierFilter == '') {
          // Filter for products with no supplier
          _items = _items.where((item) => item.supplierId == null).toList();
        } else {
          // Filter by specific supplier
          _items = _items.where((item) => item.supplierId == supplierFilter).toList();
        }
      }

      // Apply search filter in memory (for product name/SKU)
      if (searchQuery.isNotEmpty) {
        final lowerQuery = searchQuery.toLowerCase();
        _items = _items.where((item) {
          return item.productName.toLowerCase().contains(lowerQuery) ||
              (item.productSku?.toLowerCase().contains(lowerQuery) ?? false);
        }).toList();
      }

      debugPrint('✅ Loaded ${_items.length} items from smart_purchase_list (after filters)');
      _error = null;
    } catch (e) {
      _error = 'Error loading purchase list: $e';
      debugPrint('❌ $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Auto-add product to purchase list when stock is low
  Future<bool> checkAndAddLowStockProduct(String productId) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return false;

      // Check if product exists in list already (any active status)
      final existing = await _client
          .from('smart_purchase_list')
          .select()
          .eq('tenant_id', tenantId)
          .eq('product_id', productId)
          .inFilter('status', ['pending', 'ordered', 'received'])
          .maybeSingle();

      if (existing != null) {
        debugPrint('⚠️ Product already in purchase list (${existing['status']}): $productId');
        return false; // Already in list
      }

      // Get product details
      final product = await _client
          .from('products')
          .select('''
            *,
            suppliers(id, name)
          ''')
          .eq('tenant_id', tenantId)
          .eq('id', productId)
          .single();

      final currentStock = product['stock_quantity'] as int? ?? 0;
      final minStock = product['min_stock_level'] as int? ?? 0;

      debugPrint('📦 Product: ${product['name']} | Stock: $currentStock / $minStock');

      // Only add if below minimum
      if (currentStock > minStock) {
        debugPrint('⏭️ Skipping ${product['name']} - stock sufficient ($currentStock > $minStock)');
        return false;
      }

      // Calculate smart metrics
      final metrics = await _calculateProductMetrics(productId, tenantId);

      // Calculate suggested quantity
      final suggestedQty = _calculateSuggestedQuantity(
        currentStock: currentStock,
        minStock: minStock,
        maxStock: product['max_stock_level'] as int? ?? 100,
        avgDailyConsumption: metrics['avgDailyConsumption'],
        leadTimeDays: product['lead_time_days'] as int? ?? 0,
      );

      // Calculate priority
      final priority = _calculatePriority(
        currentStock: currentStock,
        minStock: minStock,
        rotationKpi: metrics['rotationKpi'],
        daysSinceLastPurchase: metrics['daysSinceLastPurchase'],
        leadTimeDays: product['lead_time_days'] as int? ?? 0,
      );

      final supplier = product['suppliers'] as Map<String, dynamic>?;

      final data = {
        'product_id': productId,
        'product_name': product['name'],
        'product_sku': product['sku'],
        'supplier_id': supplier?['id'],
        'supplier_name': supplier?['name'],
        'suggested_quantity': suggestedQty,
        'status': 'pending',
        'priority': priority,
        'rotation_kpi': metrics['rotationKpi'],
        'days_since_last_purchase': metrics['daysSinceLastPurchase'],
        'current_stock': currentStock,
        'min_stock_level': minStock,
        'avg_daily_consumption': metrics['avgDailyConsumption'],
        'lead_time_days': product['lead_time_days'] ?? 0,
        'estimated_stockout_date': metrics['estimatedStockoutDate'],
        'added_by': _client.auth.currentUser?.id,
        'added_date': DateTime.now().toIso8601String(),
      };

      await _db.insert('smart_purchase_list', data);
      debugPrint('✅ Auto-added product to purchase list: ${product['name']}');
      
      await loadItems(); // Reload list
      return true; // Successfully added
    } catch (e) {
      debugPrint('❌ Error auto-adding product: $e');
      return false;
    }
  }

  /// Manually add item to purchase list (for ad-hoc items)
  Future<void> addItem({
    String? productId,
    required String productName,
    String? productSku,
    String? supplierId,
    String? supplierName,
    required int quantity,
    String? notes,
  }) async {
    try {
      final data = {
        'product_id': productId,
        'product_name': productName,
        'product_sku': productSku,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'suggested_quantity': quantity,
        'status': 'pending',
        'priority': 50.0, // Default priority for manual additions
        'current_stock': 0,
        'min_stock_level': 0,
        'lead_time_days': 0,
        'notes': notes,
        'added_by': _client.auth.currentUser?.id,
        'added_date': DateTime.now().toIso8601String(),
      };

      await _db.insert('smart_purchase_list', data);
      await loadItems();
    } catch (e) {
      _error = 'Error adding item: $e';
      debugPrint('❌ $_error');
      notifyListeners();
    }
  }

  /// Update item
  Future<void> updateItem(String itemId, Map<String, dynamic> updates) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant ID');

      updates['updated_at'] = DateTime.now().toIso8601String();

      await _client
          .from('smart_purchase_list')
          .update(updates)
          .eq('id', itemId)
          .eq('tenant_id', tenantId);

      await loadItems();
    } catch (e) {
      _error = 'Error updating item: $e';
      debugPrint('❌ $_error');
      notifyListeners();
    }
  }

  /// Delete item
  Future<void> deleteItem(String itemId) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant ID');

      await _client
          .from('smart_purchase_list')
          .delete()
          .eq('id', itemId)
          .eq('tenant_id', tenantId);

      await loadItems();
    } catch (e) {
      _error = 'Error deleting item: $e';
      debugPrint('❌ $_error');
      notifyListeners();
    }
  }

  /// Delete ALL items (for cleanup/reset)
  Future<void> deleteAllItems() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant ID');

      // Delete all items for this tenant
      await _client
          .from('smart_purchase_list')
          .delete()
          .eq('tenant_id', tenantId)
          .neq('id', '00000000-0000-0000-0000-000000000000'); // Match all records

      _items = [];
      notifyListeners();
      
      debugPrint('🧹 Deleted all items from smart purchase list');
    } catch (e) {
      _error = 'Error deleting all items: $e';
      debugPrint('❌ $_error');
      notifyListeners();
      rethrow;
    }
  }

  /// Mark item as ordered and link to purchase invoice
  Future<void> markAsOrdered(String itemId, String purchaseInvoiceId) async {
    await updateItem(itemId, {
      'status': 'ordered',
      'linked_purchase_invoice_id': purchaseInvoiceId,
      'ordered_date': DateTime.now().toIso8601String(),
    });
  }

  /// Mark item as received
  Future<void> markAsReceived(String itemId) async {
    await updateItem(itemId, {
      'status': 'received',
      'received_date': DateTime.now().toIso8601String(),
    });
  }

  /// Mark item as ignored
  Future<void> markAsIgnored(String itemId) async {
    await updateItem(itemId, {
      'status': 'ignored',
    });
  }

  /// Get items grouped by supplier
  Map<String, List<SmartPurchaseListItem>> getItemsBySupplier({bool pendingOnly = true}) {
    final filteredItems = pendingOnly
        ? _items.where((i) => i.isPending).toList()
        : _items;

    final Map<String, List<SmartPurchaseListItem>> grouped = {};
    
    for (var item in filteredItems) {
      final supplier = item.supplierName ?? 'Sin proveedor';
      grouped.putIfAbsent(supplier, () => []).add(item);
    }

    return grouped;
  }

  /// Get list of items for a specific supplier (for creating purchase order)
  List<SmartPurchaseListItem> getItemsForSupplier(String supplierId) {
    return _items
        .where((i) => i.supplierId == supplierId && i.isPending)
        .toList();
  }

  /// Scan all products and auto-add low stock items
  Future<ScanResult> scanAndAddLowStockProducts() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return ScanResult(added: 0, removed: 0);

      // Get all existing products in purchase list (pending status only for cleanup)
      final existingPendingItems = await _client
          .from('smart_purchase_list')
          .select('id, product_id')
          .eq('tenant_id', tenantId)
          .eq('status', 'pending');
      
      // Get all existing products in purchase list (all active statuses to avoid duplicates)
      final allExistingItems = await _client
          .from('smart_purchase_list')
          .select('product_id')
          .eq('tenant_id', tenantId)
          .inFilter('status', ['pending', 'ordered', 'received']);
      
      final existingIds = <String>{};
      for (var row in allExistingItems) {
        final productId = row['product_id'];
        if (productId != null) {
          existingIds.add(productId.toString());
        }
      }

      // Get all active products with their stock levels
      // We need to filter in Dart since Supabase doesn't support column-to-column comparison
      final allProducts = await _client
          .from('products')
          .select('id, stock_quantity, min_stock_level')
          .eq('tenant_id', tenantId)
          .eq('is_active', true);

      // Create a map for quick product lookup
      final productMap = <String, Map<String, dynamic>>{};
      for (var product in allProducts) {
        final productId = product['id']?.toString();
        if (productId != null) {
          productMap[productId] = product;
        }
      }

      // 1. CLEANUP: Remove pending items that now have sufficient stock
      int removedCount = 0;
      for (var item in existingPendingItems) {
        final productId = item['product_id']?.toString();
        if (productId == null) continue;
        
        final product = productMap[productId];
        if (product != null) {
          final stockQty = product['stock_quantity'] as int? ?? 0;
          final minStock = product['min_stock_level'] as int? ?? 0;
          
          // Remove if stock is now above minimum (no longer needed)
          if (stockQty > minStock) {
            await _client
                .from('smart_purchase_list')
                .delete()
                .eq('id', item['id'])
                .eq('tenant_id', tenantId);
            removedCount++;
            debugPrint('🧹 Removed item from list (stock now sufficient): ${item['id']}');
          }
        }
      }

      // 2. ADD: Find products with low stock that aren't in the list yet
      final lowStockProducts = (allProducts as List).where((product) {
        final productId = product['id']?.toString();
        final stockQty = product['stock_quantity'] as int? ?? 0;
        final minStock = product['min_stock_level'] as int? ?? 0;
        
        // Skip if already in purchase list (any status)
        if (productId != null && existingIds.contains(productId)) {
          return false;
        }
        
        return stockQty <= minStock;
      }).toList();

      int addedCount = 0;
      for (var product in lowStockProducts) {
        final wasAdded = await checkAndAddLowStockProduct(product['id']);
        if (wasAdded) {
          addedCount++;
        }
      }

      if (removedCount > 0) {
        debugPrint('🧹 Cleaned up $removedCount items with sufficient stock');
      }
      debugPrint('✅ Scanned: added $addedCount, removed $removedCount');
      
      // Don't call loadItems() here - let the UI handle it to avoid render cycle issues
      return ScanResult(added: addedCount, removed: removedCount);
    } catch (e) {
      debugPrint('❌ Error scanning products: $e');
      return ScanResult(added: 0, removed: 0);
    }
  }

  /// Calculate product metrics for smart suggestions
  Future<Map<String, dynamic>> _calculateProductMetrics(
    String productId,
    String tenantId,
  ) async {
    try {
      // Get sales history for last 90 days
      final salesHistory = await _client
          .from('sales_invoices')
          .select('items')
          .eq('tenant_id', tenantId)
          .gte('date', DateTime.now().subtract(const Duration(days: 90)).toIso8601String());

      int totalSold = 0;
      for (var invoice in salesHistory) {
        final items = invoice['items'] as List?;
        if (items != null) {
          for (var item in items) {
            if (item['product_id'] == productId) {
              totalSold += (item['quantity'] as int? ?? 0);
            }
          }
        }
      }

      final avgDailyConsumption = totalSold / 90.0;
      final rotationKpi = avgDailyConsumption; // Sales per day

      // Get last purchase date
      final lastPurchase = await _client
          .from('purchase_invoices')
          .select('date')
          .eq('tenant_id', tenantId)
          .contains('items', [{'product_id': productId}])
          .order('date', ascending: false)
          .limit(1)
          .maybeSingle();

      int? daysSinceLastPurchase;
      if (lastPurchase != null) {
        final lastDate = DateTime.parse(lastPurchase['date']);
        daysSinceLastPurchase = DateTime.now().difference(lastDate).inDays;
      }

      // Get current stock
      final product = await _client
          .from('products')
          .select('stock_quantity')
          .eq('id', productId)
          .single();

      final currentStock = product['stock_quantity'] as int? ?? 0;

      // Calculate estimated stockout date
      String? estimatedStockoutDate;
      if (avgDailyConsumption > 0) {
        final daysUntilStockout = currentStock / avgDailyConsumption;
        estimatedStockoutDate = DateTime.now()
            .add(Duration(days: daysUntilStockout.ceil()))
            .toIso8601String();
      }

      return {
        'avgDailyConsumption': avgDailyConsumption,
        'rotationKpi': rotationKpi,
        'daysSinceLastPurchase': daysSinceLastPurchase,
        'estimatedStockoutDate': estimatedStockoutDate,
      };
    } catch (e) {
      debugPrint('❌ Error calculating metrics: $e');
      return {
        'avgDailyConsumption': 0.0,
        'rotationKpi': 0.0,
        'daysSinceLastPurchase': null,
        'estimatedStockoutDate': null,
      };
    }
  }

  /// Calculate suggested restock quantity
  int _calculateSuggestedQuantity({
    required int currentStock,
    required int minStock,
    required int maxStock,
    required double avgDailyConsumption,
    required int leadTimeDays,
  }) {
    // Safety stock = average consumption during lead time * 1.5 (buffer)
    final safetyStock = (avgDailyConsumption * leadTimeDays * 1.5).ceil();
    
    // Suggested quantity = max stock - current stock + safety stock
    final suggested = maxStock - currentStock + safetyStock;
    
    // Minimum suggestion should at least restore to min stock level
    final minimum = minStock - currentStock;
    
    return suggested > minimum ? suggested : minimum.clamp(1, 10000);
  }

  /// Calculate priority score (0-100)
  double _calculatePriority({
    required int currentStock,
    required int minStock,
    required double rotationKpi,
    required int? daysSinceLastPurchase,
    required int leadTimeDays,
  }) {
    // Base score: Stock level urgency (40%)
    final stockUrgency = currentStock == 0
        ? 40.0
        : (1 - (currentStock / minStock).clamp(0, 1)) * 40;

    // Rotation factor (30%)
    final rotationFactor = rotationKpi.clamp(0, 10) * 3; // Max 30 points

    // Lead time urgency (20%)
    final leadTimeUrgency = leadTimeDays > 0
        ? (1 - (currentStock / (rotationKpi * leadTimeDays + 1)).clamp(0, 1)) * 20
        : 10.0;

    // Time since last purchase (10%)
    final timeFactor = daysSinceLastPurchase != null && daysSinceLastPurchase > 30
        ? ((daysSinceLastPurchase - 30) / 60 * 10).clamp(0, 10)
        : 0.0;

    final priority = (stockUrgency + rotationFactor + leadTimeUrgency + timeFactor)
        .clamp(0, 100);

    return double.parse(priority.toStringAsFixed(2));
  }
}
