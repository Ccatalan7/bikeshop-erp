class StockMovement {
  final String id;
  final String productId;
  final String productName;
  final String? productSku;
  final String? productImageUrl;
  final DateTime transactionDate;
  final String movementType;
  final String source;
  final String? referenceId;
  final String? referenceNumber;
  final int stockBefore;
  final int quantity;
  final int stockAfter;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;

  const StockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    this.productSku,
    this.productImageUrl,
    required this.transactionDate,
    required this.movementType,
    required this.source,
    this.referenceId,
    this.referenceNumber,
    required this.stockBefore,
    required this.quantity,
    required this.stockAfter,
    this.notes,
    this.createdBy,
    required this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      id: json['id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name'] as String? ?? '',
      productSku: json['product_sku'] as String?,
      transactionDate: json['transaction_date'] != null
          ? DateTime.parse(json['transaction_date'] as String)
          : DateTime.now(),
      movementType: json['movement_type'] as String? ?? 'adjustment',
      source: json['source'] as String? ?? 'unknown',
      referenceId: json['reference_id']?.toString(),
      referenceNumber: json['reference_number'] as String?,
      stockBefore: json['stock_before'] as int? ?? 0,
      quantity: json['quantity'] as int? ?? 0,
      stockAfter: json['stock_after'] as int? ?? 0,
      notes: json['notes'] as String?,
      createdBy: json['created_by']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      productImageUrl: json['product_image_url'] as String? ??
          (json['products'] != null
              ? (json['products'] as Map)['image_url'] as String?
              : null),
    );
  }

  StockMovement copyWith({
    String? id,
    String? productId,
    String? productName,
    String? productSku,
    String? productImageUrl,
    DateTime? transactionDate,
    String? movementType,
    String? source,
    String? referenceId,
    String? referenceNumber,
    int? stockBefore,
    int? quantity,
    int? stockAfter,
    String? notes,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return StockMovement(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSku: productSku ?? this.productSku,
      productImageUrl: productImageUrl ?? this.productImageUrl,
      transactionDate: transactionDate ?? this.transactionDate,
      movementType: movementType ?? this.movementType,
      source: source ?? this.source,
      referenceId: referenceId ?? this.referenceId,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      stockBefore: stockBefore ?? this.stockBefore,
      quantity: quantity ?? this.quantity,
      stockAfter: stockAfter ?? this.stockAfter,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'product_sku': productSku,
      'transaction_date': transactionDate.toIso8601String(),
      'movement_type': movementType,
      'source': source,
      'reference_id': referenceId,
      'reference_number': referenceNumber,
      'stock_before': stockBefore,
      'quantity': quantity,
      'stock_after': stockAfter,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isIncrease => quantity > 0;
  bool get isDecrease => quantity < 0;

  String get movementTypeDisplay {
    switch (movementType) {
      case 'purchase':
        return 'Compra';
      case 'sale':
        return 'Venta';
      case 'adjustment':
        return 'Ajuste';
      case 'transfer':
        return 'Transferencia';
      default:
        return movementType;
    }
  }

  String get sourceDisplay {
    switch (source) {
      case 'pos':
        return 'POS';
      case 'manual_sale':
        return 'Venta Manual';
      case 'manual_purchase':
        return 'Compra Manual';
      case 'stock_adjustment':
        return 'Ajuste de Stock';
      case 'ecommerce':
        return 'Tienda Online';
      case 'mechanic_job':
        return 'Taller';
      // Adjustment types (when movement_type = 'adjustment')
      case 'manual':
        return 'Ajuste Manual';
      case 'import':
        return 'Importación';
      case 'correction':
        return 'Corrección';
      case 'initial':
        return 'Stock Inicial';
      case 'damage':
        return 'Daño';
      case 'loss':
        return 'Pérdida';
      case 'found':
        return 'Hallazgo';
      default:
        return source;
    }
  }
}
