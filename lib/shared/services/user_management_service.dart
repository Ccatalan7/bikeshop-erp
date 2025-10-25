import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tenant_service.dart';

/// Service for managing users within a tenant
/// 
/// Provides CRUD operations for:
/// - Inviting new users (creates auth.users with tenant_id)
/// - Updating user roles and permissions
/// - Suspending/activating users
/// - Deleting users
/// - Listing all users in current tenant
class UserManagementService {
  final _supabase = Supabase.instance.client;
  final TenantService _tenantService;

  UserManagementService(this._tenantService);

  /// Get all users in the current tenant
  Future<List<Map<String, dynamic>>> getTenantUsers() async {
    final tenantId = _tenantService.currentTenantId;
    if (tenantId == null) {
      throw Exception('No tenant_id found. Cannot fetch users.');
    }

    try {
      final response = await _supabase
          .rpc('get_tenant_users', params: {'p_tenant_id': tenantId});

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error fetching tenant users: $e');
      rethrow;
    }
  }

  /// Invite a new user to the current tenant
  /// 
  /// Creates an auth.users record with:
  /// - email and password
  /// - tenant_id (current tenant)
  /// - role (manager, cashier, mechanic, accountant)
  /// - permissions (custom permission map)
  /// 
  /// Optionally links to an existing employee record
  Future<void> inviteUser({
    required String email,
    required String password,
    required String role,
    Map<String, bool>? permissions,
    String? employeeId,
  }) async {
    final tenantId = _tenantService.currentTenantId;
    if (tenantId == null) {
      throw Exception('No tenant_id found. Cannot invite user.');
    }

    try {
      // Default permissions based on role
      final defaultPermissions = _getDefaultPermissions(role);
      final finalPermissions = permissions ?? defaultPermissions;

      // Create auth user using admin API
      // Note: This requires service_role key or proper RLS policies
      final authResponse = await _supabase.auth.admin.createUser(
        AdminUserAttributes(
          email: email,
          password: password,
          emailConfirm: true,
          userMetadata: {
            'tenant_id': tenantId,
            'role': role,
            'permissions': finalPermissions,
          },
        ),
      );

      // Link to employee if provided
      if (employeeId != null) {
        await _supabase.from('employees').update({
          'user_id': authResponse.user!.id,
        }).eq('id', employeeId);
      }

      // Log the action
      await _logUserAction(
        userId: authResponse.user!.id,
        action: 'user_created',
        details: {
          'email': email,
          'role': role,
          'created_by': _supabase.auth.currentUser?.id,
        },
      );

      debugPrint('✅ User invited successfully: $email');
    } catch (e) {
      debugPrint('❌ Error inviting user: $e');
      rethrow;
    }
  }

  /// Update user role and permissions
  Future<void> updateUserRole({
    required String userId,
    required String newRole,
    required Map<String, bool> newPermissions,
  }) async {
    final tenantId = _tenantService.currentTenantId;
    if (tenantId == null) {
      throw Exception('No tenant_id found.');
    }

    try {
      await _supabase.auth.admin.updateUserById(
        userId,
        attributes: AdminUserAttributes(
          userMetadata: {
            'tenant_id': tenantId, // Keep same tenant
            'role': newRole,
            'permissions': newPermissions,
          },
        ),
      );

      // Log the action
      await _logUserAction(
        userId: userId,
        action: 'role_changed',
        details: {
          'new_role': newRole,
          'changed_by': _supabase.auth.currentUser?.id,
        },
      );

      debugPrint('✅ User role updated: $userId → $newRole');
    } catch (e) {
      debugPrint('❌ Error updating user role: $e');
      rethrow;
    }
  }

  /// Suspend or activate a user
  Future<void> toggleUserStatus(String userId, bool isActive) async {
    try {
      if (isActive) {
        // Unban user
        await _supabase.auth.admin.updateUserById(
          userId,
          attributes: AdminUserAttributes(
            banDuration: 'none',
          ),
        );
      } else {
        // Ban user indefinitely
        await _supabase.auth.admin.updateUserById(
          userId,
          attributes: AdminUserAttributes(
            banDuration: '876600h', // ~100 years
          ),
        );
      }

      // Log the action
      await _logUserAction(
        userId: userId,
        action: isActive ? 'user_activated' : 'user_suspended',
        details: {
          'changed_by': _supabase.auth.currentUser?.id,
        },
      );

      debugPrint('✅ User ${isActive ? "activated" : "suspended"}: $userId');
    } catch (e) {
      debugPrint('❌ Error toggling user status: $e');
      rethrow;
    }
  }

  /// Delete a user
  /// 
  /// Unlinks from employee first, then deletes auth record
  Future<void> deleteUser(String userId) async {
    try {
      // Unlink from employee
      await _supabase
          .from('employees')
          .update({'user_id': null})
          .eq('user_id', userId);

      // Delete auth user
      await _supabase.auth.admin.deleteUser(userId);

      debugPrint('✅ User deleted: $userId');
    } catch (e) {
      debugPrint('❌ Error deleting user: $e');
      rethrow;
    }
  }

  /// Send password reset email
  Future<void> sendPasswordReset(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      debugPrint('✅ Password reset email sent to: $email');
    } catch (e) {
      debugPrint('❌ Error sending password reset: $e');
      rethrow;
    }
  }

  /// Log user action to user_activity_log
  Future<void> _logUserAction({
    required String userId,
    required String action,
    Map<String, dynamic>? details,
  }) async {
    final tenantId = _tenantService.currentTenantId;
    if (tenantId == null) return;

    try {
      await _supabase.from('user_activity_log').insert({
        'tenant_id': tenantId,
        'user_id': userId,
        'action': action,
        'details': details,
        'performed_by': _supabase.auth.currentUser?.id,
      });
    } catch (e) {
      debugPrint('⚠️ Failed to log user action: $e');
      // Don't throw - logging failure shouldn't break main operation
    }
  }

  /// Get default permissions for a role
  Map<String, bool> _getDefaultPermissions(String role) {
    switch (role) {
      case 'manager':
        return {
          'access_pos': true,
          'create_invoices': true,
          'edit_prices': true,
          'delete_invoices': true,
          'access_accounting': true,
          'manage_users': true,
          'edit_settings': true,
        };
      case 'cashier':
        return {
          'access_pos': true,
          'create_invoices': true,
          'edit_prices': false,
          'delete_invoices': false,
          'access_accounting': false,
          'manage_users': false,
          'edit_settings': false,
        };
      case 'mechanic':
        return {
          'access_pos': false,
          'create_invoices': false,
          'edit_prices': false,
          'delete_invoices': false,
          'access_accounting': false,
          'manage_users': false,
          'edit_settings': false,
        };
      case 'accountant':
        return {
          'access_pos': false,
          'create_invoices': false,
          'edit_prices': false,
          'delete_invoices': false,
          'access_accounting': true,
          'manage_users': false,
          'edit_settings': false,
        };
      default:
        return {};
    }
  }
}
