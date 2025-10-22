class Invoice {
  final String id;
  final String invoiceNumber;
  final String customerId;
  final String customerName;
  final String? customerRut;
  final DateTime date;
  final DateTime dueDate;
  final InvoiceType type;
  final InvoiceStatus status;
  final List<InvoiceItem> items;
  final double subtotal; // Before IVA
  final double ivaAmount; // 19% IVA
  final double discount;
  final double total;
  final String? notes;
  final String? terms;
  final PaymentMethod? paymentMethod;
  final DateTime? paidDate;
  final String? userId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.customerId,
    required this.customerName,
    this.customerRut,
    required this.date,
    required this.dueDate,
    this.type = InvoiceType.sale,
    this.status = InvoiceStatus.draft,
    required this.items,
    required this.subtotal,
    required this.ivaAmount,
    this.discount = 0.0,
    required this.total,
    this.notes,
    this.terms,
    this.paymentMethod,
    this.paidDate,
    this.userId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['id'] as String,
      invoiceNumber: json['invoice_number'] as String,
      customerId: json['customer_id'] as String,
      customerName: json['customer_name'] as String,
      customerRut: json['customer_rut'] as String?,
      date: DateTime.parse(json['date'] as String),
      dueDate: DateTime.parse(json['due_date'] as String),
      type: InvoiceType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => InvoiceType.sale,
      ),
      status: InvoiceStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => InvoiceStatus.draft,
      ),
      items: (json['items'] as List?)
              ?.map((item) => InvoiceItem.fromJson(item))
              .toList() ??
          [],
      subtotal: (json['subtotal'] as num).toDouble(),
      ivaAmount: (json['iva_amount'] as num).toDouble(),
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num).toDouble(),
      notes: json['notes'] as String?,
      terms: json['terms'] as String?,
      paymentMethod: json['payment_method'] != null
          ? PaymentMethod.values.firstWhere(
              (m) => m.name == json['payment_method'],
              orElse: () => PaymentMethod.cash,
            )
          : null,
      paidDate: json['paid_date'] != null
          ? DateTime.parse(json['paid_date'] as String)
          : null,
      userId: json['user_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'invoice_number': invoiceNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_rut': customerRut,
      'date': date.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'type': type.name,
      'status': status.name,
      'items': items.map((item) => item.toJson()).toList(),
      'subtotal': subtotal,
      'iva_amount': ivaAmount,
      'discount': discount,
      'total': total,
      'notes': notes,
      'terms': terms,
      'payment_method': paymentMethod?.name,
      'paid_date': paidDate?.toIso8601String(),
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Invoice copyWith({
    String? id,
    String? invoiceNumber,
    String? customerId,
    String? customerName,
    String? customerRut,
    DateTime? date,
    DateTime? dueDate,
    InvoiceType? type,
    InvoiceStatus? status,
    List<InvoiceItem>? items,
    double? subtotal,
    double? ivaAmount,
    double? discount,
    double? total,
    String? notes,
    String? terms,
    PaymentMethod? paymentMethod,
    DateTime? paidDate,
    String? userId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Invoice(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerRut: customerRut ?? this.customerRut,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      type: type ?? this.type,
      status: status ?? this.status,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      ivaAmount: ivaAmount ?? this.ivaAmount,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      notes: notes ?? this.notes,
      terms: terms ?? this.terms,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paidDate: paidDate ?? this.paidDate,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isPaid => status == InvoiceStatus.paid;
  bool get isOverdue =>
      status == InvoiceStatus.sent && DateTime.now().isAfter(dueDate);
  int get daysOverdue =>
      isOverdue ? DateTime.now().difference(dueDate).inDays : 0;

  double get totalQuantity =>
      items.fold(0.0, (sum, item) => sum + item.quantity);

  @override
  String toString() {
    return 'Invoice(id: $id, number: $invoiceNumber, customer: $customerName, total: \$${total.toStringAsFixed(2)})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Invoice && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

class InvoiceItem {
  final String id;
  final String invoiceId;
  final String productId;
  final String productSku;
  final String productName;
  final double quantity;
  final double unitPrice; // Price without IVA
  final double discount;
  final double total; // Total without IVA

  const InvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.productId,
    required this.productSku,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0.0,
    required this.total,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    return InvoiceItem(
      id: json['id'] as String,
      invoiceId: json['invoice_id'] as String,
      productId: json['product_id'] as String,
      productSku: json['product_sku'] as String,
      productName: json['product_name'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unitPrice: (json['unit_price'] as num).toDouble(),
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_id': productId,
      'product_sku': productSku,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount': discount,
      'total': total,
    };
  }

  InvoiceItem copyWith({
    String? id,
    String? invoiceId,
    String? productId,
    String? productSku,
    String? productName,
    double? quantity,
    double? unitPrice,
    double? discount,
    double? total,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      productSku: productSku ?? this.productSku,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discount: discount ?? this.discount,
      total: total ?? this.total,
    );
  }

  double get subtotal => (quantity * unitPrice) - discount;
  double get unitPriceWithIva => unitPrice * 1.19;
  double get totalWithIva => subtotal * 1.19;

  @override
  String toString() {
    return 'InvoiceItem(product: $productSku, qty: $quantity, price: \$${unitPrice.toStringAsFixed(2)})';
  }
}

enum InvoiceType {
  sale('Factura de Venta'),
  service('Factura de Servicio'),
  proforma('Proforma'),
  quote('Cotización');

  const InvoiceType(this.displayName);
  final String displayName;
}

enum InvoiceStatus {
  draft('Borrador'),
  sent('Enviada'),
  confirmed('Confirmada'),
  paid('Pagada'),
  overdue('Vencida'),
  cancelled('Anulada');

  const InvoiceStatus(this.displayName);
  final String displayName;
}

enum PaymentMethod {
  cash('Efectivo'),
  card('Tarjeta'),
  transfer('Transferencia'),
  check('Cheque'),
  credit('Crédito');

  const PaymentMethod(this.displayName);
  final String displayName;
}
