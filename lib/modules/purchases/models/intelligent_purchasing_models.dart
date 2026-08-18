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
    this.media = ProductMedia.empty,
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

  /// Foto de la ficha del producto, resuelta al leer el plan.
  ///
  /// **Anulación registrada.** `handoff-t23/spec.json` dice, en
  /// `image_contract`, que «el plan no repite imágenes: ya no aportan a la
  /// decisión». El dueño pidió lo contrario y manda: en el plan real las líneas
  /// llegan de rutas distintas —candidato, canasta, compra local— y el nombre
  /// solo no basta para reconocer cuál de dos variantes quedó adentro. Se copia
  /// la geometría del contrato de imagen (`table_row`, 38 px) porque el
  /// contrato no publica una para el plan.
  final ProductMedia media;

  PurchasePlanLine withProduct({String? name, ProductMedia? media}) =>
      PurchasePlanLine(
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
        media: media ?? this.media,
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
      media: ProductMedia.fromJson(json),
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

// ───────────────────────────────────────────────────────────────────────────
// Fase B1/B2 — resolución de stock por familia y candidatos externos.
//
// **La revisión no vive en `supply_needs`.** `SupplyNeed` sale de esa tabla y
// por eso no puede llevar `revisionNo`: la autoridad es la revisión de
// interpretación más alta, y quien la conoce es el envelope autocontenido de
// cada lectura. `needVersion` y `revisionNo` viajan por acá, y son los dos
// números que los comandos de esta fase exigen.
// ───────────────────────────────────────────────────────────────────────────

/// Una página del servidor, con su total real y el siguiente corte.
///
/// `total` es del conjunto entero, no de la página: un recuento tomado de una
/// página truncada miente, y este módulo ya pagó ese error una vez.
class SupplyPage {
  const SupplyPage({
    required this.limit,
    required this.offset,
    required this.total,
    required this.returned,
    required this.hasMore,
    this.nextOffset,
  });

  static const SupplyPage empty = SupplyPage(
    limit: 0,
    offset: 0,
    total: 0,
    returned: 0,
    hasMore: false,
  );

  final int limit;
  final int offset;
  final int total;
  final int returned;
  final bool hasMore;
  final int? nextOffset;

  factory SupplyPage.fromJson(Map<String, dynamic> json) {
    return SupplyPage(
      limit: _asInt(json['limit']),
      offset: _asInt(json['offset']),
      total: _asInt(json['total']),
      returned: _asInt(json['returned']),
      hasMore: json['hasMore'] == true,
      nextOffset: json['nextOffset'] == null ? null : _asInt(json['nextOffset']),
    );
  }
}

/// Una alternativa interna del conjunto elegible, con su cobertura y con qué
/// tan verificada quedó contra los criterios técnicos.
class SupplyStockOption {
  const SupplyStockOption({
    required this.productId,
    required this.name,
    required this.availableToPromise,
    required this.coverage,
    required this.matchState,
    required this.blocksExternal,
    this.sku,
    this.media = ProductMedia.empty,
    this.matchDetail = const [],
  });

  final String productId;
  final String name;
  final String? sku;
  final ProductMedia media;
  final int availableToPromise;

  /// `full` · `partial` · `none`.
  final String coverage;

  /// `strong` · `weak` · `no_criteria` · `unverified`. `conflict` nunca llega:
  /// el servidor lo excluye antes.
  final String matchState;

  /// Evidencia por predicado, tal como la publicó el servidor.
  final List<Map<String, dynamic>> matchDetail;

  /// Esta alternativa, por sí sola, cubre entera la necesidad.
  final bool blocksExternal;

  /// «No lo sé» no es «no cumple»: se muestra rotulado, nunca oculto.
  bool get isUnverified => matchState == 'unverified';

  factory SupplyStockOption.fromJson(Map<String, dynamic> json) {
    final rawDetail = json['matchDetail'];
    return SupplyStockOption(
      productId: json['productId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sku: _asNullableText(json['sku']),
      media: ProductMedia.fromJson(json),
      availableToPromise: _asInt(json['atp']),
      coverage: json['coverage']?.toString() ?? 'none',
      matchState: json['matchState']?.toString() ?? 'no_criteria',
      matchDetail: rawDetail is List
          ? rawDetail
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList(growable: false)
          : const [],
      blocksExternal: json['blocksExternal'] == true,
    );
  }
}

/// Conteos del conjunto elegible completo.
class SupplyStockCounts {
  const SupplyStockCounts({
    this.eligible = 0,
    this.full = 0,
    this.partial = 0,
    this.none = 0,
    this.unverified = 0,
  });

  final int eligible;
  final int full;
  final int partial;
  final int none;
  final int unverified;

  factory SupplyStockCounts.fromJson(Map<String, dynamic> json) {
    return SupplyStockCounts(
      eligible: _asInt(json['eligible']),
      full: _asInt(json['full']),
      partial: _asInt(json['partial']),
      none: _asInt(json['none']),
      unverified: _asInt(json['unverified']),
    );
  }
}

/// Lectura stock-first de una necesidad, en cualquiera de sus dos carriles.
///
/// Es autocontenida a propósito: trae `needVersion` y `revisionNo`, que son
/// exactamente lo que `reject_supply_need_internal_stock_v2` y
/// `confirm_supply_need_family_choice_v1` exigen para no escribir sobre una
/// interpretación que ya cambió.
class SupplyStockResolution {
  const SupplyStockResolution({
    required this.needId,
    required this.needVersion,
    required this.revisionNo,
    required this.quantity,
    required this.unit,
    required this.lane,
    required this.status,
    required this.coverage,
    required this.blocksExternal,
    required this.items,
    required this.counts,
    this.categoryId,
    this.universeSize = 0,
    this.safeLimit,
    this.availableFields = const [],
    this.internalStockRejectionReason,
    this.page = SupplyPage.empty,
    this.familyAggregateAtp = 0,
    this.familyAggregateProvesCoverage = false,
  });

  final String needId;
  final int needVersion;
  final int revisionNo;
  final double quantity;
  final String unit;

  /// `exact` cuando la necesidad ya tiene producto confirmado; `family`
  /// mientras se resuelve por categoría y criterios.
  final String lane;

  /// `ok` · `identity_unresolved` · `needs_refinement`.
  final String status;
  final String? categoryId;
  final int universeSize;
  final int? safeLimit;

  /// Campos de la plantilla que sirven para acotar cuando el universo desbordó.
  final List<String> availableFields;
  final String coverage;

  /// Hay una alternativa interna que cubre entera la necesidad.
  final bool blocksExternal;
  final String? internalStockRejectionReason;
  final List<SupplyStockOption> items;
  final SupplyPage page;
  final SupplyStockCounts counts;

  /// Informativo. Sumar dos variantes distintas no prueba cobertura.
  final int familyAggregateAtp;
  final bool familyAggregateProvesCoverage;

  bool get isOk => status == 'ok';
  bool get isFamilyLane => lane == 'family';

  /// El paso externo está abierto: o no hay stock que bloquee, o alguien ya
  /// registró por qué no sirve.
  bool get externalAllowed =>
      !blocksExternal ||
      (internalStockRejectionReason != null &&
          internalStockRejectionReason!.trim().isNotEmpty);

  factory SupplyStockResolution.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawFields = json['availableFields'];
    final rawPage = json['page'];
    final rawCounts = json['counts'];
    return SupplyStockResolution(
      needId: json['needId']?.toString() ?? '',
      needVersion: _asInt(json['needVersion'], fallback: 1),
      revisionNo: _asInt(json['revisionNo']),
      quantity: _asDouble(json['quantity'], fallback: 1),
      unit: json['unit']?.toString() ?? 'unit',
      lane: json['lane']?.toString() ?? 'family',
      status: json['status']?.toString() ?? 'identity_unresolved',
      categoryId: _asNullableText(json['categoryId']),
      universeSize: _asInt(json['universeSize']),
      safeLimit: json['safeLimit'] == null ? null : _asInt(json['safeLimit']),
      availableFields: rawFields is List
          ? rawFields
              .map(_asNullableText)
              .whereType<String>()
              .toList(growable: false)
          : const [],
      coverage: json['coverage']?.toString() ?? 'none',
      blocksExternal: json['blocksExternal'] == true,
      internalStockRejectionReason:
          _asNullableText(json['internalStockRejectionReason']),
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) =>
                  SupplyStockOption.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const [],
      page: rawPage is Map
          ? SupplyPage.fromJson(Map<String, dynamic>.from(rawPage))
          : SupplyPage.empty,
      counts: rawCounts is Map
          ? SupplyStockCounts.fromJson(Map<String, dynamic>.from(rawCounts))
          : const SupplyStockCounts(),
      familyAggregateAtp: _asInt(json['familyAggregateAtp']),
      familyAggregateProvesCoverage:
          json['familyAggregateProvesCoverage'] == true,
    );
  }
}

