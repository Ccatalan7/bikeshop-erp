import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/stock_movement.dart';

class StockMovementsService extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  
  List<StockMovement> _movements = [];
  bool _isLoading = false;
  String? _error;
  String? _selectedProductId;

  List<StockMovement> get movements => _movements;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get selectedProductId => _selectedProductId;

  /// Load movements for a specific product
  Future<void> loadMovementsForProduct(String productId) async {
    _isLoading = true;
    _error = null;
    _selectedProductId = productId;
    notifyListeners();

    try {
      // Query stock_movements view (we'll create this in database)
      final response = await _supabase
          .from('stock_movements_view')
          .select()
          .eq('product_id', productId)
          .order('transaction_date', ascending: false)
          .order('created_at', ascending: false);

      _movements = (response as List)
          .map((json) => StockMovement.fromJson(json))
          .toList();
      
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Error loading stock movements: $e');
      _movements = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear selection
  void clearSelection() {
    _selectedProductId = null;
    _movements = [];
    notifyListeners();
  }

  /// Filter movements by date range
  List<StockMovement> filterByDateRange(DateTime? startDate, DateTime? endDate) {
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
