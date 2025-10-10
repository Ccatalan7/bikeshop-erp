import '../utils/chilean_utils.dart';

class Supplier {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? rut; // Chilean RUT for businesses
  final String? address;
  final String? city;
  final String? region;
  final String? comuna;
  final SupplierType type;
  final String? contactPerson;
  final String? website;
  final Map<String, String> bankDetails;
  final PaymentTerms paymentTerms;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Supplier({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.rut,
    this.address,
    this.city,
    this.region,
    this.comuna,
    this.type = SupplierType.local,
    this.contactPerson,
    this.website,
    this.bankDetails = const {},
    this.paymentTerms = PaymentTerms.net30,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      rut: json['rut'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      region: json['region'] as String?,
      comuna: json['comuna'] as String?,
      type: SupplierType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => SupplierType.local,
      ),
      contactPerson: json['contact_person'] as String?,
      website: json['website'] as String?,
      bankDetails: Map<String, String>.from(json['bank_details'] as Map? ?? {}),
      paymentTerms: PaymentTerms.values.firstWhere(
        (t) => t.name == json['payment_terms'],
        orElse: () => PaymentTerms.net30,
      ),
      notes: json['notes'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'rut': rut,
      'address': address,
      'city': city,
      'region': region,
      'comuna': comuna,
      'type': type.name,
      'contact_person': contactPerson,
      'website': website,
      'bank_details': bankDetails,
      'payment_terms': paymentTerms.name,
      'notes': notes,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Supplier copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? rut,
    String? address,
    String? city,
    String? region,
    String? comuna,
    SupplierType? type,
    String? contactPerson,
    String? website,
    Map<String, String>? bankDetails,
    PaymentTerms? paymentTerms,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      rut: rut ?? this.rut,
      address: address ?? this.address,
      city: city ?? this.city,
      region: region ?? this.region,
      comuna: comuna ?? this.comuna,
      type: type ?? this.type,
      contactPerson: contactPerson ?? this.contactPerson,
      website: website ?? this.website,
      bankDetails: bankDetails ?? this.bankDetails,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Validation methods
  bool get hasValidRut => rut != null && ChileanUtils.isValidRut(rut!);
  
  bool get hasValidEmail => email == null || ChileanUtils.isValidEmail(email!);
  
  bool get hasValidPhone => phone == null || ChileanUtils.isValidChileanPhone(phone!);

  String get formattedRut => rut != null ? ChileanUtils.formatRut(rut!) : '';

  String get displayName => name;

  String get fullAddress {
    final parts = <String>[];
    if (address != null && address!.isNotEmpty) parts.add(address!);
    if (comuna != null && comuna!.isNotEmpty) parts.add(comuna!);
    if (city != null && city!.isNotEmpty) parts.add(city!);
    if (region != null && region!.isNotEmpty) parts.add(region!);
    return parts.join(', ');
  }

  @override
  String toString() {
    return 'Supplier(id: $id, name: $name, rut: $formattedRut)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Supplier && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

enum SupplierType {
  local('Proveedor Local'),
  national('Proveedor Nacional'),
  international('Proveedor Internacional'),
  manufacturer('Fabricante'),
  distributor('Distribuidor'),
  service('Proveedor de Servicios');

  const SupplierType(this.displayName);
  final String displayName;
}

enum PaymentTerms {
  immediate('Contado'),
  net15('15 días'),
  net30('30 días'),
  net45('45 días'),
  net60('60 días'),
  prepaid('Prepago');

  const PaymentTerms(this.displayName);
  final String displayName;
  
  int get days {
    switch (this) {
      case PaymentTerms.immediate:
        return 0;
      case PaymentTerms.net15:
        return 15;
      case PaymentTerms.net30:
        return 30;
      case PaymentTerms.net45:
        return 45;
      case PaymentTerms.net60:
        return 60;
      case PaymentTerms.prepaid:
        return -1; // Special case for prepaid
    }
  }
}