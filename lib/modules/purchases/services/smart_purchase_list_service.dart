import 'dart:async';
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
  // Singleton pattern - persists across app lifecycle
  static final SmartPurchaseListService _instance = SmartPurchaseListService._internal();
  factory SmartPurchaseListService() => _instance;
  SmartPurchaseListService._internal();

  final DatabaseService _db = DatabaseService();
  final TenantService _tenantService = TenantService();
  final SupabaseClient _client = Supabase.instance.client;

  List<SmartPurchaseListItem> _items = [];
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _error;
  
  // Real-time subscriptions
  RealtimeChannel? _purchaseListChannel;
  RealtimeChannel? _productsChannel;
  
  // Debounce timer for bulk operations
  Timer? _debounceTimer;
  
  // Pause realtime updates during bulk operations
  bool _pauseRealtime = false;
  
  // Cache for enriched product data (product_id → product details)
  final Map<String, Map<String, dynamic>> _productCache = {};
  
  // Timestamp of last full sync
  DateTime? _lastFullSync;

  List<SmartPurchaseListItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _isInitialized;

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
  
  /// Initialize service with real-time listeners (call once on app start or page mount)
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚡ SmartPurchaseListService already initialized - using cached data (0ms)');
      return;
    }
    
    final initStartTime = DateTime.now();
    debugPrint('⏱️ [PERF] Starting Smart Purchase List initialization...');
    
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final tenantStartTime = DateTime.now();
      final tenantId = await _tenantService.getTenantId();
      final tenantDuration = DateTime.now().difference(tenantStartTime).inMilliseconds;
      debugPrint('⏱️ [PERF] Got tenant ID in ${tenantDuration}ms');
      
      if (tenantId == null) {
        throw Exception('No tenant ID found');
      }

      // 1. Initial load - fetch base data WITHOUT per-item enrichment
      final dataStartTime = DateTime.now();
      await _loadBaseData(tenantId);
      final dataDuration = DateTime.now().difference(dataStartTime).inMilliseconds;
      debugPrint('⏱️ [PERF] Loaded base data in ${dataDuration}ms');
      
      // 2. Set up real-time listeners for incremental updates
      final listenerStartTime = DateTime.now();
      _setupRealtimeListeners(tenantId);
      final listenerDuration = DateTime.now().difference(listenerStartTime).inMilliseconds;
      debugPrint('⏱️ [PERF] Set up realtime listeners in ${listenerDuration}ms');
      
      _isInitialized = true;
      _lastFullSync = DateTime.now();
      
      final totalDuration = DateTime.now().difference(initStartTime).inMilliseconds;
      debugPrint('✅ [PERF] TOTAL INITIALIZATION TIME: ${totalDuration}ms (${_items.length} items)');
      debugPrint('   ├─ Tenant ID fetch: ${tenantDuration}ms');
      debugPrint('   ├─ Database query: ${dataDuration}ms');
      debugPrint('   ├─ Realtime setup: ${listenerDuration}ms');
      debugPrint('   └─ Last sync: ${_lastFullSync}');
    } catch (e) {
      _error = 'Error initializing service: $e';
      debugPrint('❌ $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
      
      final notifyDuration = DateTime.now().difference(initStartTime).inMilliseconds;
      debugPrint('⏱️ [PERF] UI notified after ${notifyDuration}ms');
    }
  }
  
  /// Load base data from smart_purchase_list (fast, no enrichment)
  Future<void> _loadBaseData(String tenantId) async {
    final queryStartTime = DateTime.now();
    
    // PERFORMANCE: Only load pending items on initial load (default view)
    // Other statuses will load on-demand when user changes filter
    final response = await _client
        .from('smart_purchase_list')
        .select('''
          *,
          products!smart_purchase_list_product_id_fkey(
            category_id,
            product_categories!products_category_id_fkey(
              id,
              name,
              full_path
            )
          )
        ''')
        .eq('tenant_id', tenantId)
        .eq('status', 'pending') // Only load pending items initially
        .order('priority', ascending: false)
        .order('added_date', ascending: false);
    
    final queryDuration = DateTime.now().difference(queryStartTime).inMilliseconds;
    debugPrint('⏱️ [PERF]   ├─ Supabase query executed in ${queryDuration}ms');
    
    final parseStartTime = DateTime.now();
    final items = response as List<dynamic>;
    
    _items = items
        .map((json) => SmartPurchaseListItem.fromJson(json))
        .toList();
    
    final parseDuration = DateTime.now().difference(parseStartTime).inMilliseconds;
    debugPrint('⏱️ [PERF]   └─ Parsed ${_items.length} items in ${parseDuration}ms');
  }
  
  /// Set up Supabase Realtime listeners for automatic updates
  void _setupRealtimeListeners(String tenantId) {
    // Unsubscribe from previous channels if any
    _purchaseListChannel?.unsubscribe();
    _productsChannel?.unsubscribe();
    
    debugPrint('🔌 Setting up Realtime listeners for tenant: $tenantId');
    
    // Listen to smart_purchase_list changes
    _purchaseListChannel = _client
        .channel('smart_purchase_list_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'smart_purchase_list',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) => _handlePurchaseListChange(payload),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            debugPrint('✅ Subscribed to smart_purchase_list changes');
          } else if (status == RealtimeSubscribeStatus.channelError) {
            debugPrint('❌ Failed to subscribe to smart_purchase_list: $error');
          }
        });
    
    // Listen to products table changes (for stock updates)
    _productsChannel = _client
        .channel('products_stock_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'products',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) => _handleProductStockChange(payload),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            debugPrint('✅ Subscribed to products stock changes');
          } else if (status == RealtimeSubscribeStatus.channelError) {
            debugPrint('❌ Failed to subscribe to products: $error');
          }
        });
    
    debugPrint('🔔 Real-time listeners setup complete');
  }
  
  /// Handle real-time changes to smart_purchase_list table
  void _handlePurchaseListChange(PostgresChangePayload payload) {
    // Skip realtime updates during bulk operations
    if (_pauseRealtime) {
      debugPrint('⏸️ [REALTIME] Paused - skipping update');
      return;
    }
    
    debugPrint('🔔 [REALTIME] Purchase list change detected! (Page may be closed)');
    debugPrint('   Event Type: ${payload.eventType}');
    debugPrint('   Current items count: ${_items.length}');
    
    try {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
          final newItem = SmartPurchaseListItem.fromJson(payload.newRecord);
          _items.insert(0, newItem); // Add to top (highest priority)
          debugPrint('➕ [REALTIME] Added item: ${newItem.productName} (${newItem.productSku})');
          debugPrint('   Total items now: ${_items.length}');
          break;
          
        case PostgresChangeEvent.update:
          final updatedItem = SmartPurchaseListItem.fromJson(payload.newRecord);
          final index = _items.indexWhere((i) => i.id == updatedItem.id);
          if (index >= 0) {
            _items[index] = updatedItem;
            debugPrint('🔄 [REALTIME] Updated item: ${updatedItem.productName} at index $index');
          } else {
            debugPrint('⚠️ [REALTIME] Item not found for update: ${updatedItem.id}');
          }
          break;
          
        case PostgresChangeEvent.delete:
          final deletedId = payload.oldRecord['id'] as String;
          final beforeCount = _items.length;
          _items.removeWhere((i) => i.id == deletedId);
          final afterCount = _items.length;
          debugPrint('➖ [REALTIME] Removed item: $deletedId');
          debugPrint('   Items before: $beforeCount, after: $afterCount');
          break;
          
        default:
          debugPrint('⚠️ [REALTIME] Unknown event type: ${payload.eventType}');
          break;
      }
      
      debugPrint('📢 [REALTIME] Scheduling debounced notify... (${_items.length} items total)');
      _debouncedNotify();
      debugPrint('✅ [REALTIME] Notify scheduled - data persisted in singleton');
    } catch (e, stackTrace) {
      debugPrint('❌ [REALTIME] Error handling purchase list change: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }
  
  /// Debounced notify to batch rapid updates (e.g., bulk operations)
  void _debouncedNotify() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      debugPrint('🔔 [DEBOUNCE] Notifying listeners now');
      notifyListeners();
    });
  }
  
  /// Handle real-time stock changes in products table
  void _handleProductStockChange(PostgresChangePayload payload) {
    debugPrint('📦 [REALTIME] Product stock change detected!');
    
    final productId = payload.newRecord['id'] as String?;
    if (productId == null) {
      debugPrint('⚠️ [REALTIME] No product ID in payload');
      return;
    }
    
    final newStock = payload.newRecord['stock_quantity'] as int? ?? 0;
    final minStock = payload.newRecord['min_stock_level'] as int? ?? 0;
    final productName = payload.newRecord['name'] as String? ?? 'Unknown';
    
    debugPrint('   Product: $productName ($productId)');
    debugPrint('   Stock: $newStock, Min: $minStock');
    
    // Update cache
    _productCache[productId] = payload.newRecord;
    
    // If stock is now above minimum, remove pending items for this product
    if (newStock > minStock) {
      debugPrint('   ✓ Stock is above minimum - checking for items to remove...');
      final removed = _items.where((i) => i.productId == productId && i.status == 'pending').toList();
      if (removed.isNotEmpty) {
        final beforeCount = _items.length;
        _items.removeWhere((i) => i.productId == productId && i.status == 'pending');
        final afterCount = _items.length;
        
        for (var item in removed) {
          debugPrint('🗑️ [REALTIME] Auto-removed item: ${item.productName} (${item.productSku})');
          debugPrint('   Reason: Stock restored ($newStock > $minStock)');
        }
        debugPrint('   Items before: $beforeCount, after: $afterCount');
        debugPrint('📢 [REALTIME] Notifying listeners...');
        notifyListeners();
        debugPrint('✅ [REALTIME] Listeners notified');
        return; // Exit early, no need to update
      } else {
        debugPrint('   ℹ️ No pending items found for this product');
      }
    } else {
      debugPrint('   ℹ️ Stock still at/below minimum - no removal needed');
    }
    
    // Update any items using this product (if still in list)
    bool updated = false;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].productId == productId) {
        final item = _items[i];
        _items[i] = SmartPurchaseListItem(
          id: item.id,
          productId: item.productId,
          productName: payload.newRecord['name'] ?? item.productName,
          productSku: payload.newRecord['sku'] ?? item.productSku,
          supplierId: item.supplierId,
          supplierName: item.supplierName,
          suggestedQuantity: item.suggestedQuantity,
          actualQuantity: item.actualQuantity,
          status: item.status,
          priority: item.priority,
          rotationKpi: item.rotationKpi,
          daysSinceLastPurchase: item.daysSinceLastPurchase,
          currentStock: newStock,
          minStockLevel: minStock,
          stockAtOrder: item.stockAtOrder,
          stockAtReceipt: item.stockAtReceipt,
          avgDailyConsumption: item.avgDailyConsumption,
          leadTimeDays: item.leadTimeDays,
          estimatedStockoutDate: item.estimatedStockoutDate,
          notes: item.notes,
          addedBy: item.addedBy,
          addedDate: item.addedDate,
          orderedDate: item.orderedDate,
          receivedDate: item.receivedDate,
          linkedPurchaseInvoiceId: item.linkedPurchaseInvoiceId,
          linkedExpenseId: item.linkedExpenseId,
          createdAt: item.createdAt,
          updatedAt: DateTime.now(), // Mark as updated
        );
        updated = true;
        debugPrint('📦 Updated stock for ${item.productName}: $newStock / $minStock');
      }
    }
    
    if (updated) {
      notifyListeners();
    }
  }

  /// Load items with filters (uses cached data + in-memory filtering)
  Future<void> loadItems({
    String? statusFilter,
    String? supplierFilter,
    String searchQuery = '',
  }) async {
    // If not initialized, do full initialization
    if (!_isInitialized) {
      await initialize();
      return;
    }
    
    // If status filter changed, fetch new data from database
    if (statusFilter != null && statusFilter != 'all') {
      debugPrint('📥 Loading items for status: $statusFilter');
      _isLoading = true;
      notifyListeners();
      
      try {
        final tenantId = await _tenantService.getTenantId();
        if (tenantId == null) return;
        
        final response = await _client
            .from('smart_purchase_list')
            .select('''
              *,
              products!smart_purchase_list_product_id_fkey(
                category_id,
                product_categories!products_category_id_fkey(
                  id,
                  name,
                  full_path
                )
              )
            ''')
            .eq('tenant_id', tenantId)
            .eq('status', statusFilter)
            .order('priority', ascending: false)
            .order('added_date', ascending: false);
        
        final items = response as List<dynamic>;
        
        // Replace items with filtered results
        _items = items
            .map((json) => SmartPurchaseListItem.fromJson(json))
            .toList();
        
        debugPrint('✅ Loaded ${_items.length} items for status: $statusFilter');
      } catch (e) {
        debugPrint('❌ Error loading items: $e');
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    } else if (statusFilter == 'all') {
      // Load all items when "all" selected
      debugPrint('📥 Loading ALL items');
      _isLoading = true;
      notifyListeners();
      
      try {
        final tenantId = await _tenantService.getTenantId();
        if (tenantId == null) return;
        
        final response = await _client
            .from('smart_purchase_list')
            .select('''
              *,
              products!smart_purchase_list_product_id_fkey(
                category_id,
                product_categories!products_category_id_fkey(
                  id,
                  name,
                  full_path
                )
              )
            ''')
            .eq('tenant_id', tenantId)
            .order('priority', ascending: false)
            .order('added_date', ascending: false);
        
        final items = response as List<dynamic>;
        
        _items = items
            .map((json) => SmartPurchaseListItem.fromJson(json))
            .toList();
        
        debugPrint('✅ Loaded ${_items.length} total items');
      } catch (e) {
        debugPrint('❌ Error loading items: $e');
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    } else {
      // Just filter cached data for pending (already loaded)
      debugPrint('⚡ Using cached pending items (instant)');
      notifyListeners();
    }
  }
  
  /// Get filtered items (computed property for UI)
  List<SmartPurchaseListItem> getFilteredItems({
    String? statusFilter,
    String? supplierFilter,
    String? categoryFilter,
    String searchQuery = '',
  }) {
    var filtered = List<SmartPurchaseListItem>.from(_items);
    
    // Apply status filter
    if (statusFilter != null && statusFilter != 'all') {
      filtered = filtered.where((item) => item.status == statusFilter).toList();
    }
    
    // Apply supplier filter
    if (supplierFilter != null && supplierFilter != 'all') {
      if (supplierFilter == 'none' || supplierFilter == '') {
        filtered = filtered.where((item) => item.supplierId == null).toList();
      } else {
        filtered = filtered.where((item) => item.supplierId == supplierFilter).toList();
      }
    }
    
    // Apply category filter
    if (categoryFilter != null && categoryFilter != 'all') {
      if (categoryFilter == 'none' || categoryFilter == '') {
        filtered = filtered.where((item) => item.categoryId == null).toList();
      } else {
        filtered = filtered.where((item) => item.categoryId == categoryFilter).toList();
      }
    }
    
    // Apply search filter
    if (searchQuery.isNotEmpty) {
      final lowerQuery = searchQuery.toLowerCase();
      filtered = filtered.where((item) {
        return item.productName.toLowerCase().contains(lowerQuery) ||
            (item.productSku?.toLowerCase().contains(lowerQuery) ?? false);
      }).toList();
    }
    
    return filtered;
  }
  
  /// Force refresh (manual reload)
  Future<void> refresh() async {
    final refreshStartTime = DateTime.now();
    debugPrint('🔄 Force refresh requested');
    
    _isInitialized = false;
    _productCache.clear();
    await initialize();
    
    final refreshDuration = DateTime.now().difference(refreshStartTime).inMilliseconds;
    debugPrint('✅ [PERF] Refresh completed in ${refreshDuration}ms');
  }
  
  /// Clear all cached data (call on logout)
  void clearCache() {
    debugPrint('🗑️ Clearing Smart Purchase List cache');
    _isInitialized = false;
    _items.clear();
    _productCache.clear();
    _purchaseListChannel?.unsubscribe();
    _productsChannel?.unsubscribe();
    _purchaseListChannel = null;
    _productsChannel = null;
    _lastFullSync = null;
    notifyListeners();
  }
  
  /// Dispose and cleanup
  @override
  void dispose() {
    clearCache();

    super.dispose();
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

  /// Update item status (e.g., archive, unarchive)
  Future<void> updateStatus(String itemId, String status) async {
    await updateItem(itemId, {
      'status': status,
    });
  }

  /// Bulk update status for multiple items (optimized for performance)
  Future<void> bulkUpdateStatus(List<String> itemIds, String status) async {
    if (itemIds.isEmpty) return;
    
    try {
      debugPrint('🔄 Bulk updating ${itemIds.length} items to status: $status');
      
      // UNSUBSCRIBE from realtime to prevent event flood
      debugPrint('📴 Unsubscribing from realtime channels...');
      await _purchaseListChannel?.unsubscribe();
      await _productsChannel?.unsubscribe();
      
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant ID');

      // Single database query for all items - MUCH FASTER!
      await _client
          .from('smart_purchase_list')
          .update({'status': status})
          .inFilter('id', itemIds)
          .eq('tenant_id', tenantId);

      debugPrint('✅ Bulk update complete - refreshing data');
      
      // Reload items with the OPPOSITE status of what we just set
      // If we archived items, reload pending. If we unarchived, reload archived.
      final reloadStatus = status == 'archived' ? 'pending' : 'archived';
      
      final response = await _client
          .from('smart_purchase_list')
          .select('''
            *,
            products!smart_purchase_list_product_id_fkey(
              category_id,
              product_categories!products_category_id_fkey(
                id,
                name,
                full_path
              )
            )
          ''')
          .eq('tenant_id', tenantId)
          .eq('status', reloadStatus)
          .order('priority', ascending: false)
          .order('added_date', ascending: false);
      
      _items = (response as List<dynamic>)
          .map((json) => SmartPurchaseListItem.fromJson(json))
          .toList();
      
      debugPrint('✅ Reloaded ${_items.length} $reloadStatus items');
      
      // RESUBSCRIBE to realtime
      debugPrint('📡 Resubscribing to realtime channels...');
      _setupRealtimeListeners(tenantId);
      
      notifyListeners();
      debugPrint('✅ Bulk operation complete - realtime restored');
    } catch (e) {
      // Always try to restore realtime on error
      final tenantId = await _tenantService.getTenantId();
      if (tenantId != null) {
        _setupRealtimeListeners(tenantId);
      }
      _error = 'Error bulk updating items: $e';
      debugPrint('❌ $_error');
      notifyListeners();
      rethrow;
    }
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
