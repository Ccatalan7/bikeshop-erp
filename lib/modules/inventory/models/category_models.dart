class Category {
  final String? id;
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

  Category({
    this.id,
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

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id']?.toString(),
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
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
    };
  }

  Category copyWith({
    String? id,
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
  }) {
    return Category(
      id: id ?? this.id,
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