/// Una señal del objetivo comercial, evaluada contra un candidato.
///
/// **`score` es nulo cuando no hay evidencia, y eso no es cero.** Un costo en
/// otra moneda, un flete que no se puede reproducir o una marca ausente son
/// «no lo sé»: se excluyen del promedio y se muestran con su razón. Convertir
/// cualquiera de los tres en 0 castigaría a un candidato por una carencia del
/// ERP, que es exactamente lo que este contrato existe para impedir.
class SupplySignalEvaluation {
  const SupplySignalEvaluation({
    required this.status,
    required this.reason,
    this.score,
  });

  /// `met` · `met_weak` · `missed` · `unknown` · `not_requested` · `delegated`.
  final String status;
  final String reason;

  /// Nulo siempre que `status` no sea una verificación concluyente.
  final double? score;

  bool get isKnown => score != null;
  bool get isUnknown => status == 'unknown';
  bool get wasRequested => status != 'not_requested';

  /// La gama se puntúa dentro del kernel; viaja para que su ausencia del
  /// promedio sea visible y no parezca un olvido.
  bool get isDelegated => status == 'delegated';

  factory SupplySignalEvaluation.fromJson(Map<String, dynamic> json) {
    return SupplySignalEvaluation(
      status: json['status']?.toString() ?? 'unknown',
      reason: json['reason']?.toString() ?? 'unknown',
      score: _asNullableDouble(json['score']),
    );
  }
}

