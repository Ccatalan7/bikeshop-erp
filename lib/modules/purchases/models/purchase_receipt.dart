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

enum PurchaseReceiptFulfillmentState {
  none,
  open,
  complete,
  closedWithDifference,
}

class PurchaseReceiptFulfillment {
  const PurchaseReceiptFulfillment({
    required this.state,
    required this.expectedQuantity,
    required this.acceptedQuantity,
    required this.reportedDifferenceQuantity,
    required this.resolvedDifferenceQuantity,
    required this.nonPhysicalResolutionQuantity,
    required this.unresolvedDifferenceQuantity,
    required this.physicalRemainingQuantity,
    required this.remainingQuantity,
    required this.receiptCount,
    this.latestReceivedAt,
    this.legacyReceived = false,
  });

  final PurchaseReceiptFulfillmentState state;
  final int expectedQuantity;
  final int acceptedQuantity;
  final int reportedDifferenceQuantity;
  final int resolvedDifferenceQuantity;
  final int nonPhysicalResolutionQuantity;
  final int unresolvedDifferenceQuantity;
  final int physicalRemainingQuantity;
  final int remainingQuantity;
  final int receiptCount;
  final DateTime? latestReceivedAt;
  final bool legacyReceived;

  factory PurchaseReceiptFulfillment.derive({
    required List<int> expectedQuantities,
    required Map<int, int> acceptedByLine,
    Map<int, int> differencesByLine = const {},
    Map<int, int> resolvedDifferencesByLine = const {},
    Map<int, int> nonPhysicalResolutionsByLine = const {},
    int receiptCount = 0,
    DateTime? latestReceivedAt,
    bool legacyReceived = false,
  }) {
    final expected = expectedQuantities.fold<int>(
      0,
      (sum, quantity) => sum + quantity,
    );
    final accepted = expectedQuantities.asMap().entries.fold<int>(
          0,
          (sum, entry) =>
              sum +
              (acceptedByLine[entry.key] ?? 0).clamp(0, entry.value).toInt(),
        );
    final differences =
        differencesByLine.values.fold<int>(0, (sum, value) => sum + value);
    final physicalRemaining = (expected - accepted).clamp(0, expected).toInt();
    final resolved = expectedQuantities.asMap().entries.fold<int>(
          0,
          (sum, entry) =>
              sum +
              (resolvedDifferencesByLine[entry.key] ?? 0)
                  .clamp(0, differencesByLine[entry.key] ?? 0)
                  .toInt(),
        );
    final nonPhysicalResolved = expectedQuantities.asMap().entries.fold<int>(
      0,
      (sum, entry) {
        final acceptedForLine =
            (acceptedByLine[entry.key] ?? 0).clamp(0, entry.value).toInt();
        final availableToClose = entry.value - acceptedForLine;
        return sum +
            (nonPhysicalResolutionsByLine[entry.key] ?? 0)
                .clamp(0, availableToClose)
                .toInt();
      },
    );
    final remaining = (physicalRemaining - nonPhysicalResolved)
        .clamp(0, physicalRemaining)
        .toInt();
    final unresolvedDifference =
        (differences - resolved).clamp(0, differences).toInt();
    final hasReceiptEvidence =
        legacyReceived || receiptCount > 0 || accepted > 0 || differences > 0;

    return PurchaseReceiptFulfillment(
      state: legacyReceived || (expected > 0 && physicalRemaining == 0)
          ? PurchaseReceiptFulfillmentState.complete
          : expected > 0 && remaining == 0 && nonPhysicalResolved > 0
              ? PurchaseReceiptFulfillmentState.closedWithDifference
              : hasReceiptEvidence
                  ? PurchaseReceiptFulfillmentState.open
                  : PurchaseReceiptFulfillmentState.none,
      expectedQuantity: expected,
      acceptedQuantity: legacyReceived ? expected : accepted,
      reportedDifferenceQuantity: differences,
      resolvedDifferenceQuantity: resolved,
      nonPhysicalResolutionQuantity: nonPhysicalResolved,
      unresolvedDifferenceQuantity: unresolvedDifference,
      physicalRemainingQuantity: legacyReceived ? 0 : physicalRemaining,
      remainingQuantity: legacyReceived ? 0 : remaining,
      receiptCount: receiptCount,
      latestReceivedAt: latestReceivedAt,
      legacyReceived: legacyReceived,
    );
  }

