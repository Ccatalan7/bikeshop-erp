import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/current_user_profile.dart';
import 'self_password_service.dart';

enum CurrentUserProfileLoadIssue {
  invalidAccessContext,
  inconsistentEmployeeLink,
  unavailable,
}

class _CurrentUserProfileUnavailable implements Exception {
  const _CurrentUserProfileUnavailable();

  @override
  String toString() => 'Current ERP profile is temporarily unavailable';
}

abstract class CurrentUserProfileGateway {
  Future<Map<String, dynamic>> getMyErpProfile();

  Future<List<Map<String, dynamic>>> getTenantRows(String tenantId);

  Future<void> updateAuthDisplayName({
    required String userId,
    required String displayName,
  });

  Future<Map<String, dynamic>> updateMyEmployeeContact(
    Map<String, dynamic> patch,
  );
}

class SupabaseCurrentUserProfileGateway implements CurrentUserProfileGateway {
  SupabaseCurrentUserProfileGateway([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> getMyErpProfile() async {
    final response = await _client.rpc('get_my_erp_profile');
    if (response is! Map) {
      throw const FormatException('Invalid ERP profile response');
    }
    return Map<String, dynamic>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> getTenantRows(String tenantId) async {
    final response = await _client
        .from('tenants')
        .select('id, shop_name, subdomain, is_active')
        .eq('id', tenantId)
        .eq('is_active', true)
        .limit(2);
    return List<Map<String, dynamic>>.from(response);
  }

  @override
  Future<void> updateAuthDisplayName({
    required String userId,
    required String displayName,
  }) async {
    final response = await _client.auth.updateUser(
      UserAttributes(
        data: {
          'display_name': displayName,
          'full_name': displayName,
          'name': displayName,
        },
      ),
    );
    if (response.user?.id != userId) {
      throw const AuthException('No pudimos actualizar el nombre visible.');
    }
  }

  @override
  Future<Map<String, dynamic>> updateMyEmployeeContact(
    Map<String, dynamic> patch,
  ) async {
    final response = await _client.rpc(
      'update_my_employee_contact',
      params: {'p_patch': patch},
    );
    if (response is! Map) {
      throw const FormatException('Invalid employee contact response');
    }
    return Map<String, dynamic>.from(response);
  }
}

/// Session-scoped read model and safe self-service commands for `/profile`.
///
/// Every load is bound to one Auth user, one resolved tenant, and one
/// resolution generation. A late response from a previous scope cannot
/// repopulate the current profile.
class CurrentUserProfileService extends ChangeNotifier {
  CurrentUserProfileService({
    CurrentUserProfileGateway? gateway,
    SelfPasswordService? passwordService,
  })  : _gateway = gateway ?? SupabaseCurrentUserProfileGateway(),
        _passwordService = passwordService;

  static const _roles = {
    'admin',
    'manager',
    'cashier',
    'mechanic',
    'accountant',
  };

  final CurrentUserProfileGateway _gateway;
  SelfPasswordService? _passwordService;

  SelfPasswordService get _password =>
      _passwordService ??= SelfPasswordService();

  CurrentUserProfile? _profile;
  CurrentUserProfileLoadIssue? _loadIssue;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _disposed = false;
  int _generation = 0;
  int _scopeGeneration = 0;
  String? _userId;
  String? _tenantId;
  String? _identityFingerprint;
  String? _pendingOtherSessionsRevocationUserId;

  CurrentUserProfile? get profile => _profile;
  CurrentUserProfileLoadIssue? get loadIssue => _loadIssue;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get hasPendingOtherSessionsRevocation =>
      _userId != null && _pendingOtherSessionsRevocationUserId == _userId;

  Future<void> synchronize({
    required CurrentUserIdentity? identity,
    required Future<String?> Function() resolveTenantId,
    bool force = false,
  }) async {
    if (_disposed) return;
    if (identity == null) {
      _clear();
      return;
    }

    final fingerprint = _fingerprint(identity);
    final sameIdentity = _userId == identity.id;
    final previousFingerprint = _identityFingerprint;
    final wasLoading = _isLoading;
    final generation = ++_generation;
    if (!sameIdentity) {
      _scopeGeneration++;
      _tenantId = null;
      _profile = null;
      _loadIssue = null;
      _isSaving = false;
      _pendingOtherSessionsRevocationUserId = null;
    }
    _userId = identity.id;
    _identityFingerprint = fingerprint;
    _isLoading = true;
    _notify();

    String? resolvedTenantId;
    String? rpcTenantId;
    try {
      resolvedTenantId = await resolveTenantId();
      if (!_isCurrent(identity.id, generation)) return;

      final scopeChanged = resolvedTenantId != null &&
          _bindResolvedTenantScope(resolvedTenantId);
      final hasCurrentProfile = _profile?.userId == identity.id &&
          _profile?.tenantId == resolvedTenantId;
      if (resolvedTenantId != null &&
          !force &&
          !scopeChanged &&
          !wasLoading &&
          previousFingerprint == fingerprint &&
          hasCurrentProfile &&
          _loadIssue == null) {
        return;
      }

      final context = await _gateway.getMyErpProfile();
      if (!_isCurrent(identity.id, generation)) return;
      rpcTenantId = _optionalString(context['tenantId']);
      final next = await _parseProfile(
        identity: identity,
        context: context,
        resolvedTenantId: resolvedTenantId,
      );
      if (!_isCurrent(identity.id, generation)) return;

      _profile = next;
      _loadIssue = null;
    } catch (error) {
      if (!_isCurrent(identity.id, generation)) return;
      final issue = _classifyLoadIssue(error);
      final preserveLastValidProfile =
          issue == CurrentUserProfileLoadIssue.unavailable &&
              _canPreserveLastValidProfile(
                identity.id,
                resolvedTenantId: resolvedTenantId,
                rpcTenantId: rpcTenantId,
              );
      if (!preserveLastValidProfile) {
        _invalidateProfileAuthority();
      }
      _loadIssue = issue;
      debugPrint('⚠️ [MyProfile] Scoped profile load failed');
    } finally {
      if (_isCurrent(identity.id, generation)) {
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> updateDisplayName(String value) async {
    final current = _profile;
    if (current == null || !current.canEditDisplayName || _isSaving) {
      throw StateError('Display name is not self-editable');
    }

    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length < 2 ||
        normalized.length > 80 ||
        normalized.contains(RegExp(r'[\u0000-\u001F\u007F]'))) {
      throw ArgumentError(
        'El nombre visible debe tener entre 2 y 80 caracteres.',
        'value',
      );
    }

    final scopeGeneration = _scopeGeneration;
    final userId = current.userId;
    final tenantId = current.tenantId;
    _isSaving = true;
    _notify();
    try {
      await _gateway.updateAuthDisplayName(
        userId: userId,
        displayName: normalized,
      );
      if (_isCurrentScope(userId, tenantId, scopeGeneration) &&
          _profile?.canEditDisplayName == true) {
        _profile = _profile!.copyWith(displayName: normalized);
      }
    } finally {
      if (_isCurrentScope(userId, tenantId, scopeGeneration)) {
        _isSaving = false;
        _notify();
      }
    }
  }

  Future<void> updateEmployeePersonalContact(
    EmployeePersonalContactUpdate update,
  ) async {
    final current = _profile;
    final currentEmployee = current?.employee;
    if (current == null ||
        currentEmployee == null ||
        !current.canEditEmployeeContact ||
        _isSaving) {
      throw StateError('Employee contact is not self-editable');
    }

    final nextPhone = _normalizeContact(update.phone, 32, 'Teléfono');
    final nextAddress = _normalizeContact(update.address, 240, 'Dirección');
    final nextCity = _normalizeContact(update.city, 120, 'Ciudad');
    final nextEmergencyName = _normalizeContact(
      update.emergencyContactName,
      160,
      'Contacto de emergencia',
    );
    final nextEmergencyPhone = _normalizeContact(
      update.emergencyContactPhone,
      32,
      'Teléfono de emergencia',
    );
    final patch = <String, dynamic>{};
    _addChangedContact(patch, 'phone', nextPhone, currentEmployee.phone);
    _addChangedContact(
      patch,
      'address',
      nextAddress,
      currentEmployee.address,
    );
    _addChangedContact(patch, 'city', nextCity, currentEmployee.city);
    _addChangedContact(
      patch,
      'emergency_contact_name',
      nextEmergencyName,
      currentEmployee.emergencyContactName,
    );
    _addChangedContact(
      patch,
      'emergency_contact_phone',
      nextEmergencyPhone,
      currentEmployee.emergencyContactPhone,
    );
    if (patch.isEmpty) return;

    final scopeGeneration = _scopeGeneration;
    final userId = current.userId;
    final tenantId = current.tenantId;
    _isSaving = true;
    _notify();
    try {
      final response = await _gateway.updateMyEmployeeContact(patch);
      final updatedEmployee = _parseEmployee(response);
      if (updatedEmployee.id != currentEmployee.id) {
        throw const FormatException('Employee identity changed');
      }
      if (_isCurrentScope(userId, tenantId, scopeGeneration) &&
          _profile?.canEditEmployeeContact == true &&
          _profile?.employee?.id == currentEmployee.id) {
        _profile = _profile!.copyWith(employee: updatedEmployee);
      }
    } finally {
      if (_isCurrentScope(userId, tenantId, scopeGeneration)) {
        _isSaving = false;
        _notify();
      }
    }
  }

  Future<void> requestPasswordReauthentication() {
    return _password.requestReauthentication();
  }

  Future<SelfPasswordUpdateResult> updatePassword(
    String newPassword, {
    String? reauthenticationNonce,
  }) async {
    final commandUserId = _userId;
    final result = await _password.updatePassword(
      newPassword,
      reauthenticationNonce: reauthenticationNonce,
    );
    if (_userId == commandUserId) {
      _pendingOtherSessionsRevocationUserId =
          result.needsOtherSessionsRevocationRetry ? commandUserId : null;
      _notify();
    }
    return result;
  }

  Future<SelfPasswordOtherSessionsRevocationOutcome>
      retryOtherSessionRevocation() async {
    if (!hasPendingOtherSessionsRevocation) {
      throw StateError('No other-session revocation retry is pending');
    }
    final commandUserId = _userId;
    final outcome = await _password.retryOtherSessionRevocation();
    if (_userId == commandUserId &&
        outcome == SelfPasswordOtherSessionsRevocationOutcome.revoked) {
      _pendingOtherSessionsRevocationUserId = null;
    }
    if (_userId == commandUserId) _notify();
    return outcome;
  }

  static SelfPasswordUpdateIssue classifyPasswordUpdateError(Object error) {
    return SelfPasswordService.classifyUpdateError(error);
  }

  Future<CurrentUserProfile> _parseProfile({
    required CurrentUserIdentity identity,
    required Map<String, dynamic> context,
    required String? resolvedTenantId,
  }) async {
    final userId = _requiredString(context, 'userId');
    final tenantId = _requiredString(context, 'tenantId');
    _requiredString(context, 'profileId');
    final role = _requiredString(context, 'role').toLowerCase();

    if (resolvedTenantId == null) {
      throw const _CurrentUserProfileUnavailable();
    }
    if (userId != identity.id ||
        resolvedTenantId != tenantId ||
        !_roles.contains(role)) {
      throw const FormatException('Invalid ERP profile authority');
    }

    final permissions = _parsePermissions(context['permissions']);
    final tenantRows = await _gateway.getTenantRows(tenantId);
    if (tenantRows.length != 1) {
      throw const FormatException('Invalid tenant context');
    }
    final tenant = tenantRows.single;
    if (_requiredString(tenant, 'id') != tenantId ||
        tenant['is_active'] != true) {
      throw const FormatException('Invalid tenant context');
    }
    final tenantName = _requiredString(tenant, 'shop_name');
    final tenantSubdomain = _optionalString(tenant['subdomain']);

    final employeeValue = context['employee'];
    final employee = employeeValue == null
        ? null
        : employeeValue is Map
            ? _parseEmployee(Map<String, dynamic>.from(employeeValue))
            : throw const FormatException('Invalid employee context');

    final displayName = employee?.fullName ??
        identity.metadataDisplayName ??
        _emailFallback(identity.email);

    return CurrentUserProfile(
      userId: identity.id,
      email: identity.email,
      emailVerified: identity.emailVerified,
      displayName: displayName,
      tenantId: tenantId,
      tenantName: tenantName,
      tenantSubdomain: tenantSubdomain,
      role: role,
      permissions: Map<String, bool>.unmodifiable(permissions),
      employeeLinkState: employee == null
          ? EmployeeLinkState.unlinked
          : EmployeeLinkState.linked,
      employee: employee,
    );
  }

  CurrentEmployeeProfile _parseEmployee(Map<String, dynamic> value) {
    final firstName = _requiredString(value, 'firstName');
    final lastName = _requiredString(value, 'lastName');
    final updatedAt =
        DateTime.tryParse(_requiredString(value, 'updatedAt'))?.toUtc();
    if (updatedAt == null) {
      throw const FormatException('Invalid employee version');
    }

    return CurrentEmployeeProfile(
      id: _requiredString(value, 'id'),
      fullName: '$firstName $lastName',
      employeeNumber: _requiredString(value, 'employeeNumber'),
      email: _optionalString(value['email']),
      rut: _optionalString(value['rut']),
      jobTitle: _requiredString(value, 'jobTitle'),
      departmentName: _optionalString(value['departmentName']),
      status: _requiredString(value, 'status'),
      photoUrl: _optionalString(value['photoUrl']),
      phone: _optionalString(value['phone']),
      address: _optionalString(value['address']),
      city: _optionalString(value['city']),
      emergencyContactName: _optionalString(value['emergencyContactName']),
      emergencyContactPhone: _optionalString(value['emergencyContactPhone']),
      updatedAt: updatedAt,
    );
  }

  Map<String, bool> _parsePermissions(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid permissions');
    }
    final result = <String, bool>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! bool) {
        throw const FormatException('Invalid permissions');
      }
      result[entry.key as String] = entry.value as bool;
    }
    return result;
  }

  CurrentUserProfileLoadIssue _classifyLoadIssue(Object error) {
    if (error is _CurrentUserProfileUnavailable) {
      return CurrentUserProfileLoadIssue.unavailable;
    }
    final message = switch (error) {
      PostgrestException exception => exception.message.toLowerCase(),
      _ => error.toString().toLowerCase(),
    };
    if (message.contains('erp_employee_link_inconsistent')) {
      return CurrentUserProfileLoadIssue.inconsistentEmployeeLink;
    }
    if (message.contains('erp_profile_context_invalid') ||
        error is FormatException) {
      return CurrentUserProfileLoadIssue.invalidAccessContext;
    }
    return CurrentUserProfileLoadIssue.unavailable;
  }

  String _fingerprint(CurrentUserIdentity identity) {
    return [
      identity.id,
      identity.email,
      identity.emailVerified,
      identity.metadataDisplayName ?? '',
    ].join('|');
  }

  bool _isCurrent(String userId, int generation) {
    return !_disposed && _userId == userId && _generation == generation;
  }

  bool _isCurrentScope(
    String userId,
    String tenantId,
    int scopeGeneration,
  ) {
    return !_disposed &&
        _userId == userId &&
        _tenantId == tenantId &&
        _scopeGeneration == scopeGeneration;
  }

  bool _bindResolvedTenantScope(String tenantId) {
    if (_tenantId == tenantId) return false;
    _scopeGeneration++;
    _tenantId = tenantId;
    _profile = null;
    _loadIssue = null;
    _isSaving = false;
    _notify();
    return true;
  }

  bool _canPreserveLastValidProfile(
    String userId, {
    required String? resolvedTenantId,
    required String? rpcTenantId,
  }) {
    final current = _profile;
    if (current == null ||
        current.userId != userId ||
        _userId != userId ||
        _tenantId != current.tenantId) {
      return false;
    }
    if (resolvedTenantId != null && resolvedTenantId != current.tenantId) {
      return false;
    }
    if (rpcTenantId != null && rpcTenantId != current.tenantId) {
      return false;
    }
    return true;
  }

  void _invalidateProfileAuthority() {
    _scopeGeneration++;
    _profile = null;
    _isSaving = false;
  }

  void _clear() {
    _generation++;
    _scopeGeneration++;
    _userId = null;
    _tenantId = null;
    _identityFingerprint = null;
    _profile = null;
    _loadIssue = null;
    _isLoading = false;
    _isSaving = false;
    _pendingOtherSessionsRevocationUserId = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _requiredString(Map<String, dynamic> value, String key) {
    final result = _optionalString(value[key]);
    if (result == null) throw FormatException('Missing $key');
    return result;
  }

  String? _optionalString(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String? _normalizeOptional(String? value) {
    final normalized = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String? _normalizeContact(String? value, int maxLength, String field) {
    final normalized = _normalizeOptional(value);
    if ((normalized?.length ?? 0) > maxLength ||
        (normalized?.contains(RegExp(r'[\u0000-\u001F\u007F]')) ?? false)) {
      throw ArgumentError('$field contiene un valor no permitido.');
    }
    return normalized;
  }

  void _addChangedContact(
    Map<String, dynamic> patch,
    String key,
    String? next,
    String? current,
  ) {
    if (next != _normalizeOptional(current)) patch[key] = next;
  }

  String _emailFallback(String email) {
    final at = email.indexOf('@');
    if (at > 0) return email.substring(0, at);
    return email.isEmpty ? 'Usuario ERP' : email;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _scopeGeneration++;
    super.dispose();
  }
}
