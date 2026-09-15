import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The only supplier keys that can carry product-identity authority.
///
/// Human option labels are deliberately excluded. A key is either the
/// supplier's immutable SKU or an ordered tuple of immutable property IDs.
final class SupplierImmutableVariantKey {
  SupplierImmutableVariantKey._(this.value);

  static final RegExp _skuPattern = RegExp(
    r'^sku:[a-z0-9][a-z0-9._-]{1,507}$',
  );
  static final RegExp _propertyPattern = RegExp(
    r'^[a-z0-9._-]+:[a-z0-9._-]+$',
  );

  final String value;

  bool get isSupplierSku => value.startsWith('sku:');
  bool get isPropertyTuple => value.startsWith('props:');

  static SupplierImmutableVariantKey parse(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.length > 512) {
      throw const FormatException('Supplier variant key is too long.');
    }
    if (_skuPattern.hasMatch(value)) {
      return SupplierImmutableVariantKey._(value);
    }
    if (!value.startsWith('props:')) {
      throw const FormatException(
        'An immutable sku: or props: supplier variant key is required.',
      );
    }

    final parts = value.substring('props:'.length).split('|');
    if (parts.isEmpty ||
        parts.any((part) => !_propertyPattern.hasMatch(part))) {
      throw const FormatException('Supplier property tuple is invalid.');
    }
    final propertyIds = <String>{};
    for (final part in parts) {
      if (!propertyIds.add(part.split(':').first)) {
        throw const FormatException(
          'Supplier property tuple repeats a property ID.',
        );
      }
    }
    parts.sort((left, right) {
      final leftParts = left.split(':');
      final rightParts = right.split(':');
      final propertyOrder = leftParts.first.compareTo(rightParts.first);
      return propertyOrder != 0
          ? propertyOrder
          : leftParts.last.compareTo(rightParts.last);
    });
    final canonical = 'props:${parts.join('|')}';
    if (canonical.length > 512) {
      throw const FormatException('Supplier variant key is too long.');
    }
    return SupplierImmutableVariantKey._(canonical);
  }

  static SupplierImmutableVariantKey? tryParse(Object? raw) {
    if (raw == null) return null;
    try {
      return parse(raw.toString());
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is SupplierImmutableVariantKey && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

String normalizeSupplierOptionEvidenceHash(String raw) {
  final normalized =
      raw.trim().toLowerCase().replaceFirst(RegExp(r'^sha-?256:'), '');
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(normalized)) {
    throw const FormatException(
      'Option evidence must be a SHA-256 hex digest.',
    );
  }
  return normalized;
}

/// Supplier-owned option evidence used to bind one immutable resolution.
///
/// Localized/human labels such as `Black` and `Negro` are intentionally absent
/// because they are not immutable option identity. Package semantics are
/// explicit: changing `2PCS` to `1PCS` changes the hash, while harmless label
/// translation does not. A conflict remains evidence and is never interpreted
/// as an authoritative pack count.
final class SupplierOptionEvidence {
  SupplierOptionEvidence({
    required String variantKey,
    this.packCount,
    String? rawUnitToken,
    this.packEvidenceConflict = false,
  })  : variantKey = SupplierImmutableVariantKey.parse(variantKey),
        rawUnitToken = normalizeRawUnitToken(rawUnitToken),
        unitClass = normalizeUnitClass(rawUnitToken) {
    if (packCount != null && (packCount! <= 0 || packCount! > 1000000)) {
      throw ArgumentError.value(
        packCount,
        'packCount',
        'Pack count must be a positive integer.',
      );
    }
    if (packCount == null && unitClass != 'unknown') {
      throw ArgumentError(
        'A supplier unit class without a pack count is contradictory.',
      );
    }
  }

  final SupplierImmutableVariantKey variantKey;
  final int? packCount;
  final String? rawUnitToken;
  final String unitClass;
  final bool packEvidenceConflict;

  /// A supplier package may be applied as one ordinary catalog unit only when
  /// the evidence explicitly says one piece/unit. A pair, set, box, or unknown
  /// supplier unit still needs a confirmed resolution graph even when its
  /// numeric count is one.
  bool get requiresExplicitComposition {
    return requiresExplicitCompositionFor(
      packCount: packCount,
      rawUnitToken: rawUnitToken,
      packEvidenceConflict: packEvidenceConflict,
    );
  }

  static bool requiresExplicitCompositionFor({
    required int? packCount,
    required String? rawUnitToken,
    required bool packEvidenceConflict,
  }) {
    if (packEvidenceConflict) return true;
    final count = packCount;
    if (count == null) return false;
    if (count != 1) return true;
    final unitClass = normalizeUnitClass(rawUnitToken);
    return unitClass != 'piece' && unitClass != 'unit';
  }

  String get canonicalJson {
    final encodedVariant = jsonEncode(variantKey.value);
    final encodedUnitClass = jsonEncode(unitClass);
    final encodedCount = packCount?.toString() ?? 'null';
    return '{"schema":"supplier_option_evidence_v1",'
        '"variant_key":$encodedVariant,'
        '"pack_count":$encodedCount,'
        '"unit_class":$encodedUnitClass,'
        '"pack_evidence_conflict":$packEvidenceConflict}';
  }

  String get sha256Hex => sha256.convert(utf8.encode(canonicalJson)).toString();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': 'supplier_option_evidence_v1',
        'variant_key': variantKey.value,
        'pack_count': packCount,
        'unit_class': unitClass,
        'pack_evidence_conflict': packEvidenceConflict,
      };

  static String normalizeUnitClass(String? raw) {
    final token = raw?.trim().toLowerCase() ?? '';
    if (token.isEmpty) return 'unknown';
    const classes = <String, String>{
      'pc': 'piece',
      'pcs': 'piece',
      'piece': 'piece',
      'pieces': 'piece',
      'pieza': 'piece',
      'piezas': 'piece',
      'pz': 'piece',
      'pzs': 'piece',
      'pair': 'pair',
      'pairs': 'pair',
      'par': 'pair',
      'pares': 'pair',
      'set': 'set',
      'sets': 'set',
      'juego': 'set',
      'juegos': 'set',
      'kit': 'set',
      'kits': 'set',
      'unit': 'unit',
      'units': 'unit',
      'unidad': 'unit',
      'unidades': 'unit',
      'un': 'unit',
      'unknown': 'unknown',
    };
    final knownClass = classes[token];
    if (knownClass != null) return knownClass;
    if (token.startsWith('supplier:')) return token;
    if (!RegExp(r'^[a-z0-9][a-z0-9_.:-]{0,31}$').hasMatch(token)) {
      throw const FormatException('Supplier unit token is invalid.');
    }
    return 'supplier:$token';
  }

  static String? normalizeRawUnitToken(String? raw) {
    final token = raw?.trim().toLowerCase() ?? '';
    if (token.isEmpty) return null;
    if (!RegExp(r'^[a-z0-9][a-z0-9_.:-]{0,31}$').hasMatch(token)) {
      throw const FormatException('Supplier unit token is invalid.');
    }
    return token;
  }
}

