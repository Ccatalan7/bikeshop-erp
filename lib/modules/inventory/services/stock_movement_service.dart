import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/stock_movement.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';

class StockMovementService extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final TenantService _tenantService = TenantService();
  final String _tableName = 'stock_movements';

  List<StockMovement> _movements = [];
  bool _isLoading = false;
  String? _error;
  
  // Realtime channels
  RealtimeChannel? _movementsChannel;
  RealtimeChannel? _adjustmentsChannel;

  List<StockMovement> get movements => List.unmodifiable(_movements);
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  StockMovementService() {
    _setupRealtime();
  }
  
  /// Setup realtime subscriptions for multi-user collaboration
  Future<void> _setupRealtime() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        debugPrint('⚠️ [StockMovementService] Cannot setup realtime: no tenant_id');
        return;
      }
      
      debugPrint('🔔 [StockMovementService] Setting up realtime for tenant: $tenantId');
      
      // Subscribe to stock_movements table changes
      _movementsChannel = Supabase.instance.client
          .channel('stock_movements_list_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'stock_movements',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              debugPrint('🔔 [StockMovementService] Movement changed: ${payload.eventType}');
              loadMovements(forceRefresh: true);
            },
          )
          .subscribe();
      
      // Subscribe to stock_adjustments table changes
      _adjustmentsChannel = Supabase.instance.client
          .channel('stock_adjustments_list_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'stock_adjustments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              debugPrint('🔔 [StockMovementService] Adjustment changed: ${payload.eventType}');
              loadMovements(forceRefresh: true);
            },
          )
          .subscribe();
      
      debugPrint('✅ [StockMovementService] Realtime subscriptions active');
    } catch (e) {
      debugPrint('❌ [StockMovementService] Realtime setup error: $e');
    }
  }

  /// Load all stock movements with optional filters
  Future<void> loadMovements({
    String? productId,
    String? productSku,
    DateTime? startDate,
    DateTime? endDate,
    String? movementType,
    String? searchQuery,
    bool forceRefresh = false,
  }) async {
    if (_isLoading && !forceRefresh) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }
      
      var query = Supabase.instance.client
          .from(_tableName)
          .select()
          .eq('tenant_id', tenantId);  // ⚠️ CRITICAL: Filter by tenant

      if (productId != null) {
        query = query.eq('product_id', productId);
      }

      if (startDate != null) {
        query = query.gte('date', startDate.toIso8601String());
      }

      if (endDate != null) {
        query = query.lte('date', endDate.toIso8601String());
      }

      if (movementType != null && movementType.isNotEmpty) {
        query = query.eq('movement_type', movementType);
      }

      final response = await query
          .order('date', ascending: false)
          .order('created_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;

      _movements = await _enrichMovements(data);

      // Apply search filter if provided
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final lowerQuery = searchQuery.toLowerCase();
        _movements = _movements.where((movement) {
          return movement.productName.toLowerCase().contains(lowerQuery) ||
              movement.productSku.toLowerCase().contains(lowerQuery) ||
              (movement.reference?.toLowerCase().contains(lowerQuery) ??
                  false) ||
              (movement.notes?.toLowerCase().contains(lowerQuery) ?? false);
        }).toList();
      }

      _error = null;
      debugPrint('✅ [StockMovementService] Loaded ${_movements.length} movements');
    } catch (e) {
      _error = 'Error al cargar movimientos: $e';
      debugPrint('❌ [StockMovementService] loadMovements error: $e');
      _movements = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Enrich movements with product information
  Future<List<StockMovement>> _enrichMovements(List<dynamic> data) async {
    final movements = <StockMovement>[];

    for (final item in data) {
      try {
        // Get product info
        String? productName;
        String? productSku;

        if (item['product_id'] != null) {
          final productResponse = await Supabase.instance.client
              .from('products')
              .select('name, sku')
              .eq('id', item['product_id'])
              .maybeSingle();

          if (productResponse != null) {
            productName = productResponse['name'] as String?;
            productSku = productResponse['sku'] as String?;
          }
        }

        movements.add(StockMovement(
          id: item['id'] as String,
          productId: item['product_id'] as String? ?? '',
          productSku: productSku ?? 'N/A',
          productName: productName ?? 'Producto desconocido',
          type: item['type'] as String? ?? 'OUT',
          movementType: item['movement_type'] as String?,
          quantity: (item['quantity'] as num?)?.toDouble() ?? 0.0,
          reference: item['reference'] as String?,
          notes: item['notes'] as String?,
          warehouseId: item['warehouse_id'] as String?,
          date: item['date'] != null
              ? DateTime.parse(item['date'] as String)
              : DateTime.now(),
          createdAt: DateTime.parse(item['created_at'] as String),
        ));
      } catch (e) {
        debugPrint('Error parsing movement: $e');
        continue;
      }
    }

    return movements;
  }

  /// Get movements for a specific product
  Future<List<StockMovement>> getProductMovements(String productId) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }
      
      final response = await Supabase.instance.client
          .from(_tableName)
          .select()
          .eq('tenant_id', tenantId)  // ⚠️ Filter by tenant
          .eq('product_id', productId)
          .order('date', ascending: false)
          .order('created_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;
      return await _enrichMovements(data);
    } catch (e) {
      debugPrint('❌ [StockMovementService] Error getting product movements: $e');
      return [];
    }
  }

  /// Create a manual adjustment
  Future<StockMovement?> createAdjustment({
    required String productId,
    required double quantity,
    required String type, // 'IN' or 'OUT'
    String? notes,
    String? warehouseId,
  }) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }
      
      // Get current inventory
      final product = await Supabase.instance.client
          .from('products')
          .select('inventory_qty, stock_quantity, name, sku')
          .eq('tenant_id', tenantId)  // ⚠️ Filter by tenant
          .eq('id', productId)
          .single();

      final currentQty = (product['inventory_qty'] as num?)?.toDouble() ?? 0;
      final adjustedQty = type == 'IN' ? quantity : -quantity;

      // Create movement using DatabaseService (auto-injects tenant_id)
      final movementData = {
        'product_id': productId,
        'warehouse_id': warehouseId,
        'type': type,
        'movement_type': 'adjustment',
        'quantity': adjustedQty,
        'reference': 'Ajuste manual',
        'notes': notes,
        'date': DateTime.now().toIso8601String(),
      };

      final response = await _databaseService.insert(_tableName, movementData);

      // Update product inventory (BOTH columns!)
      await Supabase.instance.client.from('products').update({
        'inventory_qty': currentQty + adjustedQty,
        'stock_quantity': currentQty + adjustedQty,  // Update both columns
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('tenant_id', tenantId).eq('id', productId);

      // Reload movements
      await loadMovements(forceRefresh: true);

      return StockMovement(
        id: response['id'] as String,
        productId: productId,
        productSku: product['sku'] as String,
        productName: product['name'] as String,
        type: type,
        movementType: 'adjustment',
        quantity: adjustedQty,
        reference: 'Ajuste manual',
        notes: notes,
        warehouseId: warehouseId,
        date: DateTime.now(),
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('❌ [StockMovementService] Error creating adjustment: $e');
      _error = 'Error al crear ajuste: $e';
      notifyListeners();
      return null;
    }
  }

  /// Get movement statistics
  Future<Map<String, dynamic>> getStatistics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }
      
      var query = Supabase.instance.client
          .from(_tableName)
          .select()
          .eq('tenant_id', tenantId);  // ⚠️ Filter by tenant

      if (startDate != null) {
        query = query.gte('date', startDate.toIso8601String());
      }

      if (endDate != null) {
        query = query.lte('date', endDate.toIso8601String());
      }

      final response = await query;
      final List<dynamic> data = response as List<dynamic>;

      int totalIn = 0;
      int totalOut = 0;
      int totalAdjustments = 0;
      Map<String, int> byType = {};

      for (final item in data) {
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final type = item['type'] as String? ?? 'OUT';
        final movementType = item['movement_type'] as String?;

        if (type == 'IN') {
          totalIn += qty.abs();
        } else {
          totalOut += qty.abs();
        }

        if (movementType != null) {
          byType[movementType] = (byType[movementType] ?? 0) + 1;
          if (movementType == 'adjustment') {
            totalAdjustments++;
          }
        }
      }

      return {
        'total_movements': data.length,
        'total_in': totalIn,
        'total_out': totalOut,
        'total_adjustments': totalAdjustments,
        'by_type': byType,
      };
    } catch (e) {
      debugPrint('❌ [StockMovementService] Error getting statistics: $e');
      return {
        'total_movements': 0,
        'total_in': 0,
        'total_out': 0,
        'total_adjustments': 0,
        'by_type': {},
      };
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
  
  @override
  void dispose() {
    _movementsChannel?.unsubscribe();
    _adjustmentsChannel?.unsubscribe();
    super.dispose();
  }
}
