enum PurchaseReceiptDiscrepancyKind { damaged, rejected, shortage }

extension PurchaseReceiptDiscrepancyKindX on PurchaseReceiptDiscrepancyKind {
  static PurchaseReceiptDiscrepancyKind fromDatabase(Object? value) {
    return PurchaseReceiptDiscrepancyKind.values.firstWhere(
      (kind) => kind.name == value?.toString(),
      orElse: () => PurchaseReceiptDiscrepancyKind.shortage,
    );
  }

  String get label => switch (this) {
        PurchaseReceiptDiscrepancyKind.damaged => 'Dañado',
        PurchaseReceiptDiscrepancyKind.rejected => 'Rechazado',
        PurchaseReceiptDiscrepancyKind.shortage => 'Faltante',
      };
}

enum PurchaseReceiptResolutionOutcome {
  creditNote,
  laterDelivery,
  documentedLoss,
  documentedLossReversal,
  unknown,
}

extension PurchaseReceiptResolutionOutcomeX
    on PurchaseReceiptResolutionOutcome {
  static PurchaseReceiptResolutionOutcome fromDatabase(Object? value) {
    return switch (value?.toString()) {
      'credit_note' => PurchaseReceiptResolutionOutcome.creditNote,
      'later_delivery' => PurchaseReceiptResolutionOutcome.laterDelivery,
      'documented_loss' => PurchaseReceiptResolutionOutcome.documentedLoss,
      'documented_loss_reversal' =>
        PurchaseReceiptResolutionOutcome.documentedLossReversal,
      _ => PurchaseReceiptResolutionOutcome.unknown,
    };
  }

  String get label => switch (this) {
        PurchaseReceiptResolutionOutcome.creditNote => 'Nota de crédito',
        PurchaseReceiptResolutionOutcome.laterDelivery => 'Entrega posterior',
        PurchaseReceiptResolutionOutcome.documentedLoss =>
          'Pérdida documentada',
        PurchaseReceiptResolutionOutcome.documentedLossReversal =>
          'Reversa de pérdida',
        PurchaseReceiptResolutionOutcome.unknown => 'Resolución desconocida',
      };
}

class PurchaseReceiptResolutionCase {
  const PurchaseReceiptResolutionCase({
    required this.id,
    required this.number,
    required this.purchaseInvoiceId,
    required this.purchaseReceiptId,
    required this.purchaseReceiptLineId,
    required this.sourceLineIndex,
    required this.sourceLineKey,
    required this.productName,
    required this.purchaseTreatment,
    required this.kind,
    required this.reportedQuantity,
    required this.resolvedQuantity,
    required this.openQuantity,
    required this.effectiveStatus,
    required this.createdAt,
    required this.allocations,
    this.purchaseReceiptNumber,
    this.productId,
    this.productSku,
    this.discrepancyReason,
  });

  final String id;
  final String number;
  final String purchaseInvoiceId;
  final String purchaseReceiptId;
  final String? purchaseReceiptNumber;
  final String purchaseReceiptLineId;
  final int sourceLineIndex;
  final String sourceLineKey;
  final String? productId;
  final String productName;
  final String purchaseTreatment;
  final String? productSku;
  final PurchaseReceiptDiscrepancyKind kind;
  final int reportedQuantity;
  final int resolvedQuantity;
  final int openQuantity;
  final String effectiveStatus;
  final DateTime createdAt;
  final String? discrepancyReason;
  final List<PurchaseReceiptResolutionAllocation> allocations;

  bool get isOpen =>
      openQuantity > 0 &&
      (effectiveStatus == 'open' || effectiveStatus == 'partially_resolved');
  bool get isResolved => effectiveStatus == 'resolved' || openQuantity == 0;
}

class PurchaseReceiptResolutionAllocation {
  const PurchaseReceiptResolutionAllocation({
    required this.id,
    required this.caseId,
    required this.resolutionGroupId,
    required this.outcome,
    required this.quantity,
    required this.effectiveStatus,
    required this.isEffective,
    required this.createdAt,
    this.purchaseCreditNoteId,
    this.purchaseCreditNoteLineId,
    this.purchaseCreditNoteNumber,
    this.laterPurchaseReceiptId,
    this.laterPurchaseReceiptLineId,
    this.laterPurchaseReceiptNumber,
    this.supplierReturnId,
    this.supplierReturnNumber,
    this.supplierReturnStatus,
    this.supplierRefunds = const [],
    this.lossJournalEntryId,
    this.lossJournalEntryNumber,
    this.lossOperationId,
    this.reason,
    this.voidReason,
  });

  final String id;
  final String caseId;
  final String resolutionGroupId;
  final PurchaseReceiptResolutionOutcome outcome;
  final int quantity;
  final String effectiveStatus;
  final bool isEffective;
  final DateTime createdAt;
  final String? purchaseCreditNoteId;
  final String? purchaseCreditNoteLineId;
  final String? purchaseCreditNoteNumber;
  final String? laterPurchaseReceiptId;
  final String? laterPurchaseReceiptLineId;
  final String? laterPurchaseReceiptNumber;
  final String? supplierReturnId;
  final String? supplierReturnNumber;
  final String? supplierReturnStatus;
  final List<PurchaseReceiptSupplierRefundReference> supplierRefunds;
  final String? lossJournalEntryId;
  final String? lossJournalEntryNumber;
  final String? lossOperationId;
  final String? reason;
  final String? voidReason;

  bool get isActive => isEffective;
}

class PurchaseReceiptSupplierRefundReference {
  const PurchaseReceiptSupplierRefundReference({
    required this.id,
    required this.number,
    required this.status,
    required this.amount,
    this.refundedAt,
  });

  final String id;
  final String number;
  final String status;
  final double amount;
  final DateTime? refundedAt;
}

class PurchaseReceiptLossResolutionResult {
  const PurchaseReceiptLossResolutionResult({
    required this.resolutionGroupId,
    required this.operationId,
    required this.replayed,
    this.journalEntryId,
  });

  final String resolutionGroupId;
  final String operationId;
  final bool replayed;
  final String? journalEntryId;

  factory PurchaseReceiptLossResolutionResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return PurchaseReceiptLossResolutionResult(
      resolutionGroupId: json['resolution_group_id']?.toString() ?? '',
      operationId: json['operation_id']?.toString() ?? '',
      replayed: json['replayed'] == true,
      journalEntryId: json['journal_entry_id']?.toString(),
    );
  }
}