/// Cómo calzó un candidato con lo que se pidió: criterios técnicos y objetivo
/// comercial, con la aritmética a la vista.
class SupplyRequestMatch {
  const SupplyRequestMatch({
    required this.state,
    required this.group,
    required this.knownSignalCount,
    required this.blendApplied,
    required this.signals,
    this.knownSignalAverage,
    this.legacyWeight = 0.75,
    this.signalWeight = 0.25,
  });

  static const SupplyRequestMatch unknownMatch = SupplyRequestMatch(
    state: 'no_criteria',
    group: 'actionable',
    knownSignalCount: 0,
    blendApplied: false,
    signals: <String, SupplySignalEvaluation>{},
  );

  final String state;
  final String group;
  final int knownSignalCount;
  final double? knownSignalAverage;
  final bool blendApplied;
  final double legacyWeight;
  final double signalWeight;
  final Map<String, SupplySignalEvaluation> signals;

  /// Sólo lo que el operador pidió. Una señal no pedida no se muestra: no
  /// aporta nada y llena la superficie de ruido.
  List<MapEntry<String, SupplySignalEvaluation>> get requestedSignals => signals
      .entries
      .where((entry) => entry.value.wasRequested)
      .toList(growable: false);

  bool get hasUnknownSignal =>
      signals.values.any((signal) => signal.isUnknown);

  factory SupplyRequestMatch.fromJson(Map<String, dynamic> json) {
    final rawSignals = json['signals'];
    return SupplyRequestMatch(
      state: json['state']?.toString() ?? 'no_criteria',
      group: json['group']?.toString() ?? 'actionable',
      knownSignalCount: _asInt(json['knownSignalCount']),
      knownSignalAverage: _asNullableDouble(json['knownSignalAverage']),
      blendApplied: json['blendApplied'] == true,
      legacyWeight: _asDouble(json['legacyWeight'], fallback: 0.75),
      signalWeight: _asDouble(json['signalWeight'], fallback: 0.25),
      signals: rawSignals is Map
          ? <String, SupplySignalEvaluation>{
              for (final entry in rawSignals.entries)
                if (entry.value is Map)
                  entry.key.toString(): SupplySignalEvaluation.fromJson(
                    Map<String, dynamic>.from(entry.value as Map),
                  ),
            }
          : const <String, SupplySignalEvaluation>{},
    );
  }
}

/// Un candidato externo del conjunto elegible de una necesidad.
///
/// Extiende el candidato histórico para que toda la superficie ya refactorizada
/// —tabla, cards, inspector— siga sirviendo sin reescribirse, y agrega lo que
/// esta fase aporta: el puesto del kernel antes de la mezcla, el puesto tras
/// ella, el grupo y la evidencia por señal.
class SupplyExternalCandidate extends PurchaseCandidate {
  const SupplyExternalCandidate({
    required super.candidateId,
    required super.rank,
    required super.productId,
    required super.productName,
    required super.supplierName,
    required super.supplierAvailability,
    required super.evidenceQuality,
    required super.purchaseCount,
    required super.evidenceAgeDays,
    required this.baseRank,
    required this.baseRankingScore,
    required this.overallRank,
    required this.rankingScore,
    required this.group,
    required this.matchState,
    required this.requestMatch,
    super.productSku,
    super.brand,
    super.gama,
    super.gamaIsConfident,
    super.category,
    super.supplierId,
    super.supplierWebsite,
    super.isConfirmedLocal,
    super.media,
    super.currency,
    super.latestLandedUnitCostNet,
    super.catalogSalePriceGross,
    super.projectedGrossMarginRatio,
    super.lastPurchaseAt,
    super.freightEvidence,
    this.catalogSalePriceCurrency,
    this.matchDetail = const [],
  });

