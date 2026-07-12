enum SalesCreditDisposition { financialOnly, salesReturn }

extension SalesCreditDispositionX on SalesCreditDisposition {
  String get databaseValue => switch (this) {
        SalesCreditDisposition.financialOnly => 'financial_only',
        SalesCreditDisposition.salesReturn => 'sales_return',
      };
}

class SalesCreditNoteLineBalance {
  const SalesCreditNoteLineBalance({
    required this.lineIndex,
    required this.sourceLineKey,
    required this.productName,
    this.productSku,
    required this.originalQuantity,
    required this.originalNet,
    required this.originalTax,
    required this.remainingQuantity,
    required this.remainingNet,
    required this.remainingTax,
  });
  final int lineIndex;
  final String sourceLineKey;
  final String productName;
  final String? productSku;
  final int originalQuantity;
  final int originalNet;
  final int originalTax;
  final int remainingQuantity;
  final int remainingNet;
  final int remainingTax;

  factory SalesCreditNoteLineBalance.fromJson(Map<String, dynamic> json) {
    int amount(String key) => (json[key] as num?)?.round() ?? 0;
    return SalesCreditNoteLineBalance(
      lineIndex: amount('source_line_index'),
      sourceLineKey: json['source_line_key']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? 'Producto',
      productSku: json['product_sku']?.toString(),
      originalQuantity: amount('original_quantity'),
      originalNet: amount('original_allocated_net'),
      originalTax: amount('original_allocated_tax'),
      remainingQuantity: amount('remaining_quantity'),
      remainingNet: amount('remaining_net'),
      remainingTax: amount('remaining_tax'),
    );
  }
}

class SalesCreditReturnOption {
  const SalesCreditReturnOption({
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

class SalesCreditNoteLineDraft {
  const SalesCreditNoteLineDraft({
    required this.balance,
    this.quantity = 0,
    this.netAmount = 0,
    this.taxAmount = 0,
    this.disposition = SalesCreditDisposition.financialOnly,
    this.salesReturnLineId,
  });
  final SalesCreditNoteLineBalance balance;
  final int quantity;
  final int netAmount;
  final int taxAmount;
  final SalesCreditDisposition disposition;
  final String? salesReturnLineId;
  int get totalAmount => netAmount + taxAmount;
  bool get isSelected => totalAmount > 0;

  SalesCreditNoteLineDraft withQuantity(int value) {
    final quantity = value.clamp(0, balance.remainingQuantity);
    final net = balance.originalQuantity == 0
        ? 0
        : (balance.originalNet * quantity / balance.originalQuantity).round();
    final tax = balance.originalNet == 0
        ? 0
        : (balance.originalTax * net / balance.originalNet).round();
    return copyWith(quantity: quantity, netAmount: net, taxAmount: tax);
  }

  String? validate({SalesCreditReturnOption? returnOption}) {
    if (!isSelected) return 'Indica un monto para ${balance.productName}.';
    if (quantity < 0 || quantity > balance.remainingQuantity) {
      return 'La cantidad de ${balance.productName} supera el saldo acreditable.';
    }
    if (netAmount < 0 ||
        taxAmount < 0 ||
        netAmount > balance.remainingNet ||
        taxAmount > balance.remainingTax) {
      return 'El monto de ${balance.productName} supera la factura original.';
    }
    if (disposition == SalesCreditDisposition.salesReturn) {
      if (salesReturnLineId == null || returnOption == null || quantity <= 0) {
        return 'Vincula la devolución física de ${balance.productName}.';
      }
      if (quantity > returnOption.remainingQuantity) {
        return 'La nota supera la devolución física vinculada.';
      }
    }
    return null;
  }

  SalesCreditNoteLineDraft copyWith({
    int? quantity,
    int? netAmount,
    int? taxAmount,
    SalesCreditDisposition? disposition,
    String? salesReturnLineId,
    bool clearSalesReturn = false,
  }) =>
      SalesCreditNoteLineDraft(
        balance: balance,
        quantity: quantity ?? this.quantity,
        netAmount: netAmount ?? this.netAmount,
        taxAmount: taxAmount ?? this.taxAmount,
        disposition: disposition ?? this.disposition,
        salesReturnLineId: clearSalesReturn
            ? null
            : salesReturnLineId ?? this.salesReturnLineId,
      );

  Map<String, dynamic> toRpcJson() => {
        'line_index': balance.lineIndex,
        'credited_quantity': quantity,
        'net_amount': netAmount,
        'tax_amount': taxAmount,
        'disposition': disposition.databaseValue,
        if (salesReturnLineId != null)
          'sales_return_line_id': salesReturnLineId,
      };
}

class SalesCreditNoteRecord {
  const SalesCreditNoteRecord({
    required this.id,
    required this.number,
    required this.status,
    required this.officialStatus,
    required this.issueDate,
    required this.reason,
    required this.totalAmount,
    this.voidReason,
  });
  final String id;
  final String number;
  final String status;
  final String officialStatus;
  final DateTime issueDate;
  final String reason;
  final int totalAmount;
  final String? voidReason;
  bool get canVoid => status == 'posted' && officialStatus != 'issued';

  factory SalesCreditNoteRecord.fromJson(Map<String, dynamic> json) =>
      SalesCreditNoteRecord(
        id: json['id']?.toString() ?? '',
        number: json['credit_note_number']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        officialStatus: json['official_dte_status']?.toString() ?? 'internal',
        issueDate: DateTime.parse(json['issue_date'].toString()),
        reason: json['reason']?.toString() ?? '',
        totalAmount: (json['total_amount'] as num?)?.round() ?? 0,
        voidReason: json['void_reason']?.toString(),
      );
}

class SalesCreditNoteResult {
  const SalesCreditNoteResult({
    required this.id,
    required this.number,
    required this.replayed,
  });
  final String id;
  final String number;
  final bool replayed;
  factory SalesCreditNoteResult.fromJson(Map<String, dynamic> json) =>
      SalesCreditNoteResult(
        id: json['sales_credit_note_id']?.toString() ?? '',
        number: json['credit_note_number']?.toString() ?? '',
        replayed: json['replayed'] == true,
      );
}