enum SupplierVariantResolutionKind {
  single,
  homogeneous,
  composite;

  static SupplierVariantResolutionKind? fromDatabase(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

enum SupplierVariantResolutionState {
  active,
  superseded,
  revoked;

  static SupplierVariantResolutionState? fromDatabase(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    for (final state in values) {
      if (state.name == value) return state;
    }
    return null;
  }
}

enum SupplierVariantResolutionStatus {
  resolved('resolved'),
  notFound('not_found'),
  supplierInactive('supplier_inactive'),
  revoked('revoked'),
  contradictoryRevisionState('contradictory_revision_state'),
  optionEvidenceChanged('option_evidence_changed'),
  invalidOptionEvidence('invalid_option_evidence'),
  packEvidenceConflict('pack_evidence_conflict'),
  inactiveOrContradictoryEdges('inactive_or_contradictory_edges'),
  edgeSnapshotMismatch('edge_snapshot_mismatch'),
  legacyCandidate('legacy_candidate'),
  invalidResponse('invalid_response');

  const SupplierVariantResolutionStatus(this.databaseValue);

  final String databaseValue;

  static SupplierVariantResolutionStatus fromDatabase(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    for (final status in values) {
      if (status.databaseValue == value) return status;
    }
    return SupplierVariantResolutionStatus.invalidResponse;
  }
}

enum SupplierVariantResolutionAction {
  activate,
  revoke,
}

enum SupplierVariantResolutionDecisionSource {
  operatorConfirmed('operator_confirmed'),
  invoiceConfirmed('invoice_confirmed'),
  administrativeCorrection('administrative_correction'),
  migrationConfirmed('migration_confirmed');

  const SupplierVariantResolutionDecisionSource(this.databaseValue);

  final String databaseValue;
}

final class SupplierVariantResolutionEdge {
  const SupplierVariantResolutionEdge({
    this.id,
    required this.position,
    required this.productId,
    required this.catalogUnitsPerPurchase,
    required this.allocationRatio,
    required this.componentRole,
  });

  final String? id;
  final int position;
  final String productId;
  final int catalogUnitsPerPurchase;
  final double allocationRatio;
  final String componentRole;

  factory SupplierVariantResolutionEdge.fromJson(Map<String, dynamic> json) {
    final position = _integer(json['edge_ordinal']);
    final catalogUnits = _integer(json['catalog_units_per_purchase']);
    final allocationRatio = _double(json['allocation_ratio']);
    final productId = json['product_id']?.toString().trim() ?? '';
    final componentRole =
        json['component_role']?.toString().trim().toLowerCase() ?? '';
    final edgeId = _nullableText(json['edge_id'] ?? json['id']);
    if (position == null ||
        catalogUnits == null ||
        allocationRatio == null ||
        !_uuidPattern.hasMatch(productId) ||
        (edgeId != null && !_uuidPattern.hasMatch(edgeId)) ||
        componentRole.isEmpty) {
      throw const FormatException('Supplier resolution edge is invalid.');
    }
    return SupplierVariantResolutionEdge(
      id: edgeId,
      position: position,
      productId: productId,
      catalogUnitsPerPurchase: catalogUnits,
      allocationRatio: allocationRatio,
      componentRole: componentRole,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null) 'edge_id': id,
        'edge_ordinal': position,
        'product_id': productId,
        'catalog_units_per_purchase': catalogUnitsPerPurchase,
        'allocation_ratio': allocationRatio,
        'component_role': componentRole,
      };

  Map<String, dynamic> toRpcJson() => <String, dynamic>{
        'edge_ordinal': position,
        'product_id': productId,
        'catalog_units_per_purchase': catalogUnitsPerPurchase,
        'allocation_ratio': allocationRatio,
        'component_role': componentRole,
      };
}

final class SupplierInvoiceSourceComponent {
  const SupplierInvoiceSourceComponent({
    required this.id,
    required this.revisionEdgeId,
    required this.position,
    required this.productId,
    required this.catalogUnitsPerPurchase,
    required this.resolvedQuantity,
    required this.allocationRatio,
    required this.allocatedLineTotalMinor,
    required this.componentRole,
  });

  final String id;
  final String revisionEdgeId;
  final int position;
  final String productId;
  final int catalogUnitsPerPurchase;
  final double resolvedQuantity;
  final double allocationRatio;
  final int allocatedLineTotalMinor;
  final String componentRole;

  factory SupplierInvoiceSourceComponent.fromJson(Map<String, dynamic> json) {
    final id = _nullableText(json['id']);
    final revisionEdgeId = _nullableText(json['revision_edge_id']);
    final position = _integer(json['edge_ordinal']);
    final productId = _nullableText(json['product_id']);
    final catalogUnits = _integer(json['catalog_units_per_purchase']);
    final resolvedQuantity = _double(json['resolved_quantity']);
    final allocationRatio = _double(json['allocation_ratio']);
    final allocatedTotal = _integer(json['allocated_line_total_minor']);
    final role = _nullableText(json['component_role'])?.toLowerCase();
    if (id == null ||
        !_uuidPattern.hasMatch(id) ||
        revisionEdgeId == null ||
        !_uuidPattern.hasMatch(revisionEdgeId) ||
        position == null ||
        productId == null ||
        !_uuidPattern.hasMatch(productId) ||
        catalogUnits == null ||
        resolvedQuantity == null ||
        allocationRatio == null ||
        allocatedTotal == null ||
        role == null) {
      throw const FormatException(
        'Prepared supplier source component is incomplete.',
      );
    }
    return SupplierInvoiceSourceComponent(
      id: id,
      revisionEdgeId: revisionEdgeId,
      position: position,
      productId: productId,
      catalogUnitsPerPurchase: catalogUnits,
      resolvedQuantity: resolvedQuantity,
      allocationRatio: allocationRatio,
      allocatedLineTotalMinor: allocatedTotal,
      componentRole: role,
    );
  }
}

/// Durable source-line parent returned before an expanded invoice is saved.
final class SupplierInvoiceSourceResolution {
  SupplierInvoiceSourceResolution._({
    required this.id,
    required this.sourceLineKey,
    required this.sourceRowIndex,
    required this.resolutionRevisionId,
    required this.supplierListingId,
    required this.supplierVariantKey,
    required this.optionEvidenceHash,
    required this.sourceOrderNumbers,
    required this.sourceTitle,
    required this.optionUnitClass,
    required this.packEvidenceConflict,
    required this.sourceSnapshot,
    required this.sourceSnapshotHash,
    required this.sourcePurchaseQuantity,
    required this.sourceLineTotalMinor,
    required this.currencyCode,
    required this.operationId,
    required this.replayed,
    required List<SupplierInvoiceSourceComponent> components,
    this.selectedOption,
    this.rawPackCount,
    this.rawUnitToken,
  }) : components = UnmodifiableListView(components);

  final String id;
  final String sourceLineKey;
  final int sourceRowIndex;
  final String resolutionRevisionId;
  final String supplierListingId;
  final SupplierImmutableVariantKey supplierVariantKey;
  final String optionEvidenceHash;
  final List<String> sourceOrderNumbers;
  final String sourceTitle;
  final String? selectedOption;
  final int? rawPackCount;
  final String? rawUnitToken;
  final String optionUnitClass;
  final bool packEvidenceConflict;
  final Map<String, dynamic> sourceSnapshot;
  final String sourceSnapshotHash;
  final double sourcePurchaseQuantity;
  final int sourceLineTotalMinor;
  final String currencyCode;
  final String operationId;
  final bool replayed;
  final List<SupplierInvoiceSourceComponent> components;

  factory SupplierInvoiceSourceResolution.fromJson(
    Map<String, dynamic> json,
  ) {
    final id = _nullableText(json['id']);
    final sourceLineKey = _nullableText(json['source_line_key']);
    final sourceRowIndex = _integer(json['source_row_index']);
    final revisionId = _nullableText(
      json['supplier_resolution_revision_id'],
    );
    final listingId = _nullableText(json['supplier_listing_id']);
    final variantKey = SupplierImmutableVariantKey.tryParse(
      json['supplier_variant_key'],
    );
    final optionHash = _validHashOrNull(json['option_evidence_hash']);
    final sourceTitle = _nullableText(json['source_title']);
    final optionUnitClass = _nullableText(json['option_unit_class']);
    final snapshotHash = _validHashOrNull(json['source_snapshot_hash']);
    final sourceQuantity = _double(json['source_purchase_quantity']);
    final sourceTotal = _integer(json['source_line_total_minor']);
    final currencyCode = _nullableText(json['currency_code'])?.toUpperCase();
    final operationId = _nullableText(json['operation_id']);
    final snapshotRaw = json['source_snapshot'];
    final componentsRaw = json['components'];
    final orderNumbersRaw = json['source_order_numbers'];
    final rawPackCount = _integer(json['raw_pack_count']);
    final rawUnitTokenValue = json['raw_unit_token'];
    final selectedOptionValue = json['selected_option'];
    if (id == null ||
        !_uuidPattern.hasMatch(id) ||
        sourceLineKey == null ||
        sourceRowIndex == null ||
        revisionId == null ||
        !_uuidPattern.hasMatch(revisionId) ||
        listingId == null ||
        listingId != listingId.toLowerCase() ||
        variantKey == null ||
        optionHash == null ||
        sourceTitle == null ||
        optionUnitClass == null ||
        snapshotHash == null ||
        sourceQuantity == null ||
        sourceTotal == null ||
        currencyCode == null ||
        operationId == null ||
        !_uuidPattern.hasMatch(operationId) ||
        snapshotRaw is! Map ||
        componentsRaw is! List ||
        orderNumbersRaw is! List ||
        orderNumbersRaw.any((value) => value is! String) ||
        !json.containsKey('selected_option') ||
        !json.containsKey('raw_pack_count') ||
        (json['raw_pack_count'] != null && rawPackCount == null) ||
        !json.containsKey('raw_unit_token') ||
        (rawUnitTokenValue != null && rawUnitTokenValue is! String) ||
        json['pack_evidence_conflict'] is! bool ||
        json['replayed'] is! bool) {
      throw const FormatException(
        'Prepared supplier source resolution is incomplete.',
      );
    }
    final orders = orderNumbersRaw
        .map((value) => value?.toString().trim() ?? '')
        .toList(growable: false);
    final components = componentsRaw
        .map((raw) => SupplierInvoiceSourceComponent.fromJson(_map(raw)))
        .toList(growable: false)
      ..sort((left, right) => left.position.compareTo(right.position));
    final resolution = SupplierInvoiceSourceResolution._(
      id: id,
      sourceLineKey: sourceLineKey,
      sourceRowIndex: sourceRowIndex,
      resolutionRevisionId: revisionId,
      supplierListingId: listingId.toLowerCase(),
      supplierVariantKey: variantKey,
      optionEvidenceHash: optionHash,
      sourceOrderNumbers: List<String>.unmodifiable(orders),
      sourceTitle: sourceTitle,
      selectedOption: _nullableText(selectedOptionValue),
      rawPackCount: rawPackCount,
      rawUnitToken: SupplierOptionEvidence.normalizeRawUnitToken(
        rawUnitTokenValue?.toString(),
      ),
      optionUnitClass: optionUnitClass,
      packEvidenceConflict: json['pack_evidence_conflict'] as bool,
      sourceSnapshot: _immutableJsonMap(_map(snapshotRaw)),
      sourceSnapshotHash: snapshotHash,
      sourcePurchaseQuantity: sourceQuantity,
      sourceLineTotalMinor: sourceTotal,
      currencyCode: currencyCode,
      operationId: operationId,
      replayed: json['replayed'] as bool,
      components: components,
    );
    final failure = resolution._validationFailure();
    if (failure != null) throw FormatException(failure);
    return resolution;
  }

  String? _validationFailure() {
    if (sourceLineKey.length > 512 || sourceRowIndex < 0) {
      return 'Prepared source-line identity is invalid.';
    }
    if (sourceOrderNumbers.isEmpty ||
        sourceOrderNumbers.length > 64 ||
        sourceOrderNumbers.any(
          (value) => value.isEmpty || value.length > 128,
        ) ||
        sourceOrderNumbers.toSet().length != sourceOrderNumbers.length) {
      return 'Prepared source order numbers are invalid.';
    }
    if (sourcePurchaseQuantity <= 0 ||
        _scaledDecimal(sourcePurchaseQuantity, 6) == null ||
        sourceLineTotalMinor < 0 ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode) ||
        components.isEmpty) {
      return 'Prepared source totals are invalid.';
    }
    if (sourceTitle.length > 2000 ||
        (selectedOption?.length ?? 0) > 1000 ||
        rawPackCount != null &&
            (rawPackCount! <= 0 || rawPackCount! > 1000000) ||
        SupplierOptionEvidence.normalizeUnitClass(rawUnitToken) !=
            optionUnitClass) {
      return 'Prepared source option evidence is invalid.';
    }
    try {
      final reconstructedEvidence = SupplierOptionEvidence(
        variantKey: supplierVariantKey.value,
        packCount: rawPackCount,
        rawUnitToken: rawUnitToken,
        packEvidenceConflict: packEvidenceConflict,
      );
      if (reconstructedEvidence.sha256Hex != optionEvidenceHash) {
        return 'Prepared source option evidence does not reproduce its hash.';
      }
    } on ArgumentError {
      return 'Prepared source option evidence is contradictory.';
    } on FormatException {
      return 'Prepared source option evidence is invalid.';
    }
    var ratioTotal = BigInt.zero;
    var allocatedTotal = 0;
    final positions = <int>{};
    final scaledSourceQuantity = _scaledDecimal(sourcePurchaseQuantity, 6)!;
    for (final component in components) {
      final scaledResolvedQuantity = _scaledDecimal(
        component.resolvedQuantity,
        6,
      );
      if (component.position <= 0 ||
          !positions.add(component.position) ||
          component.productId.trim().isEmpty ||
          component.catalogUnitsPerPurchase <= 0 ||
          component.resolvedQuantity <= 0 ||
          scaledResolvedQuantity == null ||
          component.allocatedLineTotalMinor < 0 ||
          scaledResolvedQuantity !=
              scaledSourceQuantity *
                  BigInt.from(component.catalogUnitsPerPurchase)) {
        return 'Prepared source component graph is invalid.';
      }
      final scaledRatio = _scaledDecimal(component.allocationRatio, 12);
      if (scaledRatio == null || scaledRatio <= BigInt.zero) {
        return 'Prepared source component allocation is invalid.';
      }
      ratioTotal += scaledRatio;
      allocatedTotal += component.allocatedLineTotalMinor;
    }
    for (var position = 1; position <= components.length; position += 1) {
      if (!positions.contains(position)) {
        return 'Prepared source component positions are not contiguous.';
      }
    }
    if (ratioTotal != _ratioScale || allocatedTotal != sourceLineTotalMinor) {
      return 'Prepared source allocation does not preserve the exact total.';
    }
    const canonicalSnapshotKeys = <String>{
      'listing_id',
      'variant_key',
      'option_evidence_hash',
      'source_row_index',
      'source_line_key',
      'source_document_date',
      'source_order_numbers',
      'source_title',
      'selected_option',
      'raw_pack_count',
      'raw_unit_code',
      'option_unit_class',
      'pack_evidence_conflict',
      'source_purchase_quantity',
      'source_line_total_minor',
      'currency_code',
    };
    if (!canonicalSnapshotKeys.every(sourceSnapshot.containsKey) ||
        sourceSnapshot.containsKey('raw_unit_token') ||
        sourceSnapshot['listing_id']?.toString().toLowerCase() !=
            supplierListingId ||
        SupplierImmutableVariantKey.tryParse(sourceSnapshot['variant_key']) !=
            supplierVariantKey ||
        _validHashOrNull(sourceSnapshot['option_evidence_hash']) !=
            optionEvidenceHash ||
        _integer(sourceSnapshot['source_row_index']) != sourceRowIndex ||
        sourceSnapshot['source_line_key'] != sourceLineKey ||
        !_validCivilDate(sourceSnapshot['source_document_date']) ||
        !_sameStringList(
          sourceSnapshot['source_order_numbers'],
          sourceOrderNumbers,
        ) ||
        sourceSnapshot['source_title'] != sourceTitle ||
        _nullableText(sourceSnapshot['selected_option']) != selectedOption ||
        _integer(sourceSnapshot['raw_pack_count']) != rawPackCount ||
        _nullableText(sourceSnapshot['raw_unit_code'])?.toLowerCase() !=
            rawUnitToken ||
        sourceSnapshot['option_unit_class'] != optionUnitClass ||
        sourceSnapshot['pack_evidence_conflict'] != packEvidenceConflict ||
        _double(sourceSnapshot['source_purchase_quantity']) !=
            sourcePurchaseQuantity ||
        _integer(sourceSnapshot['source_line_total_minor']) !=
            sourceLineTotalMinor ||
        sourceSnapshot['currency_code'] != currencyCode) {
      return 'Prepared source snapshot does not match supplier identity.';
    }
    return null;
  }
}

/// Immutable header plus the complete ordered edge graph for one supplier
/// variant revision.
///
/// [authoritative] is true only for a validated `resolved` + `active` graph.
/// Review-only legacy aliases, changed evidence, revoked revisions and malformed
/// responses deliberately expose no usable edges.
final class SupplierVariantResolution {
  SupplierVariantResolution._({
    required this.status,
    required this.authoritative,
    required List<SupplierVariantResolutionEdge> edges,
    this.revisionId,
    this.tenantId,
    this.supplierId,
    this.listingId,
    this.variantKey,
    this.revisionNumber,
    this.state,
    this.kind,
    this.optionEvidenceHash,
    this.optionPackCount,
    this.optionUnitClass,
    this.packEvidenceConflict = false,
    this.edgeSetHash,
    this.operationId,
    this.requestFingerprint,
    this.supersedesRevisionId,
    this.correctionReason,
    this.decisionSource,
    this.decisionEvidenceHash,
    Map<String, dynamic> decisionEvidence = const <String, dynamic>{},
    this.createdBy,
    this.createdAt,
    this.replayed,
    this.requiresConfirmation = false,
    this.legacyAliasId,
    this.failureReason,
  })  : decisionEvidence = _immutableJsonMap(decisionEvidence),
        edges = UnmodifiableListView(edges);

