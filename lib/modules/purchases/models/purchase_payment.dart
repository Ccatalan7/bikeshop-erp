/// Purchase payment model matching purchase_payments table in core_schema.sql
/// CRITICAL: Uses payment_method_id (uuid) to reference payment_methods table
class PurchasePayment {
  final String? id; // uuid
  final String invoiceId; // uuid - references purchase_invoices(id)
  final String? invoiceNumber; // for display
  final String? supplierName; // for display
  final String paymentMethodId; // uuid - references payment_methods(id)
  final double amount;
  final DateTime date;
  final String? reference; // bank reference, check number, etc.
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  PurchasePayment({
    this.id,
    required this.invoiceId,
    this.invoiceNumber,
    this.supplierName,
    required this.paymentMethodId,
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
      invoiceId: json['invoice_id']?.toString() ?? '',
      invoiceNumber: json['invoice_number'] as String?,
      supplierName: json['supplier_name'] as String?,
      paymentMethodId: json['payment_method_id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      date: _parseDate(json['date']),
      reference: json['reference'] as String?,
      notes: json['notes'] as String?,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'invoice_id': invoiceId,
      'invoice_number': invoiceNumber,
      'supplier_name': supplierName,
      'payment_method_id': paymentMethodId,
      'amount': amount,
      'date': date.toIso8601String(),
      'reference': reference,
      'notes': notes,
    };
  }

  PurchasePayment copyWith({
    String? id,
    String? invoiceId,
    String? invoiceNumber,
    String? supplierName,
    String? paymentMethodId,
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
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
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
