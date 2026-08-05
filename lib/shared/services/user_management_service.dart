import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tenant_service.dart';
import '../utils/auth_input_validation.dart';

enum EmployeeErpLinkState {
  available,
  pendingInvitation,
  erpLinked,
  workerActive,
  workerSuspended,
  inconsistent,
}

enum InvitationIdentityStatus {
  availableNewIdentity,
  availableExistingCustomer,
  activeStaffRequiresDirectLink,
  inactiveStaffMembership,
  externalErpMembership,
  workerIdentityConflict,
  historicalEmployeeIdentityConflict,
}

class InvitationIdentityCheck {
  const InvitationIdentityCheck({
    required this.eligible,
    required this.status,
    required this.hasExistingAuthIdentity,
    required this.isExistingCustomer,
  });

  factory InvitationIdentityCheck.fromJson(Map<String, dynamic> json) {
    final eligible = json['eligible'];
    final status = json['status'];
    final hasExistingAuthIdentity = json['hasExistingAuthIdentity'];
    final isExistingCustomer = json['isExistingCustomer'];
    if (eligible is! bool ||
        status is! String ||
        hasExistingAuthIdentity is! bool ||
        isExistingCustomer is! bool) {
      throw const FormatException(
        'Respuesta inválida al verificar la identidad de invitación.',
      );
    }

    final parsedStatus = switch (status) {
      'available_new_identity' => InvitationIdentityStatus.availableNewIdentity,
      'available_existing_customer' =>
        InvitationIdentityStatus.availableExistingCustomer,
      'active_staff_email_requires_direct_link' =>
        InvitationIdentityStatus.activeStaffRequiresDirectLink,
      'staff_membership_inactive' =>
        InvitationIdentityStatus.inactiveStaffMembership,
      'staff_identity_tenant_conflict' =>
        InvitationIdentityStatus.externalErpMembership,
      'worker_identity_conflict' =>
        InvitationIdentityStatus.workerIdentityConflict,
      'historical_employee_identity_conflict' =>
        InvitationIdentityStatus.historicalEmployeeIdentityConflict,
      _ => throw const FormatException(
          'La verificación devolvió un estado de identidad desconocido.',
        ),
    };
    final statusIsEligible =
        parsedStatus == InvitationIdentityStatus.availableNewIdentity ||
            parsedStatus == InvitationIdentityStatus.availableExistingCustomer;
    if (eligible != statusIsEligible ||
        (isExistingCustomer &&
            parsedStatus !=
                InvitationIdentityStatus.availableExistingCustomer) ||
        (!hasExistingAuthIdentity && isExistingCustomer)) {
      throw const FormatException(
        'La verificación devolvió evidencia de identidad contradictoria.',
      );
    }

    return InvitationIdentityCheck(
      eligible: eligible,
      status: parsedStatus,
      hasExistingAuthIdentity: hasExistingAuthIdentity,
      isExistingCustomer: isExistingCustomer,
    );
  }

  final bool eligible;
  final InvitationIdentityStatus status;
  final bool hasExistingAuthIdentity;
  final bool isExistingCustomer;

  String get code => switch (status) {
        InvitationIdentityStatus.availableNewIdentity =>
          'available_new_identity',
        InvitationIdentityStatus.availableExistingCustomer =>
          'available_existing_customer',
        InvitationIdentityStatus.activeStaffRequiresDirectLink =>
          'active_staff_email_requires_direct_link',
        InvitationIdentityStatus.inactiveStaffMembership =>
          'staff_membership_inactive',
        InvitationIdentityStatus.externalErpMembership =>
          'staff_identity_tenant_conflict',
        InvitationIdentityStatus.workerIdentityConflict =>
          'worker_identity_conflict',
        InvitationIdentityStatus.historicalEmployeeIdentityConflict =>
          'historical_employee_identity_conflict',
      };
}

class EmployeeAccessState {
  const EmployeeAccessState({
    required this.employeeId,
    required this.employeeName,
    required this.email,
    required this.status,
    required this.erpUserId,
    required this.erpProfileActive,
    required this.pendingInvitation,
    required this.workerAccessExists,
    required this.workerAccessActive,
    required this.workerUsername,
    required this.linkState,
  });

