import '../../../shared/models/tax_treatment.dart';
import '../../../shared/models/product.dart'
    show PurchaseTreatment, parsePurchaseTreatment;

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

class PurchaseInvoice {
  static const String listPreviewSelect =
      'id,tenant_id,invoice_number,supplier_id,supplier_name,supplier_rut,'
      'date,due_date,status,subtotal,tax,total,net_amount,paid_amount,balance,'
      'supplier_refunded_amount,credited_amount,supplier_credit_balance,'
      'prepayment_model,sent_date,confirmed_date,received_date,paid_date,'
      'created_at,updated_at';

  final String? id;
  final String tenantId;
  final String invoiceNumber;
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

  PurchaseInvoice({
    this.id,
    required this.tenantId,
    required this.invoiceNumber,
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
    double? balance,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        balance = balance ?? (total - (paidAmount));

  PurchaseInvoice copyWith({
    String? id,
    String? tenantId,
    String? invoiceNumber,
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
    double? balance,
  }) {
    return PurchaseInvoice(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
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

  PurchaseInvoiceItem({
    required this.productId,
    this.productName,
    this.productSku,
    this.description,
    this.purchaseTreatment = PurchaseTreatment.inventory,
    this.quantity = 1,
    required this.unitCost,
    this.discount = 0,
    this.ivaRate = 0.19,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  PurchaseInvoiceItem copyWith({
    String? productId,
    String? productName,
    String? productSku,
    String? description,
    PurchaseTreatment? purchaseTreatment,
    double? quantity,
    double? unitCost,
    double? discount,
    double? ivaRate,
    DateTime? createdAt,
  }) {
    return PurchaseInvoiceItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSku: productSku ?? this.productSku,
      description: description ?? this.description,
      purchaseTreatment: purchaseTreatment ?? this.purchaseTreatment,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
      discount: discount ?? this.discount,
      ivaRate: ivaRate ?? this.ivaRate,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory PurchaseInvoiceItem.fromJson(Map<String, dynamic> json) {
    return PurchaseInvoiceItem(
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
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
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
    };
  }

  double get netAmount => (quantity * unitCost) - discount;
  double get netAmountClamped => netAmount < 0 ? 0 : netAmount;
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
