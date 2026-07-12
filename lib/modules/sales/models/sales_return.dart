import 'sales_models.dart';

enum SalesReturnDisposition { restock, quarantine, scrap }

extension SalesReturnDispositionX on SalesReturnDisposition {
  String get databaseValue => name;
  String get label => switch (this) {
        SalesReturnDisposition.restock => 'Reponer al stock',
        SalesReturnDisposition.quarantine => 'Enviar a inspección',
        SalesReturnDisposition.scrap => 'Dar de baja',
      };
}

class SalesReturnableLine {
  const SalesReturnableLine({
    required this.lineIndex,
    required this.productName,
    this.productSku,
    required this.soldQuantity,
    required this.returnedQuantity,
  });

  final int lineIndex;
  final String productName;
  final String? productSku;
  final int soldQuantity;
  final int returnedQuantity;
  int get remainingQuantity => soldQuantity - returnedQuantity;

  factory SalesReturnableLine.fromInvoiceItem(
    int lineIndex,
    InvoiceItem item,
    int returnedQuantity,
  ) =>
      SalesReturnableLine(
        lineIndex: lineIndex,
        productName: item.productName ?? 'Producto',
        productSku: item.productSku,
        soldQuantity: item.quantity.round(),
        returnedQuantity: returnedQuantity,
      );
}

class SalesReturnLineDraft {
  const SalesReturnLineDraft({
    required this.line,
    this.quantity = 0,
    this.disposition = SalesReturnDisposition.restock,
  });

  final SalesReturnableLine line;
  final int quantity;
  final SalesReturnDisposition disposition;
  bool get isSelected => quantity > 0;

  SalesReturnLineDraft copyWith({
    int? quantity,
    SalesReturnDisposition? disposition,
  }) =>
      SalesReturnLineDraft(
        line: line,
        quantity: quantity ?? this.quantity,
        disposition: disposition ?? this.disposition,
      );

  String? validate() {
    if (quantity <= 0) return 'Indica una cantidad para ${line.productName}.';
    if (quantity > line.remainingQuantity) {
      return 'La devolución de ${line.productName} supera lo vendido pendiente.';
    }
    return null;
  }

  Map<String, dynamic> toRpcJson() => {
        'line_index': line.lineIndex,
        'returned_quantity': quantity,
        'disposition': disposition.databaseValue,
      };
}

class SalesReturnHistoryLine {
  const SalesReturnHistoryLine({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.disposition,
    this.quarantineId,
    this.quarantineStatus,
    this.resolutionId,
  });

  final String id;
  final String productName;
  final int quantity;
  final String disposition;
  final String? quarantineId;
  final String? quarantineStatus;
  final String? resolutionId;
  bool get isHeld => quarantineStatus == 'held';
  bool get hasActiveResolution =>
      quarantineStatus == 'released' || quarantineStatus == 'scrapped';
}

class SalesReturnRecord {
  const SalesReturnRecord({
    required this.id,
    required this.number,
    required this.status,
    required this.returnedAt,
    required this.reason,
    required this.lines,
    this.voidReason,
  });

  final String id;
  final String number;
  final String status;
  final DateTime returnedAt;
  final String reason;
  final String? voidReason;
  final List<SalesReturnHistoryLine> lines;
  bool get canVoid => status == 'posted';
}

class SalesReturnResult {
  const SalesReturnResult({
    required this.id,
    required this.number,
    required this.replayed,
  });
  final String id;
  final String number;
  final bool replayed;

  factory SalesReturnResult.fromJson(Map<String, dynamic> json) =>
      SalesReturnResult(
        id: json['sales_return_id']?.toString() ?? '',
        number: json['return_number']?.toString() ?? '',
        replayed: json['replayed'] == true,
      );
}

class QuarantineResolutionResult {
  const QuarantineResolutionResult({
    required this.id,
    required this.disposition,
    required this.replayed,
  });
  final String id;
  final String disposition;
  final bool replayed;

  factory QuarantineResolutionResult.fromJson(Map<String, dynamic> json) =>
      QuarantineResolutionResult(
        id: json['resolution_id']?.toString() ?? '',
        disposition: json['disposition']?.toString() ?? '',
        replayed: json['replayed'] == true,
      );
}
