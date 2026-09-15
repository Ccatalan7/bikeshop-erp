import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/supplier_variant_resolution.dart';
import 'database_service.dart';

typedef SupplierVariantResolutionRpc = Future<dynamic> Function(
  String functionName,
  Map<String, dynamic> params,
);

/// Client boundary for revisioned supplier-variant resolution authority.
///
/// The service accepts only immutable `sku:`/`props:` keys and returns usable
/// edges only after the response proves an active graph for the exact option
/// evidence submitted by the caller.
final class SupplierVariantResolutionService {
  SupplierVariantResolutionService({
    DatabaseService? database,
    SupplierVariantResolutionRpc? rpc,
  }) : _rpc = rpc ?? _databaseRpc(database);

  final SupplierVariantResolutionRpc _rpc;

  Future<SupplierVariantResolution> resolve({
    required String supplierId,
    required String itemId,
    required String productUrl,
    required SupplierOptionEvidence optionEvidence,
  }) async {
    final supplier = _requiredText(supplierId, 'supplierId');
    final immutableKey = optionEvidence.variantKey;
    final evidenceHash = optionEvidence.sha256Hex;
    final result = await _rpc(
      'resolve_supplier_variant_resolution',
      <String, dynamic>{
        'p_supplier_id': supplier,
        'p_item_id': itemId.trim(),
        'p_product_url': productUrl.trim(),
        'p_variant_key': immutableKey.value,
        'p_option_evidence_hash': evidenceHash,
        'p_option_pack_count': optionEvidence.packCount,
        'p_option_unit_class': optionEvidence.unitClass,
        'p_pack_evidence_conflict': optionEvidence.packEvidenceConflict,
      },
    );
    if (result == null) return SupplierVariantResolution.notFound();
    if (result is! Map) {
      return SupplierVariantResolution.invalid(
        'Supplier resolution RPC returned a non-object response.',
      );
    }
    final resolution = SupplierVariantResolution.fromLookupJson(
      _map(result),
    );
    return _matchesRequestedEvidence(
      resolution,
      supplierId: supplier,
      optionEvidence: optionEvidence,
    );
  }

