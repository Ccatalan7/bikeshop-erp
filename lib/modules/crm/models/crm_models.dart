DateTime _parseDate(dynamic value) {
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

class Customer {
  final String? id;
  final String name;
  final String rut;
  final String? email;
  final String? phone;
  final String? address;
  final String? region;
  final String? imageUrl;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Customer({
    this.id,
    required this.name,
    required this.rut,
    this.email,
    this.phone,
    this.address,
    this.region,
    this.imageUrl,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      rut: json['rut'] ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      region: json['region'] as String?,
      imageUrl: json['image_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    final json = {
      'name': name,
      'rut': rut,
      'email': email,
      'phone': phone,
      'address': address,
      'region': region,
      'image_url': imageUrl,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
    
    // Only include id if it's not null (for updates)
    if (id != null) {
      json['id'] = id;
    }
    
    return json;
  }

  Customer copyWith({
    String? id,
    String? name,
    String? rut,
    String? email,
    String? phone,
    String? address,
    String? region,
    String? imageUrl,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      rut: rut ?? this.rut,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      region: region ?? this.region,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get initials {
    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    } else if (words.isNotEmpty) {
      return words[0][0].toUpperCase();
    }
    return '?';
  }
}

class Loyalty {
  final String? id;
  final String customerId;
  final int points;
  final LoyaltyTier tier;
  final DateTime? lastUpdated;

  const Loyalty({
    this.id,
    required this.customerId,
    this.points = 0,
    this.tier = LoyaltyTier.bronze,
    this.lastUpdated,
  });

  factory Loyalty.fromJson(Map<String, dynamic> json) {
    return Loyalty(
      id: json['id']?.toString(),
      customerId: json['customer_id']?.toString() ?? '',
      points: json['points'] as int? ?? 0,
      tier: LoyaltyTier.values.firstWhere(
        (e) => e.toString().split('.').last == json['tier'],
        orElse: () => LoyaltyTier.bronze,
      ),
      lastUpdated: json['last_updated'] != null
          ? _parseDate(json['last_updated'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'points': points,
      'tier': tier.toString().split('.').last,
      'last_updated': lastUpdated?.toIso8601String(),
    };
  }

  Loyalty copyWith({
    String? id,
    String? customerId,
    int? points,
    LoyaltyTier? tier,
    DateTime? lastUpdated,
  }) {
    return Loyalty(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      points: points ?? this.points,
      tier: tier ?? this.tier,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  LoyaltyTier calculateTier() {
    if (points >= 5000) return LoyaltyTier.platinum;
    if (points >= 2000) return LoyaltyTier.gold;
    if (points >= 500) return LoyaltyTier.silver;
    return LoyaltyTier.bronze;
  }
}

enum LoyaltyTier {
  bronze,
  silver,
  gold,
  platinum,
}

class BikeHistory {
  final String? id;
  final String customerId;
  final String brand;
  final String model;
  final String? serialNumber;
  final int? year;
  final String? color;
  final String? imageUrl;
  final DateTime purchaseDate;
  final double purchaseAmount;
  final String? notes;

  const BikeHistory({
    this.id,
    required this.customerId,
    required this.brand,
    required this.model,
    this.serialNumber,
    this.year,
    this.color,
    this.imageUrl,
    required this.purchaseDate,
    required this.purchaseAmount,
    this.notes,
  });

  factory BikeHistory.fromJson(Map<String, dynamic> json) {
    final purchaseAmount = json['purchase_amount'];
    return BikeHistory(
      id: json['id']?.toString(),
      customerId: json['customer_id']?.toString() ?? '',
      brand: json['brand'] ?? '',
      model: json['model'] ?? '',
      serialNumber: json['serial_number'] as String?,
      year: json['year'] as int?,
      color: json['color'] as String?,
      imageUrl: json['image_url'] as String?,
      purchaseDate: _parseDate(json['purchase_date']),
      purchaseAmount: purchaseAmount is num
          ? purchaseAmount.toDouble()
          : double.tryParse(purchaseAmount?.toString() ?? '') ?? 0.0,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'brand': brand,
      'model': model,
      'serial_number': serialNumber,
      'year': year,
      'color': color,
      'image_url': imageUrl,
      'purchase_date': purchaseDate.toIso8601String(),
      'purchase_amount': purchaseAmount,
      'notes': notes,
    };
  }

  BikeHistory copyWith({
    String? id,
    String? customerId,
    String? brand,
    String? model,
    String? serialNumber,
    int? year,
    String? color,
    String? imageUrl,
    DateTime? purchaseDate,
    double? purchaseAmount,
    String? notes,
  }) {
    return BikeHistory(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      serialNumber: serialNumber ?? this.serialNumber,
      year: year ?? this.year,
      color: color ?? this.color,
      imageUrl: imageUrl ?? this.imageUrl,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      purchaseAmount: purchaseAmount ?? this.purchaseAmount,
      notes: notes ?? this.notes,
    );
  }
}