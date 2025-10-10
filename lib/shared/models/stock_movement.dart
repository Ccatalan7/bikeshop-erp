class StockMovement {
  final String id;
  final String productId;
  final String productSku;
  final String productName;
  final StockMovementType type;
  final int quantity; // Positive for increases, negative for decreases
  final int previousQuantity;
  final int newQuantity;
  final double unitCost;
  final double totalCost;
  final String? sourceModule; // 'Sales', 'Purchases', 'Adjustment', etc.
  final String? sourceReference; // Invoice number, PO number, etc.
  final String? sourceId; // Invoice ID, PO ID, etc.
  final String? warehouseId;
  final String? userId;
  final String? notes;
  final DateTime date;
  final DateTime createdAt;

  const StockMovement({
    required this.id,
    required this.productId,
    required this.productSku,
    required this.productName,
    required this.type,
    required this.quantity,
    required this.previousQuantity,
    required this.newQuantity,
    required this.unitCost,
    required this.totalCost,
    this.sourceModule,
    this.sourceReference,
    this.sourceId,
    this.warehouseId,
    this.userId,
    this.notes,
    required this.date,
    required this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      productSku: json['product_sku'] as String,
      productName: json['product_name'] as String,
      type: StockMovementType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => StockMovementType.adjustment,
      ),
      quantity: json['quantity'] as int,
      previousQuantity: json['previous_quantity'] as int,
      newQuantity: json['new_quantity'] as int,
      unitCost: (json['unit_cost'] as num).toDouble(),
      totalCost: (json['total_cost'] as num).toDouble(),
      sourceModule: json['source_module'] as String?,
      sourceReference: json['source_reference'] as String?,
      sourceId: json['source_id'] as String?,
      warehouseId: json['warehouse_id'] as String?,
      userId: json['user_id'] as String?,
      notes: json['notes'] as String?,
      date: DateTime.parse(json['date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_sku': productSku,
      'product_name': productName,
      'type': type.name,
      'quantity': quantity,
      'previous_quantity': previousQuantity,
      'new_quantity': newQuantity,
      'unit_cost': unitCost,
      'total_cost': totalCost,
      'source_module': sourceModule,
      'source_reference': sourceReference,
      'source_id': sourceId,
      'warehouse_id': warehouseId,
      'user_id': userId,
      'notes': notes,
      'date': date.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  StockMovement copyWith({
    String? id,
    String? productId,
    String? productSku,
    String? productName,
    StockMovementType? type,
    int? quantity,
    int? previousQuantity,
    int? newQuantity,
    double? unitCost,
    double? totalCost,
    String? sourceModule,
    String? sourceReference,
    String? sourceId,
    String? warehouseId,
    String? userId,
    String? notes,
    DateTime? date,
    DateTime? createdAt,
  }) {
    return StockMovement(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productSku: productSku ?? this.productSku,
      productName: productName ?? this.productName,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      previousQuantity: previousQuantity ?? this.previousQuantity,
      newQuantity: newQuantity ?? this.newQuantity,
      unitCost: unitCost ?? this.unitCost,
      totalCost: totalCost ?? this.totalCost,
      sourceModule: sourceModule ?? this.sourceModule,
      sourceReference: sourceReference ?? this.sourceReference,
      sourceId: sourceId ?? this.sourceId,
      warehouseId: warehouseId ?? this.warehouseId,
      userId: userId ?? this.userId,
      notes: notes ?? this.notes,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get isInbound => quantity > 0;
  bool get isOutbound => quantity < 0;
  int get absoluteQuantity => quantity.abs();

  String get formattedQuantity {
    if (isInbound) {
      return '+$quantity';
    } else {
      return quantity.toString();
    }
  }

  String get sourceDescription {
    if (sourceModule != null && sourceReference != null) {
      return '$sourceModule: $sourceReference';
    } else if (sourceModule != null) {
      return sourceModule!;
    } else if (sourceReference != null) {
      return sourceReference!;
    }
    return type.displayName;
  }

  @override
  String toString() {
    return 'StockMovement(id: $id, product: $productSku, type: ${type.name}, qty: $quantity)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StockMovement && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

enum StockMovementType {
  purchase('Compra'),
  sale('Venta'),
  adjustment('Ajuste'),
  transfer('Transferencia'),
  return_('Devolución'),
  damage('Daño'),
  loss('Pérdida'),
  found('Encontrado'),
  initialStock('Stock Inicial'),
  production('Producción'),
  consumption('Consumo');

  const StockMovementType(this.displayName);
  final String displayName;

  bool get isInbound {
    switch (this) {
      case StockMovementType.purchase:
      case StockMovementType.return_:
      case StockMovementType.found:
      case StockMovementType.initialStock:
      case StockMovementType.production:
        return true;
      case StockMovementType.sale:
      case StockMovementType.damage:
      case StockMovementType.loss:
      case StockMovementType.consumption:
        return false;
      case StockMovementType.adjustment:
      case StockMovementType.transfer:
        return false; // Depends on quantity sign
    }
  }
}