  Future<SupplierVariantResolution> remember({
    required String operationId,
    required String supplierId,
    required String itemId,
    required String productUrl,
    required SupplierOptionEvidence optionEvidence,
    required SupplierVariantResolutionAction action,
    SupplierVariantResolutionKind? kind,
    List<SupplierVariantResolutionEdge> edges = const [],
    String? expectedPriorRevisionId,
    String? correctionReason,
    SupplierVariantResolutionDecisionSource decisionSource =
        SupplierVariantResolutionDecisionSource.operatorConfirmed,
    required Map<String, dynamic> decisionEvidence,
  }) async {
    final operation = _requiredText(operationId, 'operationId');
    final supplier = _requiredText(supplierId, 'supplierId');
    final immutableKey = optionEvidence.variantKey;
    final evidenceHash = optionEvidence.sha256Hex;
    final normalizedReason = _nullableText(correctionReason);

    if (decisionEvidence.isEmpty ||
        _containsForbiddenSnapshotKey(decisionEvidence) ||
        utf8.encode(jsonEncode(decisionEvidence)).length > 16384 ||
        !_validDecisionEvidence(decisionSource, decisionEvidence)) {
      throw ArgumentError(
        'Bounded, sanitized decision evidence is required.',
      );
    }

    if (action == SupplierVariantResolutionAction.activate &&
        optionEvidence.packEvidenceConflict) {
      throw ArgumentError(
        'Conflicting supplier pack evidence cannot establish authority.',
      );
    }

    if (action == SupplierVariantResolutionAction.activate) {
      if (kind == null) {
        throw ArgumentError.value(kind, 'kind', 'Activation requires a kind.');
      }
      final graphFailure = SupplierVariantResolution.validateGraph(
        kind: kind,
        edges: edges,
      );
      if (graphFailure != null) {
        throw ArgumentError.value(edges, 'edges', graphFailure);
      }
    } else if (kind != null || edges.isNotEmpty) {
      throw ArgumentError(
        'A revoked supplier resolution cannot contain a kind or edges.',
      );
    }

    final result = await _rpc(
      'remember_supplier_variant_resolution',
      <String, dynamic>{
        'p_operation_id': operation,
        'p_supplier_id': supplier,
        'p_item_id': itemId.trim(),
        'p_product_url': productUrl.trim(),
        'p_variant_key': immutableKey.value,
        'p_option_evidence_hash': evidenceHash,
        'p_option_pack_count': optionEvidence.packCount,
        'p_option_unit_class': optionEvidence.unitClass,
        'p_pack_evidence_conflict': optionEvidence.packEvidenceConflict,
        'p_action': action.name,
        'p_resolution_kind': kind?.name,
        'p_edges':
            edges.map((edge) => edge.toRpcJson()).toList(growable: false),
        'p_expected_prior_revision_id': _nullableText(
          expectedPriorRevisionId,
        ),
        'p_correction_reason': normalizedReason,
        'p_decision_source': decisionSource.databaseValue,
        'p_decision_evidence': decisionEvidence,
      },
    );
    if (result is! Map) {
      throw SupplierResolutionCommittedUnverifiedException(operation);
    }
    final resolution = SupplierVariantResolution.fromRememberJson(_map(result));
    final verified = _matchesRequestedEvidence(
      resolution,
      supplierId: supplier,
      optionEvidence: optionEvidence,
    );

    if (!_rememberedReceiptMatches(
      verified,
      supplierId: supplier,
      operationId: operation,
      optionEvidence: optionEvidence,
      decisionSource: decisionSource,
      decisionEvidence: decisionEvidence,
    )) {
      throw SupplierResolutionCommittedUnverifiedException(operation);
    }

    if (action == SupplierVariantResolutionAction.revoke) {
      if (verified.status != SupplierVariantResolutionStatus.revoked ||
          verified.authoritative ||
          verified.edges.isNotEmpty ||
          verified.operationId != operation) {
        throw SupplierResolutionCommittedUnverifiedException(operation);
      }
      return verified;
    }
    if (!verified.isResolved ||
        verified.kind != kind ||
        !_sameEdges(verified.edges, edges)) {
      throw SupplierResolutionCommittedUnverifiedException(operation);
    }
    return verified;
  }

