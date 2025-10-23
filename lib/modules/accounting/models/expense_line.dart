class ExpenseLine {
  ExpenseLine({
    this.id,
    this.expenseId,
    this.lineIndex = 0,
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    this.description,
    this.quantity = 1,
    this.unitPrice = 0,
    double? subtotal,
    this.taxRate = 0,
    double? taxAmount,
    double? total,
    this.costCenter,
    this.createdAt,
    this.updatedAt,
  })  : subtotal = subtotal ?? (quantity * unitPrice),
        taxAmount = taxAmount ?? ((subtotal ?? (quantity * unitPrice)) * (taxRate / 100)),
        total = total ?? ((subtotal ?? (quantity * unitPrice)) + (taxAmount ?? 0));

  final String? id;
  final String? expenseId;
  final int lineIndex;
  final String accountId;
  final String accountCode;
  final String accountName;
  final String? description;
  final double quantity;
  final double unitPrice;
  final double subtotal;
  final double taxRate;
  final double taxAmount;
  final double total;
  final String? costCenter;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ExpenseLine.fromJson(Map<String, dynamic> json) {
    final quantity = _parseDouble(json['quantity']) ?? 1;
    final unitPrice = _parseDouble(json['unit_price']) ?? 0;
    final subtotal = _parseDouble(json['subtotal']) ?? quantity * unitPrice;
    final taxRate = _parseDouble(json['tax_rate']) ?? 0;
    final taxAmount = _parseDouble(json['tax_amount']) ?? subtotal * (taxRate / 100);
    final total = _parseDouble(json['total']) ?? subtotal + taxAmount;

    return ExpenseLine(
      id: json['id']?.toString(),
      expenseId: json['expense_id']?.toString(),
      lineIndex: _parseInt(json['line_index']) ?? 0,
      accountId: json['account_id']?.toString() ?? '',
      accountCode: json['account_code']?.toString() ?? '',
      accountName: json['account_name']?.toString() ?? '',
      description: json['description']?.toString(),
      quantity: quantity,
      unitPrice: unitPrice,
      subtotal: subtotal,
      taxRate: taxRate,
      taxAmount: taxAmount,
      total: total,
      costCenter: json['cost_center']?.toString(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson({bool includeIdentifier = true}) {
    final payload = <String, dynamic>{
      'expense_id': expenseId,
      'line_index': lineIndex,
      'account_id': accountId,
      'account_code': accountCode,
      'account_name': accountName,
      'description': description,
      'quantity': quantity,
      'unit_price': unitPrice,
      'subtotal': subtotal,
      'tax_rate': taxRate,
      'tax_amount': taxAmount,
      'total': total,
      'cost_center': costCenter,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };

    if (includeIdentifier && id != null) {
      payload['id'] = id;
    }

    return payload;
  }

  ExpenseLine copyWith({
    String? id,
    String? expenseId,
    int? lineIndex,
    String? accountId,
    String? accountCode,
    String? accountName,
    String? description,
    double? quantity,
    double? unitPrice,
    double? subtotal,
    double? taxRate,
    double? taxAmount,
    double? total,
    String? costCenter,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExpenseLine(
      id: id ?? this.id,
      expenseId: expenseId ?? this.expenseId,
      lineIndex: lineIndex ?? this.lineIndex,
      accountId: accountId ?? this.accountId,
      accountCode: accountCode ?? this.accountCode,
      accountName: accountName ?? this.accountName,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      subtotal: subtotal ?? this.subtotal,
      taxRate: taxRate ?? this.taxRate,
      taxAmount: taxAmount ?? this.taxAmount,
      total: total ?? this.total,
      costCenter: costCenter ?? this.costCenter,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
