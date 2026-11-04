class ProductBrand {
  final String? id;
  final String tenantId; // uuid - MULTI-TENANT ISOLATION
  final String name;
  final String? description;
  final String? website;
  final String? country;

  /// La imagen cuadrada de la marca (20261103120000), o null: la app muestra
  /// sus iniciales.
  final String? logoUrl;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Del catálogo compartido (sin taller): la plataforma la cura y el taller
  /// no la cambia.
  bool get isShared => tenantId.isEmpty;

  ProductBrand({
    this.id,
    required this.tenantId,
    required this.name,
    this.description,
    this.website,
    this.country,
    this.logoUrl,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ProductBrand.fromJson(Map<String, dynamic> json) {
    return ProductBrand(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      website: json['website'],
      country: json['country'],
      logoUrl: json['logo_url']?.toString(),
      isActive: json['is_active'] ?? true,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'name': name,
      'description': description,
      'website': website,
      'country': country,
      // Sin la clave, guardar la ficha no borra el logo: se cambia aparte.
      if (logoUrl != null) 'logo_url': logoUrl,
      'is_active': isActive,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  ProductBrand copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? description,
    String? website,
    String? country,
    String? logoUrl,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProductBrand(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      description: description ?? this.description,
      website: website ?? this.website,
      country: country ?? this.country,
      logoUrl: logoUrl ?? this.logoUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Otro logo, o ninguno con `null` (copyWith no puede quitarlo).
  ProductBrand copyWithLogo(String? logoUrl) => ProductBrand(
        id: id,
        tenantId: tenantId,
        name: name,
        description: description,
        website: website,
        country: country,
        logoUrl: logoUrl,
        isActive: isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProductBrand && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ProductBrand(id: $id, name: $name)';
}

DateTime _parseDate(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  try {
    final dynamic dynamicValue = value;
    final result = dynamicValue.toDate();
    if (result is DateTime) {
      return result;
    }
  } catch (_) {
    // Ignore conversion errors and fall back to now.
  }
  return DateTime.now();
}
