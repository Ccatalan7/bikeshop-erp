import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for managing multi-tenant operations
/// 
/// Handles tenant context and provides utilities for:
/// - Getting current user's tenant_id
/// - Fetching tenant details
/// - Tenant-aware data operations
class TenantService extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  
  // Cache for tenant_id to avoid repeated database queries
  String? _cachedTenantId;
  String? _cachedUserId;

  /// Get the current user's tenant_id from user_profiles table
  /// This is the single source of truth for tenant_id
  Future<String?> getTenantId() async {
    debugPrint('[TenantService] getTenantId called');
    final user = _supabase.auth.currentUser;
    if (user == null) {
      debugPrint('[TenantService] No current user');
      return null;
    }
    
    // Return cached value if same user
    if (_cachedTenantId != null && _cachedUserId == user.id) {
      debugPrint('[TenantService] Returning cached tenant_id: $_cachedTenantId');
      return _cachedTenantId;
    }
    
    try {
      debugPrint('[TenantService] Querying user_profiles...');
      final response = await _supabase
          .from('user_profiles')
          .select('tenant_id')
          .eq('user_id', user.id)
          .maybeSingle();
      
      if (response == null) {
        debugPrint('[TenantService] No profile found');
        return null;
      }
      
      // Cache the result
      _cachedTenantId = response['tenant_id'] as String?;
      _cachedUserId = user.id;
      debugPrint('[TenantService] Got tenant_id: $_cachedTenantId');
      return _cachedTenantId;
    } catch (e) {
      debugPrint('❌ Error getting tenant_id: $e');
      return null;
    }
  }
  
  /// Clear the cached tenant_id (call on logout)
  void clearCache() {
    _cachedTenantId = null;
    _cachedUserId = null;
  }

  /// Get the current user's tenant_id (synchronous - from cache)
  /// For immediate use, but may be null if not cached
  /// Prefer using getTenantId() for reliable results
  String? get currentTenantId {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    
    // CRITICAL FIX: Try app_metadata first (set by database trigger)
    final appMetadata = user.appMetadata;
    if (appMetadata['tenant_id'] != null) {
      return appMetadata['tenant_id'] as String?;
    }
    
    // Try to get from user_metadata second (cached)
    final metadata = user.userMetadata;
    if (metadata != null && metadata['tenant_id'] != null) {
      return metadata['tenant_id'] as String?;
    }
    
    // If not in metadata, need to query database (use getTenantId() instead)
    return null;
  }

  /// Get the current user's role
  String? get currentUserRole {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    
    final metadata = user.userMetadata;
    if (metadata == null) return null;
    
    return metadata['role'] as String?;
  }

  /// Get the current user's permissions
  Map<String, dynamic>? get currentUserPermissions {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    
    final metadata = user.userMetadata;
    if (metadata == null) return null;
    
    return metadata['permissions'] as Map<String, dynamic>?;
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
          .maybeSingle(); // ✅ Use maybeSingle() instead of single() - returns null if not found

      if (response == null) {
        debugPrint('⚠️ No tenant found with id: $tenantId');
        debugPrint('⚠️ This user may need to create a tenant or be assigned to one');
        return null;
      }

      debugPrint('✅ Loaded tenant: ${response['shop_name']} (${response['subdomain']})');
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
  void initialize() {
    _supabase.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.signedOut ||
          event.event == AuthChangeEvent.userUpdated) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }
}
