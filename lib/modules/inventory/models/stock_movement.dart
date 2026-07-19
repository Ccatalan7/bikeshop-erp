import '../../../shared/models/stock_adjustment_origin.dart'
    as stock_adjustment_origin;

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
  final int rawQuantity;
  final int actualStockDelta;
  final int reconciledQuantity;
  final String balanceProvenance;
  final String integrityStatus;
  final bool isSummaryExcluded;
  final String? linkedAdjustmentId;
  final String? canonicalMovementId;
  final String? operationId;
  final String? sourceDocumentType;
  final String? sourceDocumentId;
  final String? triggerOperationId;
  final String? triggerAction;
  final String? triggerSourceChannel;
  final String? triggerActorId;
  final String? triggerReason;
  final int evidenceStockBefore;
  final int evidenceStockAfter;
  final String evidenceBalanceProvenance;
  final String evidenceIntegrityStatus;
  final String? adjustmentOrigin;
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
    required this.rawQuantity,
    required this.actualStockDelta,
    required this.reconciledQuantity,
    required this.balanceProvenance,
    required this.integrityStatus,
    required this.isSummaryExcluded,
    this.linkedAdjustmentId,
    this.canonicalMovementId,
    this.operationId,
    this.sourceDocumentType,
    this.sourceDocumentId,
    this.triggerOperationId,
    this.triggerAction,
    this.triggerSourceChannel,
    this.triggerActorId,
    this.triggerReason,
    required this.evidenceStockBefore,
    required this.evidenceStockAfter,
    required this.evidenceBalanceProvenance,
    required this.evidenceIntegrityStatus,
    this.adjustmentOrigin,
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
      rawQuantity: (json['raw_quantity'] as num?)?.toInt() ??
          (json['quantity'] as num?)?.toInt() ??
          0,
      actualStockDelta: (json['actual_stock_delta'] as num?)?.toInt() ??
          (json['quantity'] as num?)?.toInt() ??
          0,
      reconciledQuantity: (json['reconciled_quantity'] as num?)?.toInt() ??
          (json['quantity'] as num?)?.toInt() ??
          0,
      balanceProvenance:
          json['balance_provenance'] as String? ?? 'reconstructed',
      integrityStatus:
          json['integrity_status'] as String? ?? 'legacy_reconstructed',
      isSummaryExcluded: json['is_summary_excluded'] as bool? ?? false,
      linkedAdjustmentId: json['linked_adjustment_id']?.toString(),
      canonicalMovementId: json['canonical_movement_id']?.toString(),
      operationId: json['operation_id']?.toString(),
      sourceDocumentType: json['source_document_type'] as String?,
      sourceDocumentId: json['source_document_id']?.toString(),
      triggerOperationId: json['trigger_operation_id']?.toString(),
      triggerAction: json['trigger_action']?.toString(),
      triggerSourceChannel: json['trigger_source_channel']?.toString(),
      triggerActorId: json['trigger_actor_id']?.toString(),
      triggerReason: json['trigger_reason']?.toString(),
      evidenceStockBefore: (json['evidence_stock_before'] as num?)?.toInt() ??
          (json['stock_before'] as num?)?.toInt() ??
          0,
      evidenceStockAfter: (json['evidence_stock_after'] as num?)?.toInt() ??
          (json['stock_after'] as num?)?.toInt() ??
          0,
      evidenceBalanceProvenance:
          json['evidence_balance_provenance'] as String? ??
              json['balance_provenance'] as String? ??
              'reconstructed',
      evidenceIntegrityStatus: json['evidence_integrity_status'] as String? ??
          json['integrity_status'] as String? ??
          'legacy_reconstructed',
      adjustmentOrigin: json['adjustment_origin'] as String?,
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
    int? rawQuantity,
    int? actualStockDelta,
    int? reconciledQuantity,
    String? balanceProvenance,
    String? integrityStatus,
    bool? isSummaryExcluded,
    String? linkedAdjustmentId,
    String? canonicalMovementId,
    String? operationId,
    String? sourceDocumentType,
    String? sourceDocumentId,
    String? triggerOperationId,
    String? triggerAction,
    String? triggerSourceChannel,
    String? triggerActorId,
    String? triggerReason,
    int? evidenceStockBefore,
    int? evidenceStockAfter,
    String? evidenceBalanceProvenance,
    String? evidenceIntegrityStatus,
    String? adjustmentOrigin,
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
      rawQuantity: rawQuantity ?? this.rawQuantity,
      actualStockDelta: actualStockDelta ?? this.actualStockDelta,
      reconciledQuantity: reconciledQuantity ?? this.reconciledQuantity,
      balanceProvenance: balanceProvenance ?? this.balanceProvenance,
      integrityStatus: integrityStatus ?? this.integrityStatus,
      isSummaryExcluded: isSummaryExcluded ?? this.isSummaryExcluded,
      linkedAdjustmentId: linkedAdjustmentId ?? this.linkedAdjustmentId,
      canonicalMovementId: canonicalMovementId ?? this.canonicalMovementId,
      operationId: operationId ?? this.operationId,
      sourceDocumentType: sourceDocumentType ?? this.sourceDocumentType,
      sourceDocumentId: sourceDocumentId ?? this.sourceDocumentId,
      triggerOperationId: triggerOperationId ?? this.triggerOperationId,
      triggerAction: triggerAction ?? this.triggerAction,
      triggerSourceChannel: triggerSourceChannel ?? this.triggerSourceChannel,
      triggerActorId: triggerActorId ?? this.triggerActorId,
      triggerReason: triggerReason ?? this.triggerReason,
      evidenceStockBefore: evidenceStockBefore ?? this.evidenceStockBefore,
      evidenceStockAfter: evidenceStockAfter ?? this.evidenceStockAfter,
      evidenceBalanceProvenance:
          evidenceBalanceProvenance ?? this.evidenceBalanceProvenance,
      evidenceIntegrityStatus:
          evidenceIntegrityStatus ?? this.evidenceIntegrityStatus,
      adjustmentOrigin: adjustmentOrigin ?? this.adjustmentOrigin,
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
      'raw_quantity': rawQuantity,
      'actual_stock_delta': actualStockDelta,
      'reconciled_quantity': reconciledQuantity,
      'balance_provenance': balanceProvenance,
      'integrity_status': integrityStatus,
      'is_summary_excluded': isSummaryExcluded,
      'linked_adjustment_id': linkedAdjustmentId,
      'canonical_movement_id': canonicalMovementId,
      'operation_id': operationId,
      'source_document_type': sourceDocumentType,
      'source_document_id': sourceDocumentId,
      'evidence_stock_before': evidenceStockBefore,
      'evidence_stock_after': evidenceStockAfter,
      'evidence_balance_provenance': evidenceBalanceProvenance,
      'evidence_integrity_status': evidenceIntegrityStatus,
      'adjustment_origin': adjustmentOrigin,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isIncrease => displayQuantity > 0;
  bool get isDecrease => displayQuantity < 0;
  int get displayQuantity => reconciledQuantity;
  int get summaryQuantity => reconciledQuantity;
  bool get hasIntegrityWarning =>
      integrityStatus == 'arithmetic_mismatch' ||
      integrityStatus == 'legacy_purchase_reversal_collision' ||
      integrityStatus == 'legacy_duplicate_footprint' ||
      integrityStatus == 'legacy_ambiguous_adjustment_match' ||
      integrityStatus == 'ledger_source_balance_mismatch';
  bool get isLegacyDuplicateFootprint =>
      integrityStatus == 'legacy_duplicate_footprint';
  bool get hasRawActualDifference => rawQuantity != actualStockDelta;
  bool get hasEvidenceBalanceDifference =>
      evidenceStockBefore != stockBefore || evidenceStockAfter != stockAfter;

  String get integrityLabel {
    switch (integrityStatus) {
      case 'verified':
      case 'verified_adjustment':
        return 'Verificado';
      case 'legacy_purchase_reversal_collision':
        return 'Colisión histórica identificada';
      case 'legacy_duplicate_footprint':
        return 'Huella duplicada histórica';
      case 'legacy_ambiguous_adjustment_match':
        return 'Vínculo histórico ambiguo';
      case 'arithmetic_mismatch':
        return 'Error aritmético';
      case 'ledger_source_balance_mismatch':
        return 'Saldo fuente no encadenado';
      case 'legacy_reconstructed':
        return 'Historial encadenado';
      default:
        return 'Historial disponible';
    }
  }

  String get integrityExplanation {
    switch (integrityStatus) {
      case 'verified':
        return 'El movimiento conserva saldo inicial, cambio y saldo final grabados por la operación.';
      case 'verified_adjustment':
        return 'Los saldos provienen directamente del ajuste de inventario asociado.';
      case 'legacy_purchase_reversal_collision':
        return 'La reversión antigua emitió una cantidad técnica distinta del cambio real. Se muestra el cambio probado por el ajuste enlazado y se conserva la cantidad original como evidencia.';
      case 'legacy_duplicate_footprint':
        return 'Este ajuste fue emitido automáticamente por la misma reversión de compra. Se conserva como evidencia, pero se excluye de los totales para no contar dos veces la misma salida.';
      case 'legacy_ambiguous_adjustment_match':
        return 'Más de un ajuste histórico coincide con esta huella técnica. El sistema conserva un solo movimiento, no inventa un vínculo y marca el caso para revisión.';
      case 'arithmetic_mismatch':
        return 'Los saldos guardados no cumplen saldo inicial + cambio = saldo final.';
      case 'ledger_source_balance_mismatch':
        return 'El libro principal fue encadenado desde el stock actual. Los saldos históricos de la fuente no encajan en esa secuencia y se conservan abajo como evidencia para revisión.';
      case 'legacy_reconstructed':
        return 'Movimiento histórico válido para el libro continuo. La versión antigua no guardaba saldos inicial y final propios, por lo que fueron encadenados desde el stock actual.';
      default:
        return 'El movimiento forma parte del historial continuo de stock.';
    }
  }

  String? get adjustmentOriginDisplay =>
      stock_adjustment_origin.stockAdjustmentOriginDisplay(adjustmentOrigin);
  bool get hasAdjustmentOrigin => adjustmentOriginDisplay != null;

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
      case 'quick_sale':
        return 'Venta Rápida';
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
        return triggerAction == 'void'
            ? 'Descarte de factura'
            : 'Reversión de venta';
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
