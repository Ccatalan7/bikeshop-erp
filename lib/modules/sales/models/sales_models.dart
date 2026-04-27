import '../../../shared/models/product.dart'
    show PurchaseTreatment, parsePurchaseTreatment;
import '../../../shared/models/tax_treatment.dart';

Map<String, dynamic> _ensureMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
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

class Invoice {
  final String? id;
  final String tenantId;
  final String invoiceNumber;
  final String? customerId;
  final String? customerName;
  final String? customerRut;
  final DateTime date;
  final DateTime? dueDate;
  final String? reference;
  final InvoiceStatus status;
  final double subtotal;
  final double ivaAmount;
  final double total;
  final double paidAmount;
  final double balance;
  final TaxTreatment taxTreatment; // actual tax choice for this invoice
  final double
      netAmount; // net amount before IVA (total÷1.19 when tax_included)
  final List<InvoiceItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ✅ UNIFIED ARCHITECTURE (Nov 18, 2025): Pega-specific fields
  final String invoiceType; // 'sale', 'pega', 'service'
  final String? bikeId; // For pegas: the bike being serviced
  final String? mechanicId; // For pegas: assigned mechanic
  final String? jobNumber; // For pegas: PG-00001 style number
  final DateTime? entryDate; // For pegas: when bike arrived
  final DateTime? deliveryDate; // For pegas: when bike was delivered
  final bool requiresApproval; // For pegas: needs customer OK
  final bool isWarranty; // For pegas: warranty work
  final String? workDescription; // For pegas: work performed
  final String? notes; // Internal notes
  final String? source; // 'pos', 'manual_sale', 'ecommerce', 'mechanic_job'