  factory EmployeeAccessState.fromJson(Map<String, dynamic> json) {
    final employeeId = json['employeeId'];
    final employeeName = json['employeeName'];
    final email = json['email'];
    final status = json['status'];
    final erpUserId = json['erpUserId'];
    final erpProfileActive = json['erpProfileActive'];
    final pendingInvitation = json['pendingInvitation'];
    final workerAccessExists = json['workerAccessExists'];
    final workerAccessActive = json['workerAccessActive'];
    final workerUsername = json['workerUsername'];
    final rawLinkState = json['linkState'];

    if (employeeId is! String ||
        employeeId.trim().isEmpty ||
        employeeName is! String ||
        employeeName.trim().isEmpty ||
        status is! String ||
        status.trim().isEmpty ||
        erpProfileActive is! bool ||
        pendingInvitation is! bool ||
        workerAccessExists is! bool ||
        workerAccessActive is! bool ||
        (email != null && email is! String) ||
        (erpUserId != null && erpUserId is! String) ||
        (workerUsername != null && workerUsername is! String) ||
        rawLinkState is! String) {
      throw const FormatException(
        'Respuesta inválida al consultar los vínculos de trabajadores.',
      );
    }

    final parsedLinkState = switch (rawLinkState) {
      'available' => EmployeeErpLinkState.available,
      'pending_invitation' => EmployeeErpLinkState.pendingInvitation,
      'erp_linked' => EmployeeErpLinkState.erpLinked,
      'worker_active' => EmployeeErpLinkState.workerActive,
      'worker_suspended' => EmployeeErpLinkState.workerSuspended,
      'inconsistent' => EmployeeErpLinkState.inconsistent,
      _ => EmployeeErpLinkState.inconsistent,
    };
    final normalizedErpUserId =
        erpUserId is String && erpUserId.trim().isNotEmpty
            ? erpUserId.trim()
            : null;
    final normalizedWorkerUsername =
        workerUsername is String && workerUsername.trim().isNotEmpty
            ? workerUsername.trim()
            : null;

    final evidenceMatchesState = switch (parsedLinkState) {
      EmployeeErpLinkState.available => normalizedErpUserId == null &&
          !pendingInvitation &&
          !workerAccessExists &&
          !workerAccessActive,
      EmployeeErpLinkState.pendingInvitation =>
        normalizedErpUserId == null && pendingInvitation && !workerAccessActive,
      EmployeeErpLinkState.erpLinked => normalizedErpUserId != null &&
          !pendingInvitation &&
          !workerAccessActive,
      EmployeeErpLinkState.workerActive => normalizedErpUserId == null &&
          !pendingInvitation &&
          workerAccessExists &&
          workerAccessActive &&
          normalizedWorkerUsername != null,
      EmployeeErpLinkState.workerSuspended => normalizedErpUserId == null &&
          !pendingInvitation &&
          workerAccessExists &&
          !workerAccessActive &&
          normalizedWorkerUsername != null,
      EmployeeErpLinkState.inconsistent => true,
    };

    return EmployeeAccessState(
      employeeId: employeeId.trim(),
      employeeName: employeeName.trim(),
      email: email is String && email.trim().isNotEmpty ? email.trim() : null,
      status: status.trim(),
      erpUserId: normalizedErpUserId,
      erpProfileActive: erpProfileActive,
      pendingInvitation: pendingInvitation,
      workerAccessExists: workerAccessExists,
      workerAccessActive: workerAccessActive,
      workerUsername: normalizedWorkerUsername,
      linkState: evidenceMatchesState
          ? parsedLinkState
          : EmployeeErpLinkState.inconsistent,
    );
  }

  final String employeeId;
  final String employeeName;
  final String? email;
  final String status;
  final String? erpUserId;
  final bool erpProfileActive;
  final bool pendingInvitation;
  final bool workerAccessExists;
  final bool workerAccessActive;
  final String? workerUsername;
  final EmployeeErpLinkState linkState;

  bool get isActiveEmployee => status == 'active';

  bool get canReceiveErpLink =>
      isActiveEmployee &&
      (linkState == EmployeeErpLinkState.available ||
          linkState == EmployeeErpLinkState.workerSuspended);
}

List<EmployeeAccessState> parseEmployeeAccessStates(dynamic value) {
  if (value is! List) {
    throw const FormatException(
      'La respuesta no incluye los vínculos de trabajadores.',
    );
  }
  final result = <EmployeeAccessState>[];
  for (final item in value) {
    if (item is! Map) {
      throw const FormatException(
        'La respuesta incluye un vínculo de trabajador inválido.',
      );
    }
    result.add(
      EmployeeAccessState.fromJson(Map<String, dynamic>.from(item)),
    );
  }
  return List.unmodifiable(result);
}

