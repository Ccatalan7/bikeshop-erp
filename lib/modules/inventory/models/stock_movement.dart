enum StockMovementCategory {
  purchase,
  sale,
  transfer,
  adjustment,
}

extension StockMovementCategoryX on StockMovementCategory {
  String get key {
    switch (this) {
      case StockMovementCategory.purchase:
        return 'purchase';
      case StockMovementCategory.sale:
        return 'sale';
      case StockMovementCategory.transfer:
        return 'transfer';
      case StockMovementCategory.adjustment:
        return 'adjustment';
    }
  }

  String get displayName {
    switch (this) {
      case StockMovementCategory.purchase:
        return 'Compra';
      case StockMovementCategory.sale:
        return 'Venta';
      case StockMovementCategory.transfer:
        return 'Transferencia';
      case StockMovementCategory.adjustment:
        return 'Ajuste';
    }
  }
}

class StockMovement {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
  static final RegExp _hashReferencePattern = RegExp(r'#([A-Za-z0-9-]+)');

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
      stockBefore: (json['stock_before'] as num?)?.toInt() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      stockAfter: (json['stock_after'] as num?)?.toInt() ?? 0,
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

  StockMovementCategory get category {
    switch (movementType) {
      case 'purchase':
      case 'purchase_invoice':
      case 'purchase_invoice_reversal':
      case 'manual_purchase':
        return StockMovementCategory.purchase;
      case 'sale':
      case 'venta':
      case 'sales_invoice':
      case 'sales_invoice_component':
      case 'sales_invoice_reversal':
      case 'manual_sale':
        return StockMovementCategory.sale;
      case 'transfer':
      case 'transfer_in':
      case 'transfer_out':
        return StockMovementCategory.transfer;
      case 'adjustment':
      case 'manual':
      case 'import':
      case 'correction':
      case 'initial':
      case 'damage':
      case 'loss':
      case 'found':
      case 'count_gain':
      case 'count_loss':
      case 'theft':
      case 'internal_use':
      case 'inventory_adjust':
      case 'inventory_adjustment':
        return StockMovementCategory.adjustment;
      default:
        if (source == 'mechanic_job') return StockMovementCategory.sale;
        return StockMovementCategory.adjustment;
    }
  }

  String get movementCategory => category.key;

  bool matchesCategoryKey(String? categoryKey) {
    return categoryKey == null || categoryKey == 'all'
        ? true
        : movementCategory == categoryKey;
  }

  bool get hasNavigableReference {
    return referenceId != null &&
        referenceId!.isNotEmpty &&
        (category == StockMovementCategory.sale ||
            category == StockMovementCategory.purchase ||
            category == StockMovementCategory.adjustment);
  }

  String get referenceDisplay {
    final trimmed = referenceNumber?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _legacyReferenceFallback;
    }

    if (trimmed == 'Manual adjustment via product form') {
      return 'Ajuste manual desde producto';
    }

    if (trimmed.startsWith('product_conversion:')) {
      final note = notes?.trim();
      if (note != null && note.isNotEmpty) {
        return note;
      }
      return 'Conversión interna de inventario';
    }

    if (_isFriendlyReference(trimmed)) {
      if (trimmed == 'Initial stock on product creation') {
        return 'Stock inicial';
      }
      return trimmed;
    }

    return _legacyReferenceFallback;
  }

  bool _isFriendlyReference(String value) {
    return !_uuidPattern.hasMatch(value);
  }

  String? get _embeddedReasonReference {
    final note = notes?.trim();
    if (note == null || note.isEmpty) return null;
    final match = _hashReferencePattern.firstMatch(note);
    return match?.group(1)?.trim();
  }

  String get _legacyReferenceFallback {
    final embeddedReference = _embeddedReasonReference;
    if (embeddedReference != null) {
      switch (source) {
        case 'correction':
          return 'Compra $embeddedReference';
        case 'sale':
        case 'sales_invoice':
          return 'Venta $embeddedReference';
        default:
          return embeddedReference;
      }
    }

    if (source == 'initial' || movementType == 'initial') {
      return 'Stock inicial';
    }

    if (source == 'correction' || movementType == 'correction') {
      final note = notes?.trim();
      if (note != null && note.isNotEmpty) {
        if (note == 'Manual adjustment via product form') {
          return 'Ajuste manual desde producto';
        }
        return note;
      }
      return 'Corrección histórica';
    }

    if (source == 'manual' || movementType == 'manual') {
      if (notes?.trim() == 'Manual adjustment via product form') {
        return 'Ajuste manual desde producto';
      }
      return 'Ajuste manual';
    }

    return 'Sin referencia';
  }

  String get movementTypeDisplay {
    return category.displayName;
  }

  String get sourceDisplay {
    switch (source) {
      case 'pos':
        return 'POS';
      case 'sale':
        return 'Venta';
      case 'manual_sale':
        return 'Venta Manual';
      case 'manual_purchase':
        return 'Compra Manual';
      case 'purchase_invoice':
        return 'Factura de compra';
      case 'purchase_invoice_reversal':
        return 'Reversión de compra';
      case 'sales_invoice_reversal':
        return 'Reversión de venta';
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
      case 'count_gain':
        return 'Reconteo positivo';
      case 'count_loss':
        return 'Reconteo negativo';
      case 'theft':
        return 'Robo / extravío';
      case 'internal_use':
        return 'Uso interno / taller';
      default:
        return source;
    }
  }
}
