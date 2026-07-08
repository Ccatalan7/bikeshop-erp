import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tenant_service.dart';

/// Tenant-scoped user administration service.
///
/// Regular tenant reads still use RLS/RPCs, but privileged auth operations run
/// through the `admin-user-management` Edge Function so service-role actions do
/// not live in the Flutter client.
class UserManagementService {
  UserManagementService(this._tenantService);

  final SupabaseClient _supabase = Supabase.instance.client;
  final TenantService _tenantService;

  Future<Map<String, dynamic>> getIdentityOverview({String search = ''}) {
    return _invokeAdmin<Map<String, dynamic>>({
      'action': 'overview',
      'search': search,
    });
  }

  Future<Map<String, dynamic>> createCustomerAccount({
    String? customerId,
    required String email,
    required String name,
    String? phone,
    String mode = 'invite',
    String? password,
    bool confirmEmail = false,
  }) {
    return _invokeAdmin<Map<String, dynamic>>({
      'action': 'create_customer_account',
      'customerId': customerId,
      'email': email,
      'name': name,
      'phone': phone,
      'mode': mode,
      'password': password,
      'confirmEmail': confirmEmail,
    });
  }

  Future<void> setCustomerAccess({
    required String customerId,
    required bool isActive,
  }) {
    return _invokeAdminVoid({
      'action': 'set_customer_access',
      'customerId': customerId,
      'isActive': isActive,
    });
  }

  Future<void> deleteCustomerAccount({
    required String customerId,
    bool deleteCustomerRecord = false,
  }) {
    return _invokeAdminVoid({
      'action': 'delete_customer_account',
      'customerId': customerId,
      'deleteCustomerRecord': deleteCustomerRecord,
    });
  }

  Future<void> deleteWebsiteAuthAccount({
    required String authUserId,
  }) {
    return _invokeAdminVoid({
      'action': 'delete_customer_account',
      'userId': authUserId,
    });
  }

  Future<void> resendCustomerVerification({
    required String customerId,
    required String email,
  }) {
    return _invokeAdminVoid({
      'action': 'resend_customer_verification',
      'customerId': customerId,
      'email': email,
    });
  }

  Future<void> confirmEmail(String userId) {
    return _invokeAdminVoid({
      'action': 'confirm_email',
      'userId': userId,
    });
  }

  /// Existing staff-list API used by other modules such as task assignment.
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
      debugPrint('Error fetching tenant users: $e');
      rethrow;
    }
  }

  Future<String> inviteUser({
    required String email,
    required String role,
    Map<String, bool>? permissions,
    String? employeeId,
    String? name,
  }) async {
    final result = await inviteInternalUser(
      email: email,
      role: role,
      permissions: permissions ?? _getDefaultPermissions(role),
      name: name,
      employeeId: employeeId,
    );
    return (result['invitationId'] ?? '').toString();
  }

  Future<Map<String, dynamic>> inviteInternalUser({
    required String email,
    required String role,
    required Map<String, bool> permissions,
    String? name,
    String? employeeId,
  }) {
    return _invokeAdmin<Map<String, dynamic>>({
      'action': 'create_internal_invitation',
      'email': email,
      'role': role,
      'permissions': permissions,
      'name': name,
      'employeeId': employeeId,
    });
  }

  Future<void> resendInternalInvitation(String invitationId) {
    return _invokeAdminVoid({
      'action': 'resend_internal_invitation',
      'invitationId': invitationId,
    });
  }

  Future<void> cancelInternalInvitation(String invitationId) {
    return _invokeAdminVoid({
      'action': 'cancel_internal_invitation',
      'invitationId': invitationId,
    });
  }

  Future<void> updateUserRole({
    required String userId,
    required String newRole,
    required Map<String, bool> newPermissions,
  }) {
    return _invokeAdminVoid({
      'action': 'update_internal_user',
      'userId': userId,
      'role': newRole,
      'permissions': newPermissions,
    });
  }

  Future<void> updateInternalIdentity({
    required String userId,
    required String name,
  }) {
    return _invokeAdminVoid({
      'action': 'update_internal_identity',
      'userId': userId,
      'name': name,
    });
  }

  Future<void> toggleUserStatus(String userId, bool isActive) {
    return _invokeAdminVoid({
      'action': 'set_internal_access',
      'userId': userId,
      'isActive': isActive,
    });
  }

  Future<void> deleteUser(String userId) {
    return _invokeAdminVoid({
      'action': 'delete_internal_account',
      'userId': userId,
    });
  }

  Future<Map<String, dynamic>> createWorkerPortalAccount({
    required String employeeId,
    required String username,
    String? password,
  }) {
    return _invokeAdmin<Map<String, dynamic>>({
      'action': 'create_worker_portal_account',
      'employeeId': employeeId,
      'username': username,
      if (password != null && password.trim().isNotEmpty)
        'password': password.trim(),
    });
  }

  Future<Map<String, dynamic>> resetWorkerPortalPassword({
    required String employeeId,
    String? password,
  }) {
    return _invokeAdmin<Map<String, dynamic>>({
      'action': 'reset_worker_portal_password',
      'employeeId': employeeId,
      if (password != null && password.trim().isNotEmpty)
        'password': password.trim(),
    });
  }

  Future<void> setWorkerPortalAccess({
    required String employeeId,
    required bool isActive,
  }) {
    return _invokeAdminVoid({
      'action': 'set_worker_portal_access',
      'employeeId': employeeId,
      'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>> sendPasswordReset(String email) {
    return _invokeAdmin<Map<String, dynamic>>({
      'action': 'send_password_reset',
      'email': email,
    });
  }

  Future<T> _invokeAdmin<T>(Map<String, dynamic> body) async {
    try {
      final response = await _supabase.functions.invoke(
        'admin-user-management',
        body: body,
      );

      if (response.status >= 400) {
        final data = response.data;
        final message = data is Map && data['error'] != null
            ? data['error'].toString()
            : 'Error ${response.status} en admin-user-management';
        throw Exception(message);
      }

      final data = response.data;
      if (data is T) return data;
      return Map<String, dynamic>.from(data as Map) as T;
    } on FunctionException catch (e) {
      final message = _extractAdminError(e.details);
      debugPrint('User admin operation failed: $message');
      throw Exception(message);
    } catch (e) {
      debugPrint('User admin operation failed: $e');
      rethrow;
    }
  }

  String _extractAdminError(dynamic value) {
    if (value == null) return 'Error en admin-user-management';
    if (value is String) return value;
    if (value is List) {
      final messages = value.map(_extractAdminError).where((m) => m.isNotEmpty);
      return messages.join(' · ');
    }
    if (value is Map) {
      for (final key in const ['error', 'message', 'details', 'msg']) {
        if (value.containsKey(key)) {
          final message = _extractAdminError(value[key]);
          if (message.isNotEmpty &&
              message != 'Error en admin-user-management') {
            return message;
          }
        }
      }
    }
    return value.toString();
  }

  Future<void> _invokeAdminVoid(Map<String, dynamic> body) async {
    await _invokeAdmin<Map<String, dynamic>>(body);
  }

  Map<String, bool> _getDefaultPermissions(String role) {
    switch (role) {
      case 'admin':
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
