class JobRole {
  final String id;
  final String tenantId;
  final String
      systemRole; // 'admin', 'manager', 'cashier', 'mechanic', 'accountant'
  final String displayName; // 'Administrador', 'Gerente', etc.
  final List<String> suggestedTitles;
  final Map<String, dynamic> defaultPermissions;
  final String? description;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  JobRole({
    required this.id,
    required this.tenantId,
    required this.systemRole,
    required this.displayName,
    required this.suggestedTitles,
    required this.defaultPermissions,
    this.description,
    required this.sortOrder,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JobRole.fromJson(Map<String, dynamic> json) {
    return JobRole(
      id: json['id'],
      tenantId: json['tenant_id'],
      systemRole: json['system_role'],
      displayName: json['display_name'],
      suggestedTitles: List<String>.from(json['suggested_titles'] ?? []),
      defaultPermissions:
          Map<String, dynamic>.from(json['default_permissions'] ?? {}),
      description: json['description'],
      sortOrder: json['sort_order'] ?? 0,
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'system_role': systemRole,
      'display_name': displayName,
      'suggested_titles': suggestedTitles,
      'default_permissions': defaultPermissions,
      'description': description,
      'sort_order': sortOrder,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Helper: Get permissions as Map<String, bool>
  Map<String, bool> get permissions {
    return defaultPermissions.map((key, value) => MapEntry(key, value as bool));
  }

  // Helper: Get Spanish role name
  static String getRoleDisplayName(String systemRole) {
    switch (systemRole) {
      case 'admin':
        return 'Administrador';
      case 'manager':
        return 'Gerente';
      case 'cashier':
        return 'Cajero';
      case 'mechanic':
        return 'Mecánico';
      case 'accountant':
        return 'Contador';
      default:
        return systemRole;
    }
  }

  // Helper: Map job title to system role (smart detection)
  static String? inferSystemRole(String jobTitle) {
    final lower = jobTitle.toLowerCase();

    if (lower.contains('admin') ||
        lower.contains('dueño') ||
        lower.contains('propietario')) {
      return 'admin';
    }
    if (lower.contains('gerente') || lower.contains('jefe')) {
      return 'manager';
    }
    if (lower.contains('cajero') || lower.contains('vendedor')) {
      return 'cashier';
    }
    if (lower.contains('mecánico') ||
        lower.contains('mecanico') ||
        lower.contains('técnico') ||
        lower.contains('tecnico')) {
      return 'mechanic';
    }
    if (lower.contains('contador') || lower.contains('contable')) {
      return 'accountant';
    }

    return null; // Unknown, user must select
  }
}
