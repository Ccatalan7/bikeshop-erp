import '../../../shared/models/stock_adjustment_origin.dart'
    as stock_adjustment_origin;

class StockAdjustmentDetail {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
  static final RegExp _hashReferencePattern = RegExp(r'#([A-Za-z0-9-]+)');

  final String id;
  final String? operationId;
  final String productId;
  final String productName;
  final String? productSku;
  final String adjustmentType;
  final String referenceNumber;
  final int quantity;
  final int stockBefore;
  final int stockAfter;
  final String reason;
  final String? adjustmentOrigin;
  final DateTime adjustmentDate;
  final DateTime createdAt;
  final String? createdBy;
  final String? createdByEmail;
  final double unitCost;
  final double inventoryValue;
  final String? journalEntryId;
  final String? journalEntryNumber;
  final DateTime? journalEntryDate;
  final String? journalEntryDescription;
  final String? counterpartAccountCode;
  final String? counterpartAccountName;
  final double counterpartDebit;
  final double counterpartCredit;

  const StockAdjustmentDetail({
    required this.id,
    this.operationId,
    required this.productId,
    required this.productName,
    this.productSku,
    required this.adjustmentType,
    required this.referenceNumber,
    required this.quantity,
    required this.stockBefore,
    required this.stockAfter,
    required this.reason,
    this.adjustmentOrigin,
    required this.adjustmentDate,
    required this.createdAt,
    this.createdBy,
    this.createdByEmail,
    required this.unitCost,
    required this.inventoryValue,
    this.journalEntryId,
    this.journalEntryNumber,
    this.journalEntryDate,
    this.journalEntryDescription,
    this.counterpartAccountCode,
    this.counterpartAccountName,
    required this.counterpartDebit,
    required this.counterpartCredit,
  });

