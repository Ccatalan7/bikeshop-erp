import 'expense_attachment.dart';
import 'expense_category.dart';
import 'expense_line.dart';
import 'expense_payment.dart';

enum ExpensePostingStatus { draft, posted, voided }

enum ExpensePaymentStatus { pending, scheduled, partial, paid, voided }

enum ExpenseApprovalStatus { pending, approved, rejected }

enum ExpenseDocumentType { invoice, receipt, ticket, reimbursement, other }

class Expense {
  Expense({
    this.id,
    required this.expenseNumber,
    this.categoryId,
    this.category,
    this.supplierId,
    this.supplierName,
    this.supplierRut,
    this.documentType = ExpenseDocumentType.invoice,
    this.documentNumber,
    required this.issueDate,
    this.dueDate,
    this.paymentTerms,
    this.currency = 'CLP',
    this.exchangeRate = 1,
    this.postingStatus = ExpensePostingStatus.draft,
    this.paymentStatus = ExpensePaymentStatus.pending,
    this.subtotal = 0,
    this.taxAmount = 0,
    this.totalAmount = 0,
    this.amountPaid = 0,
    this.balance = 0,
    this.notes,
    this.reference,
    this.approvalStatus = ExpenseApprovalStatus.pending,
    this.approvedBy,
    this.approvedAt,
    this.postedAt,
    this.paidAt,
    this.liabilityAccountId,
    this.paymentAccountId,
    this.paymentMethodId,
    this.tags = const [],
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.lines = const [],
    this.payments = const [],
    this.attachments = const [],
  });

