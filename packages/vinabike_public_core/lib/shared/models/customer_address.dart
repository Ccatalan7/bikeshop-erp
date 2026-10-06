// Moved from lib/shared/models/customer_address.dart (2026-10-06): the
// Flutter portal, the checkout and the HTML store's portal read and write a
// customer's addresses with this model; the app re-exports it.
class CustomerAddress {
  final String id;
  final String customerId;
  final String label;
  final String recipientName;
  final String phone;
  final String streetAddress;
  final String? streetNumber;
  final String? apartment;
  final String comuna;
  final String city;
  final String region;
  final String? postalCode;
  final String? additionalInfo;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomerAddress({
    required this.id,
    required this.customerId,
    required this.label,
    required this.recipientName,
    required this.phone,
    required this.streetAddress,
    this.streetNumber,
    this.apartment,
    required this.comuna,
    required this.city,
    required this.region,
    this.postalCode,
    this.additionalInfo,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomerAddress.fromJson(Map<String, dynamic> json) {
    return CustomerAddress(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      label: json['label'] as String,
      recipientName: json['recipient_name'] as String,
      phone: json['phone'] as String,
      streetAddress: json['street_address'] as String,
      streetNumber: json['street_number'] as String?,
      apartment: json['apartment'] as String?,
      comuna: json['comuna'] as String,
      city: json['city'] as String,
      region: json['region'] as String,
      postalCode: json['postal_code'] as String?,
      additionalInfo: json['additional_info'] as String?,
      isDefault: json['is_default'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'label': label,
      'recipient_name': recipientName,
      'phone': phone,
      'street_address': streetAddress,
      'street_number': streetNumber,
      'apartment': apartment,
      'comuna': comuna,
      'city': city,
      'region': region,
      'postal_code': postalCode,
      'additional_info': additionalInfo,
      'is_default': isDefault,
      // An instant in UTC: a local `DateTime.now()` without its offset is
      // read by the database as UTC, three or four hours off in Chile.
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  String get fullAddress {
    final streetLine = [streetAddress, streetNumber]
        .whereType<String>()
        .where((part) => part.trim().isNotEmpty)
        .join(' ')
        .trim();
    final normalizedComuna = comuna.trim().toLowerCase();
    final normalizedCity = city.trim().toLowerCase();
    final normalizedRegion = region.trim().toLowerCase();
    final parts = <String>[
      if (streetLine.isNotEmpty) streetLine,
      if (apartment != null && apartment!.trim().isNotEmpty) apartment!.trim(),
      if (comuna.trim().isNotEmpty) comuna.trim(),
      if (city.trim().isNotEmpty && normalizedCity != normalizedComuna)
        city.trim(),
      if (region.trim().isNotEmpty && normalizedRegion != normalizedCity)
        region.trim(),
    ];
    return parts.join(', ');
  }

  CustomerAddress copyWith({
    String? id,
    String? customerId,
    String? label,
    String? recipientName,
    String? phone,
    String? streetAddress,
    String? streetNumber,
    String? apartment,
    String? comuna,
    String? city,
    String? region,
    String? postalCode,
    String? additionalInfo,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomerAddress(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      label: label ?? this.label,
      recipientName: recipientName ?? this.recipientName,
      phone: phone ?? this.phone,
      streetAddress: streetAddress ?? this.streetAddress,
      streetNumber: streetNumber ?? this.streetNumber,
      apartment: apartment ?? this.apartment,
      comuna: comuna ?? this.comuna,
      city: city ?? this.city,
      region: region ?? this.region,
      postalCode: postalCode ?? this.postalCode,
      additionalInfo: additionalInfo ?? this.additionalInfo,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
