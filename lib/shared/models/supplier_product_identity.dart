class SupplierProductAliasRecord {
  const SupplierProductAliasRecord({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.productId,
    required this.listingId,
    required this.variantKey,
    required this.replayed,
    this.normalizedTitle,
    this.normalizedModel,
    this.imageUrl,
    this.imageContentHash,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String supplierId;
  final String supplierName;
  final String productId;
  final String listingId;
  final String variantKey;
  final bool replayed;
  final String? normalizedTitle;
  final String? normalizedModel;
  final String? imageUrl;
  final String? imageContentHash;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SupplierProductAliasRecord.fromJson(Map<String, dynamic> json) {
    return SupplierProductAliasRecord(
      id: _requiredString(json, 'id'),
      supplierId: _requiredString(json, 'supplier_id'),
      supplierName: _requiredString(json, 'supplier_name'),
      productId: _requiredString(json, 'product_id'),
      listingId: _requiredString(json, 'listing_id'),
      variantKey: _requiredString(json, 'variant_key'),
      replayed: json['replayed'] == true,
      normalizedTitle: _optionalString(json['normalized_title']),
      normalizedModel: _optionalString(json['normalized_model']),
      imageUrl: _optionalString(json['image_url']),
      imageContentHash: _optionalString(json['image_content_hash']),
      createdAt: _optionalDate(json['created_at']),
      updatedAt: _optionalDate(json['updated_at']),
    );
  }
}

class AliExpressSkuReservation {
  const AliExpressSkuReservation({
    required this.receiptId,
    required this.supplierId,
    required this.supplierName,
    required this.operationKey,
    required this.requestedCount,
    required this.firstSequence,
    required this.lastSequence,
    required this.skus,
    required this.replayed,
    this.createdAt,
  });

  final String receiptId;
  final String supplierId;
  final String supplierName;
  final String operationKey;
  final int requestedCount;
  final int firstSequence;
  final int lastSequence;
  final List<String> skus;
  final bool replayed;
  final DateTime? createdAt;

  factory AliExpressSkuReservation.fromJson(Map<String, dynamic> json) {
    final rawSkus = json['skus'];
    if (rawSkus is! List) {
      throw const FormatException('SKU reservation response has no SKU list.');
    }

    final skus = rawSkus
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final requestedCount = _requiredInt(json, 'requested_count');
    if (skus.length != requestedCount) {
      throw const FormatException(
        'SKU reservation response count does not match its SKU list.',
      );
    }

    return AliExpressSkuReservation(
      receiptId: _requiredString(json, 'id'),
      supplierId: _requiredString(json, 'supplier_id'),
      supplierName: _requiredString(json, 'supplier_name'),
      operationKey: _requiredString(json, 'operation_key'),
      requestedCount: requestedCount,
      firstSequence: _requiredInt(json, 'first_sequence'),
      lastSequence: _requiredInt(json, 'last_sequence'),
      skus: List.unmodifiable(skus),
      replayed: json['replayed'] == true,
      createdAt: _optionalDate(json['created_at']),
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw FormatException('Missing required response field: $key');
  }
  return value;
}

String? _optionalString(dynamic value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null) {
    throw FormatException('Missing numeric response field: $key');
  }
  return parsed;
}

DateTime? _optionalDate(dynamic value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : DateTime.tryParse(normalized);
}