  /// Puesto y puntaje del kernel, **antes** del objetivo comercial. Sin ellos
  /// nadie puede ver cuánto movió el objetivo.
  final int baseRank;
  final double baseRankingScore;

  /// Puesto sobre los dos grupos juntos; `rank` es el del grupo.
  final int overallRank;
  final double rankingScore;

  /// `actionable` · `unverified`.
  final String group;

  /// `strong` · `weak` · `no_criteria` · `unverified`.
  final String matchState;
  final List<Map<String, dynamic>> matchDetail;

  /// Moneda del precio de catálogo. Viaja para que el margen sea auditable en
  /// el cliente: sin ella nadie puede comprobar por qué quedó desconocido.
  final String? catalogSalePriceCurrency;
  final SupplyRequestMatch requestMatch;

  bool get isUnverified => group == 'unverified';

  /// El objetivo movió a este candidato respecto del ranking del kernel.
  bool get movedByTarget => requestMatch.blendApplied && overallRank != baseRank;

  factory SupplyExternalCandidate.fromJson(Map<String, dynamic> json) {
    final rawMatch = json['requestMatch'];
    final rawDetail = json['matchDetail'];
    return SupplyExternalCandidate(
      candidateId: json['candidateId']?.toString() ?? '',
      rank: _asInt(json['rank']),
      baseRank: _asInt(json['baseRank']),
      baseRankingScore: _asDouble(json['baseRankingScore']),
      overallRank: _asInt(json['overallRank']),
      rankingScore: _asDouble(json['rankingScore']),
      group: json['group']?.toString() ?? 'actionable',
      matchState: json['matchState']?.toString() ?? 'no_criteria',
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
      catalogSalePriceCurrency: _asNullableText(
        json['catalogSalePriceCurrency'],
      ),
      latestLandedUnitCostNet:
          _asNullableDouble(json['latestLandedUnitCostNet']),
      catalogSalePriceGross: _asNullableDouble(json['catalogSalePriceGross']),
      projectedGrossMarginRatio:
          _asNullableDouble(json['projectedGrossMarginRatio']),
      purchaseCount: _asInt(json['purchaseCount']),
      lastPurchaseAt:
          DateTime.tryParse(json['lastPurchaseAt']?.toString() ?? ''),
      evidenceAgeDays: _asInt(json['evidenceAgeDays']),
      evidenceQuality: json['evidenceQuality']?.toString() ?? 'weak',
      freightEvidence: json['freightEvidence']?.toString(),
      matchDetail: rawDetail is List
          ? rawDetail
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList(growable: false)
          : const [],
      requestMatch: rawMatch is Map
          ? SupplyRequestMatch.fromJson(Map<String, dynamic>.from(rawMatch))
          : SupplyRequestMatch.unknownMatch,
    );
  }
}

/// Alcance del puntaje. Dos pantallas con universos distintos dan números
/// distintos por diseño; decirlo es lo que impide compararlos.
class SupplyScoreScope {
  const SupplyScoreScope({
    this.basis = 'eligible_set',
    this.candidateCount = 0,
    this.candidateSafeLimit = 0,
    this.comparableAcrossRequests = false,
  });

  final String basis;
  final int candidateCount;
  final int candidateSafeLimit;
  final bool comparableAcrossRequests;

  factory SupplyScoreScope.fromJson(Map<String, dynamic> json) {
    return SupplyScoreScope(
      basis: json['basis']?.toString() ?? 'eligible_set',
      candidateCount: _asInt(json['candidateCount']),
      candidateSafeLimit: _asInt(json['candidateSafeLimit']),
      comparableAcrossRequests: json['comparableAcrossRequests'] == true,
    );
  }
}

/// Conteos del conjunto de candidatos externos.
class SupplyExternalCounts {
  const SupplyExternalCounts({
    this.eligibleProducts = 0,
    this.candidates = 0,
    this.actionable = 0,
    this.unverified = 0,
    this.strong = 0,
    this.weak = 0,
    this.noCriteria = 0,
  });

  final int eligibleProducts;
  final int candidates;
  final int actionable;
  final int unverified;
  final int strong;
  final int weak;
  final int noCriteria;

  factory SupplyExternalCounts.fromJson(Map<String, dynamic> json) {
    return SupplyExternalCounts(
      eligibleProducts: _asInt(json['eligibleProducts']),
      candidates: _asInt(json['candidates']),
      actionable: _asInt(json['actionable']),
      unverified: _asInt(json['unverified']),
      strong: _asInt(json['strong']),
      weak: _asInt(json['weak']),
      noCriteria: _asInt(json['noCriteria']),
    );
  }
}