  final SupplierVariantResolutionStatus status;
  final bool authoritative;
  final String? revisionId;
  final String? tenantId;
  final String? supplierId;
  final String? listingId;
  final SupplierImmutableVariantKey? variantKey;
  final int? revisionNumber;
  final SupplierVariantResolutionState? state;
  final SupplierVariantResolutionKind? kind;
  final String? optionEvidenceHash;
  final int? optionPackCount;
  final String? optionUnitClass;
  final bool packEvidenceConflict;
  final String? edgeSetHash;
  final String? operationId;
  final String? requestFingerprint;
  final String? supersedesRevisionId;
  final String? correctionReason;
  final String? decisionSource;
  final String? decisionEvidenceHash;
  final Map<String, dynamic> decisionEvidence;
  final String? createdBy;
  final DateTime? createdAt;
  final bool? replayed;
  final bool requiresConfirmation;
  final String? legacyAliasId;
  final String? failureReason;
  final List<SupplierVariantResolutionEdge> edges;

  bool get isResolved =>
      status == SupplierVariantResolutionStatus.resolved && authoritative;

  factory SupplierVariantResolution.notFound() => SupplierVariantResolution._(
        status: SupplierVariantResolutionStatus.notFound,
        authoritative: false,
        edges: const <SupplierVariantResolutionEdge>[],
      );