  factory PurchaseReceiptFulfillment.fromListReadModel(
    Map<String, dynamic> json,
  ) {
    final rawState = json['receipt_state']?.toString();
    final state = switch (rawState) {
      'open' => PurchaseReceiptFulfillmentState.open,
      'complete' => PurchaseReceiptFulfillmentState.complete,
      'closed_with_difference' =>
        PurchaseReceiptFulfillmentState.closedWithDifference,
      _ => PurchaseReceiptFulfillmentState.none,
    };

    int integer(String key) => (json[key] as num?)?.round() ?? 0;

    final latestReceivedAt =
        DateTime.tryParse(json['receipt_latest_received_at']?.toString() ?? '');
    return PurchaseReceiptFulfillment(
      state: state,
      expectedQuantity: integer('receipt_expected_quantity'),
      acceptedQuantity: integer('receipt_accepted_quantity'),
      reportedDifferenceQuantity:
          integer('receipt_reported_difference_quantity'),
      resolvedDifferenceQuantity:
          integer('receipt_resolved_difference_quantity'),
      nonPhysicalResolutionQuantity:
          integer('receipt_nonphysical_resolution_quantity'),
      unresolvedDifferenceQuantity:
          integer('receipt_unresolved_difference_quantity'),
      physicalRemainingQuantity: integer('receipt_physical_remaining_quantity'),
      remainingQuantity: integer('receipt_remaining_quantity'),
      receiptCount: integer('receipt_count'),
      latestReceivedAt: latestReceivedAt,
      legacyReceived: json['receipt_legacy_received'] as bool? ?? false,
    );
  }

  static const none = PurchaseReceiptFulfillment(
    state: PurchaseReceiptFulfillmentState.none,
    expectedQuantity: 0,
    acceptedQuantity: 0,
    reportedDifferenceQuantity: 0,
    resolvedDifferenceQuantity: 0,
    nonPhysicalResolutionQuantity: 0,
    unresolvedDifferenceQuantity: 0,
    physicalRemainingQuantity: 0,
    remainingQuantity: 0,
    receiptCount: 0,
  );

  bool get hasReceiptEvidence =>
      legacyReceived ||
      receiptCount > 0 ||
      acceptedQuantity > 0 ||
      reportedDifferenceQuantity > 0;
  bool get isComplete => state == PurchaseReceiptFulfillmentState.complete;
  bool get isClosedWithDifference =>
      state == PurchaseReceiptFulfillmentState.closedWithDifference;
  bool get isClosed => isComplete || isClosedWithDifference;
  bool get isOpen => state == PurchaseReceiptFulfillmentState.open;
  bool get hasReportedDifferences => reportedDifferenceQuantity > 0;
}

class PurchaseReceiptLineDraft {
  const PurchaseReceiptLineDraft({
    required this.lineIndex,
    required this.productName,
    this.productSku,
    this.productImageUrl,
    required this.expectedQuantity,
    required this.previouslyReceivedQuantity,
    this.previouslyResolvedQuantity = 0,
    required this.acceptedQuantity,
    this.damagedQuantity = 0,
    this.rejectedQuantity = 0,
    this.shortageQuantity = 0,
    this.discrepancyReason,
  });

  final int lineIndex;
  final String productName;
  final String? productSku;
  final String? productImageUrl;
  final int expectedQuantity;
  final int previouslyReceivedQuantity;
  final int previouslyResolvedQuantity;
  final int acceptedQuantity;
  final int damagedQuantity;
  final int rejectedQuantity;
  final int shortageQuantity;
  final String? discrepancyReason;

