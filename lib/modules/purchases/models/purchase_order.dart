class PurchaseOrder {
  final int? id;
  final String orderNumber;
  final int supplierId;
  final DateTime date;
  final DateTime? expectedDate;
  final String status; // pending, received, cancelled
  final double subtotal;
  final double tax;
  final double total;
  final String? notes;
  final List<PurchaseOrderItem> items;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Related data
  final String? supplierName;

  const PurchaseOrder({
    this.id,
    required this.orderNumber,
    required this.supplierId,
    required this.date,
    this.expectedDate,
    required this.status,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.notes,
    this.items = const [],
    this.createdAt,
    this.updatedAt,
    this.supplierName,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    return PurchaseOrder(
      id: json['id'] as int?,
      orderNumber: json['order_number'] as String,
      supplierId: json['supplier_id'] as int,
      date: DateTime.parse(json['date'] as String),
      expectedDate: json['expected_date'] != null
          ? DateTime.parse(json['expected_date'] as String)
          : null,
      status: json['status'] as String,
      subtotal: (json['subtotal'] as num).toDouble(),
      tax: (json['tax'] as num).toDouble(),
      total: (json['total'] as num).toDouble(),
      notes: json['notes'] as String?,
      items: json['purchase_order_items'] != null
          ? (json['purchase_order_items'] as List)
              .map((item) => PurchaseOrderItem.fromJson(item))
              .toList()
          : [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      supplierName: json['suppliers']?['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_number': orderNumber,
      'supplier_id': supplierId,
      'date': date.toIso8601String(),
      'expected_date': expectedDate?.toIso8601String(),
      'status': status,
      'subtotal': subtotal,
      'tax': tax,
      'total': total,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  PurchaseOrder copyWith({
    int? id,
    String? orderNumber,
    int? supplierId,
    DateTime? date,
    DateTime? expectedDate,
    String? status,
    double? subtotal,
    double? tax,
    double? total,
    String? notes,
    List<PurchaseOrderItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? supplierName,
  }) {
    return PurchaseOrder(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      supplierId: supplierId ?? this.supplierId,
      date: date ?? this.date,
      expectedDate: expectedDate ?? this.expectedDate,
      status: status ?? this.status,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      total: total ?? this.total,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      supplierName: supplierName ?? this.supplierName,
    );
  }
}

class PurchaseOrderItem {
  final int? id;
  final int? purchaseOrderId;
  final int productId;
  final int quantity;
  final double unitCost;
  final double total;

  // Related data
  final String? productName;
  final String? productSku;

  const PurchaseOrderItem({
    this.id,
    this.purchaseOrderId,
    required this.productId,
    required this.quantity,
    required this.unitCost,
    required this.total,
    this.productName,
    this.productSku,
  });

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderItem(
      id: json['id'] as int?,
      purchaseOrderId: json['purchase_order_id'] as int?,
      productId: json['product_id'] as int,
      quantity: json['quantity'] as int,
      unitCost: (json['unit_cost'] as num).toDouble(),
      total: (json['total'] as num).toDouble(),
      productName: json['products']?['name'] as String?,
      productSku: json['products']?['sku'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'purchase_order_id': purchaseOrderId,
      'product_id': productId,
      'quantity': quantity,
      'unit_cost': unitCost,
      'total': total,
    };
  }

  PurchaseOrderItem copyWith({
    int? id,
    int? purchaseOrderId,
    int? productId,
    int? quantity,
    double? unitCost,
    double? total,
    String? productName,
    String? productSku,
  }) {
    return PurchaseOrderItem(
      id: id ?? this.id,
      purchaseOrderId: purchaseOrderId ?? this.purchaseOrderId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
      total: total ?? this.total,
      productName: productName ?? this.productName,
      productSku: productSku ?? this.productSku,
    );
  }
}
