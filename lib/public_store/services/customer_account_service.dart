import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/customer_address.dart';
import '../../shared/services/tenant_detection_service.dart';
import '../../modules/website/models/website_models.dart';

/// Service for managing customer accounts on the public store
///
/// Handles:
/// - Account creation and authentication
/// - Profile management
/// - Address book (multiple shipping addresses)
/// - Order history and tracking
/// - Bikes registered to customer
/// - Service history (mechanic jobs/pegas)
enum CustomerAuthResult {
  success,
  emailVerificationRequired,
}

class CustomerAccountService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? _currentUser;
  Map<String, dynamic>? _customerProfile;
  String? _tenantId; // CRITICAL: Required for multi-tenant customer creation

  /// Set the tenant ID (must be called before any operations)
  void setTenantId(String? tenantId) {
    _tenantId = tenantId;
  }

  String? get tenantId => _tenantId;
  List<CustomerAddress> _addresses = [];
  List<OnlineOrder> _orders = [];
  List<Map<String, dynamic>> _bikes = [];
  List<Map<String, dynamic>> _serviceHistory = [];
  bool _isLoading = false;
  String? _error;
  String? _pendingVerificationEmail;

  User? get currentUser => _currentUser;
  Map<String, dynamic>? get customerProfile => _customerProfile;
  List<CustomerAddress> get addresses => _addresses;
  List<OnlineOrder> get orders => _orders;
  List<Map<String, dynamic>> get bikes => _bikes;
  List<Map<String, dynamic>> get serviceHistory => _serviceHistory;
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
        _bikes = [];
        _serviceHistory = [];
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
      _bikes = [];
      _serviceHistory = [];
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
      // AUTO-DETECT tenant from URL if not already set
      if (_tenantId == null && kIsWeb) {
        final detectionService = TenantDetectionService();
        final tenant = await detectionService.detectTenant();
        if (tenant != null) {
          _tenantId = tenant.id;
          debugPrint('🔍 Auto-detected tenant: ${tenant.shopName} (${tenant.id})');
        }
      }
      
      // Get customer profile - filter by tenant if available
      var query = _supabase
          .from('customers')
          .select()
          .eq('auth_user_id', _currentUser!.id);
      
      // Filter by tenant_id for multi-tenant isolation
      if (_tenantId != null) {
        query = query.eq('tenant_id', _tenantId!);
      }
      
      final profileResponse = await query.maybeSingle();

      if (profileResponse != null) {
        _customerProfile = profileResponse;

        // Load addresses, orders, bikes, and service history in parallel
        await Future.wait([
          loadAddresses(),
          loadOrders(),
          loadBikes(),
          loadServiceHistory(),
        ]);
      } else {
        // Create customer profile if it doesn't exist (Google login or first visit)
        if (_tenantId == null) {
          debugPrint('⚠️ Cannot create customer: tenant_id not set');
          return;
        }
        
        final userData = _currentUser!.userMetadata;
        await _supabase.from('customers').insert({
          'tenant_id': _tenantId, // CRITICAL: Include tenant_id
          'auth_user_id': _currentUser!.id,
          'name': userData?['full_name'] ?? userData?['name'] ?? 'Usuario',
          'email': _currentUser!.email,
        });
        
        debugPrint('✅ Created customer for tenant $_tenantId');

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

  // ============================================================================
  // BIKES MANAGEMENT
  // ============================================================================

  /// Load customer's registered bikes with service count
  Future<void> loadBikes() async {
    if (_customerProfile == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      // Get bikes with brand/model info
      final response = await _supabase
          .from('bikes')
          .select('''
            *,
            bike_brands(name),
            bike_models(name)
          ''')
          .eq('customer_id', _customerProfile!['id'])
          .eq('is_active', true)
          .order('created_at', ascending: false);

      _bikes = List<Map<String, dynamic>>.from(response);

      // Enrich with service count and last service date
      for (var i = 0; i < _bikes.length; i++) {
        final bikeId = _bikes[i]['id'];
        
        // Get service count
        final countResponse = await _supabase
            .from('mechanic_jobs')
            .select('id')
            .eq('bike_id', bikeId)
            .isFilter('deleted_at', null);
        
        _bikes[i]['service_count'] = (countResponse as List).length;

        // Get last service date
        final lastServiceResponse = await _supabase
            .from('mechanic_jobs')
            .select('completed_at, delivered_at')
            .eq('bike_id', bikeId)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .limit(1);

        if ((lastServiceResponse as List).isNotEmpty) {
          final lastService = lastServiceResponse.first;
          _bikes[i]['last_service_date'] = lastService['delivered_at'] ?? 
              lastService['completed_at'];
        }

        // Extract brand/model names from joins
        if (_bikes[i]['bike_brands'] != null) {
          _bikes[i]['brand_name'] = _bikes[i]['bike_brands']['name'];
        }
        if (_bikes[i]['bike_models'] != null) {
          _bikes[i]['model_name'] = _bikes[i]['bike_models']['name'];
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading bikes: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get a single bike by ID
  Future<Map<String, dynamic>?> getBikeById(String bikeId) async {
    try {
      final response = await _supabase
          .from('bikes')
          .select('''
            *,
            bike_brands(name),
            bike_models(name)
          ''')
          .eq('id', bikeId)
          .single();

      final bike = Map<String, dynamic>.from(response);
      
      // Extract brand/model names
      if (bike['bike_brands'] != null) {
        bike['brand_name'] = bike['bike_brands']['name'];
      }
      if (bike['bike_models'] != null) {
        bike['model_name'] = bike['bike_models']['name'];
      }

      return bike;
    } catch (e) {
      debugPrint('Error loading bike: $e');
      return null;
    }
  }

  // ============================================================================
  // SERVICE HISTORY (MECHANIC JOBS / PEGAS)
  // ============================================================================

  /// Load customer's service history (mechanic jobs)
  Future<void> loadServiceHistory() async {
    if (_customerProfile == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      debugPrint('📋 Loading service history for customer: ${_customerProfile!['id']}');

      // Query mechanic_jobs without join first (RLS might block joins)
      final response = await _supabase
          .from('mechanic_jobs')
          .select('*')
          .eq('customer_id', _customerProfile!['id'])
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);

      debugPrint('📋 Found ${response.length} mechanic jobs');

      _serviceHistory = List<Map<String, dynamic>>.from(response);

      // Load bike info separately for each job
      for (var i = 0; i < _serviceHistory.length; i++) {
        final bikeId = _serviceHistory[i]['bike_id'];
        if (bikeId != null) {
          try {
            final bikeResponse = await _supabase
                .from('bikes')
                .select('brand, model, color, bike_type')
                .eq('id', bikeId)
                .maybeSingle();
            
            if (bikeResponse != null) {
              _serviceHistory[i]['bike_brand'] = bikeResponse['brand'] ?? '';
              _serviceHistory[i]['bike_model'] = bikeResponse['model'] ?? '';
              _serviceHistory[i]['bike_color'] = bikeResponse['color'];
              _serviceHistory[i]['bike_type'] = bikeResponse['bike_type'];
            }
          } catch (e) {
            debugPrint('⚠️ Could not load bike $bikeId: $e');
          }
        }
      }

      debugPrint('📋 Service history loaded: ${_serviceHistory.length} items');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading service history: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get service history for a specific bike
  Future<List<Map<String, dynamic>>> getServiceHistoryForBike(String bikeId) async {
    try {
      final response = await _supabase
          .from('mechanic_jobs')
          .select('*')
          .eq('bike_id', bikeId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error loading bike service history: $e');
      return [];
    }
  }

  /// Get a single service job by ID
  Future<Map<String, dynamic>?> getServiceById(String jobId) async {
    try {
      final response = await _supabase
          .from('mechanic_jobs')
          .select('''
            *,
            bikes(brand, model, color, bike_type, serial_number),
            mechanic_job_parts(
              id,
              product_id,
              product_name,
              quantity,
              unit_price,
              subtotal
            )
          ''')
          .eq('id', jobId)
          .single();

      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('Error loading service: $e');
      return null;
    }
  }

  /// Get active services count (not delivered or cancelled)
  int get activeServicesCount {
    return _serviceHistory.where((s) => 
      !['ENTREGADO', 'CANCELADO'].contains(s['status'])).length;
  }

  /// Get services awaiting customer approval
  List<Map<String, dynamic>> get servicesAwaitingApproval {
    return _serviceHistory.where((s) => 
      s['status'] == 'ESPERANDO_APROBACION' && 
      s['approved_by_customer'] != true).toList();
  }

  /// Approve a service estimate
  Future<void> approveServiceEstimate(String jobId) async {
    try {
      await _supabase
          .from('mechanic_jobs')
          .update({
            'approved_by_customer': true,
            'approved_at': DateTime.now().toIso8601String(),
            'status': 'EN_CURSO', // Move to in progress after approval
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', jobId);

      await loadServiceHistory();
    } catch (e) {
      _error = 'Error al aprobar el presupuesto: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  /// Reject a service estimate (will be handled as cancellation)
  Future<void> rejectServiceEstimate(String jobId, String? reason) async {
    try {
      await _supabase
          .from('mechanic_jobs')
          .update({
            'approved_by_customer': false,
            'approved_at': DateTime.now().toIso8601String(),
            'status': 'CANCELADO',
            'notes': reason ?? 'Presupuesto rechazado por el cliente',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', jobId);

      await loadServiceHistory();
    } catch (e) {
      _error = 'Error al rechazar el presupuesto: $e';
      debugPrint(_error);
      rethrow;
    }
  }
}