  factory SupplierVariantResolution.invalid([String? reason]) =>
      SupplierVariantResolution._(
        status: SupplierVariantResolutionStatus.invalidResponse,
        authoritative: false,
        edges: const <SupplierVariantResolutionEdge>[],
        failureReason: reason,
      );

  factory SupplierVariantResolution.fromLookupJson(
    Map<String, dynamic> json,
  ) {
    final status = SupplierVariantResolutionStatus.fromDatabase(json['status']);
    final advertisedAuthority = json['authoritative'] == true;
    if (status != SupplierVariantResolutionStatus.resolved ||
        !advertisedAuthority) {
      return SupplierVariantResolution._nonAuthoritative(json, status);
    }
    return SupplierVariantResolution._active(json);
  }

  factory SupplierVariantResolution.fromRememberJson(
    Map<String, dynamic> json,
  ) {
    final state = SupplierVariantResolutionState.fromDatabase(json['state']);
    if (state == SupplierVariantResolutionState.revoked) {
      return SupplierVariantResolution._nonAuthoritative(
        json,
        SupplierVariantResolutionStatus.revoked,
      );
    }
    if (state != SupplierVariantResolutionState.active) {
      return SupplierVariantResolution.invalid(
        'Remembered revision is not active or revoked.',
      );
    }
    return SupplierVariantResolution._active(json);
  }

