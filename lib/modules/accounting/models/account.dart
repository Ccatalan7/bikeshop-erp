class Account {
  final int? id;
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
      id: json['id'] as int?,
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
      parentId: json['parent_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
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
  }

  Account copyWith({
    int? id,
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

  @override
  String toString() {
    return '$code - $name';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Account && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
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