import 'package:flutter/foundation.dart';

/// Redacted coworker identity returned by `get_erp_employee_directory()`.
///
/// This model deliberately excludes employee contact, health, contract,
/// banking and remuneration fields. Consumers that only need to identify a
/// coworker must use this projection instead of the full HR employee model.
@immutable
class ErpEmployeeDirectoryEntry {
  const ErpEmployeeDirectoryEntry({
    required this.employeeId,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.jobTitle,
    required this.systemRole,
    required this.status,
    required this.photoUrl,
    required this.departmentId,
  });

  final String employeeId;
  final String? userId;
  final String firstName;
  final String lastName;
  final String? jobTitle;
  final String? systemRole;
  final String status;
  final String? photoUrl;
  final String? departmentId;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final first = firstName.trim();
    final last = lastName.trim();
    if (first.isEmpty && last.isEmpty) return '?';
    if (last.isEmpty) return first.substring(0, 1).toUpperCase();
    if (first.isEmpty) return last.substring(0, 1).toUpperCase();
    return '${first[0]}${last[0]}'.toUpperCase();
  }
}
