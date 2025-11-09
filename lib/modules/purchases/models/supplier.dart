import '../../../shared/models/tax_treatment.dart';

class Supplier {
  final int? id;
  final String tenantId;
  final String name;
  final String? rut;
  final String? email;
  final String? phone;
  final String? address;
  final String? contactPerson;
  final bool isActive;
  final String? notes;
  final TaxTreatment defaultTaxTreatment; // suggested tax treatment for purchases
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Supplier({
    this.id,
    required this.tenantId,
    required this.name,
    this.rut,
    this.email,
    this.phone,
    this.address,
    this.contactPerson,
    this.isActive = true,
    this.notes,
    this.defaultTaxTreatment = TaxTreatment.noTax,
    this.createdAt,
    this.updatedAt,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] as int?,
      tenantId: json['tenant_id']?.toString() ?? '',
      name: json['name'] as String,
      rut: json['rut'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      contactPerson: json['contact_person'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      notes: json['notes'] as String?,
      defaultTaxTreatment: TaxTreatment.fromString(json['default_tax_treatment']?.toString()),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'name': name,
      'rut': rut,
      'email': email,
      'phone': phone,
      'address': address,
      'contact_person': contactPerson,
      'is_active': isActive,
      'notes': notes,
      'default_tax_treatment': defaultTaxTreatment.toValue(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Supplier copyWith({
    int? id,
    String? tenantId,
    String? name,
    String? rut,
    String? email,
    String? phone,
    String? address,
    String? contactPerson,
    bool? isActive,
    String? notes,
    TaxTreatment? defaultTaxTreatment,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      rut: rut ?? this.rut,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      contactPerson: contactPerson ?? this.contactPerson,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      defaultTaxTreatment: defaultTaxTreatment ?? this.defaultTaxTreatment,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