  final String? id;
  final String expenseNumber;
  final String? categoryId;
  final ExpenseCategory? category;
  final String? supplierId;
  final String? supplierName;
  final String? supplierRut;
  final ExpenseDocumentType documentType;
  final String? documentNumber;
  final DateTime issueDate;
  final DateTime? dueDate;
  final String? paymentTerms;
  final String currency;
  final double exchangeRate;
  final ExpensePostingStatus postingStatus;
  final ExpensePaymentStatus paymentStatus;
  final double subtotal;
  final double taxAmount;
  final double totalAmount;
  final double amountPaid;
  final double balance;
  final String? notes;
  final String? reference;
  final ExpenseApprovalStatus approvalStatus;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime? postedAt;
  final DateTime? paidAt;
  final String? liabilityAccountId;
  final String? paymentAccountId;
  final String? paymentMethodId;
  final List<String> tags;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ExpenseLine> lines;
  final List<ExpensePayment> payments;
  final List<ExpenseAttachment> attachments;

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id']?.toString(),
      expenseNumber: json['expense_number']?.toString() ?? '',
      categoryId: json['category_id']?.toString(),
      supplierId: json['supplier_id']?.toString(),
      supplierName: json['supplier_name']?.toString(),
      supplierRut: json['supplier_rut']?.toString(),
      documentType: _parseDocumentType(json['document_type']),
      documentNumber: json['document_number']?.toString(),
      issueDate: _parseDate(json['issue_date']) ?? DateTime.now(),
      dueDate: _parseDate(json['due_date']),
      paymentTerms: json['payment_terms']?.toString(),
      currency: json['currency']?.toString() ?? 'CLP',
      exchangeRate: _parseDouble(json['exchange_rate']) ?? 1,
      postingStatus: _parsePostingStatus(json['posting_status']),
      paymentStatus: _parsePaymentStatus(json['payment_status']),
      subtotal: _parseDouble(json['subtotal']) ?? 0,
      taxAmount: _parseDouble(json['tax_amount']) ?? 0,
      totalAmount: _parseDouble(json['total_amount']) ?? 0,
      amountPaid: _parseDouble(json['amount_paid']) ?? 0,
      balance: _parseDouble(json['balance']) ?? 0,
      notes: json['notes']?.toString(),
      reference: json['reference']?.toString(),
      approvalStatus: _parseApprovalStatus(json['approval_status']),
      approvedBy: json['approved_by']?.toString(),
      approvedAt: _parseDate(json['approved_at']),
      postedAt: _parseDate(json['posted_at']),
      paidAt: _parseDate(json['paid_at']),
      liabilityAccountId: json['liability_account_id']?.toString(),
      paymentAccountId: json['payment_account_id']?.toString(),
      paymentMethodId: json['payment_method_id']?.toString(),
      tags: _parseTags(json['tags']),
      createdBy: json['created_by']?.toString(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Expense copyWith({
    String? id,
    String? expenseNumber,
    String? categoryId,
    ExpenseCategory? category,
    String? supplierId,
    String? supplierName,
    String? supplierRut,
    ExpenseDocumentType? documentType,
    String? documentNumber,
    DateTime? issueDate,
    DateTime? dueDate,
    String? paymentTerms,
    String? currency,
    double? exchangeRate,
    ExpensePostingStatus? postingStatus,
    ExpensePaymentStatus? paymentStatus,
    double? subtotal,
    double? taxAmount,
    double? totalAmount,
    double? amountPaid,
    double? balance,
    String? notes,
    String? reference,
    ExpenseApprovalStatus? approvalStatus,
    String? approvedBy,
    DateTime? approvedAt,
    DateTime? postedAt,
    DateTime? paidAt,
    String? liabilityAccountId,
    String? paymentAccountId,
    String? paymentMethodId,
    List<String>? tags,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ExpenseLine>? lines,
    List<ExpensePayment>? payments,
    List<ExpenseAttachment>? attachments,
  }) {
    return Expense(
      id: id ?? this.id,
      expenseNumber: expenseNumber ?? this.expenseNumber,
      categoryId: categoryId ?? this.categoryId,
      category: category ?? this.category,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      supplierRut: supplierRut ?? this.supplierRut,
      documentType: documentType ?? this.documentType,
      documentNumber: documentNumber ?? this.documentNumber,
      issueDate: issueDate ?? this.issueDate,
      dueDate: dueDate ?? this.dueDate,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      currency: currency ?? this.currency,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      postingStatus: postingStatus ?? this.postingStatus,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      amountPaid: amountPaid ?? this.amountPaid,
      balance: balance ?? this.balance,
      notes: notes ?? this.notes,
      reference: reference ?? this.reference,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      postedAt: postedAt ?? this.postedAt,
      paidAt: paidAt ?? this.paidAt,
      liabilityAccountId: liabilityAccountId ?? this.liabilityAccountId,
      paymentAccountId: paymentAccountId ?? this.paymentAccountId,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      tags: tags ?? List<String>.from(this.tags),
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lines: lines ?? List<ExpenseLine>.from(this.lines),
      payments: payments ?? List<ExpensePayment>.from(this.payments),
      attachments: attachments ?? List<ExpenseAttachment>.from(this.attachments),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'expense_number': expenseNumber,
      'category_id': categoryId,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'supplier_rut': supplierRut,
      'document_type': documentType.name,
      'document_number': documentNumber,
      'issue_date': issueDate.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'payment_terms': paymentTerms,
      'currency': currency,
      'exchange_rate': exchangeRate,
      'posting_status': postingStatus == ExpensePostingStatus.voided ? 'void' : postingStatus.name,
      'payment_status': _encodePaymentStatus(paymentStatus),
      'subtotal': subtotal,
      'tax_amount': taxAmount,
      'total_amount': totalAmount,
      'amount_paid': amountPaid,
      'balance': balance,
      'notes': notes,
      'reference': reference,
      'approval_status': approvalStatus.name,
      'approved_by': approvedBy,
      'approved_at': approvedAt?.toIso8601String(),
      'posted_at': postedAt?.toIso8601String(),
      'paid_at': paidAt?.toIso8601String(),
      'liability_account_id': liabilityAccountId,
      'payment_account_id': paymentAccountId,
      'payment_method_id': paymentMethodId,
      'tags': tags,
      'created_by': createdBy,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toDatabasePayload() {
    final payload = toJson();
    payload.remove('id');
    return payload;
  }

  Expense withDetails({
    List<ExpenseLine>? lines,
    List<ExpensePayment>? payments,
    List<ExpenseAttachment>? attachments,
    ExpenseCategory? category,
  }) {
    return copyWith(
      lines: lines ?? this.lines,
      payments: payments ?? this.payments,
      attachments: attachments ?? this.attachments,
      category: category ?? this.category,
    );
  }

  static ExpensePostingStatus _parsePostingStatus(dynamic value) {
    final normalized = _normalize(value);
    switch (normalized) {
      case 'posted':
        return ExpensePostingStatus.posted;
      case 'void':
      case 'voided':
        return ExpensePostingStatus.voided;
      default:
        return ExpensePostingStatus.draft;
    }
  }

  static ExpensePaymentStatus _parsePaymentStatus(dynamic value) {
    final normalized = _normalize(value);
    switch (normalized) {
      case 'scheduled':
        return ExpensePaymentStatus.scheduled;
      case 'partial':
        return ExpensePaymentStatus.partial;
      case 'paid':
        return ExpensePaymentStatus.paid;
      case 'void':
      case 'voided':
        return ExpensePaymentStatus.voided;
      default:
        return ExpensePaymentStatus.pending;
    }
  }

  static ExpenseApprovalStatus _parseApprovalStatus(dynamic value) {
    final normalized = _normalize(value);
    switch (normalized) {
      case 'approved':
        return ExpenseApprovalStatus.approved;
      case 'rejected':
        return ExpenseApprovalStatus.rejected;
      default:
        return ExpenseApprovalStatus.pending;
    }
  }

  static ExpenseDocumentType _parseDocumentType(dynamic value) {
    final normalized = _normalize(value);
    switch (normalized) {
      case 'receipt':
        return ExpenseDocumentType.receipt;
      case 'ticket':
        return ExpenseDocumentType.ticket;
      case 'reimbursement':
        return ExpenseDocumentType.reimbursement;
      case 'other':
        return ExpenseDocumentType.other;
      default:
        return ExpenseDocumentType.invoice;
    }
  }

  static List<String> _parseTags(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return value.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static String _encodePaymentStatus(ExpensePaymentStatus status) {
    switch (status) {
      case ExpensePaymentStatus.scheduled:
        return 'scheduled';
      case ExpensePaymentStatus.partial:
        return 'partial';
      case ExpensePaymentStatus.paid:
        return 'paid';
      case ExpensePaymentStatus.voided:
        return 'void';
      case ExpensePaymentStatus.pending:
        return 'pending';
    }
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

  static String _normalize(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }
}
