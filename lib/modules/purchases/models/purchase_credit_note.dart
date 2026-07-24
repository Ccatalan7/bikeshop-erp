enum PurchaseCreditDisposition { financialOnly, supplierReturn }

extension PurchaseCreditDispositionX on PurchaseCreditDisposition {
  String get databaseValue => switch (this) {
        PurchaseCreditDisposition.financialOnly => 'financial_only',
        PurchaseCreditDisposition.supplierReturn => 'supplier_return',
      };
}

class PurchaseCreditNoteLineBalance {
  const PurchaseCreditNoteLineBalance({
    required this.lineIndex,
    required this.sourceLineKey,
    required this.productName,
    this.productSku,
    required this.purchaseTreatment,
    required this.originalQuantity,
    required this.originalNet,
    required this.originalTax,
    required this.creditedQuantity,
    required this.creditedNet,
    required this.creditedTax,
    required this.remainingQuantity,
    required this.remainingNet,
    required this.remainingTax,
  });

  final int lineIndex;
  final String sourceLineKey;
  final String productName;
  final String? productSku;
  final String purchaseTreatment;
  final int originalQuantity;
  final int originalNet;
  final int originalTax;
  final int creditedQuantity;
  final int creditedNet;
  final int creditedTax;
  final int remainingQuantity;
  final int remainingNet;
  final int remainingTax;

  factory PurchaseCreditNoteLineBalance.fromJson(Map<String, dynamic> json) {
    int amount(String key) => (json[key] as num?)?.round() ?? 0;
    return PurchaseCreditNoteLineBalance(
      lineIndex: amount('source_line_index'),
      sourceLineKey: json['source_line_key']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? 'Producto',
      productSku: json['product_sku']?.toString(),
      purchaseTreatment: json['purchase_treatment']?.toString() ?? 'inventory',
      originalQuantity: amount('original_quantity'),
      originalNet: amount('original_allocated_net'),
      originalTax: amount('original_allocated_tax'),
      creditedQuantity: amount('credited_quantity'),
      creditedNet: amount('credited_net'),
      creditedTax: amount('credited_tax'),
      remainingQuantity: amount('remaining_quantity'),
      remainingNet: amount('remaining_net'),
      remainingTax: amount('remaining_tax'),
    );
  }
}

class PurchaseCreditReturnOption {
  const PurchaseCreditReturnOption({
    required this.id,
    required this.sourceLineKey,
    required this.returnNumber,
    required this.returnedQuantity,
    required this.creditedQuantity,
  });

  final String id;
  final String sourceLineKey;
  final String returnNumber;
  final int returnedQuantity;
  final int creditedQuantity;
  int get remainingQuantity => returnedQuantity - creditedQuantity;
}

class PurchaseCreditNoteLineDraft {
  const PurchaseCreditNoteLineDraft({
    required this.balance,
    this.quantity = 0,
    this.netAmount = 0,
    this.taxAmount = 0,
    this.disposition = PurchaseCreditDisposition.financialOnly,
    this.supplierReturnLineId,
    this.receiptResolutionCaseId,
    this.receiptResolutionMaximum,
  });

  final PurchaseCreditNoteLineBalance balance;
  final int quantity;
  final int netAmount;
  final int taxAmount;
  final PurchaseCreditDisposition disposition;
  final String? supplierReturnLineId;
  final String? receiptResolutionCaseId;
  final int? receiptResolutionMaximum;

  int get totalAmount => netAmount + taxAmount;
  bool get isSelected => totalAmount > 0;

  PurchaseCreditNoteLineDraft withQuantity(int value) {
    final maximum = receiptResolutionMaximum == null
        ? balance.remainingQuantity
        : receiptResolutionMaximum!.clamp(0, balance.remainingQuantity);
    final quantity = value.clamp(0, maximum);
    final net = balance.originalQuantity == 0
        ? 0
        : (balance.originalNet * quantity / balance.originalQuantity).round();
    final tax = balance.originalNet == 0
        ? 0
        : (balance.originalTax * net / balance.originalNet).round();
    return copyWith(quantity: quantity, netAmount: net, taxAmount: tax);
  }

