class OnlineOrderCorrectionLinePreview {
  const OnlineOrderCorrectionLinePreview({
    required this.lineIndex,
    required this.productName,
    this.productSku,
    required this.remainingQuantity,
    required this.remainingNet,
    required this.remainingTax,
    required this.remainingTotal,
    required this.isService,
    required this.physicalReturnAllowed,
  });

  final int lineIndex;
  final String productName;
  final String? productSku;
  final int remainingQuantity;
  final double remainingNet;
  final double remainingTax;
  final double remainingTotal;
  final bool isService;
  final bool physicalReturnAllowed;

  double amountForQuantity(int quantity) {
    if (remainingQuantity <= 0 || quantity <= 0) return 0;
    final boundedQuantity = quantity.clamp(0, remainingQuantity);
    final ratio = boundedQuantity / remainingQuantity;
    return (remainingNet * ratio).roundToDouble() +
        (remainingTax * ratio).roundToDouble();
  }

  factory OnlineOrderCorrectionLinePreview.fromJson(
    Map<String, dynamic> json,
  ) {
    return OnlineOrderCorrectionLinePreview(
      lineIndex: (json['line_index'] as num?)?.toInt() ?? -1,
      productName: json['product_name']?.toString() ?? 'Línea de venta',
      productSku: json['product_sku']?.toString(),
      remainingQuantity: (json['remaining_quantity'] as num?)?.toInt() ?? 0,
      remainingNet: (json['remaining_net'] as num?)?.toDouble() ?? 0,
      remainingTax: (json['remaining_tax'] as num?)?.toDouble() ?? 0,
      remainingTotal: (json['remaining_total'] as num?)?.toDouble() ?? 0,
      isService: json['is_service'] == true,
      physicalReturnAllowed: json['physical_return_allowed'] == true,
    );
  }
}

class OnlineOrderCorrectionPreview {
  const OnlineOrderCorrectionPreview({
    required this.orderId,
    required this.orderNumber,
    required this.orderVersion,
    required this.paymentMethod,
    required this.controlsReady,
    required this.controlModes,
    required this.lines,
  });

  final String orderId;
  final String orderNumber;
  final int orderVersion;
  final String? paymentMethod;
  final bool controlsReady;
  final Map<String, String> controlModes;
  final List<OnlineOrderCorrectionLinePreview> lines;

  bool get isMercadoPago =>
      paymentMethod?.trim().toLowerCase() == 'mercadopago';

  factory OnlineOrderCorrectionPreview.fromJson(Map<String, dynamic> json) {
    final rawModes = json['control_modes'];
    final rawLines = json['lines'];
    return OnlineOrderCorrectionPreview(
      orderId: json['order_id']?.toString() ?? '',
      orderNumber: json['order_number']?.toString() ?? '',
      orderVersion: (json['order_version'] as num?)?.toInt() ?? 0,
      paymentMethod: json['payment_method']?.toString(),
      controlsReady: json['controls_ready'] == true,
      controlModes: rawModes is Map
          ? rawModes.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
      lines: rawLines is List
          ? rawLines
              .whereType<Map>()
              .map(
                (line) => OnlineOrderCorrectionLinePreview.fromJson(
                  Map<String, dynamic>.from(line),
                ),
              )
              .toList(growable: false)
          : const [],
    );
  }
}

class OnlineOrderCorrectionRecord {
  const OnlineOrderCorrectionRecord({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.provider,
    required this.providerState,
    required this.processingState,
    required this.correctionIntent,
    this.lastErrorMessage,
  });

  final String id;
  final String orderId;
  final double amount;
  final String provider;
  final String providerState;
  final String processingState;
  final String correctionIntent;
  final String? lastErrorMessage;

  bool get isApplied => processingState == 'applied';
  bool get needsManualEvidence =>
      provider == 'manual' && providerState != 'succeeded';

  factory OnlineOrderCorrectionRecord.fromJson(Map<String, dynamic> json) {
    return OnlineOrderCorrectionRecord(
      id: (json['id'] ?? json['correction_id'])?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? '',
      amount: (json['requested_amount'] as num?)?.toDouble() ?? 0,
      provider: json['provider']?.toString() ?? 'manual',
      providerState: json['provider_state']?.toString() ?? 'pending',
      processingState:
          json['processing_state']?.toString() ?? 'provider_pending',
      correctionIntent: json['correction_intent']?.toString() ?? 'return',
      lastErrorMessage: json['last_error_message']?.toString(),
    );
  }
}

class OnlineOrderCorrectionLineRequest {
  const OnlineOrderCorrectionLineRequest({
    required this.lineIndex,
    required this.quantity,
    required this.disposition,
  });

  final int lineIndex;
  final int quantity;
  final String disposition;

  Map<String, dynamic> toJson() => {
        'line_index': lineIndex,
        'quantity': quantity,
        'disposition': disposition,
      };
}
