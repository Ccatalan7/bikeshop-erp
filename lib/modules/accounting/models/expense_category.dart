class ExpenseCategory {
  static const Object _unset = Object();

  const ExpenseCategory({
    required this.id,
    required this.name,
    this.description,
    this.defaultAccountId,
    this.defaultTaxRate = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final String? defaultAccountId;
  final double defaultTaxRate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      defaultAccountId: json['default_account_id']?.toString(),
      defaultTaxRate: _parseDouble(json['default_tax_rate']) ?? 0,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'default_account_id': defaultAccountId,
      'default_tax_rate': defaultTaxRate,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  ExpenseCategory copyWith({
    String? id,
    String? name,
    Object? description = _unset,
    Object? defaultAccountId = _unset,
    double? defaultTaxRate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExpenseCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      description: identical(description, _unset)
          ? this.description
          : description as String?,
      defaultAccountId: identical(defaultAccountId, _unset)
          ? this.defaultAccountId
          : defaultAccountId as String?,
      defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExpenseCategory && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
