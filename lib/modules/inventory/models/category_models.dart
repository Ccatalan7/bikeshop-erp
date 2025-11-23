class Category {
  final String? id;
  final String tenantId; // uuid - MULTI-TENANT ISOLATION
  final String name;
  final String fullPath; // "Accesorios / Asientos / Tija"
  final String? parentId;
  final int level; // 0 = root, 1 = child, 2 = grandchild
  final String? description;
  final String? imageUrl;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Phase 1: Compatibility Engine Integration (OLD - kept for backward compatibility)
  final Map<String, dynamic>? compatibilityMetadata; // JSONB with component_code, attributes array
  final List<String>? disciplineScope; // ['mtb', 'road', 'gravel']
  final String? iconName; // 'cassette', 'hub', 'fork'
  
  // NEW Flexible System: Simple FK reference to global component library
  final String? componentTypeCode; // e.g., 'hub', 'frame', 'cassette' - user maps manually

  Category({
    this.id,
    required this.tenantId,
    required this.name,
    required this.fullPath,
    this.parentId,
    this.level = 0,
    this.description,
    this.imageUrl,
    this.isActive = true,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.compatibilityMetadata,
    this.disciplineScope,
    this.iconName,
    this.componentTypeCode,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Get breadcrumb parts: ["Accesorios", "Asientos", "Tija"]
  List<String> get breadcrumbs => fullPath.split(' / ').map((s) => s.trim()).toList();
  
  // Is this a root category?
  bool get isRoot => level == 0 && parentId == null;
  
  // Get the direct parent name (last part before this one)
  String? get parentName {
    final parts = breadcrumbs;
    if (parts.length > 1) {
      return parts[parts.length - 2];
    }
    return null;
  }
  
  // Phase 1: Compatibility helpers (OLD system)
  bool get hasCompatibilityMetadata => 
    compatibilityMetadata != null && 
    compatibilityMetadata!.containsKey('component_code');
  
  // NEW Flexible System: Check if category is mapped to a component type
  bool get hasComponentType => componentTypeCode != null && componentTypeCode!.isNotEmpty;
  
  String? get componentCode => 
    hasCompatibilityMetadata ? compatibilityMetadata!['component_code'] as String? : null;
  
  List<Map<String, dynamic>> get compatibilityAttributes {
    if (!hasCompatibilityMetadata) return [];
    final attrs = compatibilityMetadata!['attributes'];
    if (attrs is List) {
      return attrs.cast<Map<String, dynamic>>();
    }
    return [];
  }

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      name: json['name'],
      fullPath: json['full_path'] ?? json['name'],
      parentId: json['parent_id']?.toString(),
      level: json['level'] ?? 0,
      description: json['description'],
      imageUrl: json['image_url'],
      isActive: json['is_active'] ?? true,
      sortOrder: json['sort_order'] ?? 0,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      compatibilityMetadata: json['compatibility_metadata'] as Map<String, dynamic>?,
      disciplineScope: json['discipline_scope'] != null
          ? List<String>.from(json['discipline_scope'] as List)
          : null,
      iconName: json['icon_name'] as String?,
      componentTypeCode: json['component_type_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'name': name,
      'full_path': fullPath,
      if (parentId != null) 'parent_id': parentId,
      'level': level,
      'description': description,
      'image_url': imageUrl,
      'is_active': isActive,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (compatibilityMetadata != null) 'compatibility_metadata': compatibilityMetadata,
      if (disciplineScope != null) 'discipline_scope': disciplineScope,
      if (iconName != null) 'icon_name': iconName,
      if (componentTypeCode != null) 'component_type_code': componentTypeCode,
    };
  }

  Category copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? fullPath,
    String? parentId,
    int? level,
    String? description,
    String? imageUrl,
    bool? isActive,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? compatibilityMetadata,
    List<String>? disciplineScope,
    String? iconName,
  }) {
    return Category(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      fullPath: fullPath ?? this.fullPath,
      parentId: parentId ?? this.parentId,
      level: level ?? this.level,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      compatibilityMetadata: compatibilityMetadata ?? this.compatibilityMetadata,
      disciplineScope: disciplineScope ?? this.disciplineScope,
      iconName: iconName ?? this.iconName,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Category && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Category(id: $id, fullPath: $fullPath, level: $level, isActive: $isActive)';
  }
}

/// Represents a breadcrumb item for navigation
class CategoryBreadcrumb {
  final String name;
  final String? categoryId; // null for "All Categories"
  final int level;

  CategoryBreadcrumb({
    required this.name,
    this.categoryId,
    required this.level,
  });
}

DateTime _parseDate(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return DateTime.now();
}
