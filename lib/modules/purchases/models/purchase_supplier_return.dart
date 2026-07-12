class PurchaseReturnableReceipt {
  const PurchaseReturnableReceipt({
    required this.id,
    required this.receiptNumber,
    required this.receivedAt,
    required this.lines,
  });

  final String id;
  final String receiptNumber;
  final DateTime receivedAt;
  final List<PurchaseSupplierReturnLineDraft> lines;

  int get returnableQuantity =>
      lines.fold(0, (sum, line) => sum + line.returnableQuantity);
}

class PurchaseSupplierReturnLineDraft {
  const PurchaseSupplierReturnLineDraft({
    required this.receiptLineId,
    required this.productName,
    this.productSku,
    required this.acceptedQuantity,
    required this.previouslyReturnedQuantity,
    this.returnedQuantity = 0,
    this.reason,
  });

  final String receiptLineId;
  final String productName;
  final String? productSku;
  final int acceptedQuantity;
  final int previouslyReturnedQuantity;
  final int returnedQuantity;
  final String? reason;

  int get returnableQuantity => acceptedQuantity - previouslyReturnedQuantity;
  bool get isSelected => returnedQuantity > 0;

  String? validate() {
    if (receiptLineId.isEmpty ||
        acceptedQuantity < 0 ||
        previouslyReturnedQuantity < 0) {
      return 'La línea de devolución no es válida.';
    }
    if (returnedQuantity <= 0) {
      return 'Indica una cantidad positiva para $productName.';
    }
    if (returnedQuantity > returnableQuantity) {
      return 'La devolución de $productName supera las $returnableQuantity unidades disponibles.';
    }
    return null;
  }

  PurchaseSupplierReturnLineDraft copyWith({
    int? returnedQuantity,
    String? reason,
  }) {
    return PurchaseSupplierReturnLineDraft(
      receiptLineId: receiptLineId,
      productName: productName,
      productSku: productSku,
      acceptedQuantity: acceptedQuantity,
      previouslyReturnedQuantity: previouslyReturnedQuantity,
      returnedQuantity: returnedQuantity ?? this.returnedQuantity,
      reason: reason ?? this.reason,
    );
  }

  Map<String, dynamic> toRpcJson() => {
        'receipt_line_id': receiptLineId,
        'returned_quantity': returnedQuantity,
        if (reason?.trim().isNotEmpty ?? false) 'reason': reason!.trim(),
      };
}

class PurchaseSupplierReturnResult {
  const PurchaseSupplierReturnResult({
    required this.supplierReturnId,
    required this.operationId,
    required this.returnNumber,
    required this.replayed,
  });

  final String supplierReturnId;
  final String operationId;
  final String returnNumber;
  final bool replayed;

  factory PurchaseSupplierReturnResult.fromJson(Map<String, dynamic> json) {
    return PurchaseSupplierReturnResult(
      supplierReturnId: json['supplier_return_id']?.toString() ?? '',
      operationId: json['operation_id']?.toString() ?? '',
      returnNumber: json['return_number']?.toString() ?? '',
      replayed: json['replayed'] == true,
    );
  }
}

class PurchaseSupplierReturnRecord {
  const PurchaseSupplierReturnRecord({
    required this.id,
    required this.returnNumber,
    required this.status,
    required this.returnedAt,
    required this.reason,
    required this.quantity,
    this.shipmentReference,
    this.voidReason,
  });

  final String id;
  final String returnNumber;
  final String status;
  final DateTime returnedAt;
  final String reason;
  final int quantity;
  final String? shipmentReference;
  final String? voidReason;

  bool get canVoid => status == 'posted';

  factory PurchaseSupplierReturnRecord.fromJson(Map<String, dynamic> json) {
    final rawLines =
        json['purchase_supplier_return_lines'] as List? ?? const [];
    final quantity = rawLines.fold<int>(
      0,
      (sum, raw) =>
          sum + (((raw as Map)['returned_quantity'] as num?)?.toInt() ?? 0),
    );
    return PurchaseSupplierReturnRecord(
      id: json['id']?.toString() ?? '',
      returnNumber: json['return_number']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      returnedAt: DateTime.parse(json['returned_at'].toString()),
      reason: json['reason']?.toString() ?? '',
      quantity: quantity,
      shipmentReference: json['shipment_reference']?.toString(),
      voidReason: json['void_reason']?.toString(),
    );
  }
}

class PurchaseSupplierReturnVoidResult {
  const PurchaseSupplierReturnVoidResult({
    required this.supplierReturnId,
    required this.operationId,
    required this.replayed,
  });

  final String supplierReturnId;
  final String operationId;
  final bool replayed;

  factory PurchaseSupplierReturnVoidResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return PurchaseSupplierReturnVoidResult(
      supplierReturnId: json['supplier_return_id']?.toString() ?? '',
      operationId: json['operation_id']?.toString() ?? '',
      replayed: json['replayed'] == true,
    );
  }
}
