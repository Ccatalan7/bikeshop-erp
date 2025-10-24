import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/customer_address.dart';
import '../../modules/website/models/website_models.dart';

/// Service for managing customer accounts on the public store
///
/// Handles:
/// - Account creation and authentication
/// - Profile management
/// - Address book (multiple shipping addresses)
/// - Order history and tracking
enum CustomerAuthResult {
  success,
  emailVerificationRequired,
}

class CustomerAccountService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? _currentUser;
  Map<String, dynamic>? _customerProfile;
  List<CustomerAddress> _addresses = [];
  List<OnlineOrder> _orders = [];
  bool _isLoading = false;
  String? _error;
  String? _pendingVerificationEmail;

  User? get currentUser => _currentUser;
  Map<String, dynamic>? get customerProfile => _customerProfile;
  List<CustomerAddress> get addresses => _addresses;
  List<OnlineOrder> get orders => _orders;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;
  bool get requiresEmailVerification => _pendingVerificationEmail != null;
  String? get pendingVerificationEmail => _pendingVerificationEmail;

  CustomerAccountService() {
    _currentUser = _supabase.auth.currentUser;
    if (_currentUser != null) {
      _loadCustomerData();
    }

    // Listen to auth state changes
    _supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        _currentUser = data.session?.user;
        _loadCustomerData();
      } else if (event == AuthChangeEvent.signedOut) {
        _currentUser = null;
        _customerProfile = null;
        _addresses = [];
        _orders = [];
        notifyListeners();
      }
    });
  }

  // ============================================================================
  // AUTHENTICATION
  // ============================================================================

  /// Sign up with email and password
  Future<CustomerAuthResult> signUp({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'name': name, 'phone': phone},
      );

      final session = response.session;
      final user = response.user;

      if (session == null || user?.emailConfirmedAt == null) {
        // Email confirmation required before session becomes active.
        _pendingVerificationEmail = email;
        _currentUser = null;
        _customerProfile = null;
        _addresses = [];
        _orders = [];
        return CustomerAuthResult.emailVerificationRequired;
      }

      // Customer profile is automatically created by database trigger
      // Just wait a moment for it to propagate
      await Future.delayed(const Duration(milliseconds: 800));

      _pendingVerificationEmail = null;
      _currentUser = user;
      await _loadCustomerData();

      // Update phone if provided
      if (phone != null && phone.isNotEmpty) {
        await updateProfile(phone: phone);
      }

      return CustomerAuthResult.success;
    } catch (e) {
      _error = 'Error al crear cuenta: $e';
      debugPrint(_error);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign in with email and password
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      _pendingVerificationEmail = null;
      _currentUser = response.user;
      await _loadCustomerData();
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('email') &&
          e.message.toLowerCase().contains('confirm')) {
        _pendingVerificationEmail = email;
        _error =
            'Tu correo electrónico aún no está verificado. Revisa tu bandeja de entrada.';
      } else {
        _error = e.message;
      }
      debugPrint('Auth error: ${e.message}');
      rethrow;
    } catch (e) {
      _error = 'Error al iniciar sesión: $e';
      debugPrint(_error);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> resendVerificationEmail() async {
    final email = _pendingVerificationEmail;
    if (email == null) return;

    try {
      await _supabase.auth.resend(
        type: OtpType.signup,
        email: email,
      );
    } catch (e) {
      debugPrint('Error al reenviar verificación: $e');
      rethrow;
    }
  }

  /// Sign in with Google
  Future<void> signInWithGoogle() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb
            ? '${Uri.base.origin}/auth/callback'
            : 'io.supabase.vinabike://callback',
      );
    } catch (e) {
      _error = 'Error al iniciar sesión con Google: $e';
      debugPrint(_error);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      _currentUser = null;
      _customerProfile = null;
      _addresses = [];
      _orders = [];
      notifyListeners();
    } catch (e) {
      _error = 'Error al cerrar sesión: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  /// Reset password (send email)
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      _error = 'Error al enviar email de recuperación: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  // ============================================================================
  // PROFILE MANAGEMENT
  // ============================================================================

  Future<void> _loadCustomerData() async {
    if (_currentUser == null) return;

    try {
      // Get customer profile
      final profileResponse = await _supabase
          .from('customers')
          .select()
          .eq('auth_user_id', _currentUser!.id)
          .maybeSingle();

      if (profileResponse != null) {
        _customerProfile = profileResponse;

        // Load addresses and orders in parallel
        await Future.wait([
          loadAddresses(),
          loadOrders(),
        ]);
      } else {
        // Create customer profile if it doesn't exist (Google login)
        final userData = _currentUser!.userMetadata;
        await _supabase.from('customers').insert({
          'auth_user_id': _currentUser!.id,
          'name': userData?['full_name'] ?? userData?['name'] ?? 'Usuario',
          'email': _currentUser!.email,
        });

        await _loadCustomerData(); // Reload
      }
    } catch (e) {
      debugPrint('Error loading customer data: $e');
    }
  }

  /// Update customer profile
  Future<void> updateProfile({
    String? name,
    String? phone,
    String? rut,
    String? imageUrl,
  }) async {
    if (_customerProfile == null) return;

    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (phone != null) updates['phone'] = phone;
      if (rut != null) updates['rut'] = rut;
      if (imageUrl != null) updates['image_url'] = imageUrl;

      if (updates.isEmpty) return;

      updates['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('customers')
          .update(updates)
          .eq('id', _customerProfile!['id']);

      await _loadCustomerData();
    } catch (e) {
      _error = 'Error al actualizar perfil: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  // ============================================================================
  // ADDRESS MANAGEMENT
  // ============================================================================

  Future<void> loadAddresses() async {
    if (_customerProfile == null) return;

    try {
      final response = await _supabase
          .from('customer_addresses')
          .select()
          .eq('customer_id', _customerProfile!['id'])
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      _addresses = (response as List)
          .map((json) => CustomerAddress.fromJson(json))
          .toList();

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading addresses: $e');
    }
  }

  Future<void> addAddress(CustomerAddress address) async {
    if (_customerProfile == null) return;

    try {
      final data = address.toJson();
      data['customer_id'] = _customerProfile!['id'];
      data.remove('id'); // Let database generate ID

      await _supabase.from('customer_addresses').insert(data);
      await loadAddresses();
    } catch (e) {
      _error = 'Error al agregar dirección: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  Future<void> updateAddress(CustomerAddress address) async {
    try {
      await _supabase
          .from('customer_addresses')
          .update(address.toJson())
          .eq('id', address.id);

      await loadAddresses();
    } catch (e) {
      _error = 'Error al actualizar dirección: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  Future<void> deleteAddress(String addressId) async {
    try {
      await _supabase.from('customer_addresses').delete().eq('id', addressId);

      await loadAddresses();
    } catch (e) {
      _error = 'Error al eliminar dirección: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  Future<void> setDefaultAddress(String addressId) async {
    try {
      await _supabase
          .from('customer_addresses')
          .update({'is_default': true}).eq('id', addressId);

      await loadAddresses();
    } catch (e) {
      _error = 'Error al establecer dirección predeterminada: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  CustomerAddress? get defaultAddress {
    try {
      return _addresses.firstWhere((addr) => addr.isDefault);
    } catch (e) {
      return _addresses.isNotEmpty ? _addresses.first : null;
    }
  }

  // ============================================================================
  // ORDER HISTORY
  // ============================================================================

  Future<void> loadOrders() async {
    if (_customerProfile == null) return;

    try {
      final response = await _supabase
          .from('online_orders')
          .select()
          .eq('customer_id', _customerProfile!['id'])
          .order('created_at', ascending: false);

      _orders =
          (response as List).map((json) => OnlineOrder.fromJson(json)).toList();

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading orders: $e');
    }
  }

  Future<OnlineOrder?> getOrderById(String orderId) async {
    try {
      final response = await _supabase
          .from('online_orders')
          .select()
          .eq('id', orderId)
          .single();

      return OnlineOrder.fromJson(response);
    } catch (e) {
      debugPrint('Error loading order: $e');
      return null;
    }
  }
}