/// Valores del objetivo comercial tipado.
///
/// La moneda no está acá a propósito: es del servidor y se lee del envelope,
/// que la denomina en la **revisión** que la fijó, no en la del taller de hoy.
class SupplyCommercialTargetValues {
  const SupplyCommercialTargetValues({
    this.gama,
    this.preferredBrandId,
    this.maxLandedUnitCostNet,
    this.minGrossMarginRatio,
  });

  static const SupplyCommercialTargetValues none =
      SupplyCommercialTargetValues();

  final String? gama;
  final String? preferredBrandId;
  final double? maxLandedUnitCostNet;
  final double? minGrossMarginRatio;

  bool get isEmpty =>
      gama == null &&
      preferredBrandId == null &&
      maxLandedUnitCostNet == null &&
      minGrossMarginRatio == null;

  bool get isNotEmpty => !isEmpty;

  factory SupplyCommercialTargetValues.fromJson(Map<String, dynamic> json) {
    return SupplyCommercialTargetValues(
      gama: _asNullableText(json['gama']),
      preferredBrandId: _asNullableText(json['preferredBrandId']),
      maxLandedUnitCostNet: _asNullableDouble(json['maxLandedUnitCostNet']),
      minGrossMarginRatio: _asNullableDouble(json['minGrossMarginRatio']),
    );
  }
}

/// Objetivo comercial vigente de una necesidad.
class SupplyCommercialTarget {
  const SupplyCommercialTarget({
    required this.needId,
    required this.needVersion,
    required this.needSupplyState,
    required this.currencyCode,
    required this.tenantCurrencyCode,
    required this.targetRevisionNo,
    required this.target,
    this.preferredBrandAvailable,
    this.legacyPreferenceNote,
  });

  final String needId;
  final int needVersion;
  final String needSupplyState;

  /// Moneda **de la revisión** que fijó el objetivo.
  final String currencyCode;

  /// Moneda del taller hoy. Distinta de la anterior significa que un tope
  /// guardado ya no se puede reinterpretar sin decidirlo.
  final String tenantCurrencyCode;
  final int targetRevisionNo;
  final SupplyCommercialTargetValues target;

  /// `null` cuando no hay marca preferida; `false` cuando la elegida se retiró.
  final bool? preferredBrandAvailable;

  /// La preferencia legada en texto libre. No rankea y se dice.
  final String? legacyPreferenceNote;

  bool get hasTarget => targetRevisionNo > 0 && target.isNotEmpty;
  bool get currencyRebased => currencyCode != tenantCurrencyCode;

  factory SupplyCommercialTarget.fromJson(Map<String, dynamic> json) {
    final rawTarget = json['target'];
    final rawNote = json['legacyPreferenceNote'];
    return SupplyCommercialTarget(
      needId: json['needId']?.toString() ?? '',
      needVersion: _asInt(json['needVersion'], fallback: 1),
      needSupplyState: json['needSupplyState']?.toString() ?? 'open',
      currencyCode: json['currencyCode']?.toString() ?? 'CLP',
      tenantCurrencyCode: json['tenantCurrencyCode']?.toString() ?? 'CLP',
      targetRevisionNo: _asInt(json['targetRevisionNo']),
      target: rawTarget is Map
          ? SupplyCommercialTargetValues.fromJson(
              Map<String, dynamic>.from(rawTarget),
            )
          : SupplyCommercialTargetValues.none,
      preferredBrandAvailable: json['preferredBrandAvailable'] is bool
          ? json['preferredBrandAvailable'] as bool
          : null,
      legacyPreferenceNote:
          rawNote is Map ? _asNullableText(rawNote['text']) : null,
    );
  }
}

/// Candidatos externos de una necesidad, en sus dos grupos y con sus dos
/// páginas independientes.
class SupplyExternalCandidates {
  const SupplyExternalCandidates({
    required this.needId,
    required this.needVersion,
    required this.revisionNo,
    required this.needSupplyState,
    required this.quantity,
    required this.unit,
    required this.status,
    required this.lane,
    required this.rankingProfile,
    required this.rankingProfileSource,
    required this.items,
    required this.unverifiedItems,
    required this.counts,
    required this.page,
    required this.unverifiedPage,
    required this.targetRevisionNo,
    required this.target,
    required this.targetCurrencyCode,
    required this.tenantCurrencyCode,
    this.rankingVersion = 'supply-need-external-candidates-v1',
    this.categoryId,
    this.universeSize = 0,
    this.safeLimit,
    this.availableFields = const [],
    this.coverage = 'none',
    this.blocksExternal = false,
    this.internalStockRejectionReason,
    this.candidateUniverseSize = 0,
    this.candidateSafeLimit = 0,
    this.scoreScope = const SupplyScoreScope(),
    this.preferredBrandAvailable,
    this.legacyPreferenceNote,
    this.supplierAvailabilitySemantics = 'historical_only_unverified',
  });

