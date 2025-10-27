/// Multi-tenant model representing a bike shop
/// Each tenant has isolated data via tenant_id
class Tenant {
  final String id;
  final String shopName;
  final String? subdomain;
  final String? ownerEmail;
  final String plan; // 'free', 'pro', 'enterprise'
  final bool isActive;
  final String? logoUrl;
  final String? customDomain;
  final String currency;
  final String timezone;
  final DateTime createdAt;
  final DateTime updatedAt;

  Tenant({
    required this.id,
    required this.shopName,
    this.subdomain,
    this.ownerEmail,
    this.plan = 'free',
    this.isActive = true,
    this.logoUrl,
    this.customDomain,
    this.currency = 'CLP',
    this.timezone = 'America/Santiago',
    required this.createdAt,
    required this.updatedAt,
  });

  factory Tenant.fromJson(Map<String, dynamic> json) {
    return Tenant(
      id: json['id'] as String,
      shopName: json['shop_name'] as String,
      subdomain: json['subdomain'] as String?,
      ownerEmail: json['owner_email'] as String?,
      plan: json['plan'] as String? ?? 'free',
      isActive: json['is_active'] as bool? ?? true,
      logoUrl: json['logo_url'] as String?,
      customDomain: json['custom_domain'] as String?,
      currency: json['currency'] as String? ?? 'CLP',
      timezone: json['timezone'] as String? ?? 'America/Santiago',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_name': shopName,
      'subdomain': subdomain,
      'owner_email': ownerEmail,
      'plan': plan,
      'is_active': isActive,
      'logo_url': logoUrl,
      'custom_domain': customDomain,
      'currency': currency,
      'timezone': timezone,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Tenant copyWith({
    String? id,
    String? shopName,
    String? subdomain,
    String? ownerEmail,
    String? plan,
    bool? isActive,
    String? logoUrl,
    String? customDomain,
    String? currency,
    String? timezone,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Tenant(
      id: id ?? this.id,
      shopName: shopName ?? this.shopName,
      subdomain: subdomain ?? this.subdomain,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      plan: plan ?? this.plan,
      isActive: isActive ?? this.isActive,
      logoUrl: logoUrl ?? this.logoUrl,
      customDomain: customDomain ?? this.customDomain,
      currency: currency ?? this.currency,
      timezone: timezone ?? this.timezone,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'Tenant(id: $id, shopName: $shopName, subdomain: $subdomain, plan: $plan)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Tenant && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
