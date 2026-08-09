import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum EmployeeLinkState {
  unlinked,
  linked,
  inconsistent,
}

@immutable
class CurrentUserIdentity {
  const CurrentUserIdentity({
    required this.id,
    required this.email,
    required this.emailVerified,
    required this.metadata,
  });

  factory CurrentUserIdentity.fromUser(User user) {
    return CurrentUserIdentity(
      id: user.id,
      email: user.email?.trim() ?? '',
      emailVerified: user.emailConfirmedAt != null,
      metadata:
          Map<String, dynamic>.unmodifiable(user.userMetadata ?? const {}),
    );
  }

  final String id;
  final String email;
  final bool emailVerified;
  final Map<String, dynamic> metadata;

  String? get metadataDisplayName {
    for (final key in const ['display_name', 'full_name', 'name']) {
      final value = metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}

@immutable
class CurrentEmployeeProfile {
  const CurrentEmployeeProfile({
    required this.id,
    required this.fullName,
    required this.employeeNumber,
    required this.email,
    required this.rut,
    required this.jobTitle,
    required this.departmentName,
    required this.status,
    required this.photoUrl,
    required this.phone,
    required this.address,
    required this.city,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.updatedAt,
  });

  final String id;
  final String fullName;
  final String employeeNumber;
  final String? email;
  final String? rut;
  final String jobTitle;
  final String? departmentName;
  final String status;
  final String? photoUrl;
  final String? phone;
  final String? address;
  final String? city;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final DateTime updatedAt;

  CurrentEmployeeProfile copyWith({
    String? phone,
    String? address,
    String? city,
    String? emergencyContactName,
    String? emergencyContactPhone,
    DateTime? updatedAt,
  }) {
    return CurrentEmployeeProfile(
      id: id,
      fullName: fullName,
      employeeNumber: employeeNumber,
      email: email,
      rut: rut,
      jobTitle: jobTitle,
      departmentName: departmentName,
      status: status,
      photoUrl: photoUrl,
      phone: phone,
      address: address,
      city: city,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  CurrentEmployeeProfile withPersonalContact({
    required String? phone,
    required String? address,
    required String? city,
    required String? emergencyContactName,
    required String? emergencyContactPhone,
    required DateTime updatedAt,
  }) {
    return CurrentEmployeeProfile(
      id: id,
      fullName: fullName,
      employeeNumber: employeeNumber,
      email: email,
      rut: rut,
      jobTitle: jobTitle,
      departmentName: departmentName,
      status: status,
      photoUrl: photoUrl,
      phone: phone,
      address: address,
      city: city,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
      updatedAt: updatedAt,
    );
  }
}

@immutable
class EmployeePersonalContactUpdate {
  const EmployeePersonalContactUpdate({
    required this.phone,
    required this.address,
    required this.city,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
  });

  final String? phone;
  final String? address;
  final String? city;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
}

@immutable
class CurrentUserProfile {
  const CurrentUserProfile({
    required this.userId,
    required this.email,
    required this.emailVerified,
    required this.displayName,
    required this.tenantId,
    required this.tenantName,
    required this.tenantSubdomain,
    required this.role,
    required this.permissions,
    required this.employeeLinkState,
    required this.employee,
  });

  final String userId;
  final String email;
  final bool emailVerified;
  final String displayName;
  final String tenantId;
  final String tenantName;
  final String? tenantSubdomain;
  final String role;
  final Map<String, bool> permissions;
  final EmployeeLinkState employeeLinkState;
  final CurrentEmployeeProfile? employee;

  bool get canEditDisplayName =>
      employeeLinkState == EmployeeLinkState.unlinked;

  bool get canEditEmployeeContact =>
      employeeLinkState == EmployeeLinkState.linked &&
      employee?.status == 'active';

  bool get canManageUsers =>
      role == 'owner' ||
      role == 'admin' ||
      role == 'manager' ||
      permissions['manage_users'] == true;

  bool get canAccessAccounting =>
      role == 'owner' ||
      role == 'admin' ||
      role == 'manager' ||
      role == 'accountant' ||
      permissions['access_accounting'] == true;

  /// Mirrors the server-owned capability returned by get_my_erp_profile.
  /// Role names are intentionally not reinterpreted in Flutter.
  bool get canManageSupplierCredentials =>
      permissions['can_manage_supplier_credentials'] == true;

  String get initials {
    final words = displayName
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      return words.single.substring(0, 1).toUpperCase();
    }
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  CurrentUserProfile copyWith({
    String? displayName,
    CurrentEmployeeProfile? employee,
  }) {
    return CurrentUserProfile(
      userId: userId,
      email: email,
      emailVerified: emailVerified,
      displayName: displayName ?? this.displayName,
      tenantId: tenantId,
      tenantName: tenantName,
      tenantSubdomain: tenantSubdomain,
      role: role,
      permissions: permissions,
      employeeLinkState: employeeLinkState,
      employee: employee ?? this.employee,
    );
  }
}