bool canChangeEmployeeLink({
  required bool actionRunning,
  required bool employeeLinkNeedsReview,
  required bool profileActive,
  required bool hasHealthyEmployeeLink,
}) {
  return !actionRunning &&
      !employeeLinkNeedsReview &&
      (profileActive || hasHealthyEmployeeLink);
}

@visibleForTesting
void validateEmployeeLinkResult(
  Map<String, dynamic> result, {
  required String userId,
  required String employeeId,
  required bool linked,
}) {
  if (result['success'] != true ||
      result['linked'] != linked ||
      result['userId'] != userId ||
      result['employeeId'] != employeeId) {
    throw const FormatException(
      'La respuesta no confirmó el vínculo solicitado.',
    );
  }
}

class UserManagementException implements Exception {
  const UserManagementException({
    required this.code,
    required this.message,
    required this.status,
  });

  final String code;
  final String message;
  final int status;

  @override
  String toString() => message;
}

String localizedUserManagementError(String? code) {
  return switch (code) {
    'worker_access_conflict' =>
      'Este trabajador tiene un acceso activo en la app de trabajadores. Suspéndelo antes de vincular o invitar una cuenta ERP.',
    'worker_identity_conflict' =>
      'Ese correo pertenece a una identidad de Worker Space. Retira primero ese acceso antes de usarlo como cuenta ERP.',
    'employee_erp_link_conflict' =>
      'El trabajador o el usuario ya está vinculado a otra cuenta ERP. Revisa el vínculo actual antes de continuar.',
    'employee_erp_link_state_changed' =>
      'El vínculo cambió mientras trabajabas. La consola se actualizará para que revises el estado antes de intentarlo nuevamente.',
    'pending_invitation_exists' =>
      'Ya existe una invitación pendiente para ese correo o trabajador. Reenvíala o cancélala desde Invitaciones.',
    'staff_membership_inactive' =>
      'Ese correo pertenece a un usuario interno suspendido. Reactívalo desde Equipo en vez de crear otra invitación.',
    'active_staff_email_requires_direct_link' =>
      'Ese correo ya tiene acceso ERP activo. Vincula directamente ese usuario con el trabajador en vez de invitarlo otra vez.',
    'staff_identity_tenant_conflict' =>
      'Ese correo tiene una identidad ERP creada fuera de esta empresa. No se envió ninguna invitación; solicita su reconciliación.',
    'historical_employee_identity_conflict' =>
      'Ese correo ya está reservado por otro vínculo de trabajador. Revisa y reconcilia ese vínculo antes de invitarlo.',
    'identity_unavailable' =>
      'Ese correo tiene un vínculo de acceso incompatible. No se envió ninguna invitación; revisa su identidad antes de continuar.',
    'staff_identity_lookup_failed' =>
      'No pudimos verificar los accesos existentes de ese correo. No se envió ninguna invitación; inténtalo nuevamente.',
    'staff_membership_exists' =>
      'Ese correo ya pertenece a un usuario interno de esta empresa.',
    'employee_not_found' =>
      'El trabajador ya no está disponible o no pertenece a esta empresa.',
    'staff_user_not_found' =>
      'El usuario interno ya no está disponible en esta empresa.',
    'invitation_rate_limited' =>
      'La invitación se envió hace poco. Espera un minuto antes de reenviarla.',
    'self_role_change_forbidden' =>
      'No puedes cambiar tu propio rol o permisos. Pídeselo a otro administrador autorizado.',
    'principal_owner_protected' =>
      'La cuenta principal de la empresa está protegida y no puede modificarse desde esta acción.',
    'staff_hierarchy_forbidden' =>
      'Tu nivel de acceso no permite modificar esa cuenta interna.',
    'role_assignment_forbidden' ||
    'permission_grant_forbidden' =>
      'No puedes conceder un rol o permisos superiores a los que administras.',
    'staff_state_changed' =>
      'La cuenta cambió mientras trabajabas. La consola se actualizará antes de otro intento.',
    'invitation_not_found' =>
      'La invitación ya no está disponible. Actualiza la consola.',
    'invitation_delivery_failed' =>
      'No se pudo entregar el correo de invitación. No se marcó como enviado; inténtalo nuevamente.',
    'employee_lookup_failed' =>
      'No pudimos verificar al trabajador en este momento. Inténtalo nuevamente.',
    _ => 'No pudimos completar la gestión de acceso. Inténtalo nuevamente.',
  };
}