  String? validate({PurchaseCreditReturnOption? returnOption}) {
    if (!isSelected) return 'Indica un monto para ${balance.productName}.';
    if (quantity < 0 || quantity > balance.remainingQuantity) {
      return 'La cantidad de ${balance.productName} supera el saldo original.';
    }
    if (netAmount < 0 ||
        taxAmount < 0 ||
        netAmount > balance.remainingNet ||
        taxAmount > balance.remainingTax) {
      return 'El monto de ${balance.productName} supera el saldo acreditable.';
    }
    if (disposition == PurchaseCreditDisposition.supplierReturn) {
      if (supplierReturnLineId == null || quantity <= 0) {
        return 'Vincula una devolución física para ${balance.productName}.';
      }
      if (returnOption == null || quantity > returnOption.remainingQuantity) {
        return 'La cantidad supera la devolución física seleccionada.';
      }
    }
    if (receiptResolutionCaseId != null &&
        disposition != PurchaseCreditDisposition.financialOnly) {
      return 'Una diferencia de recepción se acredita como ajuste financiero; '
          'la devolución física usa su propio documento.';
    }
    if (receiptResolutionMaximum != null &&
        quantity > receiptResolutionMaximum!) {
      return 'La cantidad supera el saldo abierto de la diferencia de '
          '${balance.productName}.';
    }
    return null;
  }

  PurchaseCreditNoteLineDraft copyWith({
    int? quantity,
    int? netAmount,
    int? taxAmount,
    PurchaseCreditDisposition? disposition,
    String? supplierReturnLineId,
    String? receiptResolutionCaseId,
    int? receiptResolutionMaximum,
    bool clearSupplierReturn = false,
    bool clearReceiptResolution = false,
  }) {
    return PurchaseCreditNoteLineDraft(
      balance: balance,
      quantity: quantity ?? this.quantity,
      netAmount: netAmount ?? this.netAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      disposition: disposition ?? this.disposition,
      supplierReturnLineId: clearSupplierReturn
          ? null
          : supplierReturnLineId ?? this.supplierReturnLineId,
      receiptResolutionCaseId: clearReceiptResolution
          ? null
          : receiptResolutionCaseId ?? this.receiptResolutionCaseId,
      receiptResolutionMaximum: clearReceiptResolution
          ? null
          : receiptResolutionMaximum ?? this.receiptResolutionMaximum,
    );
  }

  Map<String, dynamic> toRpcJson() => {
        'line_index': balance.lineIndex,
        'credited_quantity': quantity,
        'net_amount': netAmount,
        'tax_amount': taxAmount,
        'disposition': disposition.databaseValue,
        if (supplierReturnLineId != null)
          'supplier_return_line_id': supplierReturnLineId,
        if (receiptResolutionCaseId != null)
          'receipt_resolution_case_id': receiptResolutionCaseId,
      };
}

class PurchaseCreditNoteRecord {
  const PurchaseCreditNoteRecord({
    required this.id,
    required this.number,
    required this.status,
    required this.officialStatus,
    required this.issueDate,
    required this.reason,
    required this.totalAmount,
    this.refundedAmount = 0,
    this.remainingRefundable = 0,
    this.invoiceCreditBalance = 0,
    this.supplierNumber,
    this.voidReason,
  });

  final String id;
  final String number;
  final String status;
  final String officialStatus;
  final DateTime issueDate;
  final String reason;
  final int totalAmount;
  final int refundedAmount;
  final int remainingRefundable;
  final int invoiceCreditBalance;
  final String? supplierNumber;
  final String? voidReason;
  int get availableToRefund => remainingRefundable < invoiceCreditBalance
      ? remainingRefundable
      : invoiceCreditBalance;
  bool get canRefund => status == 'posted' && availableToRefund > 0;
  bool get canVoid =>
      status == 'posted' && officialStatus != 'issued' && refundedAmount == 0;

  factory PurchaseCreditNoteRecord.fromJson(Map<String, dynamic> json) {
    return PurchaseCreditNoteRecord(
      id: json['id']?.toString() ?? '',
      number: json['credit_note_number']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      officialStatus: json['official_dte_status']?.toString() ?? 'internal',
      issueDate: DateTime.parse(json['issue_date'].toString()),
      reason: json['reason']?.toString() ?? '',
      totalAmount: (json['total_amount'] as num?)?.round() ?? 0,
      refundedAmount: (json['refunded_amount'] as num?)?.round() ?? 0,
      remainingRefundable: (json['remaining_refundable'] as num?)?.round() ?? 0,
      invoiceCreditBalance:
          (json['invoice_credit_balance'] as num?)?.round() ?? 0,
      supplierNumber: json['supplier_credit_note_number']?.toString(),
      voidReason: json['void_reason']?.toString(),
    );
  }
}

