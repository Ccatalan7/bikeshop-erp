class StockMovement {
  final String id;
  final String productId;
  final String productSku;
  final String productName;
  final String type; // 'IN' or 'OUT'
  final String?
      movementType; // 'sales_invoice', 'purchase_invoice', 'adjustment', etc.
  final double quantity; // Positive for IN, negative for OUT
  final String? reference;
  final String? notes;
  final String? warehouseId;
  final DateTime date;
  final DateTime createdAt;

  const StockMovement({
    required this.id,
    required this.productId,
    required this.productSku,
    required this.productName,
    required this.type,
    this.movementType,
    required this.quantity,
    this.reference,
    this.notes,
    this.warehouseId,
    required this.date,
    required this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      id: json['id'] as String,
      productId: json['product_id'] as String? ?? '',
      productSku: json['product_sku'] as String? ?? 'N/A',
      productName: json['product_name'] as String? ?? 'Producto desconocido',
      type: json['type'] as String? ?? 'OUT',
      movementType: json['movement_type'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      reference: json['reference'] as String?,
      notes: json['notes'] as String?,
      warehouseId: json['warehouse_id'] as String?,
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'type': type,
      'movement_type': movementType,
      'quantity': quantity,
      'reference': reference,
      'notes': notes,
      'warehouse_id': warehouseId,
      'date': date.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  StockMovement copyWith({
    String? id,
    String? productId,
    String? productSku,
    String? productName,
    String? type,
    String? movementType,
    double? quantity,
    String? reference,
    String? notes,
    String? warehouseId,
    DateTime? date,
    DateTime? createdAt,
  }) {
    return StockMovement(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productSku: productSku ?? this.productSku,
      productName: productName ?? this.productName,
      type: type ?? this.type,
      movementType: movementType ?? this.movementType,
      quantity: quantity ?? this.quantity,
      reference: reference ?? this.reference,
      notes: notes ?? this.notes,
      warehouseId: warehouseId ?? this.warehouseId,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get isInbound => type == 'IN' || quantity > 0;
  bool get isOutbound => type == 'OUT' || quantity < 0;
  double get absoluteQuantity => quantity.abs();

  String get formattedQuantity {
    if (isInbound) {
      return '+${absoluteQuantity.toStringAsFixed(0)}';
    } else {
      return '-${absoluteQuantity.toStringAsFixed(0)}';
    }
  }

  String get movementTypeDisplay {
    switch (movementType) {
      case 'sales_invoice':
        return 'Venta';
      case 'purchase_invoice':
        return 'Compra';
      case 'adjustment':
        return 'Ajuste';
      case 'transfer':
        return 'Transferencia';
      case 'return':
        return 'Devolución';
      default:
        return movementType ?? type;
    }
  }

  @override
  String toString() {
    return 'StockMovement(id: $id, product: $productSku, type: $type, qty: $quantity)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StockMovement && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