  Invoice({
    this.id,
    required this.tenantId,
    this.customerId,
    this.invoiceNumber = '',
    this.customerName,
    this.customerRut,
    required this.date,
    this.dueDate,
    this.reference,
    this.status = InvoiceStatus.draft,
    this.subtotal = 0,
    this.ivaAmount = 0,
    this.total = 0,
    this.paidAmount = 0,
    this.balance = 0,
    this.taxTreatment = TaxTreatment.noTax,
    this.netAmount = 0,
    this.items = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
    this.invoiceType = 'sale',
    this.bikeId,
    this.mechanicId,
    this.jobNumber,
    this.entryDate,
    this.deliveryDate,
    this.requiresApproval = false,
    this.isWarranty = false,
    this.workDescription,
    this.notes,
    this.source,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Invoice copyWith({
    String? id,
    String? tenantId,
    String? customerId,
    String? invoiceNumber,
    String? customerName,
    String? customerRut,
    DateTime? date,
    DateTime? dueDate,
    String? reference,
    InvoiceStatus? status,
    double? subtotal,
    double? ivaAmount,
    double? total,
    double? paidAmount,
    double? balance,
    TaxTreatment? taxTreatment,
    double? netAmount,
    List<InvoiceItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? invoiceType,
    String? bikeId,
    String? mechanicId,
    String? jobNumber,
    DateTime? entryDate,
    DateTime? deliveryDate,
    bool? requiresApproval,
    bool? isWarranty,
    String? workDescription,
    String? notes,
    String? source,
  }) {
    return Invoice(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      customerId: customerId ?? this.customerId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      customerName: customerName ?? this.customerName,
      customerRut: customerRut ?? this.customerRut,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      reference: reference ?? this.reference,
      status: status ?? this.status,
      subtotal: subtotal ?? this.subtotal,
      ivaAmount: ivaAmount ?? this.ivaAmount,
      total: total ?? this.total,
      paidAmount: paidAmount ?? this.paidAmount,
      balance: balance ?? this.balance,
      taxTreatment: taxTreatment ?? this.taxTreatment,
      netAmount: netAmount ?? this.netAmount,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      invoiceType: invoiceType ?? this.invoiceType,
      bikeId: bikeId ?? this.bikeId,
      mechanicId: mechanicId ?? this.mechanicId,
      jobNumber: jobNumber ?? this.jobNumber,
      entryDate: entryDate ?? this.entryDate,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      requiresApproval: requiresApproval ?? this.requiresApproval,
      isWarranty: isWarranty ?? this.isWarranty,
      workDescription: workDescription ?? this.workDescription,
      notes: notes ?? this.notes,
      source: source ?? this.source,
    );
  }

  factory Invoice.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return Invoice(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      customerId: json['customer_id']?.toString(),
      invoiceNumber: json['invoice_number']?.toString() ?? '',
      customerName: json['customer_name']?.toString(),
      customerRut: json['customer_rut']?.toString(),
      date: _parseDate(json['date']),
      dueDate: json['due_date'] != null ? _parseDate(json['due_date']) : null,
      reference: json['reference']?.toString(),
      status: InvoiceStatusX.fromName(json['status']) ?? InvoiceStatus.draft,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      ivaAmount: (json['iva_amount'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      balance: (json['balance'] as num?)?.toDouble() ??
          ((json['total'] as num?)?.toDouble() ?? 0) -
              ((json['paid_amount'] as num?)?.toDouble() ?? 0),
      taxTreatment: TaxTreatment.fromString(json['tax_treatment']?.toString()),
      netAmount: (json['net_amount'] as num?)?.toDouble() ?? 0,
      items: rawItems
          .map((item) => InvoiceItem.fromJson(_ensureMap(item)))
          .toList(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      invoiceType: json['invoice_type']?.toString() ?? 'sale',
      bikeId: json['bike_id']?.toString(),
      mechanicId: json['mechanic_id']?.toString(),
      jobNumber: json['job_number']?.toString(),
      entryDate:
          json['entry_date'] != null ? _parseDate(json['entry_date']) : null,
      deliveryDate: json['delivery_date'] != null
          ? _parseDate(json['delivery_date'])
          : null,
      requiresApproval: json['requires_approval'] as bool? ?? false,
      isWarranty: json['is_warranty'] as bool? ?? false,
      workDescription: json['work_description']?.toString(),
      notes: json['notes']?.toString(),
      source: json['source']?.toString(),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'customer_id': customerId,
      'invoice_number': invoiceNumber,
      'customer_name': customerName,
      'customer_rut': customerRut,
      'date': date
          .toUtc()
          .toIso8601String(), // CRITICAL: Convert to UTC before sending
      'due_date':
          dueDate?.toUtc().toIso8601String(), // CRITICAL: Convert to UTC
      'reference': reference,
      'status': status.name,
      'subtotal': subtotal,
      'iva_amount': ivaAmount,
      'total': total,
      'paid_amount': paidAmount,
      'balance': balance,
      'tax_treatment': taxTreatment.toValue(),
      'net_amount': netAmount,
      'items': items.map((item) => item.toFirestoreMap()).toList(),
      'invoice_type': invoiceType,
      if (bikeId != null) 'bike_id': bikeId,
      if (mechanicId != null) 'mechanic_id': mechanicId,
      if (jobNumber != null) 'job_number': jobNumber,
      if (entryDate != null) 'entry_date': entryDate!.toUtc().toIso8601String(),
      if (deliveryDate != null)
        'delivery_date': deliveryDate!.toUtc().toIso8601String(),
      'requires_approval': requiresApproval,
      'is_warranty': isWarranty,
      if (workDescription != null) 'work_description': workDescription,
      if (notes != null) 'notes': notes,
      if (source != null) 'source': source,
    };
  }

  double get remainingAmount => balance;

  bool get isPaid => status == InvoiceStatus.paid;
}

enum InvoiceStatus {
  draft,
  sent,
  confirmed,
  paid,
  overdue,
  cancelled,
}

extension InvoiceStatusX on InvoiceStatus {
  static InvoiceStatus? fromName(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    return InvoiceStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () {
        final normalized = value.toLowerCase();
        const aliases = <String, InvoiceStatus>{
          'borrador': InvoiceStatus.draft,
          'draft': InvoiceStatus.draft,
          'enviado': InvoiceStatus.sent,
          'sent': InvoiceStatus.sent,
          'confirmado': InvoiceStatus.confirmed,
          'confirmada': InvoiceStatus.confirmed,
          'confirmed': InvoiceStatus.confirmed,
          'pagado': InvoiceStatus.paid,
          'pagada': InvoiceStatus.paid,
          'paid': InvoiceStatus.paid,
          'vencido': InvoiceStatus.overdue,
          'vencida': InvoiceStatus.overdue,
          'overdue': InvoiceStatus.overdue,
          'cancelado': InvoiceStatus.cancelled,
          'cancelada': InvoiceStatus.cancelled,
          'anulado': InvoiceStatus.cancelled,
          'anulada': InvoiceStatus.cancelled,
          'cancelled': InvoiceStatus.cancelled,
          'canceled': InvoiceStatus.cancelled,
        };
        final alias = aliases[normalized];
        if (alias != null) {
          return alias;
        }
        return InvoiceStatus.values.firstWhere(
          (status) => status.name.toLowerCase() == normalized,
          orElse: () => InvoiceStatus.draft,
        );
      },
    );
  }
}

class InvoiceItem {
  final String? id;
  final String? invoiceId;
  final String? productId; // Nullable - null for ad-hoc/custom items
  final String? productName;
  final String? productSku;
  final String? description; // Custom description/notes for line item
  final bool isCatalogProduct; // true = official product, false = ad-hoc item
  final double quantity;
  final double unitPrice;
  final double discount;
  final double lineTotal;
  final double cost;
  final PurchaseTreatment purchaseTreatment;

  // ✅ UNIFIED ARCHITECTURE (Nov 18, 2025): Service/Labor fields
  final bool isService; // true = labor/service, false = product
  final double? hours; // For services: hours worked
  final double? hourlyRate; // For services: rate per hour

  // ✅ Multi-bike sync metadata (preserves bike assignment through round-trip)
  final String? jobBikeId; // Links to mechanic_job_bikes.id
  final String? bikeName; // Display name for bike grouping

  InvoiceItem({
    this.id,
    this.invoiceId,
    this.productId, // Now nullable
    this.productName,
    this.productSku,
    this.description,
    this.isCatalogProduct = true, // Default to catalog product
    this.quantity = 1,
    required this.unitPrice,
    this.discount = 0,
    double? lineTotal,
    this.cost = 0,
    this.purchaseTreatment = PurchaseTreatment.inventory,
    this.isService = false,
    this.hours,
    this.hourlyRate,
    this.jobBikeId,
    this.bikeName,
  }) : lineTotal = lineTotal ?? (quantity * unitPrice - discount);

  InvoiceItem copyWith({
    String? id,
    String? invoiceId,
    String? productId,
    String? productName,
    String? productSku,
    String? description,
    bool? isCatalogProduct,
    double? quantity,
    double? unitPrice,
    double? discount,
    double? lineTotal,
    double? cost,
    PurchaseTreatment? purchaseTreatment,
    bool? isService,
    double? hours,
    double? hourlyRate,
    String? jobBikeId,
    String? bikeName,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSku: productSku ?? this.productSku,
      description: description ?? this.description,
      isCatalogProduct: isCatalogProduct ?? this.isCatalogProduct,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discount: discount ?? this.discount,
      lineTotal: lineTotal ?? this.lineTotal,
      cost: cost ?? this.cost,
      purchaseTreatment: purchaseTreatment ?? this.purchaseTreatment,
      isService: isService ?? this.isService,
      hours: hours ?? this.hours,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      jobBikeId: jobBikeId ?? this.jobBikeId,
      bikeName: bikeName ?? this.bikeName,
    );
  }

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    // Handle both 'price' (from process_online_order) and 'unit_price' (from manual invoices)
    final price = (json['unit_price'] as num?)?.toDouble() ??
        (json['price'] as num?)?.toDouble() ??
        0;
    // Handle both 'line_total' and 'subtotal' (from process_online_order)
    final lineTotal = (json['line_total'] as num?)?.toDouble() ??
        (json['subtotal'] as num?)?.toDouble();

    return InvoiceItem(
      id: json['id']?.toString(),
      invoiceId: json['invoice_id']?.toString(),
      productId: json['product_id']?.toString(), // Nullable now
      productName: json['product_name']?.toString(),
      productSku: json['product_sku']?.toString(),
      description: json['description']?.toString(),
      isCatalogProduct: json['is_catalog_product'] ?? true,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: price,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      lineTotal: lineTotal,
      cost: (json['cost'] as num?)?.toDouble() ?? 0,
      purchaseTreatment: parsePurchaseTreatment(
        json['purchase_treatment'],
      ),
      isService:
          json['is_service'] as bool? ?? (json['item_type'] == 'service'),
      hours: (json['hours'] as num?)?.toDouble(),
      hourlyRate: (json['hourly_rate'] as num?)?.toDouble(),
      jobBikeId: json['job_bike_id']?.toString(),
      bikeName: json['bike_name']?.toString(),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      if (id != null) 'id': id,
      'invoice_id': invoiceId,
      'product_id': productId, // Can be null for ad-hoc items
      'product_name': productName,
      'product_sku': productSku,
      'description': description,
      'is_catalog_product': isCatalogProduct,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount': discount,
      'line_total': lineTotal,
      'cost': cost,
      'purchase_treatment': purchaseTreatment.dbValue,
      'is_service': isService,
      if (hours != null) 'hours': hours,
      if (hourlyRate != null) 'hourly_rate': hourlyRate,
      if (jobBikeId != null) 'job_bike_id': jobBikeId,
      if (bikeName != null) 'bike_name': bikeName,
    };
  }
}

/// Sales payment model matching sales_payments table in core_schema.sql
/// CRITICAL: Uses payment_method_id (uuid) to reference payment_methods table
class Payment {
  final String? id; // uuid
  final String tenantId; // uuid - MULTI-TENANT ISOLATION
  final String invoiceId; // uuid - references sales_invoices(id)
  final String? invoiceReference; // invoice number for display
  final String paymentMethodId; // uuid - references payment_methods(id)
  final double amount;
  final DateTime date;
  final String? reference; // bank reference, check number, etc.
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deletedBy;

  // Payment-level tax handling (multi-payment with split tax)
  final String taxTreatment; // 'no_tax', 'tax_included', 'tax_excluded'
  final double netAmount; // Amount excluding IVA
  final double ivaAmount; // IVA amount (0 if no_tax)

  Payment({
    this.id,
    required this.tenantId,
    required this.invoiceId,
    this.invoiceReference,
    required this.paymentMethodId,
    required this.amount,
    required this.date,
    this.reference,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deletedBy,
    this.taxTreatment = 'no_tax',
    double? netAmount,
    double? ivaAmount,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        netAmount = netAmount ??
            (taxTreatment == 'tax_included'
                ? (amount / 1.19).roundToDouble()
                : amount),
        ivaAmount = ivaAmount ??
            (taxTreatment == 'tax_included'
                ? (amount - (amount / 1.19).roundToDouble())
                : 0);

  Payment copyWith({
    String? id,
    String? tenantId,
    String? invoiceId,
    String? invoiceReference,
    String? paymentMethodId,
    double? amount,
    DateTime? date,
    String? reference,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? deletedBy,
    String? taxTreatment,
    double? netAmount,
    double? ivaAmount,
  }) {
    return Payment(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      invoiceId: invoiceId ?? this.invoiceId,
      invoiceReference: invoiceReference ?? this.invoiceReference,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      reference: reference ?? this.reference,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      taxTreatment: taxTreatment ?? this.taxTreatment,
      netAmount: netAmount ?? this.netAmount,
      ivaAmount: ivaAmount ?? this.ivaAmount,
    );
  }

  factory Payment.fromJson(Map<String, dynamic> json) {
    final amount = (json['amount'] as num?)?.toDouble() ?? 0;
    final taxTreatment = json['tax_treatment']?.toString() ?? 'no_tax';

    return Payment(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      invoiceId: json['invoice_id']?.toString() ?? '',
      invoiceReference: json['invoice_reference'] as String?,
      paymentMethodId: json['payment_method_id']?.toString() ?? '',
      amount: amount,
      date: _parseDate(json['date']),
      reference: json['reference'] as String?,
      notes: json['notes'] as String?,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      deletedAt:
          json['deleted_at'] != null ? _parseDate(json['deleted_at']) : null,
      deletedBy: json['deleted_by']?.toString(),
      taxTreatment: taxTreatment,
      netAmount: (json['net_amount'] as num?)?.toDouble(),
      ivaAmount: (json['iva_amount'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'invoice_id': invoiceId,
      'invoice_reference': invoiceReference,
      'payment_method_id': paymentMethodId,
      'amount': amount,
      'date': date.toUtc().toIso8601String(), // CRITICAL: Convert to UTC
      'reference': reference,
      'notes': notes,
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
      'deleted_by': deletedBy,
      'tax_treatment': taxTreatment,
      'net_amount': netAmount,
      'iva_amount': ivaAmount,
    };
  }

  /// True if this payment includes IVA
  bool get hasIva => taxTreatment == 'tax_included' && ivaAmount > 0;
}