  Future<SupplierInvoiceSourceResolution> prepareInvoiceSource({
    required String operationId,
    required SupplierVariantResolution resolution,
    required String sourceLineKey,
    required int sourceRowIndex,
    required DateTime sourceDocumentDate,
    required double sourcePurchaseQuantity,
    required int sourceLineTotalMinor,
    required String currencyCode,
    required List<String> sourceOrderNumbers,
    required String sourceTitle,
    required SupplierOptionEvidence optionEvidence,
    String? selectedOption,
    Map<String, dynamic> sourceSnapshot = const <String, dynamic>{},
  }) async {
    final operation = _requiredText(operationId, 'operationId');
    final lineKey = _requiredText(sourceLineKey, 'sourceLineKey');
    final title = _requiredText(sourceTitle, 'sourceTitle');
    final normalizedSelectedOption = _nullableText(selectedOption);
    final currency = currencyCode.trim().toUpperCase();
    final sourceDocumentDateWire = _canonicalSourceDate(
      sourceDocumentDate,
      'sourceDocumentDate',
    );
    if (!resolution.isResolved ||
        resolution.revisionId == null ||
        resolution.listingId == null ||
        resolution.variantKey == null ||
        resolution.optionEvidenceHash == null) {
      throw ArgumentError.value(
        resolution,
        'resolution',
        'An exact active supplier resolution is required.',
      );
    }
    if (optionEvidence.packEvidenceConflict) {
      throw ArgumentError(
        'Conflicting supplier pack evidence cannot be applied to an invoice.',
      );
    }
    if (resolution.variantKey != optionEvidence.variantKey ||
        resolution.optionEvidenceHash != optionEvidence.sha256Hex) {
      throw ArgumentError(
        'Source option evidence does not match the active supplier revision.',
      );
    }
    if (lineKey.length > 512 || sourceRowIndex < 0) {
      throw ArgumentError('Source-line identity is invalid.');
    }
    if (!_positiveWithAtMostSixDecimals(sourcePurchaseQuantity) ||
        sourceLineTotalMinor < 0 ||
        currency != 'CLP') {
      throw ArgumentError('Source quantity, total, or currency is invalid.');
    }
    if (title.length > 2000 || (normalizedSelectedOption?.length ?? 0) > 1000) {
      throw ArgumentError('Supplier source text exceeds its safe limit.');
    }

    final orders = sourceOrderNumbers.map((value) => value.trim()).toList()
      ..sort();
    if (orders.isEmpty ||
        orders.length > 64 ||
        orders.any((value) => value.isEmpty || value.length > 128) ||
        orders.toSet().length != orders.length) {
      throw ArgumentError('Supplier order numbers must be distinct and valid.');
    }
    if (_containsForbiddenSnapshotKey(sourceSnapshot)) {
      throw ArgumentError(
        'Supplier source snapshot contains a forbidden sensitive field.',
      );
    }
    final snapshot = <String, dynamic>{
      ...sourceSnapshot,
      'listing_id': resolution.listingId!.toLowerCase(),
      'variant_key': optionEvidence.variantKey.value,
      'option_evidence_hash': optionEvidence.sha256Hex,
      'source_row_index': sourceRowIndex,
      'source_line_key': lineKey,
      'source_document_date': sourceDocumentDateWire,
      'source_order_numbers': orders,
      'source_title': title,
      'selected_option': normalizedSelectedOption,
      'raw_pack_count': optionEvidence.packCount,
      'raw_unit_code': optionEvidence.rawUnitToken,
      'option_unit_class': optionEvidence.unitClass,
      'pack_evidence_conflict': optionEvidence.packEvidenceConflict,
      'source_purchase_quantity': sourcePurchaseQuantity,
      'source_line_total_minor': sourceLineTotalMinor,
      'currency_code': currency,
    };
    if (utf8.encode(jsonEncode(snapshot)).length > 32768) {
      throw ArgumentError('Supplier source snapshot exceeds 32 KiB.');
    }

    final result = await _rpc(
      'prepare_purchase_invoice_source_resolution',
      <String, dynamic>{
        'p_operation_id': operation,
        'p_revision_id': resolution.revisionId,
        'p_source_line_key': lineKey,
        'p_source_row_index': sourceRowIndex,
        'p_source_purchase_quantity': sourcePurchaseQuantity,
        'p_source_line_total_minor': sourceLineTotalMinor,
        'p_currency_code': currency,
        'p_source_order_numbers': orders,
        'p_source_title': title,
        'p_selected_option': normalizedSelectedOption,
        'p_raw_pack_count': optionEvidence.packCount,
        'p_raw_unit_token': optionEvidence.rawUnitToken,
        'p_pack_evidence_conflict': optionEvidence.packEvidenceConflict,
        'p_source_snapshot': snapshot,
      },
    );
    if (result is! Map) {
      throw SupplierSourceResolutionCommittedUnverifiedException(operation);
    }
    try {
      final prepared = SupplierInvoiceSourceResolution.fromJson(_map(result));
      if (prepared.operationId != operation ||
          prepared.resolutionRevisionId != resolution.revisionId ||
          prepared.sourceLineKey != lineKey ||
          prepared.sourceRowIndex != sourceRowIndex ||
          prepared.supplierListingId != resolution.listingId!.toLowerCase() ||
          prepared.supplierVariantKey != optionEvidence.variantKey ||
          prepared.optionEvidenceHash != optionEvidence.sha256Hex ||
          prepared.sourcePurchaseQuantity != sourcePurchaseQuantity ||
          prepared.sourceLineTotalMinor != sourceLineTotalMinor ||
          prepared.currencyCode != currency ||
          !_sameStrings(prepared.sourceOrderNumbers, orders) ||
          prepared.sourceTitle != title ||
          prepared.selectedOption != normalizedSelectedOption ||
          prepared.rawPackCount != optionEvidence.packCount ||
          prepared.rawUnitToken != optionEvidence.rawUnitToken ||
          prepared.optionUnitClass != optionEvidence.unitClass ||
          prepared.packEvidenceConflict !=
              optionEvidence.packEvidenceConflict ||
          !_deepJsonEqual(prepared.sourceSnapshot, snapshot) ||
          !_samePreparedComponents(prepared.components, resolution.edges)) {
        throw const FormatException(
          'Prepared source receipt does not match the requested evidence.',
        );
      }
      return prepared;
    } on FormatException {
      throw SupplierSourceResolutionCommittedUnverifiedException(operation);
    }
  }

