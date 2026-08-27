/// Una persona del directorio de asignación
/// (`get_smart_task_assignment_directory_v1`).
///
/// Un principal canónico por persona, con acceso explícito:
///  * `erp`    — principal ERP; elegible y principal de mensajería.
///  * `portal` — trabajador con cuenta de portal; elegible, sin mensajería.
///  * `none`   — empleado activo sin cuenta: NO elegible; la UI lo muestra
///    honesto con «Sin acceso» / «Invitar», nunca lo esconde.
enum TaskPrincipalAccess { erp, portal, none }

class TaskAssignmentPrincipal {
  final String tenantId;
  final String? userId;
  final String? employeeId;
  final String displayName;
  final String role;
  final String? photoUrl;
  final TaskPrincipalAccess access;

  const TaskAssignmentPrincipal({
    required this.tenantId,
    required this.userId,
    required this.employeeId,
    required this.displayName,
    required this.role,
    required this.photoUrl,
    required this.access,
  });

  factory TaskAssignmentPrincipal.fromJson(Map<String, dynamic> json) {
    final access = switch (json['access']?.toString()) {
      'erp' => TaskPrincipalAccess.erp,
      'portal' => TaskPrincipalAccess.portal,
      _ => TaskPrincipalAccess.none,
    };
    return TaskAssignmentPrincipal(
      tenantId: json['tenant_id'].toString(),
      userId: json['user_id']?.toString(),
      employeeId: json['employee_id']?.toString(),
      displayName: json['display_name']?.toString() ?? 'Sin nombre',
      role: json['role']?.toString() ?? 'worker',
      photoUrl: json['photo_url']?.toString(),
      access: access,
    );
  }

  bool get isAssignable =>
      userId != null && access != TaskPrincipalAccess.none;

  String get initials {
    final words = displayName
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.single[0].toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}
