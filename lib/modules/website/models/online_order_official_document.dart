/// Immutable evidence for a formal document associated with an online order.
///
/// The database ledger is the authority. This model deliberately keeps the
/// internal ERP sale separate from fiscal evidence and only exposes a browser
/// URI when the stored row has a complete, coherent official-document shape.
class OnlineOrderOfficialDocument {
  const OnlineOrderOfficialDocument({
    required this.id,
    required this.orderId,
    required this.documentKind,
    required this.provider,
    required this.providerDocumentId,
    required this.fiscalValidity,
    required this.amount,
    required this.currency,
    required this.issuedAt,
    required this.artifactUrl,
    required this.artifactSha256,
    required this.status,
    required this.recordedAt,
    this.paymentOperationId,
    this.documentType,
    this.folio,
  });

  final String id;
  final String orderId;
  final String documentKind;
  final String provider;
  final String providerDocumentId;
  final String? paymentOperationId;
  final String fiscalValidity;
  final String? documentType;
  final String? folio;
  final double amount;
  final String currency;
  final DateTime issuedAt;
  final String artifactUrl;
  final String artifactSha256;
  final String status;
  final DateTime recordedAt;

  bool get isMercadoPagoVoucherValidAsBoleta =>
      documentKind == 'payment_voucher' &&
      provider == 'mercadopago' &&
      fiscalValidity == 'voucher_valid_as_boleta' &&
      status == 'approved' &&
      paymentOperationId?.trim().isNotEmpty == true;

  bool get isOfficialChileanDte =>
      documentKind == 'tax_document' &&
      fiscalValidity == 'official_chilean_dte' &&
      const {'issued', 'accepted'}.contains(status) &&
      documentType?.trim().isNotEmpty == true &&
      folio?.trim().isNotEmpty == true;

  bool get isBoletaElectronica {
    final normalized = documentType
        ?.trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return isOfficialChileanDte &&
        normalized != null &&
        normalized.contains('boleta');
  }

  bool get hasVerifiedFiscalShape =>
      isMercadoPagoVoucherValidAsBoleta || isOfficialChileanDte;

  /// An artifact is actionable only when both its fiscal shape and immutable
  /// content fingerprint are complete, and its address is an HTTPS URL without
  /// embedded user-info. HTTP, URL user-info and malformed hashes fail closed.
  Uri? get verifiedArtifactUri {
    if (!hasVerifiedFiscalShape ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(artifactSha256)) {
      return null;
    }

    final normalizedUrl = artifactUrl.trim();
    if (RegExp(r'\s').hasMatch(normalizedUrl)) return null;
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  String get displayLabel {
    if (isMercadoPagoVoucherValidAsBoleta) {
      return 'Voucher Mercado Pago válido como boleta';
    }
    if (isBoletaElectronica) return 'Boleta electrónica (DTE)';
    if (isOfficialChileanDte) return 'Documento tributario electrónico (DTE)';
    return 'Documento formal no verificable';
  }

  String get referenceLabel {
    if (isMercadoPagoVoucherValidAsBoleta) {
      return 'Operación ${paymentOperationId!}';
    }
    if (folio?.trim().isNotEmpty == true) return 'Folio ${folio!.trim()}';
    return 'Documento $providerDocumentId';
  }

  factory OnlineOrderOfficialDocument.fromJson(Map<String, dynamic> json) {
    return OnlineOrderOfficialDocument(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      documentKind: json['document_kind'] as String,
      provider: json['provider'] as String,
      providerDocumentId: json['provider_document_id'] as String,
      paymentOperationId: json['payment_operation_id'] as String?,
      fiscalValidity: json['fiscal_validity'] as String,
      documentType: json['document_type'] as String?,
      folio: json['folio'] as String?,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      issuedAt: DateTime.parse(json['issued_at'] as String),
      artifactUrl: json['artifact_url'] as String,
      artifactSha256: json['artifact_sha256'] as String,
      status: json['status'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
    );
  }
}