  final String needId;
  final int needVersion;
  final int revisionNo;
  final String needSupplyState;
  final double quantity;
  final String unit;

  /// `success` · `supply_closed` · `identity_unresolved` · `needs_refinement`
  /// · `technical_conflict` · `analysis_too_broad` · `no_eligible_products`
  /// · `no_historical_candidates`.
  final String status;
  final String lane;
  final String rankingProfile;

  /// `revision` · `default` · `default_unrecognized`.
  final String rankingProfileSource;
  final String rankingVersion;
  final String? categoryId;
  final int universeSize;
  final int? safeLimit;
  final List<String> availableFields;
  final String coverage;
  final bool blocksExternal;
  final String? internalStockRejectionReason;

  /// Fanout histórico y su techo. **No** son `universeSize`/`safeLimit`: esos
  /// cuentan productos del catálogo, y estos combinaciones ya compradas.
  final int candidateUniverseSize;
  final int candidateSafeLimit;
  final SupplyScoreScope scoreScope;
  final List<SupplyExternalCandidate> items;
  final List<SupplyExternalCandidate> unverifiedItems;
  final SupplyExternalCounts counts;
  final SupplyPage page;
  final SupplyPage unverifiedPage;
  final int targetRevisionNo;
  final SupplyCommercialTargetValues target;
  final String targetCurrencyCode;
  final String tenantCurrencyCode;
  final bool? preferredBrandAvailable;
  final String? legacyPreferenceNote;
  final String supplierAvailabilitySemantics;

  bool get isSuccess => status == 'success';
  bool get isFamilyLane => lane == 'family';
  bool get hasAnyCandidate => items.isNotEmpty || unverifiedItems.isNotEmpty;

  /// Vista compatible con la superficie histórica: sólo el grupo accionable.
  /// Los no verificados tienen su propio bloque rotulado y no se mezclan.
  PurchaseRanking get asRanking => PurchaseRanking(
        status: isSuccess ? 'success' : 'verifiedEmpty',
        items: items,
        hasMore: page.hasMore,
        supplierAvailabilitySemantics: supplierAvailabilitySemantics,
      );

  static List<SupplyExternalCandidate> _candidates(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) =>
            SupplyExternalCandidate.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  factory SupplyExternalCandidates.fromJson(Map<String, dynamic> json) {
    final rawFields = json['availableFields'];
    final rawTarget = json['target'];
    final rawNote = json['legacyPreferenceNote'];
    final rawScope = json['scoreScope'];
    final rawCounts = json['counts'];
    final rawPage = json['page'];
    final rawUnverifiedPage = json['unverifiedPage'];
    return SupplyExternalCandidates(
      needId: json['needId']?.toString() ?? '',
      needVersion: _asInt(json['needVersion'], fallback: 1),
      revisionNo: _asInt(json['revisionNo']),
      needSupplyState: json['needSupplyState']?.toString() ?? 'open',
      quantity: _asDouble(json['quantity'], fallback: 1),
      unit: json['unit']?.toString() ?? 'unit',
      status: json['status']?.toString() ?? 'no_historical_candidates',
      lane: json['lane']?.toString() ?? 'family',
      rankingProfile: json['rankingProfile']?.toString() ?? 'balanced',
      rankingProfileSource:
          json['rankingProfileSource']?.toString() ?? 'default',
      rankingVersion: json['rankingVersion']?.toString() ??
          'supply-need-external-candidates-v1',
      categoryId: _asNullableText(json['categoryId']),
      universeSize: _asInt(json['universeSize']),
      safeLimit: json['safeLimit'] == null ? null : _asInt(json['safeLimit']),
      availableFields: rawFields is List
          ? rawFields
              .map(_asNullableText)
              .whereType<String>()
              .toList(growable: false)
          : const [],
      coverage: json['coverage']?.toString() ?? 'none',
      blocksExternal: json['blocksExternal'] == true,
      internalStockRejectionReason:
          _asNullableText(json['internalStockRejectionReason']),
      candidateUniverseSize: _asInt(json['candidateUniverseSize']),
      candidateSafeLimit: _asInt(json['candidateSafeLimit']),
      scoreScope: rawScope is Map
          ? SupplyScoreScope.fromJson(Map<String, dynamic>.from(rawScope))
          : const SupplyScoreScope(),
      items: _candidates(json['items']),
      unverifiedItems: _candidates(json['unverifiedItems']),
      counts: rawCounts is Map
          ? SupplyExternalCounts.fromJson(Map<String, dynamic>.from(rawCounts))
          : const SupplyExternalCounts(),
      page: rawPage is Map
          ? SupplyPage.fromJson(Map<String, dynamic>.from(rawPage))
          : SupplyPage.empty,
      unverifiedPage: rawUnverifiedPage is Map
          ? SupplyPage.fromJson(Map<String, dynamic>.from(rawUnverifiedPage))
          : SupplyPage.empty,
      targetRevisionNo: _asInt(json['targetRevisionNo']),
      target: rawTarget is Map
          ? SupplyCommercialTargetValues.fromJson(
              Map<String, dynamic>.from(rawTarget),
            )
          : SupplyCommercialTargetValues.none,
      targetCurrencyCode: json['targetCurrencyCode']?.toString() ?? 'CLP',
      tenantCurrencyCode: json['tenantCurrencyCode']?.toString() ?? 'CLP',
      preferredBrandAvailable: json['preferredBrandAvailable'] is bool
          ? json['preferredBrandAvailable'] as bool
          : null,
      legacyPreferenceNote:
          rawNote is Map ? _asNullableText(rawNote['text']) : null,
      supplierAvailabilitySemantics:
          json['supplierAvailabilitySemantics']?.toString() ??
              'historical_only_unverified',
    );
  }
}