  factory SupplierVariantResolution._active(Map<String, dynamic> json) {
    try {
      final revisionId = _nullableText(json['id'] ?? json['revision_id']);
      final tenantId = _nullableText(json['tenant_id']);
      final supplierId = _nullableText(json['supplier_id']);
      final listingId = _nullableText(json['listing_id']);
      final operationId = _nullableText(json['operation_id']);
      final edgeSetHash = _validHashOrNull(json['edge_set_hash']);
      final requestFingerprint = _validHashOrNull(
        json['request_fingerprint'],
      );
      final revisionNumber = _integer(json['revision_number']);
      final state = SupplierVariantResolutionState.fromDatabase(json['state']);
      final kind = SupplierVariantResolutionKind.fromDatabase(
        json['resolution_kind'],
      );
      final variantKey = SupplierImmutableVariantKey.tryParse(
        json['variant_key'],
      );
      final optionEvidenceHash = normalizeSupplierOptionEvidenceHash(
        json['option_evidence_hash']?.toString() ?? '',
      );
      final optionPackCount = _integer(json['option_pack_count']);
      final optionUnitClass = _nullableText(json['option_unit_class']);
      final packEvidenceConflict = json['pack_evidence_conflict'];
      final decisionSource = _nullableText(json['decision_source']);
      final decisionEvidenceHash = _validHashOrNull(
        json['decision_evidence_hash'],
      );
      final decisionEvidence = _optionalJsonMap(json['decision_evidence']);
      final rawEdges = json['edges'];
      if (revisionId == null ||
          !_uuidPattern.hasMatch(revisionId) ||
          tenantId == null ||
          !_uuidPattern.hasMatch(tenantId) ||
          supplierId == null ||
          !_uuidPattern.hasMatch(supplierId) ||
          listingId == null ||
          listingId != listingId.toLowerCase() ||
          operationId == null ||
          !_uuidPattern.hasMatch(operationId) ||
          edgeSetHash == null ||
          requestFingerprint == null ||
          revisionNumber == null ||
          revisionNumber <= 0 ||
          state != SupplierVariantResolutionState.active ||
          kind == null ||
          variantKey == null ||
          !json.containsKey('option_pack_count') ||
          optionUnitClass == null ||
          packEvidenceConflict is! bool ||
          packEvidenceConflict ||
          decisionSource == null ||
          !SupplierVariantResolutionDecisionSource.values.any(
            (source) => source.databaseValue == decisionSource,
          ) ||
          decisionEvidenceHash == null ||
          decisionEvidence.isEmpty ||
          rawEdges is! List) {
        return SupplierVariantResolution.invalid(
          'Resolved supplier revision header is incomplete.',
        );
      }
      final reconstructedEvidence = SupplierOptionEvidence(
        variantKey: variantKey.value,
        packCount: optionPackCount,
        rawUnitToken: optionUnitClass,
        packEvidenceConflict: packEvidenceConflict,
      );
      if (reconstructedEvidence.sha256Hex != optionEvidenceHash) {
        return SupplierVariantResolution.invalid(
          'Resolved supplier option evidence does not reproduce its hash.',
        );
      }
      final edges = rawEdges
          .map((raw) => SupplierVariantResolutionEdge.fromJson(_map(raw)))
          .toList(growable: false)
        ..sort((left, right) => left.position.compareTo(right.position));
      if (edges.any((edge) => edge.id == null)) {
        return SupplierVariantResolution.invalid(
          'Resolved supplier graph edges are missing immutable IDs.',
        );
      }
      final graphFailure = validateGraph(kind: kind, edges: edges);
      if (graphFailure != null) {
        return SupplierVariantResolution.invalid(graphFailure);
      }
      return SupplierVariantResolution._(
        status: SupplierVariantResolutionStatus.resolved,
        authoritative: true,
        revisionId: revisionId,
        tenantId: tenantId,
        supplierId: supplierId,
        listingId: listingId,
        variantKey: variantKey,
        revisionNumber: revisionNumber,
        state: state,
        kind: kind,
        optionEvidenceHash: optionEvidenceHash,
        optionPackCount: optionPackCount,
        optionUnitClass: optionUnitClass,
        packEvidenceConflict: packEvidenceConflict,
        edgeSetHash: edgeSetHash,
        operationId: operationId,
        requestFingerprint: requestFingerprint,
        supersedesRevisionId: _nullableText(json['supersedes_revision_id']),
        correctionReason: _nullableText(json['correction_reason']),
        decisionSource: decisionSource,
        decisionEvidenceHash: decisionEvidenceHash,
        decisionEvidence: decisionEvidence,
        createdBy: _nullableText(json['created_by']),
        createdAt: _date(json['created_at']),
        replayed: json['replayed'] as bool?,
        edges: edges,
      );
    } on FormatException catch (error) {
      return SupplierVariantResolution.invalid(error.message.toString());
    } on ArgumentError catch (error) {
      return SupplierVariantResolution.invalid(error.message.toString());
    }
  }

