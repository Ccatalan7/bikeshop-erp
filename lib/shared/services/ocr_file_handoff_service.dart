import 'package:flutter/foundation.dart';

enum OcrFileHandoffTarget {
  quickExpense,
  purchaseInvoice,
}

class OcrFileHandoffPayload {
  const OcrFileHandoffPayload({
    required this.id,
    required this.target,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.extension,
    this.sourceFileId,
    this.sourceLabel,
    this.sourceSupplierId,
    this.sourceSupplierName,
    this.sourceSupplierWebsite,
  });

  final String id;
  final OcrFileHandoffTarget target;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  final String extension;
  final String? sourceFileId;
  final String? sourceLabel;
  final String? sourceSupplierId;
  final String? sourceSupplierName;
  final String? sourceSupplierWebsite;
}

class OcrFileHandoffService extends ChangeNotifier {
  OcrFileHandoffPayload? _pending;
  int _sequence = 0;

  bool hasPendingFor(OcrFileHandoffTarget target) => _pending?.target == target;

  void queue({
    required OcrFileHandoffTarget target,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    required String extension,
    String? sourceFileId,
    String? sourceLabel,
    String? sourceSupplierId,
    String? sourceSupplierName,
    String? sourceSupplierWebsite,
  }) {
    _pending = OcrFileHandoffPayload(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      target: target,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      extension: extension,
      sourceFileId: sourceFileId,
      sourceLabel: sourceLabel,
      sourceSupplierId: sourceSupplierId,
      sourceSupplierName: sourceSupplierName,
      sourceSupplierWebsite: sourceSupplierWebsite,
    );
    notifyListeners();
  }

  OcrFileHandoffPayload? take(OcrFileHandoffTarget target) {
    final payload = _pending;
    if (payload == null || payload.target != target) return null;
    _pending = null;
    notifyListeners();
    return payload;
  }
}