class PurchaseCreditNoteLineRecord {
  const PurchaseCreditNoteLineRecord({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.netAmount,
    required this.taxAmount,
    required this.totalAmount,
    required this.disposition,
    this.productSku,
  });

  final String id;
  final String productName;
  final String? productSku;
  final int quantity;
  final int netAmount;
  final int taxAmount;
  final int totalAmount;
  final String disposition;

  factory PurchaseCreditNoteLineRecord.fromJson(Map<String, dynamic> json) {
    return PurchaseCreditNoteLineRecord(
      id: json['id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? 'Producto',
      productSku: json['product_sku']?.toString(),
      quantity: (json['credited_quantity'] as num?)?.round() ?? 0,
      netAmount: (json['net_amount'] as num?)?.round() ?? 0,
      taxAmount: (json['tax_amount'] as num?)?.round() ?? 0,
      totalAmount: (json['total_amount'] as num?)?.round() ?? 0,
      disposition: json['disposition']?.toString() ?? 'financial_only',
    );
  }
}

class PurchaseSupplierRefundRecord {
  const PurchaseSupplierRefundRecord({
    required this.id,
    required this.purchaseCreditNoteId,
    required this.number,
    required this.status,
    required this.refundedAt,
    required this.paymentMethodName,
    required this.amount,
    required this.reference,
    required this.reason,
    this.voidReason,
  });

  final String id;
  final String purchaseCreditNoteId;
  final String number;
  final String status;
  final DateTime refundedAt;
  final String paymentMethodName;
  final int amount;
  final String reference;
  final String reason;
  final String? voidReason;
  bool get canVoid => status == 'posted';

  factory PurchaseSupplierRefundRecord.fromJson(Map<String, dynamic> json) {
    final method = json['payment_methods'];
    final methodJson = method is Map
        ? Map<String, dynamic>.from(method)
        : const <String, dynamic>{};
    return PurchaseSupplierRefundRecord(
      id: json['id']?.toString() ?? '',
      purchaseCreditNoteId: json['purchase_credit_note_id']?.toString() ?? '',
      number: json['refund_number']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      refundedAt: DateTime.parse(json['refunded_at'].toString()),
      paymentMethodName: methodJson['name']?.toString() ?? 'Medio de pago',
      amount: (json['amount'] as num?)?.round() ?? 0,
      reference: json['reference']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      voidReason: json['void_reason']?.toString(),
    );
  }
}

class PurchaseRefundPaymentMethod {
  const PurchaseRefundPaymentMethod({
    required this.id,
    required this.name,
    required this.requiresReference,
  });

  final String id;
  final String name;
  final bool requiresReference;

  factory PurchaseRefundPaymentMethod.fromJson(Map<String, dynamic> json) =>
      PurchaseRefundPaymentMethod(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        requiresReference: json['requires_reference'] == true,
      );
}

class PurchaseSupplierRefundResult {
  const PurchaseSupplierRefundResult({
    required this.id,
    required this.number,
    required this.replayed,
  });

  final String id;
  final String number;
  final bool replayed;

  factory PurchaseSupplierRefundResult.fromJson(Map<String, dynamic> json) =>
      PurchaseSupplierRefundResult(
        id: json['refund_id']?.toString() ?? '',
        number: json['refund_number']?.toString() ?? '',
        replayed: json['replayed'] == true,
      );
}

class PurchaseCreditNoteResult {
  const PurchaseCreditNoteResult(
      {required this.id, required this.number, required this.replayed});
  final String id;
  final String number;
  final bool replayed;
  factory PurchaseCreditNoteResult.fromJson(Map<String, dynamic> json) =>
      PurchaseCreditNoteResult(
        id: json['purchase_credit_note_id']?.toString() ?? '',
        number: json['credit_note_number']?.toString() ?? '',
        replayed: json['replayed'] == true,
      );
}