  /// Stable source identity derived only from document and supplier-owned row
  /// identity. Display labels and cleaned names cannot change this key.
  static String buildSourceLineKey({
    required String supplierId,
    required DateTime sourceDate,
    required List<String> sourceOrderNumbers,
    required String listingId,
    required SupplierImmutableVariantKey variantKey,
    String? commercialSplitKey,
  }) {
    final supplier = _requiredText(supplierId, 'supplierId').toLowerCase();
    final listing = _requiredText(listingId, 'listingId').toLowerCase();
    final orders = sourceOrderNumbers.map((value) => value.trim()).toList()
      ..sort();
    if (orders.isEmpty ||
        orders.any((value) => value.isEmpty || value.length > 128) ||
        orders.toSet().length != orders.length) {
      throw ArgumentError('Source order numbers must be distinct and valid.');
    }
    final normalizedDate = _canonicalSourceDate(sourceDate, 'sourceDate');
    final wire = jsonEncode(<String, dynamic>{
      'schema': 'supplier_source_line_v1',
      'supplier_id': supplier,
      'source_date': normalizedDate,
      'source_order_numbers': orders,
      'listing_id': listing,
      'variant_key': variantKey.value,
      if (_nullableText(commercialSplitKey) != null)
        'commercial_split_key': _nullableText(commercialSplitKey),
    });
    return 'supplier-line-v1:${sha256.convert(utf8.encode(wire))}';
  }

  SupplierVariantResolution _matchesRequestedEvidence(
    SupplierVariantResolution resolution, {
    required String supplierId,
    required SupplierOptionEvidence optionEvidence,
  }) {
    if (!resolution.isResolved) return resolution;
    if (resolution.variantKey != optionEvidence.variantKey ||
        resolution.optionEvidenceHash != optionEvidence.sha256Hex ||
        resolution.optionPackCount != optionEvidence.packCount ||
        resolution.optionUnitClass != optionEvidence.unitClass ||
        resolution.packEvidenceConflict !=
            optionEvidence.packEvidenceConflict ||
        (resolution.supplierId != null &&
            resolution.supplierId!.toLowerCase() != supplierId.toLowerCase())) {
      return SupplierVariantResolution.invalid(
        'Supplier resolution response does not match requested evidence.',
      );
    }
    return resolution;
  }

  static bool _rememberedReceiptMatches(
    SupplierVariantResolution resolution, {
    required String supplierId,
    required String operationId,
    required SupplierOptionEvidence optionEvidence,
    required SupplierVariantResolutionDecisionSource decisionSource,
    required Map<String, dynamic> decisionEvidence,
  }) =>
      resolution.operationId == operationId &&
      resolution.variantKey == optionEvidence.variantKey &&
      resolution.optionEvidenceHash == optionEvidence.sha256Hex &&
      resolution.optionPackCount == optionEvidence.packCount &&
      resolution.optionUnitClass == optionEvidence.unitClass &&
      resolution.packEvidenceConflict == optionEvidence.packEvidenceConflict &&
      resolution.decisionSource == decisionSource.databaseValue &&
      resolution.decisionEvidenceHash != null &&
      _deepJsonEqual(resolution.decisionEvidence, decisionEvidence) &&
      (resolution.supplierId == null ||
          resolution.supplierId!.toLowerCase() == supplierId.toLowerCase());

