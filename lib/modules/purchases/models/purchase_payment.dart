/// Purchase payment model matching purchase_payments table in core_schema.sql
/// CRITICAL: Uses payment_method_id (uuid) to reference payment_methods table
double _clp(num value) => value.roundToDouble();

class PurchasePayment {
  final String? id; // uuid
  final String tenantId; // uuid - tenant isolation
  final String invoiceId; // uuid - references purchase_invoices(id)
  final String? invoiceNumber; // for display
  final String? supplierName; // for display
  final String paymentMethodId; // uuid - references payment_methods(id)
  final String? idempotencyKey; // client-generated duplicate-submit guard
  final double amount;
  final DateTime date;
  final String? reference; // bank reference, check number, etc.
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deletedBy;

  PurchasePayment({
    this.id,
    required this.tenantId,
    required this.invoiceId,
    this.invoiceNumber,
    this.supplierName,
    required this.paymentMethodId,
    this.idempotencyKey,
    required this.amount,
    required this.date,
    this.reference,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deletedBy,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory PurchasePayment.fromJson(Map<String, dynamic> json) {
    return PurchasePayment(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      invoiceId: json['invoice_id']?.toString() ?? '',
      invoiceNumber: json['invoice_number'] as String?,
      supplierName: json['supplier_name'] as String?,
      paymentMethodId: json['payment_method_id']?.toString() ?? '',
      idempotencyKey: json['idempotency_key']?.toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      date: _parseDate(json['date']),
      reference: json['reference'] as String?,
      notes: json['notes'] as String?,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      deletedAt:
          json['deleted_at'] != null ? _parseDate(json['deleted_at']) : null,
      deletedBy: json['deleted_by']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'invoice_id': invoiceId,
      'payment_method_id': paymentMethodId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      'amount': _clp(amount),
      'date': date.toIso8601String(),
      'reference': reference,
      'notes': notes,
      'deleted_at': deletedAt?.toIso8601String(),
      'deleted_by': deletedBy,
    };
  }

  PurchasePayment copyWith({
    String? id,
    String? tenantId,
    String? invoiceId,
    String? invoiceNumber,
    String? supplierName,
    String? paymentMethodId,
    String? idempotencyKey,
    double? amount,
    DateTime? date,
    String? reference,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? deletedBy,
  }) {
    return PurchasePayment(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      invoiceId: invoiceId ?? this.invoiceId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      supplierName: supplierName ?? this.supplierName,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      reference: reference ?? this.reference,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
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