class WorkerPortalAccessState {
  const WorkerPortalAccessState({
    required this.employeeId,
    required this.hasAccess,
    required this.username,
    required this.isActive,
    required this.mustResetPassword,
    required this.lastLoginAt,
    required this.identityHealthy,
  });

  factory WorkerPortalAccessState.fromJson(Map<String, dynamic> json) {
    final employeeId = json['employeeId'];
    final hasAccess = json['hasAccess'];
    final username = json['username'];
    final isActive = json['isActive'];
    final mustResetPassword = json['mustResetPassword'];
    final lastLoginAt = json['lastLoginAt'];
    final identityHealthy = json['identityHealthy'];

    if (employeeId is! String ||
        employeeId.trim().isEmpty ||
        hasAccess is! bool ||
        isActive is! bool ||
        mustResetPassword is! bool ||
        identityHealthy is! bool ||
        (username != null && username is! String) ||
        (lastLoginAt != null && lastLoginAt is! String)) {
      throw const FormatException(
        'Respuesta inválida al consultar el acceso trabajador.',
      );
    }
    if (hasAccess && (username is! String || username.trim().isEmpty)) {
      throw const FormatException(
        'El acceso trabajador no tiene un usuario válido.',
      );
    }
    final parsedLastLoginAt =
        lastLoginAt == null ? null : DateTime.tryParse(lastLoginAt);
    if (lastLoginAt != null && parsedLastLoginAt == null) {
      throw const FormatException(
        'El acceso trabajador tiene una fecha de ingreso inválida.',
      );
    }

    return WorkerPortalAccessState(
      employeeId: employeeId,
      hasAccess: hasAccess,
      username: username as String?,
      isActive: isActive,
      mustResetPassword: mustResetPassword,
      lastLoginAt: parsedLastLoginAt,
      identityHealthy: identityHealthy,
    );
  }

  final String employeeId;
  final bool hasAccess;
  final String? username;
  final bool isActive;
  final bool mustResetPassword;
  final DateTime? lastLoginAt;
  final bool identityHealthy;
}

/// Tenant-scoped user administration service.
///
/// Regular tenant reads still use RLS/RPCs, but privileged auth operations run
/// through the `admin-user-management` Edge Function so service-role actions do
/// not live in the Flutter client.
class UserManagementService {
  UserManagementService(this._tenantService);

  final SupabaseClient _supabase = Supabase.instance.client;
  final TenantService _tenantService;

  Future<Map<String, dynamic>> getIdentityOverview({
    String search = '',
    String? customerId,
  }) {
    return _invokeAdmin<Map<String, dynamic>>({
      'action': 'overview',
      'search': search,
      if (customerId?.trim().isNotEmpty == true)
        'customerId': customerId!.trim(),
    });
  }