/// El servidor exige decidir primero el stock interno.
///
/// **Es un estado, no una caída.** El backend levanta `P0001
/// stock_first_required` cuando el conjunto elegible cubre entera la necesidad
/// y nadie registró por qué no sirve. Tratarlo como error genérico dejaría al
/// operador delante de «no se pudo completar el análisis» sin la única acción
/// que lo desatasca.
class SupplyStockFirstRequired implements Exception {
  const SupplyStockFirstRequired(this.needId);

  final String needId;

  @override
  String toString() => 'SupplyStockFirstRequired($needId)';
}

/// La necesidad o su interpretación cambiaron entre la lectura y el comando.
///
/// Recuperable releyendo: nunca se reintenta con la versión vieja, porque esa
/// versión ya describe otra cosa.
class SupplyConcurrencyConflict implements Exception {
  const SupplyConcurrencyConflict(this.needId);

  final String needId;

  @override
  String toString() => 'SupplyConcurrencyConflict($needId)';
}

/// Traduce los dos fallos del servidor que este flujo sabe atender.
///
/// Vive acá y no dentro del servicio para que la regla sea afirmable sin un
/// cliente de red: es contrato, no fontanería. Cualquier otro error devuelve
/// `null` y sube tal cual — inventarle un significado sería peor que no
/// entenderlo.
Object? supplyCommandFailure(
  String needId, {
  required String? code,
  required String message,
}) {
  if (code == 'P0001' && message.contains('stock_first_required')) {
    return SupplyStockFirstRequired(needId);
  }
  if (code == '40001') return SupplyConcurrencyConflict(needId);
  return null;
}

/// Copia de un estado de la lectura de candidatos externos: qué pasó y qué
/// puede hacer el operador.
///
/// Los siete estados **no** son «sin resultados». Colapsarlos borraría
/// justamente la acción siguiente, que es distinta en cada uno.
class SupplyExternalStatusCopy {
  const SupplyExternalStatusCopy({
    required this.title,
    required this.body,
    this.actionLabel,
  });

  final String title;
  final String body;

  /// `null` cuando no hay nada que el operador pueda hacer desde acá.
  final String? actionLabel;
}