  factory SupplierVariantResolution._nonAuthoritative(
    Map<String, dynamic> json,
    SupplierVariantResolutionStatus status,
  ) {
    if (status == SupplierVariantResolutionStatus.resolved ||
        status == SupplierVariantResolutionStatus.invalidResponse) {
      return SupplierVariantResolution.invalid(
        'Supplier resolution response claimed inconsistent authority.',
      );
    }
    return SupplierVariantResolution._(
      status: status,
      authoritative: false,
      revisionId: _nullableText(json['revision_id'] ?? json['id']),
      tenantId: _nullableText(json['tenant_id']),
      supplierId: _nullableText(json['supplier_id']),
      listingId: _nullableText(json['listing_id']),
      variantKey: SupplierImmutableVariantKey.tryParse(json['variant_key']),
      revisionNumber: _integer(json['revision_number']),
      state: SupplierVariantResolutionState.fromDatabase(json['state']),
      kind: SupplierVariantResolutionKind.fromDatabase(
        json['resolution_kind'],
      ),
      optionEvidenceHash: _validHashOrNull(json['option_evidence_hash']),
      optionPackCount: _integer(json['option_pack_count']),
      optionUnitClass: _nullableText(json['option_unit_class']),
      packEvidenceConflict: json['pack_evidence_conflict'] == true,
      edgeSetHash: _nullableText(json['edge_set_hash']),
      operationId: _nullableText(json['operation_id']),
      requestFingerprint: _nullableText(json['request_fingerprint']),
      supersedesRevisionId: _nullableText(json['supersedes_revision_id']),
      correctionReason: _nullableText(json['correction_reason']),
      decisionSource: _nullableText(json['decision_source']),
      decisionEvidenceHash: _validHashOrNull(json['decision_evidence_hash']),
      decisionEvidence: _optionalJsonMap(json['decision_evidence']),
      createdBy: _nullableText(json['created_by']),
      createdAt: _date(json['created_at']),
      replayed: json['replayed'] as bool?,
      requiresConfirmation: json['requires_confirmation'] == true,
      legacyAliasId: _nullableText(json['legacy_alias_id']),
      edges: const <SupplierVariantResolutionEdge>[],
    );
  }