  static SupplierVariantResolutionRpc _databaseRpc(DatabaseService? database) {
    if (database == null) {
      throw ArgumentError('A DatabaseService or RPC adapter is required.');
    }
    return (functionName, params) => database.rpc(functionName, params: params);
  }

  static bool _sameEdges(
    List<SupplierVariantResolutionEdge> received,
    List<SupplierVariantResolutionEdge> requested,
  ) {
    if (received.length != requested.length) return false;
    final expected = [...requested]
      ..sort((left, right) => left.position.compareTo(right.position));
    for (var index = 0; index < received.length; index += 1) {
      final actual = received[index];
      final wanted = expected[index];
      if (actual.position != wanted.position ||
          actual.productId.toLowerCase() != wanted.productId.toLowerCase() ||
          actual.catalogUnitsPerPurchase != wanted.catalogUnitsPerPurchase ||
          actual.allocationRatio != wanted.allocationRatio ||
          actual.componentRole.toLowerCase() !=
              wanted.componentRole.toLowerCase()) {
        return false;
      }
    }
    return true;
  }

  static bool _samePreparedComponents(
    List<SupplierInvoiceSourceComponent> received,
    List<SupplierVariantResolutionEdge> authoritative,
  ) {
    if (received.length != authoritative.length) return false;
    final expected = [...authoritative]
      ..sort((left, right) => left.position.compareTo(right.position));
    for (var index = 0; index < received.length; index += 1) {
      final actual = received[index];
      final wanted = expected[index];
      if (wanted.id == null ||
          actual.revisionEdgeId.toLowerCase() != wanted.id!.toLowerCase() ||
          actual.position != wanted.position ||
          actual.productId.toLowerCase() != wanted.productId.toLowerCase() ||
          actual.catalogUnitsPerPurchase != wanted.catalogUnitsPerPurchase ||
          actual.allocationRatio != wanted.allocationRatio ||
          actual.componentRole.toLowerCase() !=
              wanted.componentRole.toLowerCase()) {
        return false;
      }
    }
    return true;
  }
}