  Future<Map<String, dynamic>> createCustomerAccount({
    String? customerId,
    required String email,
    required String name,
    String? phone,
  }) {
    return _invokeAdmin<Map<String, dynamic>>({
      'action': 'create_customer_account',
      'customerId': customerId,
      'email': email,
      'name': name,
      'phone': phone,
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

  Future<Map<String, dynamic>> deleteCustomerAccount({
    required String customerId,
    bool deleteCustomerRecord = false,
  }) {
    return _invokeAdmin<Map<String, dynamic>>({
      'action': 'delete_customer_account',
      'customerId': customerId,
      'deleteCustomerRecord': deleteCustomerRecord,
    });
  }

  Future<Map<String, dynamic>> deleteWebsiteAuthAccount({
    required String authUserId,
  }) {
    return _invokeAdmin<Map<String, dynamic>>({
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
  }) async {
    final result = await _invokeAdmin<Map<String, dynamic>>({
      'action': 'create_internal_invitation',
      'email': email,
      'role': role,
      'permissions': permissions,
      'name': name,
      'employeeId': employeeId,
    });
    if (result['success'] != true || result['emailSent'] != true) {
      throw Exception('No se pudo enviar el correo de invitación.');
    }
    return result;
  }

  Future<InvitationIdentityCheck> checkInternalInvitationIdentity({
    required String email,
    String? employeeId,
  }) async {
    final result = await _invokeAdmin<Map<String, dynamic>>({
      'action': 'check_internal_invitation_identity',
      'email': email,
      'employeeId': employeeId,
    });
    return InvitationIdentityCheck.fromJson(result);
  }

  Future<void> linkInternalUserEmployee({
    required String userId,
    required String employeeId,
  }) async {
    final result = await _invokeAdmin<Map<String, dynamic>>({
      'action': 'link_internal_user_employee',
      'userId': userId,
      'employeeId': employeeId,
    });
    validateEmployeeLinkResult(
      result,
      userId: userId,
      employeeId: employeeId,
      linked: true,
    );
  }

  Future<void> unlinkInternalUserEmployee({
    required String userId,
    required String employeeId,
  }) async {
    final result = await _invokeAdmin<Map<String, dynamic>>({
      'action': 'unlink_internal_user_employee',
      'userId': userId,
      'employeeId': employeeId,
    });
    validateEmployeeLinkResult(
      result,
      userId: userId,
      employeeId: employeeId,
      linked: false,
    );
  }

  Future<void> resendInternalInvitation(String invitationId) async {
    final result = await _invokeAdmin<Map<String, dynamic>>({
      'action': 'resend_internal_invitation',
      'invitationId': invitationId,
    });
    if (result['success'] != true || result['emailSent'] != true) {
      throw Exception('No se pudo reenviar el correo de invitación.');
    }
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

  Future<Map<String, dynamic>> deleteUser(String userId) {
    return _invokeAdmin<Map<String, dynamic>>({
      'action': 'delete_internal_account',
      'userId': userId,
    });
  }

  Future<Map<String, dynamic>> createWorkerPortalAccount({
    required String employeeId,
    required String username,
    required String password,
  }) {
    _validateAdminManagedPassword(password);
    return _invokeAdmin<Map<String, dynamic>>({
      'action': 'create_worker_portal_account',
      'employeeId': employeeId,
      'username': username,
      'password': password,
    });
  }

  Future<WorkerPortalAccessState> getWorkerPortalAccess({
    required String employeeId,
  }) async {
    final result = await _invokeAdmin<Map<String, dynamic>>({
      'action': 'get_worker_portal_access',
      'employeeId': employeeId,
    });
    final access = WorkerPortalAccessState.fromJson(result);
    if (access.employeeId != employeeId) {
      throw const FormatException(
        'La respuesta de acceso no corresponde al trabajador solicitado.',
      );
    }
    return access;
  }

  Future<Map<String, dynamic>> resetWorkerPortalPassword({
    required String employeeId,
    required String password,
  }) {
    _validateAdminManagedPassword(password);
    return _invokeAdmin<Map<String, dynamic>>({
      'action': 'reset_worker_portal_password',
      'employeeId': employeeId,
      'password': password,
    });
  }

  void _validateAdminManagedPassword(String password) {
    final validationError =
        AuthInputValidation.validateAdminManagedPassword(password);
    if (validationError != null) {
      throw ArgumentError(validationError, 'password');
    }
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

  Future<Map<String, dynamic>> sendPasswordReset(String email) async {
    final result = await _invokeAdmin<Map<String, dynamic>>({
      'action': 'send_password_reset',
      'email': email,
    });
    if (result['accessEmailSent'] != true) {
      throw Exception('No se pudo enviar el correo de acceso.');
    }
    return result;
  }

  Future<T> _invokeAdmin<T>(Map<String, dynamic> body) async {
    try {
      final response = await _supabase.functions.invoke(
        'admin-user-management',
        body: body,
      );

      if (response.status >= 400) {
        final data = response.data;
        final code = _extractAdminCode(data);
        throw UserManagementException(
          code: code ?? 'admin_operation_failed',
          message: localizedUserManagementError(code),
          status: response.status,
        );
      }

      final data = response.data;
      if (data is T) return data;
      return Map<String, dynamic>.from(data as Map) as T;
    } on FunctionException catch (e) {
      final code = _extractAdminCode(e.details);
      final message = localizedUserManagementError(code);
      debugPrint(
        'User admin operation failed: ${code ?? 'function_error'}',
      );
      throw UserManagementException(
        code: code ?? 'function_error',
        message: message,
        status: e.status,
      );
    } on UserManagementException {
      rethrow;
    } catch (e) {
      debugPrint('User admin operation failed');
      rethrow;
    }
  }

  String? _extractAdminCode(dynamic value) {
    if (value is Map) {
      final code = value['code'];
      if (code is String && code.trim().isNotEmpty) return code.trim();
      for (final key in const ['details', 'error']) {
        final nested = _extractAdminCode(value[key]);
        if (nested != null) return nested;
      }
    }
    if (value is List) {
      for (final item in value) {
        final nested = _extractAdminCode(item);
        if (nested != null) return nested;
      }
    }
    return null;
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
