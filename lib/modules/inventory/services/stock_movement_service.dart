import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/stock_movement.dart';
import '../../../shared/services/database_service.dart';

class StockMovementService extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final String _tableName = 'stock_movements';

  List<StockMovement> _movements = [];
  bool _isLoading = false;
  String? _error;

  List<StockMovement> get movements => List.unmodifiable(_movements);
  bool get isLoading => _isLoading;
  String? get error => _error;

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
      var query = Supabase.instance.client.from(_tableName).select();

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
    } catch (e) {
      _error = 'Error al cargar movimientos: $e';
      debugPrint('StockMovementService.loadMovements error: $e');
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
      final response = await Supabase.instance.client
          .from(_tableName)
          .select()
          .eq('product_id', productId)
          .order('date', ascending: false)
          .order('created_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;
      return await _enrichMovements(data);
    } catch (e) {
      debugPrint('Error getting product movements: $e');
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
      // Get current inventory
      final product = await Supabase.instance.client
          .from('products')
          .select('inventory_qty, name, sku')
          .eq('id', productId)
          .single();

      final currentQty = (product['inventory_qty'] as num?)?.toDouble() ?? 0;
      final adjustedQty = type == 'IN' ? quantity : -quantity;

      // Create movement
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

      final response = await Supabase.instance.client
          .from(_tableName)
          .insert(movementData)
          .select()
          .single();

      // Update product inventory
      await Supabase.instance.client.from('products').update({
        'inventory_qty': currentQty + adjustedQty,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', productId);

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
      debugPrint('Error creating adjustment: $e');
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
      var query = Supabase.instance.client.from(_tableName).select();

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
      debugPrint('Error getting statistics: $e');
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
}
