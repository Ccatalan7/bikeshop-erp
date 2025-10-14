import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/payment_method.dart';

/// Service for managing payment methods
/// Loads payment methods dynamically from the database
class PaymentMethodService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<PaymentMethod> _paymentMethods = [];
  bool _isLoading = false;
  String? _error;

  List<PaymentMethod> get paymentMethods => _paymentMethods;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load all active payment methods from database
  /// Sorted by sort_order
  Future<void> loadPaymentMethods({bool forceRefresh = false}) async {
    if (_isLoading) return;
    if (!forceRefresh && _paymentMethods.isNotEmpty) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _supabase
          .from('payment_methods')
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      _paymentMethods = (response as List)
          .map((json) => PaymentMethod.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint(
          'PaymentMethodService: Loaded ${_paymentMethods.length} payment methods');
    } catch (e) {
      debugPrint('PaymentMethodService.loadPaymentMethods error: $e');
      _error = 'No se pudieron cargar los métodos de pago.';
      _paymentMethods = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get a payment method by ID
  PaymentMethod? getPaymentMethodById(String id) {
    try {
      return _paymentMethods.firstWhere((pm) => pm.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get a payment method by code
  PaymentMethod? getPaymentMethodByCode(String code) {
    try {
      return _paymentMethods.firstWhere((pm) => pm.code == code);
    } catch (e) {
      return null;
    }
  }

  /// Refresh payment methods from database
  Future<void> refresh() async {
    await loadPaymentMethods(forceRefresh: true);
  }

  /// Create a new payment method (admin only)
  Future<PaymentMethod?> createPaymentMethod(PaymentMethod method) async {
    try {
      final response = await _supabase
          .from('payment_methods')
          .insert(method.toJson())
          .select()
          .single();

      final created = PaymentMethod.fromJson(response as Map<String, dynamic>);
      await refresh();
      return created;
    } catch (e) {
      debugPrint('PaymentMethodService.createPaymentMethod error: $e');
      _error = 'No se pudo crear el método de pago.';
      notifyListeners();
      return null;
    }
  }

  /// Update an existing payment method (admin only)
  Future<PaymentMethod?> updatePaymentMethod(PaymentMethod method) async {
    try {
      final response = await _supabase
          .from('payment_methods')
          .update(method.toJson())
          .eq('id', method.id)
          .select()
          .single();

      final updated = PaymentMethod.fromJson(response as Map<String, dynamic>);
      await refresh();
      return updated;
    } catch (e) {
      debugPrint('PaymentMethodService.updatePaymentMethod error: $e');
      _error = 'No se pudo actualizar el método de pago.';
      notifyListeners();
      return null;
    }
  }

  /// Deactivate a payment method (soft delete)
  Future<bool> deactivatePaymentMethod(String id) async {
    try {
      await _supabase
          .from('payment_methods')
          .update({'is_active': false}).eq('id', id);

      await refresh();
      return true;
    } catch (e) {
      debugPrint('PaymentMethodService.deactivatePaymentMethod error: $e');
      _error = 'No se pudo desactivar el método de pago.';
      notifyListeners();
      return false;
    }
  }
}
