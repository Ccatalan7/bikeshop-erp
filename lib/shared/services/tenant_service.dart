import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for managing multi-tenant operations
///
/// Handles tenant context and provides utilities for:
/// - Getting current user's tenant_id
/// - Fetching tenant details
/// - Tenant-aware data operations
///
/// NOTE: This is a SINGLETON to ensure cache is shared across all callers.
class TenantService extends ChangeNotifier {
  // Singleton pattern
  static final TenantService _instance = TenantService._internal();
  factory TenantService() => _instance;
  TenantService._internal();

  final _supabase = Supabase.instance.client;

  // Public Store mobile optimization: when enabled (via dart-define), skip any
  // auth-based tenant lookup. Store mode should use TenantDetectionService.
  static const bool _ignoreAuthForPublicStore =
      bool.fromEnvironment('PUBLIC_STORE_IGNORE_AUTH');

  // Cache for tenant_id to avoid repeated database queries
  String? _cachedTenantId;
  String? _cachedUserId;
  String? _cachedUserRole;
  Map<String, dynamic>? _cachedUserPermissions;

  // Track if a query is in progress to prevent duplicate concurrent queries
  bool _isQuerying = false;

  // Completer for pending requests to wait on
  Future<String?>? _pendingQuery;

  /// Get the current user's tenant_id from user_profiles table
  /// This is the single source of truth for tenant_id
  ///
  /// OPTIMIZED: Uses caching to prevent multiple database queries
  Future<String?> getTenantId() async {
    if (_ignoreAuthForPublicStore) {
      if (!kReleaseMode) {
        debugPrint(
            '🏪 [TenantService] PUBLIC_STORE_IGNORE_AUTH enabled; skipping user_profiles lookup');
      }
      return null;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      return null;
    }

    // FAST PATH: Return cached value immediately if same user
    // We check _cachedUserId to ensure we have a result (even if null) for this user
    if (_cachedUserId == user.id) {
      return _cachedTenantId;
    }

    // Prevent duplicate concurrent queries - wait for existing query
    if (_isQuerying && _pendingQuery != null) {
      return _pendingQuery;
    }

    // Start new query
    _isQuerying = true;
    _pendingQuery = _fetchTenantId(user.id);

    try {
      return await _pendingQuery;
    } finally {
      _isQuerying = false;
      _pendingQuery = null;
    }
  }

  /// Internal method to fetch tenant_id from database
  Future<String?> _fetchTenantId(String userId) async {
    try {
      if (!kReleaseMode) {
        debugPrint('[TenantService] Querying user_profiles...');
      }
      final response = await _supabase
          .from('user_profiles')
          .select('tenant_id, role, permissions')
          .eq('user_id', userId)
          .eq('is_active', true)
          .limit(2);

      final profiles = List<Map<String, dynamic>>.from(response);
      if (profiles.length != 1) {
        if (!kReleaseMode) {
          debugPrint(
            '[TenantService] Active profile resolution failed closed',
          );
        }
        _cachedTenantId = null;
        _cachedUserRole = null;
        _cachedUserPermissions = null;
        _cachedUserId = userId;
        return null;
      }

      final profile = profiles.single;
      var tid = profile['tenant_id'] as String?;
      if (tid != null && tid.isEmpty) tid = null;

      _cachedTenantId = tid;
      _cachedUserRole = profile['role'] as String?;
      final permissions = profile['permissions'];
      _cachedUserPermissions = permissions is Map
          ? Map<String, dynamic>.unmodifiable(
              Map<String, dynamic>.from(permissions),
            )
          : null;
      _cachedUserId = userId;
      if (!kReleaseMode) {
        debugPrint('[TenantService] Got tenant_id: $_cachedTenantId');
      }
      return _cachedTenantId;
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('❌ Error getting tenant_id: $e');
      }
      return null;
    }
  }

  /// Clear the cached tenant_id (call on logout)
  void clearCache() {
    _cachedTenantId = null;
    _cachedUserId = null;
    _cachedUserRole = null;
    _cachedUserPermissions = null;
  }

  /// Get the current user's tenant_id (synchronous - from cache)
  /// For immediate use, but may be null if not cached
  /// Prefer using getTenantId() for reliable results
  String? get currentTenantId {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    if (_cachedUserId != user.id) return null;
    return _cachedTenantId;
  }

  /// Get the current user's role
  String? get currentUserRole {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    if (_cachedUserId != user.id) return null;
    return _cachedUserRole;
  }

  /// Get the current user's permissions
  Map<String, dynamic>? get currentUserPermissions {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    if (_cachedUserId != user.id) return null;
    return _cachedUserPermissions;
  }

  /// Check if current user has a specific role
  bool hasRole(String role) {
    return currentUserRole == role;
  }

  /// Check if current user has any of the given roles
  bool hasAnyRole(List<String> roles) {
    final userRole = currentUserRole;
    if (userRole == null) return false;
    return roles.contains(userRole);
  }

  /// Check if current user has a specific permission
  bool hasPermission(String permissionKey) {
    final permissions = currentUserPermissions;
    if (permissions == null) return false;
    return permissions[permissionKey] == true;
  }

  /// Convenience: Check if user is a manager
  bool get isManager => hasRole('manager');

  /// Convenience: Check if user is a cashier
  bool get isCashier => hasRole('cashier');

  /// Convenience: Check if user is a mechanic
  bool get isMechanic => hasRole('mechanic');

  /// Convenience: Check if user is an accountant
  bool get isAccountant => hasRole('accountant');

  /// Fetch current tenant details
  Future<Map<String, dynamic>?> getCurrentTenant() async {
    final tenantId = await getTenantId(); // ✅ Use async version
    if (tenantId == null) {
      debugPrint('❌ No tenant_id found for current user');
      return null;
    }

    try {
      debugPrint('🔍 Fetching tenant with id: $tenantId');
      final response = await _supabase
          .from('tenants')
          .select()
          .eq('id', tenantId)
          .eq('is_active', true)
          .maybeSingle(); // ✅ Use maybeSingle() instead of single() - returns null if not found

      if (response == null) {
        debugPrint('⚠️ No tenant found with id: $tenantId');
        debugPrint(
            '⚠️ This user may need to create a tenant or be assigned to one');
        return null;
      }

      debugPrint(
          '✅ Loaded tenant: ${response['shop_name']} (${response['subdomain']})');
      return response;
    } catch (e) {
      debugPrint('❌ Error fetching tenant: $e');
      return null;
    }
  }

  /// Ensure user has a tenant_id (throws if not)
  void ensureTenantId() {
    if (currentTenantId == null) {
      throw Exception('User does not have a tenant_id. Cannot proceed.');
    }
  }

  /// Add tenant_id to a data map for inserts/updates
  Map<String, dynamic> addTenantId(Map<String, dynamic> data) {
    ensureTenantId();
    data['tenant_id'] = currentTenantId;
    return data;
  }

  /// Subscribe to auth state changes and notify listeners
  /// IMPORTANT: This is guarded to prevent duplicate subscriptions on the singleton
  bool _isInitialized = false;
  StreamSubscription<AuthState>? _authSubscription;

  void initialize() {
    if (_isInitialized) return; // Prevent duplicate subscriptions
    _isInitialized = true;

    _authSubscription = _supabase.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.signedOut ||
          event.event == AuthChangeEvent.userUpdated) {
        // Clear cache on auth state changes so we re-fetch for new user
        clearCache();
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