  factory StockAdjustmentDetail.fromJson(Map<String, dynamic> json) {
    return StockAdjustmentDetail(
      id: json['id']?.toString() ?? '',
      operationId: json['operation_id']?.toString(),
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name'] as String? ?? '',
      productSku: json['product_sku'] as String?,
      adjustmentType: json['adjustment_type'] as String? ?? 'manual',
      referenceNumber: json['reference_number'] as String? ?? '-',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      stockBefore: (json['stock_before'] as num?)?.toInt() ?? 0,
      stockAfter: (json['stock_after'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String? ?? '',
      adjustmentOrigin: json['adjustment_origin'] as String?,
      adjustmentDate: json['adjustment_date'] != null
          ? DateTime.parse(json['adjustment_date'] as String)
          : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      createdBy: json['created_by']?.toString(),
      createdByEmail: json['created_by_email'] as String?,
      unitCost: (json['unit_cost'] as num?)?.toDouble() ?? 0,
      inventoryValue: (json['inventory_value'] as num?)?.toDouble() ?? 0,
      journalEntryId: json['journal_entry_id']?.toString(),
      journalEntryNumber: json['journal_entry_number'] as String?,
      journalEntryDate: json['journal_entry_date'] != null
          ? DateTime.parse(json['journal_entry_date'] as String)
          : null,
      journalEntryDescription: json['journal_entry_description'] as String?,
      counterpartAccountCode: json['counterpart_account_code'] as String?,
      counterpartAccountName: json['counterpart_account_name'] as String?,
      counterpartDebit: (json['counterpart_debit'] as num?)?.toDouble() ?? 0,
      counterpartCredit: (json['counterpart_credit'] as num?)?.toDouble() ?? 0,
    );
  }

  bool get isIncrease => quantity > 0;
  bool get isDecrease => quantity < 0;
  String? get adjustmentOriginDisplay =>
      stock_adjustment_origin.stockAdjustmentOriginDisplay(adjustmentOrigin);
  bool get hasAdjustmentOrigin => adjustmentOriginDisplay != null;

  String get createdByDisplay {
    final email = createdByEmail?.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return 'Sistema';
  }

  double get counterpartAmount =>
      counterpartDebit > 0 ? counterpartDebit : counterpartCredit;
  bool get hasPostedJournal => (journalEntryNumber ?? '').isNotEmpty;
  double get displayedInventoryValue =>
      hasPostedJournal ? counterpartAmount : inventoryValue;
  double get displayedUnitCost =>
      quantity == 0 ? unitCost : displayedInventoryValue / quantity.abs();
  String get unitCostLabel =>
      hasPostedJournal ? 'Costo unitario registrado' : 'Costo unitario actual';
  String get inventoryValueLabel => hasPostedJournal
      ? 'Impacto contable registrado'
      : 'Estimación a costo actual';

  bool get _hasFriendlyStoredReference {
    final trimmed = referenceNumber.trim();
    if (trimmed.isEmpty || trimmed == '-') return false;
    return !_uuidPattern.hasMatch(trimmed);
  }

  String? get _reasonEmbeddedReference {
    final match = _hashReferencePattern.firstMatch(reason);
    if (match == null) return null;
    final value = match.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String get referenceDisplay {
    if (_hasFriendlyStoredReference) {
      return referenceNumber.trim();
    }

    final embeddedReference = _reasonEmbeddedReference;
    if (embeddedReference != null) {
      if (reason.startsWith('Reversal: Purchase Invoice Deleted')) {
        return 'Compra $embeddedReference';
      }
      if (reason.startsWith('Reversal: Sales Invoice Deleted')) {
        return 'Venta $embeddedReference';
      }
      return embeddedReference;
    }

    switch (adjustmentType) {
      case 'initial':
        return 'Stock inicial';
      case 'correction':
        return 'Corrección histórica';
      case 'manual':
        return 'Ajuste manual';
      default:
        return 'Ajuste sin folio';
    }
  }

  String get reasonDisplay {
    if (reason.startsWith('Reversal: Purchase Invoice Deleted #')) {
      final embeddedReference = _reasonEmbeddedReference;
      return embeddedReference == null
          ? 'Reversa por eliminación de factura de compra.'
          : 'Reversa por eliminación de factura de compra $embeddedReference.';
    }

    if (reason.startsWith('Reversal: Sales Invoice Deleted #')) {
      final embeddedReference = _reasonEmbeddedReference;
      return embeddedReference == null
          ? 'Reversa por eliminación de factura de venta.'
          : 'Reversa por eliminación de factura de venta $embeddedReference.';
    }

    if (reason == 'Manual adjustment via product form') {
      return 'Ajuste manual realizado desde el formulario del producto.';
    }

    if (reason == 'Ajuste Manual') {
      return 'Ajuste manual registrado en inventario.';
    }

    return reason;
  }

  String get accountingImpactMessage {
    if ((journalEntryNumber ?? '').isEmpty) {
      if (inventoryValue <= 0) {
        return 'No se generó asiento porque el producto no tenía costo valorizado al momento del ajuste.';
      }
      return 'Este ajuste histórico no tiene un asiento contable asociado.';
    }

    return 'Asiento ${journalEntryNumber!} asociado al ajuste.';
  }

  String get adjustmentTypeLabel {
    switch (adjustmentType) {
      case 'count_gain':
        return 'Reconteo positivo';
      case 'count_loss':
        return 'Reconteo negativo';
      case 'loss':
        return 'Merma';
      case 'damage':
        return 'Daño';
      case 'theft':
        return 'Robo / extravío';
      case 'internal_use':
        return 'Uso interno / taller';
      case 'found':
        return 'Hallazgo / recuperación';
      case 'manual':
        return 'Ajuste manual';
      case 'initial':
        return 'Stock inicial';
      case 'correction':
        return 'Corrección';
      case 'import':
        return 'Importación';
      case 'purchase':
        return 'Compra';
      default:
        return adjustmentType;
    }
  }
}
