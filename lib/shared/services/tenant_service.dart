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

  /// Get the current user's tenant_id from their metadata
  String? get currentTenantId {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    
    final metadata = user.userMetadata;
    if (metadata == null) return null;
    
    return metadata['tenant_id'] as String?;
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
    final tenantId = currentTenantId;
    if (tenantId == null) {
      debugPrint('❌ No tenant_id found in user metadata');
      return null;
    }

    try {
      final response = await _supabase
          .from('tenants')
          .select()
          .eq('id', tenantId)
          .single();

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
