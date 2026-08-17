/// Product photo of one catalog identity, resolved in the order the design
/// handoff fixed: optimized, raw, then the first usable entry of the gallery.
///
/// The chain stays open at render time on purpose. A stored optimized URL can
/// still fail to load, and the surface must degrade to the next real candidate
/// before it degrades to a monogram, without ever changing the tile geometry.
class ProductMedia {
  const ProductMedia({
    this.imageUrlOptimized,
    this.imageUrl,
    this.imageUrls = const [],
  });

  static const ProductMedia empty = ProductMedia();

  final String? imageUrlOptimized;
  final String? imageUrl;
  final List<String> imageUrls;

  /// Every usable URL, deduplicated, in resolution order.
  ///
  /// A consumer walks this list: entry `n + 1` is what a failed entry `n`
  /// falls back to, and an exhausted list falls back to the monogram.
  List<String> get resolutionChain {
    final chain = <String>[];
    void add(String? value) {
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty) return;
      if (chain.contains(normalized)) return;
      chain.add(normalized);
    }

    add(imageUrlOptimized);
    add(imageUrl);
    for (final entry in imageUrls) {
      add(entry);
    }
    return List.unmodifiable(chain);
  }

  /// First usable URL, or `null` when the ficha carries no image at all.
  String? get primaryUrl {
    final chain = resolutionChain;
    return chain.isEmpty ? null : chain.first;
  }

  bool get hasImage => resolutionChain.isNotEmpty;

  factory ProductMedia.fromJson(Map<String, dynamic> json) {
    final rawUrls = json['imageUrls'] ?? json['image_urls'];
    return ProductMedia(
      imageUrlOptimized: _asNullableText(
          json['imageUrlOptimized'] ?? json['image_url_optimized']),
      imageUrl: _asNullableText(json['imageUrl'] ?? json['image_url']),
      imageUrls: rawUrls is List
          ? rawUrls
              .map(_asNullableText)
              .whereType<String>()
              .toList(growable: false)
          : const [],
    );
  }
}

