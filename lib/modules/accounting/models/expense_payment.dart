class ExpensePayment {
  const ExpensePayment({
    this.id,
    required this.expenseId,
    this.paymentMethodId,
    this.paymentAccountId,
    required this.amount,
    required this.paymentDate,
    this.reference,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String expenseId;
  final String? paymentMethodId;
  final String? paymentAccountId;
  final double amount;
  final DateTime paymentDate;
  final String? reference;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ExpensePayment.fromJson(Map<String, dynamic> json) {
    return ExpensePayment(
      id: json['id']?.toString(),
      expenseId: json['expense_id']?.toString() ?? '',
      paymentMethodId: json['payment_method_id']?.toString(),
      paymentAccountId: json['payment_account_id']?.toString(),
      amount: _parseDouble(json['amount']) ?? 0,
      paymentDate: _parseDate(json['payment_date']) ?? DateTime.now(),
      reference: json['reference']?.toString(),
      notes: json['notes']?.toString(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson({bool includeIdentifier = true}) {
    final payload = <String, dynamic>{
      'expense_id': expenseId,
      'payment_method_id': paymentMethodId,
      'payment_account_id': paymentAccountId,
      'amount': amount,
      'payment_date': paymentDate.toIso8601String(),
      'reference': reference,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };

    if (includeIdentifier && id != null) {
      payload['id'] = id;
    }

    return payload;
  }

  ExpensePayment copyWith({
    String? id,
    String? expenseId,
    String? paymentMethodId,
    String? paymentAccountId,
    double? amount,
    DateTime? paymentDate,
    String? reference,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExpensePayment(
      id: id ?? this.id,
      expenseId: expenseId ?? this.expenseId,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      paymentAccountId: paymentAccountId ?? this.paymentAccountId,
      amount: amount ?? this.amount,
      paymentDate: paymentDate ?? this.paymentDate,
      reference: reference ?? this.reference,
      notes: notes ?? this.notes,
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
}