/// Palabras de cada estado. Un solo dueño, para que la tabla y las cards no
/// digan cosas distintas del mismo hecho.
SupplyExternalStatusCopy supplyExternalStatusCopy(
  SupplyExternalCandidates result,
) {
  switch (result.status) {
    case 'supply_closed':
      return const SupplyExternalStatusCopy(
        title: 'Esta necesidad ya está resuelta',
        body: 'Está cubierta o cancelada, así que no corresponde comprar.',
      );
    case 'identity_unresolved':
      return const SupplyExternalStatusCopy(
        title: 'Falta decir qué categoría es',
        body: 'Sin categoría no hay conjunto que comparar. '
            'Edita la necesidad para dejarla dentro de una.',
        actionLabel: 'Editar la necesidad',
      );
    case 'needs_refinement':
      return SupplyExternalStatusCopy(
        title: 'La categoría es demasiado amplia',
        body: result.availableFields.isEmpty
            ? 'Hay ${result.universeSize} productos por evaluar y el máximo '
                'seguro es ${result.safeLimit ?? 0}. Acota la necesidad.'
            : 'Hay ${result.universeSize} productos por evaluar y el máximo '
                'seguro es ${result.safeLimit ?? 0}. Puedes acotar por: '
                '${result.availableFields.join(', ')}.',
        actionLabel: 'Editar la necesidad',
      );
    case 'technical_conflict':
      return const SupplyExternalStatusCopy(
        title: 'El producto confirmado contradice lo pedido',
        body: 'Su ficha no cumple los criterios de la necesidad, así que '
            'buscar proveedores para él sería trabajo perdido.',
        actionLabel: 'Editar la necesidad',
      );
    case 'analysis_too_broad':
      return SupplyExternalStatusCopy(
        title: 'Demasiado historial que comparar',
        body: 'El conjunto tiene ${result.candidateUniverseSize} '
            'combinaciones de producto y proveedor, sobre un máximo seguro de '
            '${result.candidateSafeLimit}. Acota la necesidad y vuelve.',
        actionLabel: 'Editar la necesidad',
      );
    case 'no_eligible_products':
      return const SupplyExternalStatusCopy(
        title: 'Ningún producto del catálogo cumple los criterios',
        body: 'Todos quedaron fuera por contradecir la ficha. '
            'Revisa los criterios de la necesidad.',
        actionLabel: 'Editar la necesidad',
      );
    case 'no_historical_candidates':
      return const SupplyExternalStatusCopy(
        title: 'Nunca se ha comprado nada de este conjunto',
        body: 'Hay productos que sirven, pero ninguno tiene historial de '
            'compra: no hay proveedor que comparar todavía.',
        actionLabel: 'Registrar una compra local',
      );
    default:
      return const SupplyExternalStatusCopy(
        title: 'Sin alternativas para comparar',
        body: 'La consulta fue válida y no encontró candidatos.',
      );
  }
}

/// Por qué una señal quedó como quedó, en palabras del negocio.
///
/// Cada razón `unknown` nombra su causa: sin eso, la superficie diría «no
/// verificable» y el operador no sabría si falta un dato, falta el flete o hay
/// dos monedas de por medio.
String supplySignalReasonLabel(String reason) {
  switch (reason) {
    case 'brand_identity_match':
      return 'Es la marca pedida.';
    case 'brand_legacy_text_match':
      return 'La ficha sólo nombra la marca en texto: coincide, pero es '
          'evidencia débil.';
    case 'brand_identity_differs':
      return 'Es otra marca.';
    case 'brand_text_differs':
      return 'El texto de la ficha nombra otra marca.';
    case 'brand_absent':
      return 'La ficha no tiene marca, así que no se puede comparar.';
    case 'preferred_brand_name_unavailable':
      return 'No se pudo leer el nombre vigente de la marca preferida.';
    case 'cost_within_ceiling':
      return 'El costo aterrizado cabe en el tope.';
    case 'cost_above_ceiling':
      return 'El costo aterrizado supera el tope.';
    case 'landed_cost_missing':
      return 'No hay costo aterrizado registrado.';
    case 'margin_meets_floor':
      return 'El margen proyectado alcanza el piso.';
    case 'margin_below_floor':
      return 'El margen proyectado queda bajo el piso.';
    case 'margin_missing':
      return 'Falta precio de venta para proyectar el margen.';
    case 'incomplete_landed_cost':
      return 'El flete de esa compra no se puede repartir, así que el costo '
          'aterrizado no es comparable.';
    case 'currency_mismatch_no_fx':
      return 'Están en monedas distintas y el sistema no convierte.';
    case 'scored_by_kernel':
      return 'Ya pesa en el puntaje del ranking.';
    case 'not_requested':
      return 'No se pidió.';
    default:
      return 'Sin evidencia suficiente.';
  }
}

/// Nombre de la señal, tal como el operador la fijó.
String supplySignalLabel(String key) {
  switch (key) {
    case 'preferredBrandId':
      return 'Marca preferida';
    case 'maxLandedUnitCostNet':
      return 'Tope de costo';
    case 'minGrossMarginRatio':
      return 'Margen mínimo';
    case 'gama':
      return 'Gama';
    default:
      return key;
  }
}

/// Veredicto corto de una señal. `unknown` **nunca** se dice como un cero.
String supplySignalVerdict(SupplySignalEvaluation signal) {
  switch (signal.status) {
    case 'met':
      return 'Cumple';
    case 'met_weak':
      return 'Cumple (evidencia débil)';
    case 'missed':
      return 'No cumple';
    case 'unknown':
      return 'No verificable';
    case 'delegated':
      return 'En el puntaje';
    default:
      return 'No se pidió';
  }
}