/// Two-letter monogram used when no URL resolves. It never replaces identity —
/// the full name stays available as the accessible label.
String productMonogram(String name) {
  final words = name
      .trim()
      .split(RegExp(r'[\s/·-]+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return '—';
  if (words.length == 1) {
    final single = words.first;
    return (single.length == 1 ? single : single.substring(0, 2)).toUpperCase();
  }
  return '${words[0][0]}${words[1][0]}'.toUpperCase();
}

class SupplyNeed {
  const SupplyNeed({
    required this.id,
    required this.originKind,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.identityState,
    required this.supplyState,
    required this.version,
    required this.createdAt,
    this.mechanicJobId,
    this.jobBikeId,
    this.productId,
    this.productName,
    this.productSku,
    this.internalStockRejectionReason,
  });

  final String id;
  final String originKind;
  final String? mechanicJobId;
  final String? jobBikeId;
  final String description;
  final String? productId;
  final String? productName;
  final String? productSku;
  final double quantity;
  final String unit;
  final String identityState;
  final String supplyState;
  final int version;
  final DateTime createdAt;
  final String? internalStockRejectionReason;

  bool get hasConfirmedProduct =>
      productId != null && identityState == 'confirmed';

  SupplyNeed withProduct({String? name, String? sku}) {
    return SupplyNeed(
      id: id,
      originKind: originKind,
      mechanicJobId: mechanicJobId,
      jobBikeId: jobBikeId,
      description: description,
      productId: productId,
      productName: name ?? productName,
      productSku: sku ?? productSku,
      quantity: quantity,
      unit: unit,
      identityState: identityState,
      supplyState: supplyState,
      version: version,
      createdAt: createdAt,
      internalStockRejectionReason: internalStockRejectionReason,
    );
  }

  factory SupplyNeed.fromJson(Map<String, dynamic> json) {
    return SupplyNeed(
      id: json['id']?.toString() ?? json['need_id']?.toString() ?? '',
      originKind: json['origin_kind']?.toString() ?? 'ad_hoc',
      mechanicJobId: json['mechanic_job_id']?.toString(),
      jobBikeId: json['job_bike_id']?.toString(),
      description: json['original_description']?.toString() ??
          json['description']?.toString() ??
          '',
      productId: json['product_id']?.toString(),
      productName: json['product_name']?.toString(),
      productSku: json['product_sku']?.toString(),
      quantity: _asDouble(json['quantity'], fallback: 1),
      unit: json['unit']?.toString() ?? 'unit',
      identityState: json['identity_state']?.toString() ?? 'unresolved',
      supplyState: json['supply_state']?.toString() ?? 'open',
      version: _asInt(json['version'], fallback: 1),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      internalStockRejectionReason:
          json['internal_stock_rejection_reason']?.toString(),
    );
  }
}

class JobSupplyAttention {
  const JobSupplyAttention({
    required this.jobId,
    required this.promptsSupplyNeedCapture,
    required this.activeNeedCount,
    required this.unresolvedIdentityCount,
    required this.requiresCapture,
  });

  final String jobId;
  final bool promptsSupplyNeedCapture;
  final int activeNeedCount;
  final int unresolvedIdentityCount;
  final bool requiresCapture;

  factory JobSupplyAttention.fromJson(Map<String, dynamic> json) {
    return JobSupplyAttention(
      jobId: json['mechanic_job_id']?.toString() ?? '',
      promptsSupplyNeedCapture: json['prompts_supply_need_capture'] == true,
      activeNeedCount: _asInt(json['active_need_count']),
      unresolvedIdentityCount: _asInt(json['unresolved_identity_count']),
      requiresCapture: json['requires_supply_capture'] == true,
    );
  }
}

class SupplyInventoryComponent {
  const SupplyInventoryComponent({
    required this.productId,
    required this.name,
    required this.requiredQuantity,
    required this.onHand,
    required this.onlineCommitted,
    required this.workshopCommitted,
    required this.availableToPromise,
    this.sku,
    this.media = ProductMedia.empty,
  });

  final String productId;
  final String name;
  final String? sku;
  final int requiredQuantity;
  final int onHand;
  final int onlineCommitted;
  final int workshopCommitted;
  final int availableToPromise;
  final ProductMedia media;

  /// Units this component can still cover for the need being resolved.
  int get coverable => availableToPromise <= 0
      ? 0
      : availableToPromise.clamp(0, requiredQuantity);

  /// Units that must still be sourced externally after using internal stock.
  int get shortfall =>
      (requiredQuantity - coverable).clamp(0, requiredQuantity);

  factory SupplyInventoryComponent.fromJson(Map<String, dynamic> json) {
    return SupplyInventoryComponent(
      productId: json['product_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sku: json['sku']?.toString(),
      media: ProductMedia.fromJson(json),
      requiredQuantity: _asInt(json['required_quantity']),
      onHand: _asInt(json['on_hand']),
      onlineCommitted: _asInt(json['online_committed']),
      workshopCommitted: _asInt(json['workshop_committed']),
      availableToPromise: _asInt(json['atp']),
    );
  }
}

class SupplyInventorySnapshot {
  const SupplyInventorySnapshot({
    required this.needId,
    required this.assignable,
    required this.components,
    this.needVersion,
    this.sourceProductId,
    this.sourceProductName,
    this.requestedQuantity,
    this.availableToPromise,
    this.reason,
  });

  final String needId;
  final int? needVersion;
  final String? sourceProductId;
  final String? sourceProductName;
  final double? requestedQuantity;
  final int? availableToPromise;
  final bool assignable;
  final String? reason;
  final List<SupplyInventoryComponent> components;

  factory SupplyInventorySnapshot.fromJson(Map<String, dynamic> json) {
    final rawComponents = json['components'];
    return SupplyInventorySnapshot(
      needId: json['need_id']?.toString() ?? '',
      needVersion:
          json['need_version'] == null ? null : _asInt(json['need_version']),
      sourceProductId: json['source_product_id']?.toString(),
      sourceProductName: json['source_product_name']?.toString(),
      requestedQuantity: json['requested_quantity'] == null
          ? null
          : _asDouble(json['requested_quantity']),
      availableToPromise: json['available_to_promise'] == null
          ? null
          : _asInt(json['available_to_promise']),
      assignable: json['assignable'] == true,
      reason: json['reason']?.toString(),
      components: rawComponents is List
          ? rawComponents
              .whereType<Map>()
              .map((item) => SupplyInventoryComponent.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
    );
  }
}

class PurchaseCandidate {
  const PurchaseCandidate({
    required this.candidateId,
    required this.rank,
    required this.productId,
    required this.productName,
    required this.supplierName,
    required this.supplierAvailability,
    required this.evidenceQuality,
    required this.purchaseCount,
    required this.evidenceAgeDays,
    this.productSku,
    this.brand,
    this.gama,
    this.gamaIsConfident = false,
    this.category,
    this.supplierId,
    this.supplierWebsite,
    this.isConfirmedLocal = false,
    this.media = ProductMedia.empty,
    this.currency = 'CLP',
    this.latestLandedUnitCostNet,
    this.catalogSalePriceGross,
    this.projectedGrossMarginRatio,
    this.lastPurchaseAt,
    this.freightEvidence,
  });

  final String candidateId;
  final int rank;
  final String productId;
  final String productName;
  final String? productSku;
  final String? brand;

  /// Banda de gama vigente: `economica`, `media`, `alta`, o `null` cuando la
  /// marca todavía no tiene historial suficiente para situarla.
  final String? gama;

  /// `false` cuando la banda salió de muy poca compra: se muestra igual, con la
  /// voz más baja. No saber no es lo mismo que no calzar.
  final bool gamaIsConfident;
  final String? category;
  final String? supplierId;
  final String supplierName;
  final String? supplierWebsite;
  final bool isConfirmedLocal;
  final ProductMedia media;
  final String supplierAvailability;
  final String currency;
  final double? latestLandedUnitCostNet;
  final double? catalogSalePriceGross;
  final double? projectedGrossMarginRatio;
  final int purchaseCount;
  final DateTime? lastPurchaseAt;
  final int evidenceAgeDays;
  final String evidenceQuality;
  final String? freightEvidence;

  factory PurchaseCandidate.fromJson(Map<String, dynamic> json) {
    return PurchaseCandidate(
      candidateId: json['candidateId']?.toString() ?? '',
      rank: _asInt(json['rank']),
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? '',
      productSku: json['productSku']?.toString(),
      brand: json['brand']?.toString(),
      gama: json['gama']?.toString(),
      gamaIsConfident: json['gamaIsConfident'] == true,
      category: json['category']?.toString(),
      supplierId: json['supplierId']?.toString(),
      supplierName: json['supplierName']?.toString() ?? 'Sin proveedor',
      supplierWebsite: json['supplierWebsite']?.toString(),
      isConfirmedLocal: json['isConfirmedLocal'] == true,
      media: ProductMedia.fromJson(json),
      supplierAvailability:
          json['supplierAvailability']?.toString() ?? 'unverified',
      currency: json['currency']?.toString() ?? 'CLP',
      latestLandedUnitCostNet: _asNullableDouble(
        json['latestLandedUnitCostNet'],
      ),
      catalogSalePriceGross: _asNullableDouble(
        json['catalogSalePriceGross'],
      ),
      projectedGrossMarginRatio: _asNullableDouble(
        json['projectedGrossMarginRatio'],
      ),
      purchaseCount: _asInt(json['purchaseCount']),
      lastPurchaseAt:
          DateTime.tryParse(json['lastPurchaseAt']?.toString() ?? ''),
      evidenceAgeDays: _asInt(json['evidenceAgeDays']),
      evidenceQuality: json['evidenceQuality']?.toString() ?? 'weak',
      freightEvidence: json['freightEvidence']?.toString(),
    );
  }
}

class PurchaseRanking {
  const PurchaseRanking({
    required this.status,
    required this.items,
    required this.hasMore,
    required this.supplierAvailabilitySemantics,
  });

  final String status;
  final List<PurchaseCandidate> items;
  final bool hasMore;
  final String supplierAvailabilitySemantics;

  factory PurchaseRanking.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return PurchaseRanking(
      status: json['status']?.toString() ?? 'verifiedEmpty',
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => PurchaseCandidate.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
      hasMore: json['hasMore'] == true,
      supplierAvailabilitySemantics:
          json['supplierAvailabilitySemantics']?.toString() ??
              'historical_only_unverified',
    );
  }
}

class PurchaseScenarioSubtotal {
  const PurchaseScenarioSubtotal({
    required this.currency,
    required this.amount,
  });

  final String currency;
  final double amount;

  factory PurchaseScenarioSubtotal.fromJson(Map<String, dynamic> json) {
    return PurchaseScenarioSubtotal(
      currency: json['currency']?.toString() ?? 'CLP',
      amount: _asDouble(
        json['historicalLandedSubtotalNet'] ?? json['amount'],
      ),
    );
  }
}

class PurchaseScenarioLine {
  const PurchaseScenarioLine({
    required this.lineRef,
    required this.productId,
    required this.productName,
    required this.requestedQuantity,
    required this.availableToPromise,
    required this.sourcing,
    required this.covered,
    this.productSku,
    this.candidateId,
    this.supplierId,
    this.supplierName,
    this.isConfirmedLocal = false,
    this.supplierAvailability,
    this.currency,
    this.latestLandedUnitCostNet,
    this.projectedGrossMarginRatio,
    this.purchaseCount,
    this.evidenceAgeDays,
    this.evidenceQuality,
    this.freightEvidence,
  });

  final String lineRef;
  final String productId;
  final String productName;
  final String? productSku;
  final double requestedQuantity;
  final int availableToPromise;
  final String sourcing;
  final bool covered;
  final String? candidateId;
  final String? supplierId;
  final String? supplierName;
  final bool isConfirmedLocal;
  final String? supplierAvailability;
  final String? currency;
  final double? latestLandedUnitCostNet;
  final double? projectedGrossMarginRatio;
  final int? purchaseCount;
  final int? evidenceAgeDays;
  final String? evidenceQuality;
  final String? freightEvidence;

  bool get hasExternalCandidate =>
      sourcing == 'external' &&
      covered &&
      candidateId != null &&
      candidateId!.isNotEmpty;

  PurchaseCandidate toCandidate({required int rank}) {
    if (!hasExternalCandidate) {
      throw StateError('La línea no contiene una alternativa externa.');
    }
    return PurchaseCandidate(
      candidateId: candidateId!,
      rank: rank,
      productId: productId,
      productName: productName,
      productSku: productSku,
      supplierName: supplierName ?? 'Sin proveedor',
      isConfirmedLocal: isConfirmedLocal,
      supplierAvailability: supplierAvailability ?? 'unverified',
      currency: currency ?? 'CLP',
      latestLandedUnitCostNet: latestLandedUnitCostNet,
      projectedGrossMarginRatio: projectedGrossMarginRatio,
      purchaseCount: purchaseCount ?? 0,
      evidenceAgeDays: evidenceAgeDays ?? 0,
      evidenceQuality: evidenceQuality ?? 'weak',
      freightEvidence: freightEvidence,
    );
  }

  factory PurchaseScenarioLine.fromJson(Map<String, dynamic> json) {
    return PurchaseScenarioLine(
      lineRef: json['lineRef']?.toString() ?? '',
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? '',
      productSku: json['productSku']?.toString(),
      requestedQuantity: _asDouble(json['requestedQuantity']),
      availableToPromise: _asInt(json['availableToPromise']),
      sourcing: json['sourcing']?.toString() ?? 'uncovered',
      covered: json['covered'] == true,
      candidateId: json['candidateId']?.toString(),
      supplierId: json['supplierId']?.toString(),
      supplierName: json['supplierName']?.toString(),
      isConfirmedLocal: json['isConfirmedLocal'] == true,
      supplierAvailability: json['supplierAvailability']?.toString(),
      currency: json['currency']?.toString(),
      latestLandedUnitCostNet:
          _asNullableDouble(json['latestLandedUnitCostNet']),
      projectedGrossMarginRatio:
          _asNullableDouble(json['projectedGrossMarginRatio']),
      purchaseCount:
          json['purchaseCount'] == null ? null : _asInt(json['purchaseCount']),
      evidenceAgeDays: json['evidenceAgeDays'] == null
          ? null
          : _asInt(json['evidenceAgeDays']),
      evidenceQuality: json['evidenceQuality']?.toString(),
      freightEvidence: json['freightEvidence']?.toString(),
    );
  }
}

class PurchaseScenario {
  const PurchaseScenario({
    required this.key,
    required this.kind,
    required this.label,
    required this.coverageLineCount,
    required this.externalCoverageLineCount,
    required this.totalLineCount,
    required this.externalLineCount,
    required this.complete,
    required this.supplierCount,
    required this.historicalSubtotals,
    required this.supplierAvailability,
    required this.freightAssumption,
    required this.lines,
    required this.explanationCodes,
  });

  final String key;
  final String kind;
  final String label;
  final int coverageLineCount;
  final int externalCoverageLineCount;
  final int totalLineCount;
  final int externalLineCount;
  final bool complete;
  final int supplierCount;
  final List<PurchaseScenarioSubtotal> historicalSubtotals;
  final String supplierAvailability;
  final String freightAssumption;
  final List<PurchaseScenarioLine> lines;
  final List<String> explanationCodes;

  List<PurchaseScenarioLine> get externalCandidates =>
      lines.where((line) => line.hasExternalCandidate).toList(growable: false);

  factory PurchaseScenario.fromJson(Map<String, dynamic> json) {
    final rawSubtotals = json['historicalSubtotals'];
    final rawLines = json['lines'];
    final rawExplanationCodes = json['explanationCodes'];
    return PurchaseScenario(
      key: json['scenarioKey']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'recommended',
      label: json['label']?.toString() ?? 'Alternativa',
      coverageLineCount: _asInt(json['coverageLineCount']),
      externalCoverageLineCount: _asInt(json['externalCoverageLineCount']),
      totalLineCount: _asInt(json['totalLineCount']),
      externalLineCount: _asInt(json['externalLineCount']),
      complete: json['complete'] == true,
      supplierCount: _asInt(json['supplierCount']),
      historicalSubtotals: rawSubtotals is List
          ? rawSubtotals
              .whereType<Map>()
              .map((item) => PurchaseScenarioSubtotal.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
      supplierAvailability:
          json['supplierAvailability']?.toString() ?? 'unverified',
      freightAssumption: json['freightAssumption']?.toString() ?? '',
      lines: rawLines is List
          ? rawLines
              .whereType<Map>()
              .map((item) => PurchaseScenarioLine.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
      explanationCodes: rawExplanationCodes is List
          ? rawExplanationCodes.map((item) => item.toString()).toList(
                growable: false,
              )
          : const [],
    );
  }
}

class PurchaseScenarioResult {
  const PurchaseScenarioResult({
    required this.status,
    required this.profile,
    required this.inputCount,
    required this.internalLineCount,
    required this.externalLineCount,
    required this.boundedSupplierCount,
    required this.scenarios,
    required this.hasMore,
    required this.supplierAvailabilitySemantics,
  });

  final String status;
  final String profile;
  final int inputCount;
  final int internalLineCount;
  final int externalLineCount;
  final int boundedSupplierCount;
  final List<PurchaseScenario> scenarios;
  final bool hasMore;
  final String supplierAvailabilitySemantics;

  factory PurchaseScenarioResult.fromJson(Map<String, dynamic> json) {
    final rawScenarios = json['scenarios'] ?? json['items'];
    return PurchaseScenarioResult(
      status: json['status']?.toString() ?? 'verifiedEmpty',
      profile: json['profile']?.toString() ?? 'balanced',
      inputCount: _asInt(json['inputCount']),
      internalLineCount: _asInt(json['internalLineCount']),
      externalLineCount: _asInt(json['externalLineCount']),
      boundedSupplierCount: _asInt(json['boundedSupplierCount']),
      scenarios: rawScenarios is List
          ? rawScenarios
              .whereType<Map>()
              .map((item) => PurchaseScenario.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
      hasMore: json['hasMore'] == true,
      supplierAvailabilitySemantics:
          json['supplierAvailabilitySemantics']?.toString() ??
              'historical_only_unverified',
    );
  }
}

class PurchasePlanLine {
  const PurchasePlanLine({
    required this.id,
    required this.sourceNeedId,
    required this.candidateId,
    required this.productId,
    required this.supplierName,
    required this.quantity,
    required this.unit,
    required this.currency,
    required this.supplierAvailability,
    this.productName,
    this.landedUnitCostNet,
    this.projectedGrossMarginRatio,
  });

  final String id;
  final String sourceNeedId;
  final String candidateId;
  final String productId;
  final String? productName;
  final String supplierName;
  final double quantity;
  final String unit;
  final String currency;
  final double? landedUnitCostNet;
  final double? projectedGrossMarginRatio;
  final String supplierAvailability;

  PurchasePlanLine withProductName(String? name) => PurchasePlanLine(
        id: id,
        sourceNeedId: sourceNeedId,
        candidateId: candidateId,
        productId: productId,
        productName: name ?? productName,
        supplierName: supplierName,
        quantity: quantity,
        unit: unit,
        currency: currency,
        landedUnitCostNet: landedUnitCostNet,
        projectedGrossMarginRatio: projectedGrossMarginRatio,
        supplierAvailability: supplierAvailability,
      );

  factory PurchasePlanLine.fromJson(Map<String, dynamic> json) {
    return PurchasePlanLine(
      id: json['id']?.toString() ?? '',
      sourceNeedId: json['source_need_id']?.toString() ?? '',
      candidateId: json['candidate_id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString(),
      supplierName: json['supplier_name']?.toString() ?? 'Sin proveedor',
      quantity: _asDouble(json['quantity']),
      unit: json['unit']?.toString() ?? 'unit',
      currency: json['currency_code']?.toString() ?? 'CLP',
      landedUnitCostNet: _asNullableDouble(json['landed_unit_cost_net']),
      projectedGrossMarginRatio:
          _asNullableDouble(json['projected_gross_margin_ratio']),
      supplierAvailability:
          json['supplier_availability']?.toString() ?? 'unverified',
    );
  }
}

class PurchasePlanSupplierGroup {
  const PurchasePlanSupplierGroup({
    required this.supplierName,
    required this.currency,
    required this.lineCount,
    required this.totalUnits,
    required this.supplierAvailability,
    required this.freightAssumption,
    this.supplierId,
    this.historicalLandedSubtotalNet,
  });

  final String? supplierId;
  final String supplierName;
  final String currency;
  final int lineCount;
  final double totalUnits;
  final double? historicalLandedSubtotalNet;
  final String supplierAvailability;
  final String freightAssumption;

  factory PurchasePlanSupplierGroup.fromJson(Map<String, dynamic> json) {
    return PurchasePlanSupplierGroup(
      supplierId: json['supplier_id']?.toString(),
      supplierName: json['supplier_name']?.toString() ?? 'Sin proveedor',
      currency: json['currency_code']?.toString() ?? 'CLP',
      lineCount: _asInt(json['line_count']),
      totalUnits: _asDouble(json['total_units']),
      historicalLandedSubtotalNet:
          _asNullableDouble(json['historical_landed_subtotal_net']),
      supplierAvailability:
          json['supplier_availability']?.toString() ?? 'unverified',
      freightAssumption: json['freight_assumption']?.toString() ?? '',
    );
  }
}

class PurchasePlanDraft {
  const PurchasePlanDraft({
    required this.id,
    required this.title,
    required this.state,
    required this.objectiveProfile,
    required this.version,
    required this.lines,
    required this.supplierGroups,
  });

  final String id;
  final String title;
  final String state;
  final String objectiveProfile;
  final int version;
  final List<PurchasePlanLine> lines;
  final List<PurchasePlanSupplierGroup> supplierGroups;

  factory PurchasePlanDraft.fromParts({
    required Map<String, dynamic> plan,
    required List<PurchasePlanLine> lines,
    required List<PurchasePlanSupplierGroup> supplierGroups,
  }) {
    return PurchasePlanDraft(
      id: plan['id']?.toString() ?? '',
      title: plan['title']?.toString() ?? 'Plan de compra',
      state: plan['state']?.toString() ?? 'draft',
      objectiveProfile: plan['objective_profile']?.toString() ?? 'balanced',
      version: _asInt(plan['version'], fallback: 1),
      lines: List.unmodifiable(lines),
      supplierGroups: List.unmodifiable(supplierGroups),
    );
  }
}

String? _asNullableText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double _asDouble(Object? value, {double fallback = 0}) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

double? _asNullableDouble(Object? value) =>
    value == null ? null : _asDouble(value);

int _asInt(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

/// Una fila de «Qué hay que comprar»: lo que el sistema propone sin que nadie
/// haya escrito una petición.
///
/// `reason` es lo más importante de la fila. Es la experiencia del que sabe,
/// puesta en palabras: «Se agotó y se vendió 3 veces en los últimos 120 días».
class PurchasePrioritySuggestion {
  const PurchasePrioritySuggestion({
    required this.rank,
    required this.source,
    required this.entityId,
    required this.productId,
    required this.title,
    required this.suggestedQuantity,
    required this.unit,
    required this.reason,
    this.signalAt,
  });

  factory PurchasePrioritySuggestion.fromJson(Map<String, dynamic> json) {
    return PurchasePrioritySuggestion(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      source: json['source']?.toString() ?? 'stockout',
      entityId: json['entityId']?.toString() ?? '',
      productId: json['productId']?.toString(),
      title: json['title']?.toString() ?? '',
      suggestedQuantity: _asDouble(json['suggestedQuantity']),
      unit: json['unit']?.toString() ?? 'unit',
      reason: json['reason']?.toString() ?? '',
      signalAt: DateTime.tryParse(json['signalAt']?.toString() ?? ''),
    );
  }

  final int rank;

  /// `workshop` · `stockout` · `below_minimum`.
  final String source;
  final String entityId;
  final String? productId;
  final String title;
  final double suggestedQuantity;
  final String unit;

  /// Por qué esta fila está aquí, en palabras del negocio.
  final String reason;
  final DateTime? signalAt;

  /// Un trabajo con cliente esperando aprieta distinto que un mínimo.
  bool get isWorkshop => source == 'workshop';
}
