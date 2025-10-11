class Account {
  final String? id;
  final String code;
  final String name;
  final AccountType type;
  final AccountCategory category;
  final String? description;
  final String? parentId;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Account({
    this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.category,
    this.description,
    this.parentId,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });
  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id']?.toString(),
      code: json['code'] as String,
      name: json['name'] as String,
      type: AccountType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AccountType.asset,
      ),
      category: AccountCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => AccountCategory.currentAsset,
      ),
      description: json['description'] as String?,
      parentId: json['parent_id']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'code': code,
      'name': name,
      'type': type.name,
      'category': category.name,
      'description': description,
      'parent_id': parentId,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };

    if (id != null) {
      data['id'] = id;
    }

    return data;
  }

  Account copyWith({
    String? id,
    String? code,
    String? name,
    AccountType? type,
    AccountCategory? category,
    String? description,
    String? parentId,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Account(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      type: type ?? this.type,
      category: category ?? this.category,
      description: description ?? this.description,
      parentId: parentId ?? this.parentId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  @override
  String toString() {
    return '$code - $name';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Account) return false;
    if (id != null && other.id != null) {
      return id == other.id;
    }
    return code == other.code;
  }

  @override
  int get hashCode => id?.hashCode ?? code.hashCode;
}

enum AccountType {
  asset('Activo'),
  liability('Pasivo'),
  equity('Patrimonio'),
  income('Ingresos'),
  expense('Gastos'),
  tax('Impuestos');

  const AccountType(this.displayName);
  final String displayName;
}

enum AccountCategory {
  // Assets
  currentAsset('Activo Circulante'),
  fixedAsset('Activo Fijo'),
  otherAsset('Otros Activos'),

  // Liabilities
  currentLiability('Pasivo Circulante'),
  longTermLiability('Pasivo Largo Plazo'),

  // Equity
  capital('Capital'),
  retainedEarnings('Utilidades Retenidas'),

  // Income
  operatingIncome('Ingresos Operacionales'),
  nonOperatingIncome('Ingresos No Operacionales'),

  // Expenses
  costOfGoodsSold('Costo de Ventas'),
  operatingExpense('Gastos Operacionales'),
  financialExpense('Gastos Financieros'),

  // Tax
  taxPayable('Impuestos por Pagar'),
  taxReceivable('Impuestos por Cobrar'),
  taxExpense('Gasto por Impuesto');

  const AccountCategory(this.displayName);
  final String displayName;
}