  static String? validateGraph({
    required SupplierVariantResolutionKind kind,
    required List<SupplierVariantResolutionEdge> edges,
  }) {
    if (edges.isEmpty || edges.length > 32) {
      return 'Supplier resolution graph must have between 1 and 32 edges.';
    }
    final positions = <int>{};
    var ratioTotal = BigInt.zero;
    for (final edge in edges) {
      if (edge.position <= 0 || !positions.add(edge.position)) {
        return 'Supplier resolution positions are invalid.';
      }
      if (edge.productId.trim().isEmpty) {
        return 'Supplier resolution product is invalid.';
      }
      if (edge.catalogUnitsPerPurchase <= 0 ||
          edge.catalogUnitsPerPurchase > 1000000) {
        return 'Catalog units per purchase must be a positive integer.';
      }
      if (!RegExp(r'^[a-z0-9][a-z0-9_.:-]{0,79}$')
          .hasMatch(edge.componentRole.trim().toLowerCase())) {
        return 'Supplier resolution component role is invalid.';
      }
      final scaledRatio = _scaledDecimal(edge.allocationRatio, 12);
      if (scaledRatio == null ||
          scaledRatio <= BigInt.zero ||
          scaledRatio > _ratioScale) {
        return 'Supplier resolution allocation ratio is invalid.';
      }
      ratioTotal += scaledRatio;
    }
    for (var position = 1; position <= edges.length; position += 1) {
      if (!positions.contains(position)) {
        return 'Supplier resolution positions must be contiguous from one.';
      }
    }
    if (ratioTotal != _ratioScale) {
      return 'Supplier resolution allocation ratios must sum exactly to one.';
    }
    if ((kind == SupplierVariantResolutionKind.single ||
            kind == SupplierVariantResolutionKind.homogeneous) &&
        edges.length != 1) {
      return 'Single and homogeneous resolutions require one edge.';
    }
    if (kind == SupplierVariantResolutionKind.single &&
        (edges.single.catalogUnitsPerPurchase != 1 ||
            _scaledDecimal(edges.single.allocationRatio, 12) != _ratioScale)) {
      return 'A single resolution must be one catalog unit at ratio one.';
    }
    if (kind == SupplierVariantResolutionKind.composite && edges.length < 2) {
      return 'A composite resolution requires at least two edges.';
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'status': status.databaseValue,
        'authoritative': authoritative,
        if (revisionId != null) 'id': revisionId,
        if (tenantId != null) 'tenant_id': tenantId,
        if (supplierId != null) 'supplier_id': supplierId,
        if (listingId != null) 'listing_id': listingId,
        if (variantKey != null) 'variant_key': variantKey!.value,
        if (revisionNumber != null) 'revision_number': revisionNumber,
        if (state != null) 'state': state!.name,
        if (kind != null) 'resolution_kind': kind!.name,
        if (optionEvidenceHash != null)
          'option_evidence_hash': optionEvidenceHash,
        if (optionPackCount != null) 'option_pack_count': optionPackCount,
        if (optionUnitClass != null) 'option_unit_class': optionUnitClass,
        if (optionEvidenceHash != null)
          'pack_evidence_conflict': packEvidenceConflict,
        if (edgeSetHash != null) 'edge_set_hash': edgeSetHash,
        if (operationId != null) 'operation_id': operationId,
        if (requestFingerprint != null)
          'request_fingerprint': requestFingerprint,
        if (supersedesRevisionId != null)
          'supersedes_revision_id': supersedesRevisionId,
        if (correctionReason != null) 'correction_reason': correctionReason,
        if (decisionSource != null) 'decision_source': decisionSource,
        if (decisionEvidenceHash != null)
          'decision_evidence_hash': decisionEvidenceHash,
        if (decisionEvidence.isNotEmpty) 'decision_evidence': decisionEvidence,
        if (createdBy != null) 'created_by': createdBy,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (replayed != null) 'replayed': replayed,
        if (requiresConfirmation) 'requires_confirmation': true,
        if (legacyAliasId != null) 'legacy_alias_id': legacyAliasId,
        'edges': edges.map((edge) => edge.toJson()).toList(growable: false),
      };
}

final BigInt _ratioScale = BigInt.from(1000000000000);

BigInt? _scaledDecimal(double value, int decimalPlaces) {
  if (!value.isFinite) return null;
  final text = value.toString();
  final match = RegExp(r'^([0-9]+)(?:\.([0-9]+))?$').firstMatch(text);
  if (match == null) return null;
  final fractional = match.group(2) ?? '';
  if (fractional.length > decimalPlaces) return null;
  final padded = fractional.padRight(decimalPlaces, '0');
  return BigInt.tryParse('${match.group(1)}$padded');
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, raw) => MapEntry(key.toString(), raw));
  }
  throw const FormatException('Expected a JSON object.');
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num) {
    if (!value.isFinite || value != value.roundToDouble()) return null;
    return value.toInt();
  }
  final text = value?.toString().trim();
  if (text == null || !RegExp(r'^[+-]?[0-9]+(?:\.0+)?$').hasMatch(text)) {
    return null;
  }
  return double.tryParse(text)?.toInt();
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().trim() ?? '');
}

