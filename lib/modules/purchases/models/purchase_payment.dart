class PurchasePayment {
  final String? id;
  final String invoiceId;
  final String? invoiceNumber;
  final String? supplierName;
  final String method; // cash, card, transfer, check, other
  final double amount;
  final DateTime date;
  final String? reference;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  PurchasePayment({
    this.id,
    required this.invoiceId,
    this.invoiceNumber,
    this.supplierName,
    required this.method,
    required this.amount,
    required this.date,
    this.reference,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory PurchasePayment.fromJson(Map<String, dynamic> json) {
    return PurchasePayment(
      id: json['id']?.toString(),
      invoiceId: json['purchase_invoice_id']?.toString() ?? '',  // Fixed: database column
      invoiceNumber: json['invoice_number'] as String?,
      supplierName: json['supplier_name'] as String?,
      method: json['payment_method']?.toString() ?? 'transfer',  // Fixed: database column
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      date: _parseDate(json['payment_date']),  // Fixed: database column
      reference: json['reference'] as String?,
      notes: json['notes'] as String?,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'purchase_invoice_id': invoiceId,  // Fixed: database column name
      'invoice_number': invoiceNumber,
      'supplier_name': supplierName,
      'payment_method': method,  // Fixed: database column name
      'amount': amount,
      'payment_date': date.toIso8601String(),  // Fixed: database column name
      'reference': reference,
      'notes': notes,
    };
  }

  PurchasePayment copyWith({
    String? id,
    String? invoiceId,
    String? invoiceNumber,
    String? supplierName,
    String? method,
    double? amount,
    DateTime? date,
    String? reference,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PurchasePayment(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      supplierName: supplierName ?? this.supplierName,
      method: method ?? this.method,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      reference: reference ?? this.reference,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }
}