  int get remainingBefore =>
      expectedQuantity -
      previouslyReceivedQuantity -
      previouslyResolvedQuantity;
  int get reportedNow =>
      acceptedQuantity + damagedQuantity + rejectedQuantity + shortageQuantity;
  int get remainingAfter => remainingBefore - acceptedQuantity;
  bool get hasDiscrepancy =>
      damagedQuantity + rejectedQuantity + shortageQuantity > 0;
  bool get hasEffect => reportedNow > 0;

  String? validate() {
    if (lineIndex < 0 ||
        expectedQuantity < 0 ||
        previouslyReceivedQuantity < 0 ||
        previouslyResolvedQuantity < 0) {
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
      productImageUrl: productImageUrl,
      expectedQuantity: expectedQuantity,
      previouslyReceivedQuantity: previouslyReceivedQuantity,
      previouslyResolvedQuantity: previouslyResolvedQuantity,
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

class PurchaseReceiptDetailRecord {
  const PurchaseReceiptDetailRecord({
    required this.id,
    required this.purchaseInvoiceId,
    required this.number,
    required this.status,
    required this.receivedAt,
    required this.operationId,
    required this.createdAt,
    required this.lines,
    this.deliveryReference,
    this.locationLabel,
    this.notes,
    this.createdBy,
    this.voidOperationId,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
  });

  final String id;
  final String purchaseInvoiceId;
  final String number;
  final String status;
  final DateTime receivedAt;
  final String operationId;
  final DateTime createdAt;
  final List<PurchaseReceiptLineRecord> lines;
  final String? deliveryReference;
  final String? locationLabel;
  final String? notes;
  final String? createdBy;
  final String? voidOperationId;
  final DateTime? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  bool get canVoid => status == 'posted';
  int get acceptedQuantity =>
      lines.fold(0, (sum, line) => sum + line.acceptedQuantity);
  int get discrepancyQuantity =>
      lines.fold(0, (sum, line) => sum + line.discrepancyQuantity);
  int get remainingQuantity =>
      lines.fold(0, (sum, line) => sum + line.remainingQuantity);
  int get stockMovementCount =>
      lines.fold(0, (sum, line) => sum + line.movements.length);
}

class PurchaseReceiptLineRecord {
  const PurchaseReceiptLineRecord({
    required this.id,
    required this.lineIndex,
    required this.productName,
    required this.purchaseTreatment,
    required this.expectedQuantity,
    required this.previouslyReceivedQuantity,
    required this.acceptedQuantity,
    required this.damagedQuantity,
    required this.rejectedQuantity,
    required this.shortageQuantity,
    required this.remainingQuantity,
    required this.unitCost,
    required this.movements,
    this.productId,
    this.productSku,
    this.stockMovementId,
    this.discrepancyReason,
  });

  final String id;
  final int lineIndex;
  final String? productId;
  final String productName;
  final String? productSku;
  final String purchaseTreatment;
  final int expectedQuantity;
  final int previouslyReceivedQuantity;
  final int acceptedQuantity;
  final int damagedQuantity;
  final int rejectedQuantity;
  final int shortageQuantity;
  final int remainingQuantity;
  final double unitCost;
  final String? stockMovementId;
  final String? discrepancyReason;
  final List<PurchaseReceiptMovementRecord> movements;

  int get discrepancyQuantity =>
      damagedQuantity + rejectedQuantity + shortageQuantity;
  bool get hasDiscrepancy => discrepancyQuantity > 0;
}

class PurchaseReceiptMovementRecord {
  const PurchaseReceiptMovementRecord({
    required this.productId,
    required this.stockMovementId,
    required this.role,
    required this.quantity,
  });

  final String productId;
  final String stockMovementId;
  final String role;
  final int quantity;
}
