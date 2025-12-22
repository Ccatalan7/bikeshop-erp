import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/stock_movement.dart';

class StockMovementsService extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  final _tenantService = TenantService();

  List<StockMovement> _movements = [];
  bool _isLoading = false;
  String? _error;
  String? _selectedProductId;

  // Realtime channels
  RealtimeChannel? _movementsChannel;
  RealtimeChannel? _adjustmentsChannel;

  List<StockMovement> get movements => _movements;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get selectedProductId => _selectedProductId;

  StockMovementsService() {
    _setupRealtime();
  }

  /// Setup realtime subscriptions for multi-user collaboration
  Future<void> _setupRealtime() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        debugPrint(
            '⚠️ [StockMovementsService] Cannot setup realtime: no tenant_id');
        return;
      }

      debugPrint(
          '🔔 [StockMovementsService] Setting up realtime for tenant: $tenantId');

      // Subscribe to stock_movements table changes
      _movementsChannel = _supabase
          .channel('stock_movements_changes')
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
              debugPrint(
                  '🔔 [StockMovementsService] Stock movement changed: ${payload.eventType}');
              // Reload if we have a product selected
              if (_selectedProductId != null) {
                loadMovementsForProduct(_selectedProductId!);
              }
            },
          )
          .subscribe();

      // Subscribe to stock_adjustments table changes
      _adjustmentsChannel = _supabase
          .channel('stock_adjustments_changes')
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
              debugPrint(
                  '🔔 [StockMovementsService] Stock adjustment changed: ${payload.eventType}');
              // Reload if we have a product selected
              if (_selectedProductId != null) {
                loadMovementsForProduct(_selectedProductId!);
              }
            },
          )
          .subscribe();

      debugPrint('✅ [StockMovementsService] Realtime subscriptions active');
    } catch (e) {
      debugPrint('❌ [StockMovementsService] Realtime setup error: $e');
    }
  }

  /// Load movements for a specific product
  Future<void> loadMovementsForProduct(String productId) async {
    _isLoading = true;
    _error = null;
    _selectedProductId = productId;
    notifyListeners();

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No tenant_id found');
      }

      // Query stock_movements_view with tenant_id filtering
      final response = await _supabase
          .from('stock_movements_view')
          .select()
          .eq('tenant_id', tenantId) // ⚠️ CRITICAL: Filter by tenant
          .eq('product_id', productId)
          .order('created_at',
              ascending:
                  false); // Order by actual creation time (UTC), not transaction_date

      _movements = (response as List)
          .map((json) => StockMovement.fromJson(json))
          .toList();

      _error = null;
      debugPrint(
          '✅ [StockMovementsService] Loaded ${_movements.length} movements for product $productId');
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ [StockMovementsService] Error loading stock movements: $e');
      _movements = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _movementsChannel?.unsubscribe();
    _adjustmentsChannel?.unsubscribe();
    super.dispose();
  }

  /// Clear selection
  void clearSelection() {
    _selectedProductId = null;
    _movements = [];
    notifyListeners();
  }

  /// Get movements list without modifying state (Pure Async)
  Future<List<StockMovement>> getMovementsList(String productId) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant_id');

      final response = await _supabase
          .from('stock_movements_view')
          .select()
          .eq('tenant_id', tenantId)
          .eq('product_id', productId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => StockMovement.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching movements list: $e');
      return [];
    }
  }

  /// Filter movements by date range
  List<StockMovement> filterByDateRange(
      DateTime? startDate, DateTime? endDate) {
    if (startDate == null && endDate == null) return _movements;

    return _movements.where((movement) {
      if (startDate != null && movement.transactionDate.isBefore(startDate)) {
        return false;
      }
      if (endDate != null && movement.transactionDate.isAfter(endDate)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Filter movements by type
  List<StockMovement> filterByType(String? type) {
    if (type == null || type == 'all') return _movements;
    return _movements.where((m) => m.movementType == type).toList();
  }

  /// Get summary statistics
  Map<String, int> getSummary() {
    int totalIncrease = 0;
    int totalDecrease = 0;

    for (var movement in _movements) {
      if (movement.isIncrease) {
        totalIncrease += movement.quantity;
      } else {
        totalDecrease += movement.quantity.abs();
      }
    }

    return {
      'total_increase': totalIncrease,
      'total_decrease': totalDecrease,
      'net_change': totalIncrease - totalDecrease,
      'transaction_count': _movements.length,
    };
  }
}