bool _deepJsonEqual(Object? left, Object? right) {
  if (left is num && right is num) return left == right;
  if (left is Map && right is Map) {
    final leftMap = <String, Object?>{
      for (final entry in left.entries) entry.key.toString(): entry.value,
    };
    final rightMap = <String, Object?>{
      for (final entry in right.entries) entry.key.toString(): entry.value,
    };
    if (leftMap.length != rightMap.length ||
        !leftMap.keys.every(rightMap.containsKey)) {
      return false;
    }
    return leftMap.entries.every(
      (entry) => _deepJsonEqual(entry.value, rightMap[entry.key]),
    );
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (!_deepJsonEqual(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class SupplierResolutionCommittedUnverifiedException
    implements Exception {
  const SupplierResolutionCommittedUnverifiedException(this.operationId);

  final String operationId;

  @override
  String toString() =>
      'Supplier resolution may be committed, but its receipt could not be '
      'verified (operation $operationId).';
}

final class SupplierSourceResolutionCommittedUnverifiedException
    implements Exception {
  const SupplierSourceResolutionCommittedUnverifiedException(this.operationId);

  final String operationId;

  @override
  String toString() =>
      'Supplier source resolution may be staged, but its receipt could not be '
      'verified (operation $operationId).';
}

String _requiredText(String raw, String name) {
  final value = raw.trim();
  if (value.isEmpty) throw ArgumentError.value(raw, name, 'Cannot be empty.');
  return value;
}

String? _nullableText(String? raw) {
  final value = raw?.trim();
  return value == null || value.isEmpty ? null : value;
}

Map<String, dynamic> _map(Map<dynamic, dynamic> value) =>
    value.map((key, raw) => MapEntry(key.toString(), raw));

bool _positiveWithAtMostSixDecimals(double value) {
  if (!value.isFinite || value <= 0 || value > 1000000000) return false;
  final match = RegExp(r'^[0-9]+(?:\.([0-9]+))?$').firstMatch(value.toString());
  return match != null && (match.group(1)?.length ?? 0) <= 6;
}

bool _containsForbiddenSnapshotKey(Object? value) {
  const forbidden = <String>{
    'email',
    'phone',
    'address',
    'recipient',
    'buyer',
    'credential',
    'cookie',
    'token',
    'authorization',
    'payment',
    'card',
  };
  if (value is Map) {
    for (final entry in value.entries) {
      if (forbidden.contains(entry.key.toString().toLowerCase()) ||
          _containsForbiddenSnapshotKey(entry.value)) {
        return true;
      }
    }
  } else if (value is Iterable) {
    return value.any(_containsForbiddenSnapshotKey);
  }
  return false;
}

bool _validDecisionEvidence(
  SupplierVariantResolutionDecisionSource source,
  Map<String, dynamic> evidence,
) {
  final modelVersion = evidence['model_version'];
  if (modelVersion != null && !_boundedText(modelVersion, 1, 128)) {
    return false;
  }
  switch (source) {
    case SupplierVariantResolutionDecisionSource.operatorConfirmed:
    case SupplierVariantResolutionDecisionSource.invoiceConfirmed:
      if (!_boundedText(evidence['source_line_key'], 1, 512) ||
          !_validDate(evidence['source_document_date']) ||
          !_validOrderNumbers(evidence['supplier_order_numbers']) ||
          !_positiveWithAtMostSixDecimals(
            _number(evidence['source_purchase_quantity']) ?? double.nan,
          ) ||
          !_positiveWithAtMostSixDecimals(
            _number(evidence['persisted_quantity']) ?? double.nan,
          ) ||
          !_minorTotal(evidence['source_total_minor']) ||
          !_minorTotal(evidence['persisted_total_minor']) ||
          evidence['currency_code']?.toString() != 'CLP') {
        return false;
      }
      if (source == SupplierVariantResolutionDecisionSource.operatorConfirmed) {
        return _boundedText(evidence['confirmation_surface'], 1, 128);
      }
      return _uuidPattern.hasMatch(
        evidence['purchase_invoice_id']?.toString() ?? '',
      );
    case SupplierVariantResolutionDecisionSource.administrativeCorrection:
      return _boundedText(evidence['actor_note'], 1, 2000);
    case SupplierVariantResolutionDecisionSource.migrationConfirmed:
      return RegExp(r'^[0-9]{14}$')
              .hasMatch(evidence['migration_version']?.toString() ?? '') &&
          _boundedText(evidence['source_reference'], 1, 512) &&
          _boundedText(evidence['actor_note'], 1, 2000);
  }
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
  r'[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

bool _boundedText(Object? value, int minimum, int maximum) {
  if (value is! String) return false;
  final text = value.trim();
  return text.length >= minimum && text.length <= maximum;
}

bool _validDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return false;
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  return parsed != null && parsed.toIso8601String().startsWith(value);
}

String _canonicalSourceDate(DateTime value, String argumentName) {
  if (value.year < 1 || value.year > 9999) {
    throw ArgumentError.value(
      value,
      argumentName,
      'Source document date must use a four-digit year.',
    );
  }
  final normalized = DateTime(value.year, value.month, value.day)
      .toIso8601String()
      .substring(0, 10);
  if (!_validDate(normalized)) {
    throw ArgumentError.value(
      value,
      argumentName,
      'Source document date is invalid.',
    );
  }
  return normalized;
}

bool _validOrderNumbers(Object? value) {
  if (value is! List || value.isEmpty || value.length > 64) return false;
  final normalized = <String>{};
  for (final order in value) {
    if (order is! String ||
        order.trim().isEmpty ||
        order.trim().length > 128 ||
        !normalized.add(order.trim())) {
      return false;
    }
  }
  return true;
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

bool _minorTotal(Object? value) {
  if (value is int) return value >= 0 && value.toString().length <= 18;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value >= 0 && value.toInt().toString().length <= 18;
  }
  return RegExp(r'^[0-9]{1,18}$').hasMatch(value?.toString() ?? '');
}
