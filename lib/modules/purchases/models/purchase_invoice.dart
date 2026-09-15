import '../../../shared/models/tax_treatment.dart';
import '../../../shared/models/product.dart'
    show PurchaseTreatment, parsePurchaseTreatment;
import 'purchase_receipt.dart';

Map<String, dynamic> _ensureMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, dynamic val) => MapEntry(key.toString(), val));
  }
  throw ArgumentError('Expected Map but received ${value.runtimeType}');
}

DateTime _parseDate(dynamic value, {DateTime? fallback}) {
  if (value == null) return fallback ?? DateTime.now();
  if (value is DateTime) return value;
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback ?? DateTime.now();
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return fallback ?? DateTime.now();
}

double _clp(num value) => value.roundToDouble();

class PurchaseSourceDocumentKind {
  const PurchaseSourceDocumentKind({
    required this.code,
    required this.displayName,
    required this.description,
    required this.workflowKind,
    required this.sortOrder,
    required this.isActive,
  });

  static const String defaultCode = 'tax_invoice';

  final String code;
  final String displayName;
  final String description;
  final String workflowKind;
  final int sortOrder;
  final bool isActive;

  bool get isDirectPurchase => workflowKind == 'direct_purchase';

  factory PurchaseSourceDocumentKind.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString().trim() ?? '';
    final displayName = json['display_name']?.toString().trim() ?? '';
    final workflowKind = json['workflow_kind']?.toString().trim() ?? '';
    if (code.isEmpty ||
        displayName.isEmpty ||
        !const {'ordered_purchase', 'direct_purchase'}.contains(workflowKind)) {
      throw const FormatException(
        'Invalid purchase source document kind row',
      );
    }
    return PurchaseSourceDocumentKind(
      code: code,
      displayName: displayName,
      description: json['description']?.toString().trim() ?? '',
      workflowKind: workflowKind,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class PurchaseInvoice {
  static const String listPreviewSelect =
      'id,tenant_id,invoice_number,supplier_id,supplier_name,supplier_rut,'
      'date,due_date,status,subtotal,tax,total,net_amount,paid_amount,balance,'
      'supplier_refunded_amount,credited_amount,supplier_credit_balance,'
      'prepayment_model,sent_date,confirmed_date,received_date,paid_date,'
      'items,created_at,updated_at,source_document_kind,'
      'source_document_kind_label,source_document_workflow_kind';
  static const String listReadModelSelect =
      '$listPreviewSelect,receipt_state,receipt_expected_quantity,'
      'receipt_accepted_quantity,receipt_reported_difference_quantity,'
      'receipt_resolved_difference_quantity,'
      'receipt_nonphysical_resolution_quantity,'
      'receipt_unresolved_difference_quantity,'
      'receipt_physical_remaining_quantity,receipt_remaining_quantity,'
      'receipt_count,receipt_latest_received_at,receipt_legacy_received';

  final String? id;
  final String tenantId;
  final String invoiceNumber;
  final String sourceDocumentKind;
  final String? sourceDocumentKindLabel;
  final String? sourceDocumentWorkflowKind;
  final String? supplierId;
  final String? supplierName;
  final String? supplierRut;
  final DateTime date;
  final DateTime? dueDate;
  final String? reference;
  final String? notes;
  final PurchaseInvoiceStatus status;
  final double subtotal;
  final double ivaAmount;
  final double total;
  final TaxTreatment taxTreatment; // actual tax choice for this purchase
  final double
      netAmount; // net amount before IVA (total÷1.19 when tax_included)
  final String discountType; // 'percentage' or 'amount'
  final double discountValue; // raw input (e.g. 10 for 10%, or 5000 for $5000)
  final double discountAmount; // computed discount in CLP
  final bool
      isDiscountBeforeTax; // true = reduces tax base, false = reduces total
  final List<PurchaseInvoiceItem> items;
  final List<PurchaseAdditionalCost> additionalCosts;
  final DateTime createdAt;
  final DateTime updatedAt;

  // New fields for 5-status workflow
  final bool prepaymentModel;
  final DateTime? sentDate;
  final DateTime? confirmedDate;
  final DateTime? receivedDate;
  final DateTime? paidDate;
  final String? supplierInvoiceNumber;
  final DateTime? supplierInvoiceDate;
  final double paidAmount;
  final double supplierRefundedAmount;
  final double balance;
  final double creditedAmount;
  final double supplierCreditBalance;
  final PurchaseReceiptFulfillment? receiptFulfillment;

  PurchaseInvoice({
    this.id,
    required this.tenantId,
    required this.invoiceNumber,
    this.sourceDocumentKind = PurchaseSourceDocumentKind.defaultCode,
    this.sourceDocumentKindLabel,
    this.sourceDocumentWorkflowKind,
    required this.supplierId,
    this.supplierName,
    this.supplierRut,
    required this.date,
    this.dueDate,
    this.reference,
    this.notes,
    this.status = PurchaseInvoiceStatus.draft,
    this.subtotal = 0,
    this.ivaAmount = 0,
    this.total = 0,
    this.taxTreatment = TaxTreatment.noTax,
    this.netAmount = 0,
    this.discountType = 'percentage',
    this.discountValue = 0,
    this.discountAmount = 0,
    this.isDiscountBeforeTax = true,
    this.items = const [],
    this.additionalCosts = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
    this.prepaymentModel = false,
    this.sentDate,
    this.confirmedDate,
    this.receivedDate,
    this.paidDate,
    this.supplierInvoiceNumber,
    this.supplierInvoiceDate,
    this.paidAmount = 0,
    this.supplierRefundedAmount = 0,
    this.creditedAmount = 0,
    this.supplierCreditBalance = 0,
    this.receiptFulfillment,
    double? balance,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        balance = balance ?? (total - (paidAmount));

  PurchaseInvoice copyWith({
    String? id,
    String? tenantId,
    String? invoiceNumber,
    String? sourceDocumentKind,
    String? sourceDocumentKindLabel,
    String? sourceDocumentWorkflowKind,
    String? supplierId,
    String? supplierName,
    String? supplierRut,
    DateTime? date,
    DateTime? dueDate,
    String? reference,
    String? notes,
    PurchaseInvoiceStatus? status,
    double? subtotal,
    double? ivaAmount,
    double? total,
    TaxTreatment? taxTreatment,
    double? netAmount,
    String? discountType,
    double? discountValue,
    double? discountAmount,
    bool? isDiscountBeforeTax,
    List<PurchaseInvoiceItem>? items,
    List<PurchaseAdditionalCost>? additionalCosts,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? prepaymentModel,
    DateTime? sentDate,
    DateTime? confirmedDate,
    DateTime? receivedDate,
    DateTime? paidDate,
    String? supplierInvoiceNumber,
    DateTime? supplierInvoiceDate,
    double? paidAmount,
    double? supplierRefundedAmount,
    double? creditedAmount,
    double? supplierCreditBalance,
    PurchaseReceiptFulfillment? receiptFulfillment,
    double? balance,
  }) {
    return PurchaseInvoice(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      sourceDocumentKind: sourceDocumentKind ?? this.sourceDocumentKind,
      sourceDocumentKindLabel:
          sourceDocumentKindLabel ?? this.sourceDocumentKindLabel,
      sourceDocumentWorkflowKind:
          sourceDocumentWorkflowKind ?? this.sourceDocumentWorkflowKind,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      supplierRut: supplierRut ?? this.supplierRut,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      reference: reference ?? this.reference,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      subtotal: subtotal ?? this.subtotal,
      ivaAmount: ivaAmount ?? this.ivaAmount,
      total: total ?? this.total,
      taxTreatment: taxTreatment ?? this.taxTreatment,
      netAmount: netAmount ?? this.netAmount,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      discountAmount: discountAmount ?? this.discountAmount,
      isDiscountBeforeTax: isDiscountBeforeTax ?? this.isDiscountBeforeTax,
      items: items ?? this.items,
      additionalCosts: additionalCosts ?? this.additionalCosts,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      prepaymentModel: prepaymentModel ?? this.prepaymentModel,
      sentDate: sentDate ?? this.sentDate,
      confirmedDate: confirmedDate ?? this.confirmedDate,
      receivedDate: receivedDate ?? this.receivedDate,
      paidDate: paidDate ?? this.paidDate,
      supplierInvoiceNumber:
          supplierInvoiceNumber ?? this.supplierInvoiceNumber,
      supplierInvoiceDate: supplierInvoiceDate ?? this.supplierInvoiceDate,
      paidAmount: paidAmount ?? this.paidAmount,
      supplierRefundedAmount:
          supplierRefundedAmount ?? this.supplierRefundedAmount,
      creditedAmount: creditedAmount ?? this.creditedAmount,
      supplierCreditBalance:
          supplierCreditBalance ?? this.supplierCreditBalance,
      receiptFulfillment: receiptFulfillment ?? this.receiptFulfillment,
      balance: balance ?? this.balance,
    );
  }

  factory PurchaseInvoice.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List?) ?? const [];
    final extraCosts = (json['additional_costs'] as List?) ?? const [];
    return PurchaseInvoice(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      invoiceNumber: json['invoice_number']?.toString() ?? '',
      sourceDocumentKind: json['source_document_kind']?.toString() ??
          PurchaseSourceDocumentKind.defaultCode,
      sourceDocumentKindLabel: json['source_document_kind_label']?.toString(),
      sourceDocumentWorkflowKind:
          json['source_document_workflow_kind']?.toString(),
      supplierId: json['supplier_id']?.toString(),
      supplierName: json['supplier_name'] as String?,
      supplierRut: json['supplier_rut'] as String?,
      date: _parseDate(json['date']),
      dueDate: json['due_date'] != null ? _parseDate(json['due_date']) : null,
      reference: json['reference'] as String?,
      notes: json['notes'] as String?,
      status: PurchaseInvoiceStatusX.fromName(json['status']) ??
          PurchaseInvoiceStatus.draft,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      ivaAmount:
          (json['tax'] as num?)?.toDouble() ?? 0, // Database column is 'tax'
      total: (json['total'] as num?)?.toDouble() ?? 0,
      taxTreatment: TaxTreatment.fromString(json['tax_treatment']?.toString()),
      netAmount: (json['net_amount'] as num?)?.toDouble() ?? 0,
      discountType: json['discount_type'] as String? ?? 'percentage',
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      isDiscountBeforeTax: json['is_discount_before_tax'] as bool? ?? true,
      items: items
          .map((item) => PurchaseInvoiceItem.fromJson(_ensureMap(item)))
          .toList(),
      additionalCosts: extraCosts
          .map((cost) => PurchaseAdditionalCost.fromJson(_ensureMap(cost)))
          .toList(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      prepaymentModel: json['prepayment_model'] as bool? ?? false,
      sentDate:
          json['sent_date'] != null ? _parseDate(json['sent_date']) : null,
      confirmedDate: json['confirmed_date'] != null
          ? _parseDate(json['confirmed_date'])
          : null,
      receivedDate: json['received_date'] != null
          ? _parseDate(json['received_date'])
          : null,
      paidDate:
          json['paid_date'] != null ? _parseDate(json['paid_date']) : null,
      supplierInvoiceNumber: json['supplier_invoice_number'] as String?,
      supplierInvoiceDate: json['supplier_invoice_date'] != null
          ? _parseDate(json['supplier_invoice_date'])
          : null,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      supplierRefundedAmount:
          (json['supplier_refunded_amount'] as num?)?.toDouble() ?? 0,
      creditedAmount: (json['credited_amount'] as num?)?.toDouble() ?? 0,
      supplierCreditBalance:
          (json['supplier_credit_balance'] as num?)?.toDouble() ?? 0,
      receiptFulfillment: json.containsKey('receipt_state')
          ? PurchaseReceiptFulfillment.fromListReadModel(json)
          : null,
      balance: (json['balance'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    final totalClp = _clp(total);
    final paidClp = _clp(paidAmount);
    final netClp = taxTreatment == TaxTreatment.taxIncluded
        ? _clp(totalClp / 1.19)
        : totalClp;
    final taxClp =
        taxTreatment == TaxTreatment.taxIncluded ? totalClp - netClp : 0.0;

    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'invoice_number': invoiceNumber,
      'source_document_kind': sourceDocumentKind,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'supplier_rut': supplierRut,
      'date': date.toUtc().toIso8601String(),
      'due_date': dueDate?.toUtc().toIso8601String(),
      'reference': reference,
      'notes': notes,
      'status': status.name,
      'subtotal': netClp,
      'tax': taxClp, // Database column is 'tax', not 'iva_amount'
      'total': totalClp,
      'tax_treatment': taxTreatment.toValue(),
      'net_amount': netClp,
      'discount_type': discountType,
      'discount_value': discountValue,
      'discount_amount': _clp(discountAmount),
      'is_discount_before_tax': isDiscountBeforeTax,
      'items': items.map((item) => item.toJson()).toList(),
      'additional_costs': additionalCosts.map((cost) => cost.toJson()).toList(),
      'prepayment_model': prepaymentModel,
      'sent_date': sentDate?.toUtc().toIso8601String(),
      'confirmed_date': confirmedDate?.toUtc().toIso8601String(),
      'received_date': receivedDate?.toUtc().toIso8601String(),
      'paid_date': paidDate?.toUtc().toIso8601String(),
      'supplier_invoice_number': supplierInvoiceNumber,
      'supplier_invoice_date': supplierInvoiceDate?.toUtc().toIso8601String(),
      'paid_amount': paidClp,
      'balance': (totalClp - paidClp).clamp(0.0, double.infinity),
    };
  }
}

enum PurchaseInvoiceStatus {
  draft('Borrador'),
  sent('Enviada'),
  confirmed('Confirmada'),
  received('Recibida'),
  paid('Pagada'),
  cancelled('Anulada');

  const PurchaseInvoiceStatus(this.displayName);
  final String displayName;
}

extension PurchaseInvoiceStatusX on PurchaseInvoiceStatus {
  static PurchaseInvoiceStatus? fromName(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString();
    return PurchaseInvoiceStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () {
        final normalized = value.toLowerCase();
        return PurchaseInvoiceStatus.values.firstWhere(
          (status) => status.name.toLowerCase() == normalized,
          orElse: () => PurchaseInvoiceStatus.draft,
        );
      },
    );
  }
}

class PurchaseInvoiceItem {
  /// Stable client/source line identity. Legacy invoice rows may omit it.
  final String? lineId;
  final String? sourceNeedId;
  final String productId;
  final String? productName;
  final String? productSku;
  final String? description; // Add description field
  final PurchaseTreatment purchaseTreatment;
  final double quantity;
  final double unitCost;
  final double discount;
  final double ivaRate;
  final DateTime createdAt;

  /// Provenance for a source row expanded through a supplier resolution graph.
  ///
  /// These fields are optional only for backward compatibility. If any of the
  /// reserved supplier-resolution fields is present, the complete staged
  /// snapshot is required by the database before the draft can be saved.
  final String? resolutionApplicationId;
  final String? resolutionRevisionId;
  final String? sourceLineKey;
  final int? componentPosition;
  final String? componentRole;
  final double? sourcePurchaseQuantity;
  final int? catalogUnitsPerPurchase;
  final int? sourceLineTotalMinor;
  final int? allocatedLineTotalMinor;
  final double? allocationRatio;

  // Lossless supplier-owned source evidence retained with every expanded row.
  final int? sourceRowIndex;
  final List<String> sourceOrderNumbers;
  final String? supplierListingId;
  final String? supplierVariantKey;
  final String? optionEvidenceHash;
  final String? sourceTitle;
  final String? selectedOption;
  final int? rawPackCount;
  final String? rawUnitToken;
  final bool rawPackEvidenceConflict;
  final Map<String, dynamic> sourceEvidenceSnapshot;

  PurchaseInvoiceItem({
    this.lineId,
    this.sourceNeedId,
    required this.productId,
    this.productName,
    this.productSku,
    this.description,
    this.purchaseTreatment = PurchaseTreatment.inventory,
    this.quantity = 1,
    required this.unitCost,
    this.discount = 0,
    this.ivaRate = 0.19,
    this.resolutionApplicationId,
    this.resolutionRevisionId,
    this.sourceLineKey,
    this.componentPosition,
    this.componentRole,
    this.sourcePurchaseQuantity,
    this.catalogUnitsPerPurchase,
    this.sourceLineTotalMinor,
    this.allocatedLineTotalMinor,
    this.allocationRatio,
    this.sourceRowIndex,
    List<String> sourceOrderNumbers = const <String>[],
    this.supplierListingId,
    this.supplierVariantKey,
    this.optionEvidenceHash,
    this.sourceTitle,
    this.selectedOption,
    this.rawPackCount,
    this.rawUnitToken,
    this.rawPackEvidenceConflict = false,
    Map<String, dynamic> sourceEvidenceSnapshot = const <String, dynamic>{},
    DateTime? createdAt,
  })  : sourceOrderNumbers = List<String>.unmodifiable(sourceOrderNumbers),
        sourceEvidenceSnapshot = _immutableJsonMap(sourceEvidenceSnapshot),
        createdAt = createdAt ?? DateTime.now();

  PurchaseInvoiceItem copyWith({
    String? lineId,
    String? sourceNeedId,
    String? productId,
    String? productName,
    String? productSku,
    String? description,
    PurchaseTreatment? purchaseTreatment,
    double? quantity,
    double? unitCost,
    double? discount,
    double? ivaRate,
    String? resolutionApplicationId,
    String? resolutionRevisionId,
    String? sourceLineKey,
    int? componentPosition,
    String? componentRole,
    double? sourcePurchaseQuantity,
    int? catalogUnitsPerPurchase,
    int? sourceLineTotalMinor,
    int? allocatedLineTotalMinor,
    double? allocationRatio,
    int? sourceRowIndex,
    List<String>? sourceOrderNumbers,
    String? supplierListingId,
    String? supplierVariantKey,
    String? optionEvidenceHash,
    String? sourceTitle,
    String? selectedOption,
    int? rawPackCount,
    String? rawUnitToken,
    bool? rawPackEvidenceConflict,
    Map<String, dynamic>? sourceEvidenceSnapshot,
    DateTime? createdAt,
  }) {
    return PurchaseInvoiceItem(
      lineId: lineId ?? this.lineId,
      sourceNeedId: sourceNeedId ?? this.sourceNeedId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSku: productSku ?? this.productSku,
      description: description ?? this.description,
      purchaseTreatment: purchaseTreatment ?? this.purchaseTreatment,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
      discount: discount ?? this.discount,
      ivaRate: ivaRate ?? this.ivaRate,
      resolutionApplicationId:
          resolutionApplicationId ?? this.resolutionApplicationId,
      resolutionRevisionId: resolutionRevisionId ?? this.resolutionRevisionId,
      sourceLineKey: sourceLineKey ?? this.sourceLineKey,
      componentPosition: componentPosition ?? this.componentPosition,
      componentRole: componentRole ?? this.componentRole,
      sourcePurchaseQuantity:
          sourcePurchaseQuantity ?? this.sourcePurchaseQuantity,
      catalogUnitsPerPurchase:
          catalogUnitsPerPurchase ?? this.catalogUnitsPerPurchase,
      sourceLineTotalMinor: sourceLineTotalMinor ?? this.sourceLineTotalMinor,
      allocatedLineTotalMinor:
          allocatedLineTotalMinor ?? this.allocatedLineTotalMinor,
      allocationRatio: allocationRatio ?? this.allocationRatio,
      sourceRowIndex: sourceRowIndex ?? this.sourceRowIndex,
      sourceOrderNumbers: sourceOrderNumbers ?? this.sourceOrderNumbers,
      supplierListingId: supplierListingId ?? this.supplierListingId,
      supplierVariantKey: supplierVariantKey ?? this.supplierVariantKey,
      optionEvidenceHash: optionEvidenceHash ?? this.optionEvidenceHash,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      selectedOption: selectedOption ?? this.selectedOption,
      rawPackCount: rawPackCount ?? this.rawPackCount,
      rawUnitToken: rawUnitToken ?? this.rawUnitToken,
      rawPackEvidenceConflict:
          rawPackEvidenceConflict ?? this.rawPackEvidenceConflict,
      sourceEvidenceSnapshot:
          sourceEvidenceSnapshot ?? this.sourceEvidenceSnapshot,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Converts a graph-backed supplier component into an ordinary manual
  /// invoice line while preserving the operator-visible commercial values.
  ///
  /// Supplier-resolution provenance is an all-or-nothing database contract:
  /// retaining only part of it would make the invoice look editable while the
  /// save trigger correctly rejects the drift. Callers must detach every line
  /// sharing the same resolution application together.
  PurchaseInvoiceItem withoutSupplierResolutionProvenance() {
    return PurchaseInvoiceItem(
      lineId: lineId,
      sourceNeedId: sourceNeedId,
      productId: productId,
      productName: productName,
      productSku: productSku,
      description: description,
      purchaseTreatment: purchaseTreatment,
      quantity: quantity,
      unitCost: unitCost,
      discount: discount,
      ivaRate: ivaRate,
      createdAt: createdAt,
    );
  }

  factory PurchaseInvoiceItem.fromJson(Map<String, dynamic> json) {
    return PurchaseInvoiceItem(
      lineId: json['line_id']?.toString(),
      sourceNeedId: json['source_need_id']?.toString(),
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name'] as String?,
      productSku: json['product_sku'] as String?,
      description: json['description'] as String?,
      purchaseTreatment: parsePurchaseTreatment(
        json['purchase_treatment'],
      ),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      unitCost: (json['unit_cost'] as num?)?.toDouble() ?? 0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      ivaRate: (json['iva_rate'] as num?)?.toDouble() ?? 0.19,
      resolutionApplicationId:
          json['supplier_resolution_application_id']?.toString(),
      resolutionRevisionId: json['supplier_resolution_revision_id']?.toString(),
      sourceLineKey: json['source_line_key']?.toString(),
      componentPosition: _optionalExactInteger(
        json,
        'supplier_resolution_edge_ordinal',
      ),
      componentRole: json['supplier_resolution_component_role']?.toString(),
      sourcePurchaseQuantity:
          (json['source_purchase_quantity'] as num?)?.toDouble(),
      catalogUnitsPerPurchase: _optionalExactInteger(
        json,
        'catalog_units_per_purchase',
      ),
      sourceLineTotalMinor:
          _optionalExactInteger(json, 'source_line_total_minor'),
      allocatedLineTotalMinor:
          _optionalExactInteger(json, 'allocated_line_total_minor'),
      allocationRatio: (json['allocation_ratio'] as num?)?.toDouble(),
      sourceRowIndex: _optionalExactInteger(json, 'source_row_index'),
      sourceOrderNumbers: _stringList(json['source_order_numbers']),
      supplierListingId: json['supplier_listing_id']?.toString(),
      supplierVariantKey: json['supplier_variant_key']?.toString(),
      optionEvidenceHash: json['option_evidence_hash']?.toString(),
      sourceTitle: json['source_title']?.toString(),
      selectedOption: json['selected_option']?.toString(),
      rawPackCount: _optionalExactInteger(json, 'raw_pack_count'),
      rawUnitToken: json['raw_unit_code']?.toString(),
      rawPackEvidenceConflict: json['pack_evidence_conflict'] == true,
      sourceEvidenceSnapshot: _optionalMap(json['source_snapshot']),
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (lineId != null) 'line_id': lineId,
      if (sourceNeedId != null) 'source_need_id': sourceNeedId,
      'product_id': productId,
      'product_name': productName,
      'product_sku': productSku,
      'description': description,
      'purchase_treatment': purchaseTreatment.dbValue,
      'quantity': quantity,
      'unit_cost': unitCost,
      'discount': discount,
      'iva_rate': ivaRate,
      'created_at': createdAt.toUtc().toIso8601String(),
      if (resolutionApplicationId != null)
        'supplier_resolution_application_id': resolutionApplicationId,
      if (resolutionRevisionId != null)
        'supplier_resolution_revision_id': resolutionRevisionId,
      if (sourceLineKey != null) 'source_line_key': sourceLineKey,
      if (componentPosition != null)
        'supplier_resolution_edge_ordinal': componentPosition,
      if (componentRole != null)
        'supplier_resolution_component_role': componentRole,
      if (sourcePurchaseQuantity != null)
        'source_purchase_quantity': sourcePurchaseQuantity,
      if (catalogUnitsPerPurchase != null)
        'catalog_units_per_purchase': catalogUnitsPerPurchase,
      if (sourceLineTotalMinor != null)
        'source_line_total_minor': sourceLineTotalMinor,
      if (allocatedLineTotalMinor != null)
        'allocated_line_total_minor': allocatedLineTotalMinor,
      if (allocationRatio != null) 'allocation_ratio': allocationRatio,
      if (sourceRowIndex != null) 'source_row_index': sourceRowIndex,
      if (sourceOrderNumbers.isNotEmpty)
        'source_order_numbers': sourceOrderNumbers,
      if (supplierListingId != null) 'supplier_listing_id': supplierListingId,
      if (supplierVariantKey != null)
        'supplier_variant_key': supplierVariantKey,
      if (optionEvidenceHash != null)
        'option_evidence_hash': optionEvidenceHash,
      if (sourceTitle != null) 'source_title': sourceTitle,
      if (selectedOption != null) 'selected_option': selectedOption,
      if (rawPackCount != null) 'raw_pack_count': rawPackCount,
      if (rawUnitToken != null) 'raw_unit_code': rawUnitToken,
      if (hasSupplierSourceEvidence || rawPackEvidenceConflict)
        'pack_evidence_conflict': rawPackEvidenceConflict,
      if (sourceEvidenceSnapshot.isNotEmpty)
        'source_snapshot': sourceEvidenceSnapshot,
    };
  }

  bool get hasSupplierResolutionProvenance =>
      resolutionApplicationId != null ||
      resolutionRevisionId != null ||
      sourceLineKey != null ||
      componentPosition != null ||
      sourcePurchaseQuantity != null ||
      catalogUnitsPerPurchase != null ||
      sourceLineTotalMinor != null ||
      allocatedLineTotalMinor != null ||
      allocationRatio != null;

  bool get hasSupplierSourceEvidence =>
      sourceRowIndex != null ||
      sourceOrderNumbers.isNotEmpty ||
      supplierListingId != null ||
      supplierVariantKey != null ||
      optionEvidenceHash != null ||
      sourceTitle != null ||
      selectedOption != null ||
      rawPackCount != null ||
      rawUnitToken != null ||
      sourceEvidenceSnapshot.isNotEmpty;

  bool get hasCompleteSupplierResolutionProvenance =>
      resolutionApplicationId != null &&
      resolutionRevisionId != null &&
      sourceLineKey != null &&
      componentPosition != null &&
      componentPosition! > 0 &&
      sourcePurchaseQuantity != null &&
      sourcePurchaseQuantity! > 0 &&
      catalogUnitsPerPurchase != null &&
      catalogUnitsPerPurchase! > 0 &&
      sourceLineTotalMinor != null &&
      sourceLineTotalMinor! >= 0 &&
      allocatedLineTotalMinor != null &&
      allocatedLineTotalMinor! >= 0 &&
      allocationRatio != null &&
      allocationRatio! > 0 &&
      allocationRatio! <= 1;

  double get netAmount => (quantity * unitCost) - discount;
  double get netAmountClamped => netAmount < 0 ? 0 : netAmount;
}

int? _optionalExactInteger(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = json[key];
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  final text = value.toString().trim();
  final match = RegExp(r'^([+-]?[0-9]+)(?:\.0+)?$').firstMatch(text);
  if (match != null) return int.parse(match.group(1)!);
  throw FormatException('$key must be an exact integer.');
}

List<String> _stringList(Object? value) {
  if (value == null) return const <String>[];
  if (value is! List) {
    throw const FormatException('Expected a JSON string list.');
  }
  return List<String>.unmodifiable(
    value.map((entry) => entry.toString()),
  );
}

Map<String, dynamic> _optionalMap(Object? value) {
  if (value == null) return const <String, dynamic>{};
  return _ensureMap(value);
}

Map<String, dynamic> _immutableJsonMap(Map<String, dynamic> value) {
  Object? freeze(Object? raw) {
    if (raw is Map) {
      return Map<String, dynamic>.unmodifiable(
        raw.map(
          (key, nested) => MapEntry(key.toString(), freeze(nested)),
        ),
      );
    }
    if (raw is List) {
      return List<Object?>.unmodifiable(raw.map(freeze));
    }
    return raw;
  }

  return freeze(value)! as Map<String, dynamic>;
}

class PurchaseAdditionalCost {
  final String label;
  final double amount;

  const PurchaseAdditionalCost({required this.label, required this.amount});

  factory PurchaseAdditionalCost.fromJson(Map<String, dynamic> json) {
    return PurchaseAdditionalCost(
      label: json['label'] as String? ?? 'Costo',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'amount': amount,
      };
}
