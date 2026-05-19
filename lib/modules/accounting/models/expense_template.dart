import 'expense.dart';

class ExpenseTemplate {
  const ExpenseTemplate({
    this.id,
    required this.tenantId,
    required this.name,
    this.isActive = true,
    this.priority = 100,
    this.triggerCategoryId,
    this.triggerSupplierId,
    this.triggerKeywords = const [],
    this.defaultCategoryId,
    this.defaultSupplierId,
    this.defaultSupplierName,
    this.defaultSupplierRut,
    this.defaultAccountId,
    this.defaultPaymentMethodId,
    this.defaultDocumentType = ExpenseDocumentType.invoice,
    this.defaultAmount,
    this.defaultDescription,
    this.defaultReferencePrefix,
    this.defaultTaxRate,
    this.recurrenceIntervalMonths,
    this.nextDueDate,
    this.nextReviewDate,
    this.reviewReminderDays = 15,
    this.linkPurchaseInvoice = false,
    this.linkKind = 'general',
    this.notes,
    this.metadata = const {},
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String tenantId;
  final String name;
  final bool isActive;
  final int priority;
  final String? triggerCategoryId;
  final String? triggerSupplierId;
  final List<String> triggerKeywords;
  final String? defaultCategoryId;
  final String? defaultSupplierId;
  final String? defaultSupplierName;
  final String? defaultSupplierRut;
  final String? defaultAccountId;
  final String? defaultPaymentMethodId;
  final ExpenseDocumentType defaultDocumentType;
  final double? defaultAmount;
  final String? defaultDescription;
  final String? defaultReferencePrefix;
  final double? defaultTaxRate;
  final int? recurrenceIntervalMonths;
  final DateTime? nextDueDate;
  final DateTime? nextReviewDate;
  final int reviewReminderDays;
  final bool linkPurchaseInvoice;
  final String linkKind;
  final String? notes;
  final Map<String, dynamic> metadata;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasDefaultAmount => defaultAmount != null;

  bool get reviewIsSoon {
    final reviewDate = nextReviewDate;
    if (reviewDate == null) return false;
    final today = DateTime.now();
    final threshold = today.add(Duration(days: reviewReminderDays));
    return !reviewDate.isBefore(today) && !reviewDate.isAfter(threshold);
  }

  bool get reviewIsOverdue {
    final reviewDate = nextReviewDate;
    if (reviewDate == null) return false;
    final today = DateTime.now();
    return DateTime(reviewDate.year, reviewDate.month, reviewDate.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }

  factory ExpenseTemplate.fromJson(Map<String, dynamic> json) {
    return ExpenseTemplate(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      isActive: json['is_active'] as bool? ?? true,
      priority: _parseInt(json['priority']) ?? 100,
      triggerCategoryId: json['trigger_category_id']?.toString(),
      triggerSupplierId: json['trigger_supplier_id']?.toString(),
      triggerKeywords: _parseStringList(json['trigger_keywords']),
      defaultCategoryId: json['default_category_id']?.toString(),
      defaultSupplierId: json['default_supplier_id']?.toString(),
      defaultSupplierName: json['default_supplier_name']?.toString(),
      defaultSupplierRut: json['default_supplier_rut']?.toString(),
      defaultAccountId: json['default_account_id']?.toString(),
      defaultPaymentMethodId: json['default_payment_method_id']?.toString(),
      defaultDocumentType: _parseDocumentType(json['default_document_type']),
      defaultAmount: _parseDouble(json['default_amount']),
      defaultDescription: json['default_description']?.toString(),
      defaultReferencePrefix: json['default_reference_prefix']?.toString(),
      defaultTaxRate: _parseDouble(json['default_tax_rate']),
      recurrenceIntervalMonths: _parseInt(json['recurrence_interval_months']),
      nextDueDate: _parseDate(json['next_due_date']),
      nextReviewDate: _parseDate(json['next_review_date']),
      reviewReminderDays: _parseInt(json['review_reminder_days']) ?? 15,
      linkPurchaseInvoice: json['link_purchase_invoice'] as bool? ?? false,
      linkKind: json['link_kind']?.toString() ?? 'general',
      notes: json['notes']?.toString(),
      metadata: _parseMap(json['metadata']),
      createdBy: json['created_by']?.toString(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson({bool includeIdentifier = true}) {
    final payload = <String, dynamic>{
      'tenant_id': tenantId,
      'name': name,
      'is_active': isActive,
      'priority': priority,
      'trigger_category_id': triggerCategoryId,
      'trigger_supplier_id': triggerSupplierId,
      'trigger_keywords': triggerKeywords,
      'default_category_id': defaultCategoryId,
      'default_supplier_id': defaultSupplierId,
      'default_supplier_name': defaultSupplierName,
      'default_supplier_rut': defaultSupplierRut,
      'default_account_id': defaultAccountId,
      'default_payment_method_id': defaultPaymentMethodId,
      'default_document_type': defaultDocumentType.name,
      'default_amount': defaultAmount,
      'default_description': defaultDescription,
      'default_reference_prefix': defaultReferencePrefix,
      'default_tax_rate': defaultTaxRate,
      'recurrence_interval_months': recurrenceIntervalMonths,
      'next_due_date': nextDueDate?.toIso8601String(),
      'next_review_date': nextReviewDate?.toIso8601String(),
      'review_reminder_days': reviewReminderDays,
      'link_purchase_invoice': linkPurchaseInvoice,
      'link_kind': linkKind,
      'notes': notes,
      'metadata': metadata,
      'created_by': createdBy,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };

    if (includeIdentifier && id != null) {
      payload['id'] = id;
    }

    return payload;
  }

  ExpenseTemplate copyWith({
    String? id,
    String? tenantId,
    String? name,
    bool? isActive,
    int? priority,
    String? triggerCategoryId,
    String? triggerSupplierId,
    List<String>? triggerKeywords,
    String? defaultCategoryId,
    String? defaultSupplierId,
    String? defaultSupplierName,
    String? defaultSupplierRut,
    String? defaultAccountId,
    String? defaultPaymentMethodId,
    ExpenseDocumentType? defaultDocumentType,
    double? defaultAmount,
    String? defaultDescription,
    String? defaultReferencePrefix,
    double? defaultTaxRate,
    int? recurrenceIntervalMonths,
    DateTime? nextDueDate,
    DateTime? nextReviewDate,
    int? reviewReminderDays,
    bool? linkPurchaseInvoice,
    String? linkKind,
    String? notes,
    Map<String, dynamic>? metadata,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExpenseTemplate(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      priority: priority ?? this.priority,
      triggerCategoryId: triggerCategoryId ?? this.triggerCategoryId,
      triggerSupplierId: triggerSupplierId ?? this.triggerSupplierId,
      triggerKeywords: triggerKeywords ?? this.triggerKeywords,
      defaultCategoryId: defaultCategoryId ?? this.defaultCategoryId,
      defaultSupplierId: defaultSupplierId ?? this.defaultSupplierId,
      defaultSupplierName: defaultSupplierName ?? this.defaultSupplierName,
      defaultSupplierRut: defaultSupplierRut ?? this.defaultSupplierRut,
      defaultAccountId: defaultAccountId ?? this.defaultAccountId,
      defaultPaymentMethodId:
          defaultPaymentMethodId ?? this.defaultPaymentMethodId,
      defaultDocumentType: defaultDocumentType ?? this.defaultDocumentType,
      defaultAmount: defaultAmount ?? this.defaultAmount,
      defaultDescription: defaultDescription ?? this.defaultDescription,
      defaultReferencePrefix:
          defaultReferencePrefix ?? this.defaultReferencePrefix,
      defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
      recurrenceIntervalMonths:
          recurrenceIntervalMonths ?? this.recurrenceIntervalMonths,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      reviewReminderDays: reviewReminderDays ?? this.reviewReminderDays,
      linkPurchaseInvoice: linkPurchaseInvoice ?? this.linkPurchaseInvoice,
      linkKind: linkKind ?? this.linkKind,
      notes: notes ?? this.notes,
      metadata: metadata ?? this.metadata,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static ExpenseDocumentType _parseDocumentType(dynamic value) {
    final raw = value?.toString();
    return ExpenseDocumentType.values.firstWhere(
      (type) => type.name == raw,
      orElse: () => ExpenseDocumentType.invoice,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
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

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
    return const [];
  }

  static Map<String, dynamic> _parseMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, dynamic val) => MapEntry(key.toString(), val));
    }
    return const {};
  }
}
