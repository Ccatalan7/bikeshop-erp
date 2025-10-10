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
  final String invoiceNumber;
  final String customerId;
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
  final List<InvoiceItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  Invoice({
    this.id,
  required this.customerId,
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
    this.items = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Invoice copyWith({
    String? id,
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
    List<InvoiceItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Invoice(
      id: id ?? this.id,
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
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Invoice.fromJson(Map<String, dynamic> json) {
  final rawItems = (json['items'] as List?) ?? const [];
    return Invoice(
      id: json['id']?.toString(),
  customerId: json['customer_id']?.toString() ?? '',
  invoiceNumber: json['invoice_number']?.toString() ?? '',
      customerName: json['customer_name'] as String?,
      customerRut: json['customer_rut'] as String?,
      date: _parseDate(json['date']),
      dueDate: json['due_date'] != null ? _parseDate(json['due_date']) : null,
      reference: json['reference'] as String?,
      status: InvoiceStatusX.fromName(json['status']) ?? InvoiceStatus.draft,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      ivaAmount: (json['iva_amount'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      balance: (json['balance'] as num?)?.toDouble() ??
          ((json['total'] as num?)?.toDouble() ?? 0) - ((json['paid_amount'] as num?)?.toDouble() ?? 0),
  items: rawItems.map((item) => InvoiceItem.fromJson(_ensureMap(item))).toList(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      if (id != null) 'id': id,
      'customer_id': customerId,
      'invoice_number': invoiceNumber,
      'customer_name': customerName,
      'customer_rut': customerRut,
      'date': date,
      'due_date': dueDate,
      'reference': reference,
      'status': status.name,
      'subtotal': subtotal,
      'iva_amount': ivaAmount,
      'total': total,
      'paid_amount': paidAmount,
      'balance': balance,
      'items': items.map((item) => item.toFirestoreMap()).toList(),
    };
  }

  double get remainingAmount => balance;

  bool get isPaid => status == InvoiceStatus.paid;
}

enum InvoiceStatus {
  draft,
  sent,
  paid,
  overdue,
  cancelled,
}

extension InvoiceStatusX on InvoiceStatus {
  static InvoiceStatus? fromName(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString();
    return InvoiceStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () {
        final normalized = value.toLowerCase();
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
  final String productId;
  final String? productName;
  final String? productSku;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double lineTotal;
  final double cost;

  InvoiceItem({
    this.id,
    this.invoiceId,
    required this.productId,
    this.productName,
    this.productSku,
    this.quantity = 1,
    required this.unitPrice,
    this.discount = 0,
    double? lineTotal,
    this.cost = 0,
  }) : lineTotal = lineTotal ?? (quantity * unitPrice - discount);

  InvoiceItem copyWith({
    String? id,
    String? invoiceId,
    String? productId,
    String? productName,
    String? productSku,
    double? quantity,
    double? unitPrice,
    double? discount,
    double? lineTotal,
    double? cost,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSku: productSku ?? this.productSku,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discount: discount ?? this.discount,
      lineTotal: lineTotal ?? this.lineTotal,
      cost: cost ?? this.cost,
    );
  }

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    return InvoiceItem(
      id: json['id']?.toString(),
      invoiceId: json['invoice_id']?.toString(),
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name'] as String?,
      productSku: json['product_sku'] as String?,
  quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
  unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
  discount: (json['discount'] as num?)?.toDouble() ?? 0,
  lineTotal: (json['line_total'] as num?)?.toDouble(),
      cost: (json['cost'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      if (id != null) 'id': id,
      'invoice_id': invoiceId,
      'product_id': productId,
      'product_name': productName,
      'product_sku': productSku,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount': discount,
      'line_total': lineTotal,
      'cost': cost,
    };
  }
}

class Payment {
  final String? id;
  final String invoiceId;
  final String? invoiceReference;
  final PaymentMethod method;
  final double amount;
  final DateTime date;
  final String? reference;
  final String? notes;
  final DateTime createdAt;

  Payment({
    this.id,
    required this.invoiceId,
    this.invoiceReference,
    required this.method,
    required this.amount,
    required this.date,
    this.reference,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Payment copyWith({
    String? id,
    String? invoiceId,
    String? invoiceReference,
    PaymentMethod? method,
    double? amount,
    DateTime? date,
    String? reference,
    String? notes,
    DateTime? createdAt,
  }) {
    return Payment(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      invoiceReference: invoiceReference ?? this.invoiceReference,
      method: method ?? this.method,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      reference: reference ?? this.reference,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id']?.toString(),
      invoiceId: json['invoice_id']?.toString() ?? '',
      invoiceReference: json['invoice_reference'] as String?,
      method: PaymentMethodX.fromName(json['method']) ?? PaymentMethod.cash,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      date: _parseDate(json['date']),
      reference: json['reference'] as String?,
      notes: json['notes'] as String?,
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      if (id != null) 'id': id,
      'invoice_id': invoiceId,
      'invoice_reference': invoiceReference,
      'method': method.name,
      'amount': amount,
      'date': date,
      'reference': reference,
      'notes': notes,
    };
  }
}

enum PaymentMethod {
  cash,
  card,
  transfer,
  check,
  other,
}

extension PaymentMethodX on PaymentMethod {
  static PaymentMethod? fromName(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString();
    return PaymentMethod.values.firstWhere(
      (method) => method.name == value,
      orElse: () {
        final normalized = value.toLowerCase();
        return PaymentMethod.values.firstWhere(
          (method) => method.name.toLowerCase() == normalized,
          orElse: () => PaymentMethod.cash,
        );
      },
    );
  }

  String get displayName {
    switch (this) {
      case PaymentMethod.cash:
        return 'Efectivo';
      case PaymentMethod.card:
        return 'Tarjeta';
      case PaymentMethod.transfer:
        return 'Transferencia';
      case PaymentMethod.check:
        return 'Cheque';
      case PaymentMethod.other:
        return 'Otro';
    }
  }
}