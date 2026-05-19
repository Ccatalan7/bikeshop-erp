class ExpenseLink {
  const ExpenseLink({
    this.id,
    required this.tenantId,
    required this.expenseId,
    required this.purchaseInvoiceId,
    this.expenseNumber,
    this.expenseSupplierName,
    this.expenseIssueDate,
    this.expenseTotalAmount,
    this.expenseTaxAmount,
    this.purchaseInvoiceNumber,
    this.purchaseSupplierName,
    this.linkKind = 'general',
    this.allocatedAmount,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String tenantId;
  final String expenseId;
  final String purchaseInvoiceId;
  final String? expenseNumber;
  final String? expenseSupplierName;
  final DateTime? expenseIssueDate;
  final double? expenseTotalAmount;
  final double? expenseTaxAmount;
  final String? purchaseInvoiceNumber;
  final String? purchaseSupplierName;
  final String linkKind;
  final double? allocatedAmount;
  final String? notes;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ExpenseLink.fromJson(Map<String, dynamic> json) {
    final purchaseInvoice = _parseNestedMap(json['purchase_invoices']);
    final expense = _parseNestedMap(json['expenses']);
    return ExpenseLink(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      expenseId: json['expense_id']?.toString() ?? '',
      purchaseInvoiceId: json['purchase_invoice_id']?.toString() ?? '',
      expenseNumber: expense?['expense_number']?.toString() ??
          json['expense_number']?.toString(),
      expenseSupplierName: expense?['supplier_name']?.toString() ??
          json['expense_supplier_name']?.toString(),
      expenseIssueDate:
          _parseDate(expense?['issue_date'] ?? json['expense_issue_date']),
      expenseTotalAmount: _parseDouble(
          expense?['total_amount'] ?? json['expense_total_amount']),
      expenseTaxAmount:
          _parseDouble(expense?['tax_amount'] ?? json['expense_tax_amount']),
      purchaseInvoiceNumber: purchaseInvoice?['invoice_number']?.toString() ??
          json['purchase_invoice_number']?.toString(),
      purchaseSupplierName: purchaseInvoice?['supplier_name']?.toString() ??
          json['purchase_supplier_name']?.toString(),
      linkKind: json['link_kind']?.toString() ?? 'general',
      allocatedAmount: _parseDouble(json['allocated_amount']),
      notes: json['notes']?.toString(),
      createdBy: json['created_by']?.toString(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson({bool includeIdentifier = true}) {
    final payload = <String, dynamic>{
      'tenant_id': tenantId,
      'expense_id': expenseId,
      'purchase_invoice_id': purchaseInvoiceId,
      'link_kind': linkKind,
      'allocated_amount': allocatedAmount,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };

    if (includeIdentifier && id != null) {
      payload['id'] = id;
    }

    return payload;
  }

  static Map<String, dynamic>? _parseNestedMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, dynamic val) => MapEntry(key.toString(), val));
    }
    return null;
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
