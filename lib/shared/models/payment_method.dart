import 'tax_treatment.dart';

/// Payment method model matching payment_methods table in core_schema.sql
class PaymentMethod {
  final String id; // uuid
  final String tenantId; // uuid - MULTI-TENANT ISOLATION
  final String code; // 'cash', 'transfer', 'card', 'check'
  final String name; // 'Efectivo', 'Transferencia Bancaria', etc.
  final String accountId; // uuid - references accounts(id)
  final bool requiresReference; // true if reference field is mandatory
  final TaxTreatment defaultTaxTreatment; // Tax treatment for this payment method
  final String? icon; // optional icon name
  final int sortOrder; // display order
  final bool isActive; // whether this method is currently available
  final DateTime createdAt;
  final DateTime updatedAt;

  PaymentMethod({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.name,
    required this.accountId,
    this.requiresReference = false,
    this.defaultTaxTreatment = TaxTreatment.noTax,
    this.icon,
    this.sortOrder = 0,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      accountId: json['account_id']?.toString() ?? '',
      requiresReference: json['requires_reference'] == true,
      defaultTaxTreatment: TaxTreatment.fromString(
        json['default_tax_treatment']?.toString(),
      ),
      icon: json['icon']?.toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] ?? true,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'code': code,
      'name': name,
      'account_id': accountId,
      'requires_reference': requiresReference,
      'default_tax_treatment': defaultTaxTreatment.name,
      'icon': icon,
      'sort_order': sortOrder,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  PaymentMethod copyWith({
    String? id,
    String? tenantId,
    String? code,
    String? name,
    String? accountId,
    bool? requiresReference,
    TaxTreatment? defaultTaxTreatment,
    String? icon,
    int? sortOrder,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PaymentMethod(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      code: code ?? this.code,
      name: name ?? this.name,
      accountId: accountId ?? this.accountId,
      requiresReference: requiresReference ?? this.requiresReference,
      defaultTaxTreatment: defaultTaxTreatment ?? this.defaultTaxTreatment,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.now();
  }
}
