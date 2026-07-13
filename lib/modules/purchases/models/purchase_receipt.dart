enum PurchaseReceiptControlMode { disabled, shadow, enforce }

extension PurchaseReceiptControlModeX on PurchaseReceiptControlMode {
  static PurchaseReceiptControlMode fromDatabase(Object? value) {
    return PurchaseReceiptControlMode.values.firstWhere(
      (mode) => mode.name == value?.toString(),
      orElse: () => PurchaseReceiptControlMode.disabled,
    );
  }

  bool get acceptsCommands => this == PurchaseReceiptControlMode.enforce;
}

class PurchaseReceiptLineDraft {
  const PurchaseReceiptLineDraft({
    required this.lineIndex,
    required this.productName,
    this.productSku,
    required this.expectedQuantity,
    required this.previouslyReceivedQuantity,
    required this.acceptedQuantity,
    this.damagedQuantity = 0,
    this.rejectedQuantity = 0,
    this.shortageQuantity = 0,
    this.discrepancyReason,
  });

  final int lineIndex;
  final String productName;
  final String? productSku;
  final int expectedQuantity;
  final int previouslyReceivedQuantity;
  final int acceptedQuantity;
  final int damagedQuantity;
  final int rejectedQuantity;
  final int shortageQuantity;
  final String? discrepancyReason;

  int get remainingBefore => expectedQuantity - previouslyReceivedQuantity;
  int get reportedNow =>
      acceptedQuantity + damagedQuantity + rejectedQuantity + shortageQuantity;
  int get remainingAfter => remainingBefore - acceptedQuantity;
  bool get hasDiscrepancy =>
      damagedQuantity + rejectedQuantity + shortageQuantity > 0;
  bool get hasEffect => reportedNow > 0;

  String? validate() {
    if (lineIndex < 0 ||
        expectedQuantity < 0 ||
        previouslyReceivedQuantity < 0) {
      return 'La línea de recepción no es válida.';
    }
    if (acceptedQuantity < 0 ||
        damagedQuantity < 0 ||
        rejectedQuantity < 0 ||
        shortageQuantity < 0) {
      return 'Las cantidades no pueden ser negativas.';
    }
    if (!hasEffect) {
      return 'Ingresa una cantidad recibida o una diferencia para $productName.';
    }
    if (reportedNow > remainingBefore) {
      return 'Las cantidades de $productName superan las $remainingBefore unidades pendientes.';
    }
    if (hasDiscrepancy && (discrepancyReason?.trim().isEmpty ?? true)) {
      return 'Explica la diferencia registrada para $productName.';
    }
    return null;
  }

  PurchaseReceiptLineDraft copyWith({
    int? acceptedQuantity,
    int? damagedQuantity,
    int? rejectedQuantity,
    int? shortageQuantity,
    String? discrepancyReason,
  }) {
    return PurchaseReceiptLineDraft(
      lineIndex: lineIndex,
      productName: productName,
      productSku: productSku,
      expectedQuantity: expectedQuantity,
      previouslyReceivedQuantity: previouslyReceivedQuantity,
      acceptedQuantity: acceptedQuantity ?? this.acceptedQuantity,
      damagedQuantity: damagedQuantity ?? this.damagedQuantity,
      rejectedQuantity: rejectedQuantity ?? this.rejectedQuantity,
      shortageQuantity: shortageQuantity ?? this.shortageQuantity,
      discrepancyReason: discrepancyReason ?? this.discrepancyReason,
    );
  }

  Map<String, dynamic> toRpcJson() => {
        'line_index': lineIndex,
        'accepted_quantity': acceptedQuantity,
        'damaged_quantity': damagedQuantity,
        'rejected_quantity': rejectedQuantity,
        'shortage_quantity': shortageQuantity,
        if (discrepancyReason?.trim().isNotEmpty ?? false)
          'discrepancy_reason': discrepancyReason!.trim(),
      };
}

class PurchaseReceiptResult {
  const PurchaseReceiptResult({
    required this.receiptId,
    required this.operationId,
    required this.receiptNumber,
    required this.replayed,
  });

  final String receiptId;
  final String operationId;
  final String receiptNumber;
  final bool replayed;

  factory PurchaseReceiptResult.fromJson(Map<String, dynamic> json) {
    return PurchaseReceiptResult(
      receiptId: json['receipt_id']?.toString() ?? '',
      operationId: json['operation_id']?.toString() ?? '',
      receiptNumber: json['receipt_number']?.toString() ?? '',
      replayed: json['replayed'] == true,
    );
  }
}

class PurchaseReceiptRecord {
  const PurchaseReceiptRecord({
    required this.id,
    required this.number,
    required this.status,
    required this.receivedAt,
    required this.acceptedQuantity,
    required this.discrepancyQuantity,
    this.deliveryReference,
    this.locationLabel,
    this.voidReason,
  });

  final String id;
  final String number;
  final String status;
  final DateTime receivedAt;
  final int acceptedQuantity;
  final int discrepancyQuantity;
  final String? deliveryReference;
  final String? locationLabel;
  final String? voidReason;

  bool get canVoid => status == 'posted';
}
