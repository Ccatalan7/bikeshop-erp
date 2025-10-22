enum PaymentType {
  cash,
  card,
  voucher,
  transfer,
}

class PaymentMethod {
  final String id;
  final PaymentType type;
  final String name;
  final String? accountCode; // Chart of accounts reference
  final bool requiresChange;
  final bool isActive;

  const PaymentMethod({
    required this.id,
    required this.type,
    required this.name,
    this.accountCode,
    required this.requiresChange,
    this.isActive = true,
  });

  // JSON serialization
  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] ?? '',
      type: PaymentType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => PaymentType.cash,
      ),
      name: json['name'] ?? '',
      accountCode: json['account_code'],
      requiresChange: json['requires_change'] ?? false,
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString().split('.').last,
      'name': name,
      'account_code': accountCode,
      'requires_change': requiresChange,
      'is_active': isActive,
    };
  }

  // Predefined payment methods
  static const PaymentMethod cash = PaymentMethod(
    id: 'cash',
    type: PaymentType.cash,
    name: 'Efectivo',
    accountCode: '1101', // Caja
    requiresChange: true,
  );

  static const PaymentMethod card = PaymentMethod(
    id: 'card',
    type: PaymentType.card,
    name: 'Tarjeta',
    accountCode: '1102', // Banco
    requiresChange: false,
  );

  static const PaymentMethod voucher = PaymentMethod(
    id: 'voucher',
    type: PaymentType.voucher,
    name: 'Vale/Voucher',
    accountCode: '1105', // Documentos por Cobrar
    requiresChange: false,
  );

  static const PaymentMethod transfer = PaymentMethod(
    id: 'transfer',
    type: PaymentType.transfer,
    name: 'Transferencia',
    accountCode: '1102', // Banco
    requiresChange: false,
  );

  static List<PaymentMethod> get defaultMethods => [
        cash,
        card,
        voucher,
        transfer,
      ];

  @override
  String toString() => 'PaymentMethod(name: $name, type: $type)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentMethod &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
