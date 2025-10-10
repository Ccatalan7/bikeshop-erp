import '../utils/chilean_utils.dart';

class Customer {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? rut; // Chilean national ID
  final String? address;
  final String? city;
  final String? region;
  final String? comuna;
  final CustomerType type;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Customer({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.rut,
    this.address,
    this.city,
    this.region,
    this.comuna,
    this.type = CustomerType.individual,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  // JSON serialization
  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      rut: json['rut'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      region: json['region'] as String?,
      comuna: json['comuna'] as String?,
      type: CustomerType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => CustomerType.individual,
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
      'notes': notes,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Customer copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? rut,
    String? address,
    String? city,
    String? region,
    String? comuna,
    CustomerType? type,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Customer(
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
    return 'Customer(id: $id, name: $name, rut: $formattedRut)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Customer && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

enum CustomerType {
  individual('Persona Natural'),
  company('Empresa'),
  government('Gobierno'),
  nonprofit('ONG');

  const CustomerType(this.displayName);
  final String displayName;
}