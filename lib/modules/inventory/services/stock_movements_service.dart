import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/stock_movement.dart';

enum StockMovementsViewMode {
  recent,
  byProduct,
}

extension StockMovementsViewModeX on StockMovementsViewMode {
  String get key {
    switch (this) {
      case StockMovementsViewMode.recent:
        return 'recent';
      case StockMovementsViewMode.byProduct:
        return 'by_product';
    }
  }
}

class StockMovementsService extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  final _tenantService = TenantService();

  List<StockMovement> _movements = [];
  bool _isLoading = false;
  String? _error;
  String? _selectedProductId;

  // View mode: 'recent' (all products) or 'by_product' (single product)
  StockMovementsViewMode _viewMode = StockMovementsViewMode.recent;

  // Realtime channels
  RealtimeChannel? _movementsChannel;
  RealtimeChannel? _adjustmentsChannel;

  List<StockMovement> get movements => _movements;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get selectedProductId => _selectedProductId;
  String get viewMode => _viewMode.key;
  bool get isRecentMode => _viewMode == StockMovementsViewMode.recent;

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
              _reloadCurrentView();
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
              _reloadCurrentView();
            },
          )
          .subscribe();

      debugPrint('✅ [StockMovementsService] Realtime subscriptions active');
    } catch (e) {
      debugPrint('❌ [StockMovementsService] Realtime setup error: $e');
    }
  }

  /// Set view mode and load appropriate data
  void setViewMode(String mode) {
    final nextMode = mode == StockMovementsViewMode.byProduct.key
        ? StockMovementsViewMode.byProduct
        : StockMovementsViewMode.recent;
    if (nextMode == _viewMode) return;
    _viewMode = nextMode;
    _selectedProductId = null;
    _movements = [];
    notifyListeners();

    if (nextMode == StockMovementsViewMode.recent) {
      loadRecentMovements();
    }
  }

  /// Load recent movements across ALL products (for 'recent' view mode)
  Future<void> loadRecentMovements({int limit = 100}) async {
    _selectedProductId = null;
    _viewMode = StockMovementsViewMode.recent;
    await _loadMovements(limit: limit);
  }

  /// Load movements for a specific product
  Future<void> loadMovementsForProduct(String productId) async {
    _selectedProductId = productId;
    _viewMode = StockMovementsViewMode.byProduct;
    await _loadMovements();
  }

  @override
  void dispose() {
    _movementsChannel?.unsubscribe();
    _adjustmentsChannel?.unsubscribe();
    super.dispose();
  }

  Future<List<StockMovement>> _enrichWithImages(
      List<StockMovement> movements) async {
    if (movements.isEmpty) return movements;

    final productIds = movements
        .map((m) => m.productId)
        .where((id) => id.isNotEmpty) // Filter empty IDs
        .toSet()
        .toList();
    if (productIds.isEmpty) return movements;

    debugPrint('🖼️ Fetching images for ${productIds.length} products');

    try {
      // Format as PostgREST filter: (val1,val2,val3)
      final filterValue = '(${productIds.join(',')})';

      final response = await _supabase
          .from('products')
          .select('id, image_url')
          .filter('id', 'in', filterValue);

      debugPrint('🖼️ Got ${(response as List).length} product records');

      final imageMap = <String, String?>{};
      for (var item in response) {
        final id = item['id']?.toString();
        final url = item['image_url'] as String?;
        if (id != null) {
          imageMap[id] = url;
          if (url != null && url.isNotEmpty) {
            debugPrint(
                '🖼️ Found image for $id: ${url.substring(0, url.length > 50 ? 50 : url.length)}...');
          }
        }
      }

      var enrichedCount = 0;
      final result = movements.map((m) {
        final img = imageMap[m.productId];
        if (img != null && img.isNotEmpty) {
          enrichedCount++;
          return m.copyWith(productImageUrl: img);
        }
        return m;
      }).toList();

      debugPrint('🖼️ Enriched $enrichedCount movements with images');
      return result;
    } catch (e) {
      debugPrint('⚠️ Error fetching product images: $e');
      return movements;
    }
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
      return await _fetchMovements(productId: productId);
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
    return _movements
        .where((movement) => movement.matchesCategoryKey(type))
        .toList();
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

  Future<void> _reloadCurrentView() async {
    if (_viewMode == StockMovementsViewMode.recent) {
      await loadRecentMovements();
      return;
    }

    final selectedProductId = _selectedProductId;
    if (selectedProductId != null) {
      await loadMovementsForProduct(selectedProductId);
    }
  }

  Future<void> _loadMovements({int? limit}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final rawMovements = await _fetchMovements(
        productId: _viewMode == StockMovementsViewMode.byProduct
            ? _selectedProductId
            : null,
        limit: _viewMode == StockMovementsViewMode.recent ? limit : null,
      );

      _movements = await _enrichWithImages(rawMovements);
      _error = null;
      debugPrint(
        '✅ [StockMovementsService] Loaded ${_movements.length} movements in ${_viewMode.key} mode',
      );
    } catch (e) {
      _error = e.toString();
      _movements = [];
      debugPrint('❌ [StockMovementsService] Error loading stock movements: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<StockMovement>> _fetchMovements({
    String? productId,
    int? limit,
  }) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) {
      throw Exception('No tenant_id found');
    }

    var query = _supabase
        .from('stock_movements_view')
        .select()
        .eq('tenant_id', tenantId);

    if (productId != null && productId.isNotEmpty) {
      query = query.eq('product_id', productId);
    }

    final orderedQuery = query
        .order('transaction_date', ascending: false)
        .order('created_at', ascending: false)
        .order('id', ascending: false);
    final response =
        limit != null ? await orderedQuery.limit(limit) : await orderedQuery;

    final rows = response as List;
    return rows.map((json) => StockMovement.fromJson(json)).toList();
  }
}
