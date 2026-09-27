/// Una persona del directorio de asignación
/// (`get_smart_task_assignment_directory_v1`).
///
/// Un principal canónico por persona, con acceso explícito:
///  * `erp`    — principal ERP; elegible y principal de mensajería.
///  * `portal` — trabajador con cuenta de portal; elegible, sin mensajería.
///  * `none`   — trabajador activo sin cuenta. **También es elegible**
///    (dueño, 2026-09-26): la tarea es de la persona y, cuando tenga una
///    cuenta, le llega sola a su bandeja (`smart_task_sync_employee_account_v1`).
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

  /// Se asigna a la persona: basta con que sea trabajador. Quien no es
  /// trabajador (un dueño sin ficha) necesita una cuenta utilizable.
  bool get isAssignable =>
      employeeId != null ||
      (userId != null && access != TaskPrincipalAccess.none);

  /// Con qué se asigna: el trabajador si lo hay, si no la cuenta. Es también
  /// la clave con la que la bandeja agrupa y nombra al responsable.
  String get assignmentKey => employeeId ?? userId!;

  /// Contexto operativo para elegir un responsable. Los valores de seguridad
  /// (`portal`, `worker`, `admin`, etc.) pertenecen al contrato interno y no
  /// son lenguaje para el operador.
  String get assignmentContextLabel => switch (access) {
        TaskPrincipalAccess.portal => 'Recibe tareas en su portal',
        TaskPrincipalAccess.erp => switch (role.trim().toLowerCase()) {
            'admin' => 'Administración',
            'manager' => 'Gerencia',
            'accountant' => 'Contabilidad',
            'mechanic' => 'Taller',
            'cashier' => 'Caja',
            _ => 'Equipo ERP',
          },
        TaskPrincipalAccess.none => 'Sin cuenta: la verá cuando tenga una',
      };

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
