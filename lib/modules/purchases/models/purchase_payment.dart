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

/// Durable audit receipt emitted by the atomic purchase-payment correction
/// command. The payment remains the accounting source identity; these events
/// preserve who changed it, why, and which settlement journal replaced the
/// prior evidence.
class PurchasePaymentEditEvent {
  const PurchasePaymentEditEvent({
    required this.id,
    required this.tenantId,
    required this.paymentId,
    required this.invoiceId,
    required this.operationKey,
    required this.reason,
    required this.financialFieldsChanged,
    required this.legacyJournalRelinked,
    required this.beforeSnapshot,
    required this.afterSnapshot,
    required this.createdAt,
    this.traceOperationId,
    this.priorJournalEntryId,
    this.currentJournalEntryId,
    this.createdBy,
  });

  final String id;
  final String tenantId;
  final String paymentId;
  final String invoiceId;
  final String operationKey;
  final String reason;
  final bool financialFieldsChanged;
  final bool legacyJournalRelinked;
  final Map<String, dynamic> beforeSnapshot;
  final Map<String, dynamic> afterSnapshot;
  final String? traceOperationId;
  final String? priorJournalEntryId;
  final String? currentJournalEntryId;
  final String? createdBy;
  final DateTime createdAt;

  factory PurchasePaymentEditEvent.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> snapshot(dynamic value) {
      if (value is Map<String, dynamic>) return Map.unmodifiable(value);
      if (value is Map) {
        return Map.unmodifiable(Map<String, dynamic>.from(value));
      }
      return const {};
    }

    return PurchasePaymentEditEvent(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      paymentId: json['payment_id']?.toString() ?? '',
      invoiceId: json['invoice_id']?.toString() ?? '',
      operationKey: json['operation_key']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      financialFieldsChanged: json['financial_fields_changed'] == true,
      legacyJournalRelinked: json['legacy_journal_relinked'] == true,
      beforeSnapshot: snapshot(json['before_snapshot']),
      afterSnapshot: snapshot(json['after_snapshot']),
      traceOperationId: json['trace_operation_id']?.toString(),
      priorJournalEntryId: json['prior_journal_entry_id']?.toString(),
      currentJournalEntryId: json['current_journal_entry_id']?.toString(),
      createdBy: json['created_by']?.toString(),
      createdAt: PurchasePayment._parseDate(json['created_at']),
    );
  }
}

/// Immutable result returned by the audited purchase-payment correction
/// command, including the durable event receipt and replay status.
class PurchasePaymentCorrectionResult {
  const PurchasePaymentCorrectionResult({
    required this.payment,
    required this.event,
    required this.replayed,
    required this.financialFieldsChanged,
    required this.legacyJournalRelinked,
  });

  final PurchasePayment payment;
  final PurchasePaymentEditEvent event;
  final bool replayed;
  final bool financialFieldsChanged;
  final bool legacyJournalRelinked;
}