DateTime? _date(Object? value) {
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}

bool _validCivilDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return false;
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  return parsed != null && parsed.toIso8601String().startsWith(value);
}

String? _validHashOrNull(Object? value) {
  final raw = value?.toString();
  if (raw == null) return null;
  try {
    return normalizeSupplierOptionEvidenceHash(raw);
  } on FormatException {
    return null;
  }
}

Map<String, dynamic> _optionalJsonMap(Object? value) {
  if (value == null) return const <String, dynamic>{};
  try {
    return _map(value);
  } on FormatException {
    return const <String, dynamic>{};
  }
}

Map<String, dynamic> _immutableJsonMap(Map<String, dynamic> value) {
  Object? freeze(Object? raw) {
    if (raw is Map) {
      return Map<String, dynamic>.unmodifiable(
        raw.map(
          (key, nested) => MapEntry(key.toString(), freeze(nested)),
        ),
      );
    }
    if (raw is List) {
      return List<Object?>.unmodifiable(raw.map(freeze));
    }
    return raw;
  }

  return freeze(value)! as Map<String, dynamic>;
}

bool _sameStringList(Object? raw, List<String> expected) {
  if (raw is! List || raw.length != expected.length) return false;
  for (var index = 0; index < raw.length; index += 1) {
    if (raw[index] is! String || raw[index] != expected[index]) return false;
  }
  return true;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
  r'[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
