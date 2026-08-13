import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' hide Category;
import 'package:http/http.dart' as http;

import '../../ai_assistant/services/ai_service.dart';
import '../../ai_assistant/services/product_identity_trace.dart';
import '../models/category_models.dart';
import '../models/inventory_models.dart';
import '../models/product_duplicate_candidate.dart';
import 'inventory_service.dart' as inv_service;
import 'product_identity/canonical_product_identity_resolver.dart';
import 'product_identity/product_catalog_identity_index.dart';
import 'product_identity/product_identity_extractor.dart';
import 'product_identity/product_identity_matcher.dart';
import 'product_identity/product_identity_profile.dart';
import 'product_identity/product_image_identity.dart';
import 'product_identity/product_visual_reading.dart';
import 'product_image_fingerprint_service.dart';

/// One invoice line asking the catalog «¿ya tengo esto?».
class ProductDuplicateProbe {
  const ProductDuplicateProbe({
    required this.name,
    this.description,
    this.sku,
    this.catalogSku,
    this.model,
    this.rawText,
    this.categoryName,
    this.categoryId,
    this.brandName,
    this.supplierId,
    this.supplierName,
    this.imageUrl,
    this.imageBytes,
    this.imageFileName,
    this.price,
    this.cost,
    this.sourcePurchaseUnitCost,
    this.supplierListingId,
    this.confirmedProductId,
    this.confirmedAliasIsImmutable = false,
    this.sourceTitle,
    this.selectedVariant,
    this.immutableVariantKey,
    this.investigation,
    this.traceId,
  });

  final String name;
  final String? description;
  final String? sku;

  /// A value known to be the ERP catalog SKU. Unlike [sku], which is retained
  /// as supplier evidence for compatibility, this may establish exact identity.
  final String? catalogSku;
  final String? model;
  final String? rawText;
  final String? categoryName;
  final String? categoryId;
  final String? brandName;
  final String? supplierId;
  final String? supplierName;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final String? imageFileName;
  final double? price;
  final double? cost;

  /// Supplier item subtotal per purchased unit, before tax/shipping/discount
  /// allocation. This is kept separate from [cost], which is the landed unit
  /// cost shown on the purchase draft.
  final double? sourcePurchaseUnitCost;

  /// Supplier listing identity (an AliExpress `itemId`), when known.
  final String? supplierListingId;

  /// A product the operator already confirmed for this exact listing variant.
  final String? confirmedProductId;

  /// Only an immutable supplier variant confirmed by an operator is exact.
  /// Legacy aliases and translated/default variant keys remain retrieval hints.
  final bool confirmedAliasIsImmutable;

  /// The supplier's own title, when [name] is an AI rewrite of it.
  final String? sourceTitle;

  /// The immutable option label selected on the supplier order line.
  ///
  /// This is stronger provenance than parsing a translated listing title. The
  /// trailing-parenthesis parser remains only as compatibility fallback for
  /// callers that have not yet transported the structured option.
  final String? selectedVariant;

  /// Immutable supplier option identity transported separately from labels.
  final String? immutableVariantKey;

  /// The primary multimodal identity receipt for this exact row revision.
  final AIProductIdentityInvestigation? investigation;

  /// Correlates authority lookup, primary investigation, every catalog gate,
  /// adjudication and the cached picker snapshot for this row revision.
  final String? traceId;
}

typedef ProductDuplicateImageLoader = Future<Uint8List?> Function(String url);

enum ProductDuplicateDecisionKind {
  authoritativeExact,
  recommendation,
  abstained,
  noMatch,
}

enum ProductDuplicateAdjudicationState {
  notRequested,
  notNeeded,
  accepted,
  abstained,
  lowConfidence,
  failed,
  tieOverflow,
  outsideTieBand,
}

/// One stable decision shared by the compact row and the operator picker.
class ProductDuplicateSearchResult {
  ProductDuplicateSearchResult({
    required this.probeIdentity,
    required this.kind,
    required List<ProductDuplicateCandidate> recommendations,
    List<ProductDuplicateCandidate>? normalCandidates,
    required List<ProductDuplicateCandidate> operatorChoices,
    required List<ProductDuplicateCandidate> categoryConflicts,
    required this.adjudicationState,
    this.investigation,
    this.adjudication,
    this.deterministicTopCandidate,
    this.reason,
  })  : recommendations = List<ProductDuplicateCandidate>.unmodifiable(
          recommendations,
        ),
        normalCandidates = List<ProductDuplicateCandidate>.unmodifiable(
          normalCandidates ?? recommendations,
        ),
        operatorChoices = List<ProductDuplicateCandidate>.unmodifiable(
          operatorChoices,
        ),
        categoryConflicts = List<ProductDuplicateCandidate>.unmodifiable(
          categoryConflicts,
        );

  final CanonicalProductIdentity probeIdentity;
  final ProductDuplicateDecisionKind kind;
  final List<ProductDuplicateCandidate> recommendations;

  /// Every viable product in the exact AI-proposed leaf before adjudication.
  /// This is deliberately distinct from the one-item recommendation and from
  /// operator choices, which may also contain ruled-out diagnostic rows.
  final List<ProductDuplicateCandidate> normalCandidates;
  final List<ProductDuplicateCandidate> operatorChoices;

  /// Same-family products placed in another authoritative tenant category.
  /// They remain inspectable but never compete with the normal shortlist.
  final List<ProductDuplicateCandidate> categoryConflicts;

  /// Leading viable candidate before AI adjudication or document-level
  /// reconciliation. This provenance is intentionally captured at the matcher
  /// boundary; reconstructing it from a final recommendation would let an AI
  /// choice manufacture listing-group consensus.
  final ProductDuplicateCandidate? deterministicTopCandidate;
  final ProductDuplicateAdjudicationState adjudicationState;
  final AIProductIdentityInvestigation? investigation;
  final AIProductMatchDecision? adjudication;
  final String? reason;

  List<AIProductMatchComponent> get compositeComponents =>
      adjudication?.decision == AIProductMatchDecisionKind.composite
          ? adjudication!.components
          : const <AIProductMatchComponent>[];

  String? get aiCompositeProposal {
    final components = compositeComponents;
    if (components.isEmpty) return null;
    final byId = <String, ProductDuplicateCandidate>{
      for (final candidate in <ProductDuplicateCandidate>[
        ...normalCandidates,
        ...operatorChoices,
        ...categoryConflicts,
      ])
        if (candidate.product.id != null) candidate.product.id!: candidate,
    };
    return components.map((component) {
      final product = byId[component.productId]?.product;
      final label = product == null
          ? component.productId
          : '${product.sku} · ${product.name}';
      return '${component.quantity} × $label';
    }).join(' + ');
  }

  bool get isAbstention => kind == ProductDuplicateDecisionKind.abstained;

  List<ProductDuplicateCandidate> forScope(
    ProductDuplicateShortlistScope scope,
  ) =>
      scope == ProductDuplicateShortlistScope.operatorChoice
          ? operatorChoices
          : recommendations;
}

/// Resolves which catalog product an invoice line refers to.
///
/// Rebuilt on 2026-08-09 after measuring the previous implementation against
/// the real 1555-product catalog: three of the seven lines of one AliExpress
/// invoice returned nothing at all, a fourth returned six different hubs all
/// labelled equally strong, and every line cost 550–700 ms of pure CPU on the
/// UI isolate. The causes were structural, not tuning:
///
/// * the product family came from a bag of words over the whole title, so a
///   crankset that ships with a bottom bracket was classified as one, and an
///   adapter that mentions tyre valves was classified as a tyre;
/// * there was no typed reading of measurements, so `32H` — a spoke count —
///   passed the model-code filter and made every 32-spoke hub an exact model
///   match;
/// * the whole catalog was re-analysed for every line.
///
/// The production review is AI-first: a versioned primary investigation owns
/// row identity, the full eligible catalog reaches deterministic contradiction
/// validation, and a grounded second pass decides among every viable exact-leaf
/// and catalog-conflict candidate. The deterministic extractor/index remains a
/// validator and diagnostic ordering trace, never a fallback identity owner.
class ProductDuplicateMatcherService {
  static const int _maxConcurrentImageDownloads = 4;
  static const int _defaultImageByteCacheMaxEntries = 48;
  static const int _defaultImageByteCacheMaxBytes = 32 * 1024 * 1024;

  ProductDuplicateMatcherService({
    required inv_service.InventoryService inventoryService,
    AIAssistantService? aiAssistantService,
    ProductDuplicateImageLoader? imageLoader,
    ProductVisualReadingService? visualReadingService,
    Iterable<String> knownBrands = const <String>[],
    Iterable<Category> categories = const <Category>[],
    Map<String, List<String>> categoryAncestry = const {},
    CanonicalProductIdentityResolver? identityResolver,
    this.enableVisualReading = true,
    this.enableMatchAdjudication = true,
    this.enableDeterministicRanking = true,
    this.requireAIPrimaryInvestigation = true,
    this.persistComputedImageFingerprints = true,
    this.imageByteCacheMaxEntries = _defaultImageByteCacheMaxEntries,
    this.imageByteCacheMaxBytes = _defaultImageByteCacheMaxBytes,
    ProductIdentityTraceSink? traceSink,
  })  : assert(imageByteCacheMaxEntries >= 0),
        assert(imageByteCacheMaxBytes >= 0),
        _inventoryService = inventoryService,
        _aiAssistantService = aiAssistantService,
        _imageLoader = imageLoader,
        _traceSink = traceSink,
        _visualReadingService = visualReadingService ??
            ProductVisualReadingService(
              aiAssistantService: aiAssistantService,
            ),
        _index = ProductCatalogIdentityIndex(
          knownBrands: knownBrands,
          categories: categories,
          categoryAncestry: categoryAncestry,
          identityResolver: identityResolver,
        ),
        _matcher = ProductIdentityMatcher(categoryAncestry: categoryAncestry),
        _identityResolver = identityResolver ??
            CanonicalProductIdentityResolver(
              categories: categories,
              knownBrands: knownBrands,
              categoryAncestry: categoryAncestry,
            ),
        _knownBrands = List<String>.unmodifiable(knownBrands);

  final inv_service.InventoryService _inventoryService;
  final AIAssistantService? _aiAssistantService;
  final ProductDuplicateImageLoader? _imageLoader;
  final ProductIdentityTraceSink? _traceSink;
  final ProductVisualReadingService _visualReadingService;
  final ProductCatalogIdentityIndex _index;
  final ProductIdentityMatcher _matcher;
  final CanonicalProductIdentityResolver _identityResolver;
  final List<String> _knownBrands;

  /// Whether the invoice photo may be read once per line to recover a family
  /// the text never states.
  final bool enableVisualReading;

  /// Whether the model may choose among the survivors when the engine is not
  /// already certain. Off in tests that measure the deterministic engine.
  final bool enableMatchAdjudication;
  final bool enableDeterministicRanking;

  /// Canonical review mode. Legacy deterministic corpus tests opt out
  /// explicitly; the production OCR flow never does.
  final bool requireAIPrimaryInvestigation;

  final bool persistComputedImageFingerprints;
  final int imageByteCacheMaxEntries;
  final int imageByteCacheMaxBytes;

  final LinkedHashMap<String, Uint8List> _imageByteCache =
      LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List?>> _imageDownloadsInFlight =
      <String, Future<Uint8List?>>{};
  int _imageByteCacheSize = 0;
  final Map<String, Future<void>> _fingerprintPersistenceCache =
      <String, Future<void>>{};
  final _AsyncPermitPool _imageDownloadPool =
      _AsyncPermitPool(_maxConcurrentImageDownloads);

  /// Model calls spent on visual readings so far, for the metrics gate.
  int get visualReadingCalls => _visualReadingService.modelCalls;

  /// Visual readings that came free with a call the OCR flow already made.
  int get primedVisualReadings => _visualReadingService.primedReadings;

  /// Hands over the photo reading that the title cleaner already obtained.
  ///
  /// One image, one model call, two answers. Without this the always-visual
  /// rule would have doubled the AI cost of every row instead of moving it.
  void primeVisualReading({
    String? imageUrl,
    Uint8List? imageBytes,
    required AIProductImageAnalysis analysis,
  }) {
    final identity = canonicalImageIdentity(imageUrl);
    final key = identity.isNotEmpty
        ? identity
        : (imageBytes == null || imageBytes.isEmpty)
            ? ''
            : ProductImageFingerprintService.contentDigest(imageBytes);
    if (key.isEmpty) return;
    _visualReadingService.prime(
      cacheKey: key,
      reading: ProductVisualReadingService.fromAnalysis(analysis),
    );
  }

  /// Legacy diagnostic compatibility only. The canonical AI-first path never
  /// restricts candidates to a deterministic score band.
  ///
  /// Inside this band the engine has no real preference and the model's
  /// reading decides; outside it, the ordering was already decided by
  /// evidence.
  static const double adjudicationTieBand = 0.10;

  /// Legacy diagnostic compatibility only. Canonical confidence is descriptive
  /// and never a linking or recommendation threshold.
  /// Below it the choices remain available to the operator, but no candidate
  /// is presented as the model-endorsed recommendation.
  static const double minimumAdjudicationConfidence = 0.85;

  /// Adjudication calls spent so far, for the cost gate.
  int _adjudications = 0;
  int get adjudicationCalls => _adjudications;
  int _lastCatalogRowsEvaluated = 0;
  int get lastCatalogRowsEvaluated => _lastCatalogRowsEvaluated;

  /// Runs the grounded second pass over the complete category review universe.
  ///
  /// In AI-first mode a legacy deterministic gate is diagnostic evidence, not
  /// an admission ticket. The model must be able to inspect a catalog row that
  /// the old parser rejected (for example `CS-M7100` vs `M7100`, or a physical
  /// measurement misread as a model code), otherwise the old matcher still
  /// decides the answer before the multimodal investigator ever sees it.
  Future<_AdjudicationOutcome> _adjudicate({
    required ProductDuplicateProbe probe,
    required CanonicalProductIdentity probeIdentity,
    required List<ProductDuplicateCandidate> candidates,
  }) async {
    final traceId = _traceIdForProbe(probe);
    ProductIdentityTrace.emit(
      traceId: traceId,
      event: 'adjudication.prepare',
      sink: _traceSink,
      data: <String, Object?>{
        'candidate_count': candidates.length,
        'ai_primary': requireAIPrimaryInvestigation,
        'image_available': probe.imageBytes?.isNotEmpty == true ||
            probe.imageUrl?.trim().isNotEmpty == true,
      },
    );
    final ai = _aiAssistantService;
    if (ai == null) {
      return _AdjudicationOutcome(
        candidates: requireAIPrimaryInvestigation
            ? const <ProductDuplicateCandidate>[]
            : candidates,
        state: ProductDuplicateAdjudicationState.notRequested,
        reason: requireAIPrimaryInvestigation
            ? 'La investigación de IA no está disponible; la fila abstiene.'
            : null,
      );
    }
    if (candidates.isEmpty) {
      return const _AdjudicationOutcome(
        candidates: <ProductDuplicateCandidate>[],
        state: ProductDuplicateAdjudicationState.notNeeded,
        reason: 'No hay candidatos comparables para la segunda pasada.',
      );
    }
    var adjudicationCandidates = candidates;
    double? legacyLeaderScore;
    if (!requireAIPrimaryInvestigation) {
      if (candidates.length < 2 ||
          candidates.first.matchTier == ProductDuplicateMatchTier.exact) {
        return _AdjudicationOutcome(
          candidates: candidates,
          state: ProductDuplicateAdjudicationState.notNeeded,
        );
      }
      legacyLeaderScore = _lineEvidenceScore(candidates.first);
      adjudicationCandidates = candidates
          .where(
            (candidate) =>
                !candidate.isRuledOut &&
                _lineEvidenceScore(candidate) >=
                    legacyLeaderScore! - adjudicationTieBand,
          )
          .toList(growable: false);
      if (adjudicationCandidates.length < 2) {
        return _AdjudicationOutcome(
          candidates: candidates,
          state: ProductDuplicateAdjudicationState.notNeeded,
        );
      }
    }
    final safeMaximum = requireAIPrimaryInvestigation
        ? AIAssistantService.maxAdjudicationCandidates
        : 12;
    if (adjudicationCandidates.length > safeMaximum) {
      return const _AdjudicationOutcome(
        candidates: <ProductDuplicateCandidate>[],
        state: ProductDuplicateAdjudicationState.tieOverflow,
        reason: 'El conjunto comparable excede el presupuesto seguro de la '
            'segunda pasada; no se truncó y la fila abstiene.',
      );
    }

    final byId = <String, ProductDuplicateCandidate>{};
    final options = <AIProductMatchOption>[];
    final candidateImages = await Future.wait<Uint8List?>(
      adjudicationCandidates.map(
        (candidate) => _firstProductImageBytes(candidate.product),
      ),
    );
    for (var index = 0; index < adjudicationCandidates.length; index++) {
      final candidate = adjudicationCandidates[index];
      final productId = candidate.product.id?.trim() ?? '';
      if (productId.isEmpty || byId.containsKey(productId)) continue;
      byId[productId] = candidate;
      final candidateIdentity = _index.identityOfProduct(candidate.product);
      final candidateProfile = candidateIdentity.profile;
      final specifications = <String, String>{
        for (final entry in candidateProfile.specs.entries)
          partSpecLabel(entry.key): partSpecValueLabel(entry.key, entry.value),
      };
      final variant = <String?>[
        candidate.product.color,
        candidate.product.size,
        candidateProfile.specs[PartSpecKind.colorVariant],
      ]
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .join(' / ');
      final model = <String?>[
        candidate.product.model,
        candidate.product.manufacturerSku,
        if (candidateProfile.primaryModelCodes.isNotEmpty)
          candidateProfile.primaryModelCodes.join(' / '),
      ]
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .join(' / ');
      options.add(AIProductMatchOption(
        id: productId,
        name: candidate.product.name,
        sku: candidate.product.sku,
        cost: candidate.product.cost,
        supplierName: candidate.product.supplierName,
        brand: candidate.product.brand,
        category: candidate.product.categoryName,
        model: model.isEmpty ? null : model,
        family: candidateIdentity.resolvedFamilyId,
        specifications: specifications,
        variant: variant.isEmpty ? null : variant,
        imageBytes: candidateImages[index],
        note: <String>[
          if (candidate.reasons.isNotEmpty)
            'Evidencia: ${candidate.reasons.join(' · ')}',
          if (candidate.objections.isNotEmpty)
            'Objeciones: ${candidate.objections.join(' · ')}',
        ].join(' | '),
      ));
      ProductIdentityTrace.emit(
        traceId: traceId,
        event: 'adjudication.candidate',
        sink: _traceSink,
        data: <String, Object?>{
          'product_id': productId,
          'sku': candidate.product.sku,
          'name': candidate.product.name,
          'catalog_cost': candidate.product.cost,
          'catalog_supplier': candidate.product.supplierName,
          'category_id': candidate.product.categoryId,
          'category_name': candidate.product.categoryName,
          'model': model.isEmpty ? null : model,
          'family': candidateIdentity.resolvedFamilyId,
          'specifications': specifications,
          'variant': variant.isEmpty ? null : variant,
          'catalog_image_available': candidateImages[index]?.isNotEmpty == true,
          'catalog_image_size_bytes': candidateImages[index]?.length ?? 0,
          'catalog_image_digest': candidateImages[index]?.isNotEmpty == true
              ? ProductIdentityTrace.digestBytes(candidateImages[index]!)
              : null,
          'legacy_ruled_out': candidate.isRuledOut,
          'legacy_reasons': candidate.reasons,
          'legacy_objections': candidate.objections,
        },
      );
    }
    if (options.isEmpty || options.length != adjudicationCandidates.length) {
      return const _AdjudicationOutcome(
        candidates: <ProductDuplicateCandidate>[],
        state: ProductDuplicateAdjudicationState.failed,
        reason: 'Un candidato no tenía identidad estable de catálogo.',
      );
    }

    _adjudications++;
    AIProductMatchDecision? decision;
    try {
      final sourceImageBytes = probe.imageBytes ??
          (probe.imageUrl == null
              ? null
              : await _downloadImageBytes(probe.imageUrl!));
      ProductIdentityTrace.emit(
        traceId: traceId,
        event: 'adjudication.source_evidence',
        sink: _traceSink,
        data: <String, Object?>{
          'landed_unit_cost': probe.cost,
          'supplier_item_unit_cost': probe.sourcePurchaseUnitCost,
          'source_image_size_bytes': sourceImageBytes?.length ?? 0,
          'source_image_digest': sourceImageBytes?.isNotEmpty == true
              ? ProductIdentityTrace.digestBytes(sourceImageBytes!)
              : null,
        },
      );
      decision = await ai
          .adjudicateProductMatch(
            invoiceTitle: _lineTitleForProbe(probe),
            supplierCode: probe.sku,
            invoiceCost: probe.cost,
            invoiceSourceUnitCost: probe.sourcePurchaseUnitCost,
            invoiceBrand: probe.investigation?.maker ?? probe.brandName,
            invoiceFamily: probeIdentity.resolvedFamilyId,
            invoiceModelCodes: probe.investigation?.modelCodes ??
                probeIdentity.profile.primaryModelCodes,
            // The purchased option travels exactly once, in
            // [selectedVariant]. Sending its values again as line specs made
            // one colour/side look like two independent witnesses.
            invoiceSpecifications: probe.investigation?.specifications ??
                <String, String>{
                  for (final entry in probeIdentity.profile.lineSpecs.entries)
                    partSpecLabel(entry.key):
                        partSpecValueLabel(entry.key, entry.value),
                },
            selectedVariant: _selectedVariantForProbe(probe),
            quantity: null,
            lineContext: probe.description,
            investigation: probe.investigation,
            options: options,
            imageBytes: sourceImageBytes,
            requireTypedBasis: requireAIPrimaryInvestigation,
            traceId: traceId,
          )
          // A grounded comparison can legitimately carry dozens of products
          // from one real leaf plus their images. Twenty-five seconds made a
          // twelve-candidate hub comparison fail in the live app even though
          // the provider was still working. Keep the UI asynchronous and give
          // the canonical multimodal pass a realistic completion window.
          .timeout(const Duration(seconds: 90));
    } on Object catch (error) {
      ProductIdentityTrace.emit(
        traceId: traceId,
        event: 'adjudication.failed',
        sink: _traceSink,
        data: <String, Object?>{
          'error_type': error.runtimeType.toString(),
          'candidate_count': options.length,
        },
      );
      return const _AdjudicationOutcome(
        candidates: <ProductDuplicateCandidate>[],
        state: ProductDuplicateAdjudicationState.failed,
        reason: 'La adjudicación de IA falló; no se conserva una elección.',
      );
    }
    ProductIdentityTrace.emit(
      traceId: traceId,
      event: 'adjudication.response',
      sink: _traceSink,
      data: <String, Object?>{
        'candidate_count': options.length,
        'decision': decision?.decision.name,
        'product_id': decision?.productId,
        'component_count': decision?.components.length ?? 0,
        'confidence': decision?.confidence,
        'invalid_product_id': decision?.invalidProductId,
        'reason': decision?.reason,
      },
    );
    if (decision == null) {
      return const _AdjudicationOutcome(
        candidates: <ProductDuplicateCandidate>[],
        state: ProductDuplicateAdjudicationState.failed,
        reason: 'La adjudicación de IA no produjo una respuesta válida.',
      );
    }
    if (decision.invalidProductId) {
      return const _AdjudicationOutcome(
        candidates: <ProductDuplicateCandidate>[],
        state: ProductDuplicateAdjudicationState.failed,
        reason:
            'La IA devolvió un producto que no estaba entre los candidatos.',
      );
    }
    if (decision.decision == AIProductMatchDecisionKind.composite) {
      return _AdjudicationOutcome(
        candidates: const <ProductDuplicateCandidate>[],
        state: ProductDuplicateAdjudicationState.abstained,
        reason: decision.reason ?? 'La IA propuso un conjunto para revisión.',
        decision: decision,
      );
    }
    if (decision.decision == AIProductMatchDecisionKind.different ||
        decision.decision == AIProductMatchDecisionKind.insufficient) {
      return _AdjudicationOutcome(
        candidates: <ProductDuplicateCandidate>[],
        state: ProductDuplicateAdjudicationState.abstained,
        reason: decision.reason ??
            (decision.decision == AIProductMatchDecisionKind.different
                ? 'La IA indicó que los candidatos ofrecidos son distintos.'
                : 'La IA indicó que no había evidencia suficiente.'),
        decision: decision,
      );
    }
    if (!decision.hasChoice) {
      return _AdjudicationOutcome(
        candidates: const <ProductDuplicateCandidate>[],
        state: ProductDuplicateAdjudicationState.failed,
        reason: 'La decisión same no contenía exactamente un producto.',
        decision: decision,
      );
    }
    if (decision.confidence < minimumAdjudicationConfidence) {
      return _AdjudicationOutcome(
        candidates: const <ProductDuplicateCandidate>[],
        state: ProductDuplicateAdjudicationState.lowConfidence,
        reason:
            'La IA no tuvo confianza suficiente para recomendar un producto.',
        decision: decision,
      );
    }
    final chosen = byId[decision.productId!];
    if (chosen == null) {
      return const _AdjudicationOutcome(
        candidates: <ProductDuplicateCandidate>[],
        state: ProductDuplicateAdjudicationState.failed,
        reason:
            'La IA devolvió un producto que no estaba entre los candidatos.',
      );
    }

    if (chosen.isRuledOut && !requireAIPrimaryInvestigation) {
      return const _AdjudicationOutcome(
        candidates: <ProductDuplicateCandidate>[],
        state: ProductDuplicateAdjudicationState.failed,
        reason: 'La IA intentó elegir un producto descartado.',
      );
    }
    if (!requireAIPrimaryInvestigation &&
        legacyLeaderScore != null &&
        _lineEvidenceScore(chosen) < legacyLeaderScore - adjudicationTieBand) {
      return _AdjudicationOutcome(
        candidates: candidates,
        state: ProductDuplicateAdjudicationState.outsideTieBand,
        reason: 'La elección de IA quedó fuera de la banda de empate.',
        decision: decision,
      );
    }

    final reason = decision.reason;
    final promoted = ProductDuplicateCandidate(
      product: chosen.product,
      // A grounded AI-first `same` decision is a recommendation for operator
      // review even when a legacy gate objected. Keep the objection and gates
      // below for transparency, but do not keep the `ruledOut` UI state after
      // the second pass explicitly selected this exact offered catalog row.
      matchTier: requireAIPrimaryInvestigation
          ? ProductDuplicateMatchTier.strong
          : chosen.matchTier,
      confidence: requireAIPrimaryInvestigation
          ? decision.confidence
          : chosen.confidence,
      reasons: List<String>.unmodifiable(<String>[
        if (reason != null && reason.isNotEmpty) reason,
        ...chosen.reasons,
      ]),
      objections: List<String>.unmodifiable(chosen.objections),
      gates: List<IdentityGate>.unmodifiable(chosen.gates),
      variantMismatch: chosen.variantMismatch,
      hasProductImage: chosen.hasProductImage,
      matchedModelCodes: Set<String>.unmodifiable(chosen.matchedModelCodes),
      isReviewOnlyFamilyScope: chosen.isReviewOnlyFamilyScope,
      lineConfidence: chosen.lineConfidence,
      variantAgreement: chosen.variantAgreement,
    );
    // An accepted adjudication establishes one recommendation. Every other
    // deterministic survivor remains available through operatorChoices; it
    // was not also endorsed merely because it entered the tie.
    return _AdjudicationOutcome(
      candidates: <ProductDuplicateCandidate>[promoted],
      state: ProductDuplicateAdjudicationState.accepted,
      reason: decision.reason,
      decision: decision,
    );
  }

  double _lineEvidenceScore(ProductDuplicateCandidate candidate) =>
      candidate.lineConfidence ?? candidate.confidence;

  Future<List<ProductDuplicateCandidate>> findCandidates({
    required ProductDuplicateProbe probe,
    required List<Product> products,
    int limit = 6,
    ProductDuplicateShortlistScope scope =
        ProductDuplicateShortlistScope.recommendation,
  }) async {
    final result = await resolveCandidates(
      probe: probe,
      products: products,
      limit: limit,
    );
    return result.forScope(scope);
  }

  Future<ProductDuplicateSearchResult> resolveCandidates({
    required ProductDuplicateProbe probe,
    required List<Product> products,
    int limit = 6,
  }) async {
    final traceId = _traceIdForProbe(probe);
    ProductIdentityTrace.emit(
      traceId: traceId,
      event: 'catalog_match.start',
      sink: _traceSink,
      data: <String, Object?>{
        'catalog_input_rows': products.length,
        'ai_primary': requireAIPrimaryInvestigation,
        'investigation_present': probe.investigation != null,
        'investigation_sufficient': probe.investigation?.isSufficient,
        'requested_category_id': probe.categoryId,
      },
    );
    _index.sync(products);
    _lastCatalogRowsEvaluated = 0;

    final profile = _buildProbeProfile(probe);
    var reading = ProductVisualReading.empty;
    if (probe.investigation == null &&
        enableVisualReading &&
        _visualReadingService.isAvailable) {
      reading = await _readProbeImage(probe);
    }
    final proposedLeafId = probe.investigation?.leafProposals.isEmpty == false
        ? probe.investigation!.leafProposals.first.categoryId
        : null;
    final probeIdentity = _identityResolver.resolveProfile(
      profile,
      reading: reading,
      categoryId: proposedLeafId ?? probe.categoryId,
      categoryPath: probe.categoryName,
    );
    ProductIdentityTrace.emit(
      traceId: traceId,
      event: 'catalog_match.probe_identity',
      sink: _traceSink,
      data: <String, Object?>{
        'family_state': probeIdentity.familyState.name,
        'family_id': probeIdentity.resolvedFamilyId,
        'category_id': proposedLeafId ?? probe.categoryId,
        'category_label': probeIdentity.category?.label,
        'model_codes': probeIdentity.profile.primaryModelCodes.toList()..sort(),
        'asserted_brand': probeIdentity.profile.assertedBrand,
      },
    );

    final probeListingIds = _extractSupplierListingIds(probe);
    final probeImageIdentity = canonicalImageIdentity(probe.imageUrl);
    final probeCatalogSku = _normalizeCode(probe.catalogSku);
    final probeFingerprint = await _probeFingerprint(probe);

    final catalog = _index.retrieve(
      probeIdentity.profile,
      identityCodes: <String>{
        if (probe.sku != null) probe.sku!,
        if (probe.catalogSku != null) probe.catalogSku!,
        ...probeListingIds,
      },
      imageIdentity: probeImageIdentity,
    );
    ProductIdentityTrace.emit(
      traceId: traceId,
      event: 'catalog_match.retrieved',
      sink: _traceSink,
      data: <String, Object?>{
        'eligible_rows': _index.length,
        'retrieved_rows': catalog.length,
        'proposed_leaf_id': proposedLeafId,
      },
    );

    final authoritative = catalog.where((product) {
      final sameCatalogSku = probeCatalogSku.isNotEmpty &&
          _normalizeCode(product.sku) == probeCatalogSku;
      final immutableAlias = probe.confirmedAliasIsImmutable &&
          probe.confirmedProductId != null &&
          probe.confirmedProductId == product.id;
      return sameCatalogSku || immutableAlias;
    }).toList(growable: false);
    final authoritativeIds =
        authoritative.map((product) => product.id ?? product.sku).toSet();
    if (authoritativeIds.length > 1) {
      return ProductDuplicateSearchResult(
        probeIdentity: probeIdentity,
        kind: ProductDuplicateDecisionKind.abstained,
        recommendations: const <ProductDuplicateCandidate>[],
        operatorChoices: const <ProductDuplicateCandidate>[],
        categoryConflicts: const <ProductDuplicateCandidate>[],
        adjudicationState: ProductDuplicateAdjudicationState.notRequested,
        reason:
            'El SKU del catálogo y el alias confirmado apuntan a productos distintos.',
      );
    }
    if (authoritative.isNotEmpty) {
      final product = authoritative.first;
      final candidateIdentity = _index.identityOfProduct(product);
      final evidence = _deterministicEvidenceFor(
        product,
        probeCatalogSku: probeCatalogSku,
        probeListingIds: probeListingIds,
        probeImageIdentity: probeImageIdentity,
        probeFingerprint: probeFingerprint,
        confirmedProductId: probe.confirmedProductId,
        confirmedAliasIsImmutable: probe.confirmedAliasIsImmutable,
      );
      final match = _matcher.evaluate(
        probe: probeIdentity.profile,
        candidate: candidateIdentity.profile,
        probeIdentity: probeIdentity,
        candidateIdentity: candidateIdentity,
        deterministic: evidence,
      );
      final exact = _buildCandidate(
        _EvaluatedCandidate(
          product: product,
          identity: candidateIdentity,
          match: match,
        ),
      );
      return ProductDuplicateSearchResult(
        probeIdentity: probeIdentity,
        kind: ProductDuplicateDecisionKind.authoritativeExact,
        recommendations: <ProductDuplicateCandidate>[exact],
        normalCandidates: <ProductDuplicateCandidate>[exact],
        operatorChoices: <ProductDuplicateCandidate>[exact],
        categoryConflicts: const <ProductDuplicateCandidate>[],
        adjudicationState: ProductDuplicateAdjudicationState.notNeeded,
        investigation: probe.investigation,
      );
    }

    final investigation = probe.investigation;
    if (requireAIPrimaryInvestigation &&
        (investigation == null || !investigation.isSufficient)) {
      return ProductDuplicateSearchResult(
        probeIdentity: probeIdentity,
        kind: ProductDuplicateDecisionKind.abstained,
        recommendations: const <ProductDuplicateCandidate>[],
        operatorChoices: const <ProductDuplicateCandidate>[],
        categoryConflicts: const <ProductDuplicateCandidate>[],
        adjudicationState: ProductDuplicateAdjudicationState.failed,
        investigation: investigation,
        reason: investigation?.abstainReason ??
            'La investigación multimodal falló o no produjo una hoja activa; '
                'no se usó un fallback heurístico.',
      );
    }

    if (!requireAIPrimaryInvestigation && !probeIdentity.hasResolvedFamily) {
      final conflict =
          probeIdentity.familyState == CanonicalProductFamilyState.conflicting;
      return ProductDuplicateSearchResult(
        probeIdentity: probeIdentity,
        kind: ProductDuplicateDecisionKind.abstained,
        recommendations: const <ProductDuplicateCandidate>[],
        operatorChoices: const <ProductDuplicateCandidate>[],
        categoryConflicts: const <ProductDuplicateCandidate>[],
        adjudicationState: ProductDuplicateAdjudicationState.notRequested,
        reason: conflict
            ? 'El título, la imagen o la categoría indican familias distintas.'
            : 'No se pudo determinar la familia del producto.',
      );
    }

    final evaluated = <_EvaluatedCandidate>[];
    final reviewOnly = <_EvaluatedCandidate>[];
    final ruledOut = <_EvaluatedCandidate>[];
    final categoryConflicts = <_EvaluatedCandidate>[];
    final candidatesByProductId = <String, _EvaluatedCandidate>{};
    var offLeafRejectedCount = 0;
    final offLeafRejectedGateCounts = <String, int>{};
    final offLeafRejectedSamples = <Map<String, Object?>>[];
    for (final product in catalog) {
      _lastCatalogRowsEvaluated++;
      final catalogIdentity = _index.identityOfProduct(product);
      final contextualized =
          catalogIdentity.contextualizedForProbe(probeIdentity);
      if (!requireAIPrimaryInvestigation && contextualized == null) continue;
      final candidateIdentity = contextualized ?? catalogIdentity;
      var match = _matcher.evaluate(
        probe: probeIdentity.profile,
        candidate: candidateIdentity.profile,
        probeIdentity: probeIdentity,
        candidateIdentity: candidateIdentity,
        deterministic: _deterministicEvidenceFor(
          product,
          probeCatalogSku: probeCatalogSku,
          probeListingIds: probeListingIds,
          probeImageIdentity: probeImageIdentity,
          probeFingerprint: probeFingerprint,
          confirmedProductId: probe.confirmedProductId,
          confirmedAliasIsImmutable: probe.confirmedAliasIsImmutable,
        ),
      );
      if (investigation != null) {
        match = _applyInvestigationContradiction(
          investigation,
          candidateIdentity,
          match,
        );
      }
      if (requireAIPrimaryInvestigation) {
        match = _admitNonContradictedForGroundedComparison(match);
      }
      if (!enableDeterministicRanking && !match.isRejected) {
        match = ProductIdentityMatch(
          verdict: IdentityMatchVerdict.possible,
          score: 0,
          lineScore: 0,
          variantAgreement: false,
          gates: match.gates,
          reasons: const <String>['Disponible para comparación AI-first'],
          objections: match.objections,
          variantMismatch: match.variantMismatch,
          matchedModelCodes: match.matchedModelCodes,
        );
      }
      final candidate = _EvaluatedCandidate(
        product: product,
        identity: candidateIdentity,
        match: match,
        categoryMissing: candidateIdentity.category == null,
      );
      final candidateProductId = product.id?.trim();
      if (candidateProductId?.isNotEmpty == true) {
        candidatesByProductId[candidateProductId!] = candidate;
      }

      if (requireAIPrimaryInvestigation && investigation != null) {
        final exactLeaf = proposedLeafId != null &&
            product.categoryId?.trim() == proposedLeafId;
        if (!exactLeaf) {
          if (match.isRejected) {
            offLeafRejectedCount++;
            final failedGateIds = match.gates
                .where((gate) => gate.failed)
                .map((gate) => gate.id)
                .toList(growable: false);
            for (final gateId in failedGateIds) {
              offLeafRejectedGateCounts[gateId] =
                  (offLeafRejectedGateCounts[gateId] ?? 0) + 1;
            }
            if (offLeafRejectedSamples.length < 32) {
              offLeafRejectedSamples.add(<String, Object?>{
                'product_id': product.id,
                'sku': product.sku,
                'category_id': product.categoryId,
                'failed_gate_ids': failedGateIds,
              });
            }
          } else {
            // Keep full evidence for every off-leaf row that can still reach
            // the grounded global comparison. Hard-rejected rows are far more
            // numerous, so their gates are aggregated below instead of
            // synchronously printing one large JSON event per catalog row.
            _traceCatalogCandidate(
              traceId,
              candidate,
              bucket: 'off_leaf_deferred_global',
              proposedLeafId: proposedLeafId,
            );
          }
          continue;
        }
        if (match.isRejected) {
          ruledOut.add(candidate);
          _traceCatalogCandidate(
            traceId,
            candidate,
            bucket: 'exact_leaf_ruled_out',
            proposedLeafId: proposedLeafId,
          );
        } else {
          evaluated.add(candidate);
          _traceCatalogCandidate(
            traceId,
            candidate,
            bucket: 'exact_leaf_viable',
            proposedLeafId: proposedLeafId,
          );
        }
        continue;
      }

      final probeCategory = probeIdentity.category;
      final candidateCategory = candidateIdentity.category;
      if (probeCategory != null &&
          candidateCategory != null &&
          !probeCategory.scopes(candidateCategory)) {
        categoryConflicts.add(candidate);
        _traceCatalogCandidate(
          traceId,
          candidate,
          bucket: 'legacy_category_conflict',
          proposedLeafId: proposedLeafId,
        );
        continue;
      }
      if (!match.isRejected) {
        if (candidateIdentity.isReviewOnlyFamilyScope) {
          reviewOnly.add(candidate);
          _traceCatalogCandidate(
            traceId,
            candidate,
            bucket: 'legacy_review_only',
            proposedLeafId: proposedLeafId,
          );
        } else {
          evaluated.add(candidate);
          _traceCatalogCandidate(
            traceId,
            candidate,
            bucket: 'legacy_viable',
            proposedLeafId: proposedLeafId,
          );
        }
        continue;
      }
      ruledOut.add(candidate);
      _traceCatalogCandidate(
        traceId,
        candidate,
        bucket: 'legacy_ruled_out',
        proposedLeafId: proposedLeafId,
      );
    }

    ProductIdentityTrace.emit(
      traceId: traceId,
      event: 'catalog_match.partitioned',
      sink: _traceSink,
      data: <String, Object?>{
        'evaluated_rows': _lastCatalogRowsEvaluated,
        'viable_count': evaluated.length,
        'review_only_count': reviewOnly.length,
        'ruled_out_count': ruledOut.length,
        'category_conflict_count': categoryConflicts.length,
        'off_leaf_rejected_count': offLeafRejectedCount,
        'off_leaf_rejected_gate_counts': offLeafRejectedGateCounts,
        'off_leaf_rejected_samples': offLeafRejectedSamples,
      },
    );

    final shown = IdentityShortlistPolicy(limit: limit).apply(
      evaluated,
      (candidate) => candidate.match,
      stableKeyOf: _stableEvaluatedKey,
    );
    final remaining = evaluated
        .where((candidate) => !shown.contains(candidate))
        .toList()
      ..sort(_compareEvaluated);
    ruledOut.sort(_compareEvaluated);
    reviewOnly.sort(_compareEvaluated);
    categoryConflicts.sort(_compareEvaluated);

    final deterministicRecommendations = <ProductDuplicateCandidate>[
      for (final candidate in shown) _buildCandidate(candidate),
    ];
    final builtNormalCandidates = <ProductDuplicateCandidate>[
      for (final candidate
          in (List<_EvaluatedCandidate>.from(evaluated)
            ..sort(_compareEvaluated)))
        _buildCandidate(candidate),
    ];
    final legacyAdjudicationPool = <ProductDuplicateCandidate>[
      for (final candidate in const IdentityShortlistPolicy(limit: 13).apply(
        evaluated,
        (candidate) => candidate.match,
        stableKeyOf: _stableEvaluatedKey,
      ))
        _buildCandidate(candidate),
    ];
    final exactLeafDetailed = <_EvaluatedCandidate>[...evaluated, ...ruledOut]
      ..sort(_compareEvaluated);
    final exactLeafAdjudicationPool = <ProductDuplicateCandidate>[
      for (final candidate in exactLeafDetailed) _buildCandidate(candidate),
    ];
    final deterministicOperatorChoices = <_EvaluatedCandidate>[
      ...shown,
      ...remaining,
      ...reviewOnly,
      ...ruledOut,
    ].map(_buildCandidate).toList(growable: false);

    // Two catalog rows that carry exactly the same identity evidence are a
    // catalog-data ambiguity, not a question for a model. Asking AI to choose
    // between them only turns SKU ordering or response noise into a false
    // recommendation. Keep every row inspectable and fail closed before the
    // adjudication cost is incurred.
    final rankedViable = <_EvaluatedCandidate>[
      ...evaluated,
      if (requireAIPrimaryInvestigation) ...categoryConflicts,
    ]..sort(_compareEvaluated);
    final duplicateCatalogRows = _strictTopCatalogDuplicates(rankedViable);
    if (duplicateCatalogRows.length >= 2) {
      final duplicateChoices = <ProductDuplicateCandidate>[
        for (final candidate in duplicateCatalogRows)
          _buildCandidate(candidate),
      ];
      return ProductDuplicateSearchResult(
        probeIdentity: probeIdentity,
        kind: ProductDuplicateDecisionKind.abstained,
        recommendations: const <ProductDuplicateCandidate>[],
        normalCandidates: builtNormalCandidates,
        operatorChoices: _promoteInsideOperatorChoices(
          duplicateChoices,
          deterministicOperatorChoices,
        ),
        categoryConflicts: const <ProductDuplicateCandidate>[],
        adjudicationState: ProductDuplicateAdjudicationState.notNeeded,
        investigation: investigation,
        reason: 'duplicate-catalog-rows: hay fichas del catálogo con la '
            'misma evidencia de identidad; elige cuál conservar.',
      );
    }

    ProductDuplicateCandidate? exactLeafTentativeSelection;
    late final _AdjudicationOutcome adjudication;
    if (!enableMatchAdjudication) {
      adjudication = _AdjudicationOutcome(
        candidates: requireAIPrimaryInvestigation
            ? const <ProductDuplicateCandidate>[]
            : deterministicRecommendations,
        state: ProductDuplicateAdjudicationState.notRequested,
        reason: requireAIPrimaryInvestigation
            ? 'La segunda pasada de IA está desactivada; no se usó el '
                'ranking heurístico como fallback.'
            : null,
      );
    } else if (!requireAIPrimaryInvestigation) {
      adjudication = await _adjudicate(
        probe: probe,
        probeIdentity: probeIdentity,
        candidates: legacyAdjudicationPool,
      );
    } else {
      ProductIdentityTrace.emit(
        traceId: traceId,
        event: 'catalog_match.leaf_first',
        sink: _traceSink,
        data: <String, Object?>{
          'leaf_id': proposedLeafId,
          'candidate_count': exactLeafAdjudicationPool.length,
          'candidate_ids': exactLeafAdjudicationPool
              .map((candidate) => candidate.product.id)
              .whereType<String>()
              .toList(growable: false),
        },
      );
      final leafAdjudication = await _adjudicate(
        probe: probe,
        probeIdentity: probeIdentity,
        candidates: exactLeafAdjudicationPool,
      );
      final leafResolved = leafAdjudication.state ==
              ProductDuplicateAdjudicationState.accepted ||
          leafAdjudication.decision?.decision ==
              AIProductMatchDecisionKind.composite;
      final tentativeLeafSame = leafAdjudication.state ==
              ProductDuplicateAdjudicationState.lowConfidence &&
          leafAdjudication.decision?.decision ==
              AIProductMatchDecisionKind.same &&
          leafAdjudication.decision?.productId != null;
      if (tentativeLeafSame) {
        final selectedId = leafAdjudication.decision!.productId!;
        for (final candidate in exactLeafAdjudicationPool) {
          if (candidate.product.id == selectedId) {
            exactLeafTentativeSelection = candidate;
            break;
          }
        }
      }
      if (leafResolved || exactLeafTentativeSelection != null) {
        adjudication = leafAdjudication;
        ProductIdentityTrace.emit(
          traceId: traceId,
          event: 'catalog_match.global_screen_skipped',
          sink: _traceSink,
          data: <String, Object?>{
            'reason': leafResolved
                ? 'exact_leaf_resolved'
                : 'exact_leaf_tentative_same_fail_closed',
            'decision': leafAdjudication.decision?.decision.name,
            'product_id': leafAdjudication.decision?.productId,
            'confidence': leafAdjudication.decision?.confidence,
          },
        );
      } else {
        final catalogScreening =
            investigation == null || _aiAssistantService == null
                ? null
                : await _aiAssistantService.screenProductCatalog(
                    investigation: investigation,
                    catalog: <AIProductCatalogCard>[
                      for (final product in catalog)
                        if (product.id?.trim().isNotEmpty == true)
                          AIProductCatalogCard(
                            id: product.id!.trim(),
                            name: product.name,
                            sku: product.sku,
                            brand: product.brand,
                            categoryId: product.categoryId,
                            category: product.categoryName,
                            model: product.model,
                            manufacturerSku: product.manufacturerSku,
                            color: product.color,
                            size: product.size,
                            supplierName: product.supplierName,
                            supplierCode: product.supplierCode,
                            description: product.description,
                          ),
                    ],
                    traceId: traceId,
                  );
        final globallyScreenedIds =
            catalogScreening?.productIds ?? const <String>[];
        ProductIdentityTrace.emit(
          traceId: traceId,
          event: 'catalog_match.global_screen',
          sink: _traceSink,
          data: <String, Object?>{
            'required': true,
            'completed': catalogScreening != null,
            'candidate_count': globallyScreenedIds.length,
            'candidate_ids': globallyScreenedIds,
          },
        );
        if (catalogScreening == null) {
          adjudication = _AdjudicationOutcome(
            candidates: const <ProductDuplicateCandidate>[],
            state: ProductDuplicateAdjudicationState.failed,
            reason: 'La hoja propuesta no resolvió el producto y la búsqueda '
                'global de IA falló después de un reintento. Las opciones de '
                'la hoja siguen disponibles para revisión manual.',
            decision: leafAdjudication.decision,
          );
        } else {
          final selected = <_EvaluatedCandidate>[];
          final selectedIds = <String>{};
          for (final productId in globallyScreenedIds) {
            final candidate = candidatesByProductId[productId];
            if (candidate == null || !selectedIds.add(productId)) continue;
            selected.add(candidate);
            if (candidate.product.categoryId?.trim() != proposedLeafId) {
              categoryConflicts.add(candidate);
            }
          }
          categoryConflicts.sort(_compareEvaluated);
          final detailedEvaluated = <_EvaluatedCandidate>[
            ...selected,
            for (final candidate in exactLeafDetailed)
              if (!selectedIds.contains(candidate.product.id)) candidate,
          ].take(AIAssistantService.maxAdjudicationCandidates).toList();
          final fullAdjudicationPool = <ProductDuplicateCandidate>[
            for (final candidate in detailedEvaluated)
              _buildCandidate(
                candidate,
                categoryConflictWith: categoryConflicts.contains(candidate)
                    ? probeIdentity.category
                    : null,
              ),
          ];
          ProductIdentityTrace.emit(
            traceId: traceId,
            event: 'catalog_match.detailed_pool',
            sink: _traceSink,
            data: <String, Object?>{
              'global_survivor_count': globallyScreenedIds.length,
              'exact_leaf_count': exactLeafDetailed.length,
              'category_conflict_count': categoryConflicts.length,
              'detailed_count': fullAdjudicationPool.length,
              'detailed_ids': fullAdjudicationPool
                  .map((candidate) => candidate.product.id)
                  .whereType<String>()
                  .toList(growable: false),
            },
          );
          adjudication = await _adjudicate(
            probe: probe,
            probeIdentity: probeIdentity,
            candidates: fullAdjudicationPool,
          );
        }
      }
    }
    final builtCategoryConflicts = <ProductDuplicateCandidate>[
      for (final candidate in categoryConflicts)
        _buildCandidate(candidate,
            categoryConflictWith: probeIdentity.category),
    ];
    var recommendations = !requireAIPrimaryInvestigation &&
            (adjudication.state ==
                    ProductDuplicateAdjudicationState.notNeeded ||
                adjudication.state ==
                    ProductDuplicateAdjudicationState.outsideTieBand)
        ? deterministicRecommendations
        : adjudication.candidates;
    var promotedCategoryConflicts = builtCategoryConflicts;
    final selectedId = adjudication.decision?.productId;
    final categoryConflictIds = builtCategoryConflicts
        .map((candidate) => candidate.product.id)
        .whereType<String>()
        .toSet();
    final choseCategoryConflict =
        selectedId != null && categoryConflictIds.contains(selectedId);
    if (choseCategoryConflict) {
      // A category conflict is catalog-placement evidence, not product-
      // identity evidence. The grounded pass may identify a misfiled row, but
      // it must remain review-only in the conflict bucket and never appear as
      // a normal recommendation under the proposed leaf.
      final chosen = recommendations.firstWhere(
        (candidate) => candidate.product.id == selectedId,
        orElse: () => builtCategoryConflicts.firstWhere(
          (candidate) => candidate.product.id == selectedId,
        ),
      );
      promotedCategoryConflicts = _promoteInsideOperatorChoices(
        <ProductDuplicateCandidate>[chosen],
        builtCategoryConflicts,
      );
    }
    recommendations = choseCategoryConflict
        ? const <ProductDuplicateCandidate>[]
        : recommendations
            .where(
              (candidate) =>
                  !categoryConflictIds.contains(candidate.product.id),
            )
            .toList(growable: false);
    final operatorChoices = _promoteInsideOperatorChoices(
      <ProductDuplicateCandidate>[
        ...recommendations,
        if (exactLeafTentativeSelection != null) exactLeafTentativeSelection,
      ],
      deterministicOperatorChoices,
    );
    final adjudicationAbstained = adjudication.state ==
            ProductDuplicateAdjudicationState.abstained ||
        adjudication.state == ProductDuplicateAdjudicationState.lowConfidence ||
        adjudication.state == ProductDuplicateAdjudicationState.failed ||
        adjudication.state == ProductDuplicateAdjudicationState.tieOverflow;
    final reviewScopedRecallExists = reviewOnly.isNotEmpty ||
        ruledOut.any(
          (candidate) => candidate.identity.isReviewOnlyFamilyScope,
        ) ||
        categoryConflicts.any(
          (candidate) => candidate.identity.isReviewOnlyFamilyScope,
        );
    final closure = recommendations.isEmpty && !reviewScopedRecallExists
        ? _index.diagnoseClosure()
        : null;
    final recallIsIncomplete = recommendations.isEmpty &&
        (reviewScopedRecallExists || (closure?.unreachableRows ?? 0) > 0);
    final recallReason = !recallIsIncomplete
        ? null
        : reviewScopedRecallExists
            ? 'Hay fichas sin familia que sólo se pueden revisar dentro de '
                'esta categoría. Verifícalas manualmente antes de crear un '
                'producto.'
            : 'El catálogo contiene ${closure!.unreachableRows} fichas sin '
                'familia ni categoría segura. Busca manualmente antes de '
                'concluir que el producto no existe.';
    final kind = requireAIPrimaryInvestigation
        ? recommendations.isNotEmpty
            ? ProductDuplicateDecisionKind.recommendation
            : ProductDuplicateDecisionKind.abstained
        : adjudicationAbstained || recallIsIncomplete
            ? ProductDuplicateDecisionKind.abstained
            : recommendations.isEmpty
                ? ProductDuplicateDecisionKind.noMatch
                : ProductDuplicateDecisionKind.recommendation;
    return ProductDuplicateSearchResult(
      probeIdentity: probeIdentity,
      kind: kind,
      recommendations: List<ProductDuplicateCandidate>.unmodifiable(
        recommendations,
      ),
      normalCandidates: builtNormalCandidates,
      operatorChoices: List<ProductDuplicateCandidate>.unmodifiable(
        operatorChoices,
      ),
      categoryConflicts: List<ProductDuplicateCandidate>.unmodifiable(
        promotedCategoryConflicts,
      ),
      deterministicTopCandidate: deterministicRecommendations.isEmpty
          ? null
          : deterministicRecommendations.first,
      adjudicationState: adjudication.state,
      investigation: investigation,
      adjudication: adjudication.decision,
      reason: choseCategoryConflict
          ? 'La IA identificó el producto, pero su ficha está fuera de la '
              'hoja propuesta; revisa y corrige la categoría del catálogo.'
          : adjudication.reason ?? recallReason,
    );
  }

  ProductIdentityMatch _applyInvestigationContradiction(
    AIProductIdentityInvestigation investigation,
    CanonicalProductIdentity candidate,
    ProductIdentityMatch current,
  ) {
    String? gateId;
    String? label;
    String? detail;
    final sourceMaker = investigation.manufacturer.asserted
        ? _normalizeCode(investigation.manufacturer.value)
        : '';
    final candidateMaker = _normalizeCode(candidate.profile.assertedBrand);
    if (sourceMaker.isNotEmpty &&
        candidateMaker.isNotEmpty &&
        sourceMaker != candidateMaker) {
      gateId = 'ai:manufacturer';
      label = 'Fabricante';
      detail = '${investigation.manufacturer.value} ≠ '
          '${candidate.profile.assertedBrand}';
    }

    final sourceModels = investigation.models
        .where((model) => model.role == AIProductModelRole.identity)
        .map((model) => _normalizeCode(model.code))
        .where((code) => code.isNotEmpty)
        .toSet();
    final candidateModels = candidate.profile.primaryModelCodes
        .map(_normalizeCode)
        .where((code) => code.isNotEmpty)
        .toSet();
    if (gateId == null &&
        sourceModels.isNotEmpty &&
        candidateModels.isNotEmpty &&
        sourceModels.intersection(candidateModels).isEmpty) {
      gateId = 'ai:model';
      label = 'Modelo';
      detail = '${sourceModels.join(' / ').toUpperCase()} ≠ '
          '${candidateModels.join(' / ').toUpperCase()}';
    }
    if (gateId == null) return current;

    final gate = IdentityGate(
      id: gateId,
      label: label!,
      outcome: IdentityGateOutcome.failed,
      detail: detail!,
    );
    return ProductIdentityMatch(
      verdict: IdentityMatchVerdict.rejected,
      score: 0,
      lineScore: 0,
      variantAgreement: false,
      gates: <IdentityGate>[...current.gates, gate],
      reasons: current.reasons,
      objections: <String>[
        ...current.objections,
        '$label incompatible: $detail',
      ],
      variantMismatch: current.variantMismatch,
      matchedModelCodes: current.matchedModelCodes,
    );
  }

  /// In the canonical flow, the deterministic engine is a contradiction
  /// validator, not an admission vocabulary. Its legacy `evidencia` rejection
  /// means only "I do not recognize enough words"; that cannot erase a novel
  /// object the primary investigation placed in a real leaf. Family, explicit
  /// manufacturer/model, and exclusive-spec failures remain hard gates.
  ProductIdentityMatch _admitNonContradictedForGroundedComparison(
    ProductIdentityMatch current,
  ) {
    if (!current.isRejected) return current;
    final failed = current.gates.where((gate) => gate.failed).toList();
    if (failed.any((gate) => gate.id != 'evidencia')) return current;

    return ProductIdentityMatch(
      verdict: IdentityMatchVerdict.possible,
      score: 0,
      lineScore: 0,
      variantAgreement: false,
      gates: <IdentityGate>[
        for (final gate in current.gates)
          if (gate.id == 'evidencia' && gate.failed)
            const IdentityGate(
              id: 'evidencia',
              label: 'Evidencia determinista',
              outcome: IdentityGateOutcome.notApplicable,
              detail: 'Sin contradicción probada; pasa a comparación AI-first',
            )
          else
            gate,
      ],
      reasons: const <String>[
        'Sin contradicción probada; disponible para comparación AI-first',
      ],
      objections: <String>[
        for (final objection in current.objections)
          if (objection != 'Sólo coinciden palabras sueltas') objection,
      ],
      variantMismatch: current.variantMismatch,
      matchedModelCodes: current.matchedModelCodes,
    );
  }

  /// The invoice photo's fingerprint, computed once per line.
  ///
  /// Bytes already downloaded for the visual reading are reused; nothing extra
  /// goes over the network for the sake of this comparison.
  Future<ProductImageFingerprint?> _probeFingerprint(
    ProductDuplicateProbe probe,
  ) async {
    final bytes = probe.imageBytes ??
        (probe.imageUrl == null
            ? null
            : await _downloadImageBytes(probe.imageUrl!));
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return ProductImageFingerprintService.fromBytes(bytes);
    } catch (error) {
      debugPrint('Probe image fingerprint failed: $error');
      return null;
    }
  }

  ProductIdentityProfile _buildProbeProfile(ProductDuplicateProbe probe) {
    final investigation = probe.investigation;
    final explicitVariant = probe.selectedVariant?.trim() ?? '';
    if (requireAIPrimaryInvestigation && investigation != null) {
      final structuredEvidence = <String>[
        ...investigation.models
            .where((model) => model.role == AIProductModelRole.identity)
            .map((model) => model.code),
        ...investigation.specs.where((spec) => spec.exclusive).map(
              (spec) => <String>[
                spec.key,
                spec.value,
                if (spec.unit != null) spec.unit!,
              ].join(' '),
            ),
      ];
      return ProductIdentityExtractor.extract(
        ProductIdentityInput(
          // The primary model owns the object label. Its cleaned display name
          // may contain inferred measurements, so it is deliberately not
          // reparsed into hard gates here.
          name: investigation.objectLabel?.trim().isNotEmpty == true
              ? investigation.objectLabel!
              : investigation.cleanedName,
          description:
              structuredEvidence.isEmpty ? null : structuredEvidence.join(' '),
          // The selected supplier option is immutable row evidence and can
          // corroborate a variant gate. Listing body/title prose has already
          // been interpreted by the primary call and cannot overrule it here.
          variantText: _selectedVariantForProbe(probe),
          brandHint: investigation.maker,
          brandIsAsserted: investigation.manufacturer.asserted,
          modelHint: investigation.modelCodes.isEmpty
              ? null
              : investigation.modelCodes.first,
          categoryPath: probe.categoryName,
          knownBrands: _knownBrands,
        ),
      );
    }
    final identitySourceTitle = _withoutMatchingTrailingSupplierOption(
      probe.sourceTitle,
      explicitVariant,
    );
    final descriptions = <String>[];
    for (final value in <String?>[
      if (investigation != null)
        <String>[
          if (investigation.objectLabel != null) investigation.objectLabel!,
          ...investigation.modelCodes,
          ...investigation.specifications.entries
              .map((entry) => '${entry.key} ${entry.value}'),
        ].join(' '),
      _withoutMatchingTrailingSupplierOption(
        probe.description,
        explicitVariant,
      ),
      identitySourceTitle,
    ]) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty || descriptions.contains(trimmed)) continue;
      descriptions.add(trimmed);
    }
    final selectedOption = _selectedVariantForProbe(probe);
    return ProductIdentityExtractor.extract(
      ProductIdentityInput(
        name: investigation?.cleanedName ?? probe.name,
        // The original supplier title is authority for more than the head
        // noun. It also carries the selected variant, model and manufacturer
        // that the readable AI name may omit (`Black`, `11S`, `K1105`). Keep
        // it in the typed evidence stream while still passing [sourceTitle]
        // separately so its family reading retains provenance and priority.
        description: descriptions.join(' ~ '),
        sourceTitle: identitySourceTitle,
        // A purchased option is variant evidence, not another product-line
        // title. Keeping it separate prevents `Black` from outweighing a
        // model/photo/material match while retaining exclusive colour gates.
        variantText: selectedOption,
        rawText: _lineEvidenceRawText(probe.rawText, explicitVariant),
        brandHint: investigation?.maker ?? probe.brandName,
        brandIsAsserted:
            investigation?.manufacturer.asserted ?? probe.brandName != null,
        modelHint: investigation?.modelCodes.isNotEmpty == true
            ? investigation!.modelCodes.first
            : probe.model,
        categoryPath: probe.categoryName,
        knownBrands: _knownBrands,
      ),
    );
  }

  static String? _selectedSupplierOption(String? sourceTitle) {
    final title = sourceTitle?.trim() ?? '';
    if (title.isEmpty) return null;
    final match = RegExp(r'\(([^()]*)\)\s*$').firstMatch(title);
    final option = match?.group(1)?.trim() ?? '';
    return option.isEmpty ? null : option;
  }

  static String? _withoutMatchingTrailingSupplierOption(
    String? sourceTitle,
    String selectedVariant,
  ) {
    final title = sourceTitle?.trim() ?? '';
    if (title.isEmpty) return sourceTitle;
    if (selectedVariant.trim().isEmpty) return title;
    final match = RegExp(r'\(([^()]*)\)\s*$').firstMatch(title);
    final trailing = match?.group(1)?.trim() ?? '';
    if (trailing.isEmpty ||
        ProductIdentityExtractor.normalize(trailing) !=
            ProductIdentityExtractor.normalize(selectedVariant)) {
      return title;
    }
    return title.substring(0, match!.start).trim();
  }

  /// Keeps genuine OCR prose while removing structured AliExpress transport
  /// markers from the evidence that may seed a product-line score.
  static String? _lineEvidenceRawText(
    String? rawText,
    String selectedVariant,
  ) {
    final raw = rawText?.trim() ?? '';
    if (raw.isEmpty) return rawText;
    final kept = <String>[];
    for (final rawLine in raw.split(RegExp(r'[\r\n]+'))) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      final marker = RegExp(
        r'^(?:VARIANT(?:_KEY)?|AI_[A-Z_]+|ITEM_ID|IMAGE_URL):',
        caseSensitive: false,
      );
      if (marker.hasMatch(line) ||
          RegExp(r'^https?://', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      line = line.replaceFirst(
        RegExp(r'^ORIGINAL_TITLE:\s*', caseSensitive: false),
        '',
      );
      line = _withoutMatchingTrailingSupplierOption(
            line,
            selectedVariant,
          ) ??
          '';
      if (line.isEmpty || kept.contains(line)) continue;
      kept.add(line);
    }
    return kept.isEmpty ? null : kept.join('\n');
  }

  static String _lineTitleForProbe(ProductDuplicateProbe probe) {
    final explicitVariant = probe.selectedVariant?.trim() ?? '';
    final source = _withoutMatchingTrailingSupplierOption(
      probe.sourceTitle,
      explicitVariant,
    )?.trim();
    if (source != null && source.isNotEmpty) return source;
    final description = _withoutMatchingTrailingSupplierOption(
      probe.description,
      explicitVariant,
    )?.trim();
    if (description != null && description.isNotEmpty) return description;
    return probe.name;
  }

  static String? _selectedVariantForProbe(ProductDuplicateProbe probe) {
    final explicit = probe.selectedVariant?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    return _selectedSupplierOption(probe.sourceTitle);
  }

  Future<ProductVisualReading> _readProbeImage(
    ProductDuplicateProbe probe,
  ) async {
    final bytes = probe.imageBytes ??
        (probe.imageUrl == null
            ? null
            : await _downloadImageBytes(probe.imageUrl!));
    if (bytes == null || bytes.isEmpty) return ProductVisualReading.empty;
    final identity = canonicalImageIdentity(probe.imageUrl);
    final cacheKey = identity.isNotEmpty
        ? identity
        : ProductImageFingerprintService.contentDigest(bytes);
    return _visualReadingService.read(
      cacheKey: cacheKey,
      bytes: bytes,
      fileName: probe.imageFileName,
      typedName: probe.name,
    );
  }

  DeterministicIdentityEvidence _deterministicEvidenceFor(
    Product product, {
    required String probeCatalogSku,
    required Set<String> probeListingIds,
    required String probeImageIdentity,
    required ProductImageFingerprint? probeFingerprint,
    required String? confirmedProductId,
    required bool confirmedAliasIsImmutable,
  }) {
    final confirmed = confirmedAliasIsImmutable &&
        confirmedProductId != null &&
        confirmedProductId == product.id;

    // The internal catalog SKU is globally unique and deterministic. A supplier
    // listing id is not: one AliExpress listing routinely holds several colours,
    // so it establishes the listing family, never the exact variant.
    final sameSku = probeCatalogSku.isNotEmpty &&
        _normalizeCode(product.sku) == probeCatalogSku;

    final sameListing = probeListingIds.isNotEmpty &&
        probeListingIds
            .intersection(_extractSupplierListingIdsFromProduct(product))
            .isNotEmpty;

    // A shared photograph corroborates a candidate, but never establishes the
    // exact sold object: one AliExpress photo can cover several variants.
    //
    // Matching only the canonical URL meant a catalog row created from another
    // listing of the same part — the ordinary case, since one part is sold by
    // several sellers — shared no identity at all, and the comparison fell
    // through to a `brand` column that says `Aliexpress`. The stored
    // fingerprint is already on the row, so this costs nothing: no download,
    // no model call.
    final sameUrl = probeImageIdentity.isNotEmpty &&
        _productImageUrls(product)
            .map(canonicalImageIdentity)
            .any((identity) => identity == probeImageIdentity);
    final samePhoto = sameUrl ||
        (probeFingerprint != null &&
            _isSamePhotograph(probeFingerprint, product));
    final sameImage = samePhoto;

    return DeterministicIdentityEvidence(
      sameCatalogSku: sameSku,
      sameSupplierListing: sameListing,
      sameImageIdentity: sameImage,
      confirmedAlias: confirmed,
    );
  }

  /// Whether the catalog row's stored fingerprint is the same photograph.
  ///
  /// The threshold is deliberately high because false visual corroboration is
  /// noisy. It still never short-circuits family, model or fitment gates.
  static const double _samePhotographFloor = 0.94;

  bool _isSamePhotograph(ProductImageFingerprint probe, Product product) {
    final stored =
        ProductImageFingerprint.fromStorageJson(product.imageFingerprint);
    if (stored == null) return false;
    return ProductImageFingerprintService.similarity(probe, stored) >=
        _samePhotographFloor;
  }

  ProductDuplicateMatchTier _tierFor(IdentityMatchVerdict verdict) {
    return switch (verdict) {
      IdentityMatchVerdict.exact => ProductDuplicateMatchTier.exact,
      IdentityMatchVerdict.strong => ProductDuplicateMatchTier.strong,
      IdentityMatchVerdict.possible => ProductDuplicateMatchTier.possible,
      IdentityMatchVerdict.rejected => ProductDuplicateMatchTier.possible,
    };
  }

  ProductDuplicateCandidate _buildCandidate(
    _EvaluatedCandidate evaluated, {
    CanonicalCategoryAuthority? categoryConflictWith,
  }) {
    final objections = <String>[
      ...evaluated.match.objections,
      if (evaluated.identity.isReviewOnlyFamilyScope)
        evaluated.identity.reviewScopeReason ??
            'La ficha no identifica el tipo de pieza; revísala manualmente.',
      if (evaluated.categoryMissing)
        'La ficha del catálogo no tiene categoría; verifica su ubicación.',
      if (categoryConflictWith != null)
        'Está en otra categoría: '
            '${evaluated.identity.category?.label ?? 'sin categoría'} '
            '(seleccionada: ${categoryConflictWith.label}).',
    ];
    return ProductDuplicateCandidate(
      product: evaluated.product,
      matchTier: evaluated.match.isRejected
          ? ProductDuplicateMatchTier.ruledOut
          : evaluated.identity.isReviewOnlyFamilyScope
              ? ProductDuplicateMatchTier.possible
              : _tierFor(evaluated.match.verdict),
      confidence: evaluated.match.score,
      reasons: List<String>.unmodifiable(evaluated.match.reasons),
      objections: List<String>.unmodifiable(objections),
      gates: List<IdentityGate>.unmodifiable(evaluated.match.gates),
      variantMismatch: evaluated.match.variantMismatch,
      hasProductImage: _productImageUrls(evaluated.product).isNotEmpty,
      matchedModelCodes: Set<String>.unmodifiable(
        evaluated.match.matchedModelCodes,
      ),
      isReviewOnlyFamilyScope: evaluated.identity.isReviewOnlyFamilyScope,
      lineConfidence: evaluated.match.lineScore,
      variantAgreement: evaluated.match.variantAgreement,
    );
  }

  int _compareEvaluated(
    _EvaluatedCandidate left,
    _EvaluatedCandidate right,
  ) {
    return IdentityShortlistPolicy.compareCandidates(
      left,
      right,
      (candidate) => candidate.match,
      stableKeyOf: _stableEvaluatedKey,
    );
  }

  static String _stableEvaluatedKey(_EvaluatedCandidate candidate) {
    final sku = candidate.product.sku.trim();
    final id = candidate.product.id?.trim();
    final stableProductKey =
        id == null || id.isEmpty ? candidate.product.name.trim() : id;
    return '$sku\u0000$stableProductKey';
  }

  List<_EvaluatedCandidate> _strictTopCatalogDuplicates(
    List<_EvaluatedCandidate> rankedViable,
  ) {
    if (rankedViable.length < 2) return const <_EvaluatedCandidate>[];
    final leader = rankedViable.first;
    final exactTopRank = rankedViable
        .where(
          (candidate) => _hasExactlyEqualMatchEvidence(leader, candidate),
        )
        .toList(growable: false);
    if (exactTopRank.length < 2) return const <_EvaluatedCandidate>[];

    for (final reference in exactTopRank) {
      final indistinguishable = exactTopRank
          .where(
            (candidate) =>
                _hasSameCatalogIdentityEvidence(reference, candidate),
          )
          .toList(growable: false);
      if (indistinguishable.length >= 2) return indistinguishable;
    }
    return const <_EvaluatedCandidate>[];
  }

  bool _hasExactlyEqualMatchEvidence(
    _EvaluatedCandidate left,
    _EvaluatedCandidate right,
  ) {
    return left.match.verdict == right.match.verdict &&
        left.match.lineScore == right.match.lineScore &&
        left.match.score == right.match.score &&
        left.match.variantAgreement == right.match.variantAgreement;
  }

  bool _hasSameCatalogIdentityEvidence(
    _EvaluatedCandidate left,
    _EvaluatedCandidate right,
  ) {
    final leftProfile = left.identity.profile;
    final rightProfile = right.identity.profile;
    return left.identity.resolvedFamilyId == right.identity.resolvedFamilyId &&
        leftProfile.assertedBrand == rightProfile.assertedBrand &&
        mapEquals(leftProfile.lineSpecs, rightProfile.lineSpecs) &&
        mapEquals(leftProfile.variantSpecs, rightProfile.variantSpecs) &&
        setEquals(
          leftProfile.primaryModelCodes,
          rightProfile.primaryModelCodes,
        ) &&
        setEquals(
          leftProfile.selectedOptionModelCodes,
          rightProfile.selectedOptionModelCodes,
        ) &&
        // These fields are intentionally stricter than the ranking inputs.
        // If supplier wording still distinguishes two rows, AI may inspect it;
        // this fail-closed branch is reserved for rows whose complete canonical
        // identity text is itself duplicated.
        leftProfile.identityText == rightProfile.identityText &&
        leftProfile.fitmentText == rightProfile.fitmentText &&
        setEquals(
          leftProfile.descriptorTokens,
          rightProfile.descriptorTokens,
        ) &&
        setEquals(
          leftProfile.compatibilityBrands,
          rightProfile.compatibilityBrands,
        ) &&
        setEquals(
          leftProfile.compatibilityModelCodes,
          rightProfile.compatibilityModelCodes,
        ) &&
        _catalogImageEvidenceKey(left.product) ==
            _catalogImageEvidenceKey(right.product);
  }

  String _catalogImageEvidenceKey(Product product) {
    final identities = _productImageUrls(product)
        .map(canonicalImageIdentity)
        .where((identity) => identity.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    final fingerprint = ProductImageFingerprint.fromStorageJson(
      product.imageFingerprint,
    );
    final fingerprintKey = fingerprint == null
        ? _rawFingerprintEvidenceKey(product.imageFingerprint)
        : <String>[
            fingerprint.averageHash.toRadixString(16),
            fingerprint.differenceHash.toRadixString(16),
            fingerprint.meanRed.toString(),
            fingerprint.meanGreen.toString(),
            fingerprint.meanBlue.toString(),
            fingerprint.aspectRatio.toString(),
          ].join(':');
    return '${identities.join('|')}\u0000$fingerprintKey';
  }

  static String _rawFingerprintEvidenceKey(Map<String, dynamic>? value) {
    if (value == null || value.isEmpty) return '';
    final keys = value.keys.toList(growable: false)..sort();
    return keys.map((key) => '$key=${value[key]}').join('|');
  }

  List<ProductDuplicateCandidate> _promoteInsideOperatorChoices(
    List<ProductDuplicateCandidate> promoted,
    List<ProductDuplicateCandidate> deterministic,
  ) {
    if (promoted.isEmpty) return deterministic;

    String keyOf(ProductDuplicateCandidate candidate) {
      final id = candidate.product.id?.trim();
      if (id != null && id.isNotEmpty) return 'id:$id';
      return 'sku:${candidate.product.sku}\u0000${candidate.product.name}';
    }

    final promotedKeys = promoted.map(keyOf).toSet();
    return <ProductDuplicateCandidate>[
      ...promoted,
      for (final candidate in deterministic)
        if (!promotedKeys.contains(keyOf(candidate))) candidate,
    ];
  }

  // ── Supplier listing identity ─────────────────────────────────────────

  Set<String> _extractSupplierListingIds(ProductDuplicateProbe probe) {
    final ids = <String>{};
    final explicit = probe.supplierListingId?.trim();
    if (explicit != null && explicit.isNotEmpty) ids.add(explicit);
    ids.addAll(
      supplierListingIdsIn(<String?>[
        probe.rawText,
        probe.sku,
        probe.description,
      ]),
    );
    return ids;
  }

  Set<String> _extractSupplierListingIdsFromProduct(Product product) {
    return supplierListingIdsIn(<String?>[
      product.supplierCode,
      product.manufacturerSku,
      product.description,
    ]);
  }

  String _normalizeCode(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  // ── Images ────────────────────────────────────────────────────────────

  Future<void> persistProductFingerprintIfNeeded(
    Product product,
    ProductImageFingerprint? fingerprint,
  ) async {
    final productId = product.id;
    if (!persistComputedImageFingerprints ||
        productId == null ||
        fingerprint == null ||
        product.imageFingerprint != null) {
      return;
    }
    await _fingerprintPersistenceCache.putIfAbsent(
      productId,
      () => _inventoryService.storeProductImageFingerprint(
        productId: productId,
        imageFingerprint: fingerprint.toStorageJson(),
      ),
    );
  }

  Future<Uint8List?> _downloadImageBytes(String imageUrl) {
    final normalizedUrl = imageUrl.trim();
    if (normalizedUrl.isEmpty) return Future<Uint8List?>.value();

    final cached = _imageByteCache.remove(normalizedUrl);
    if (cached != null) {
      // Removal + insertion promotes the entry to most recently used without
      // changing the byte accounting.
      _imageByteCache[normalizedUrl] = cached;
      return Future<Uint8List?>.value(cached);
    }

    final inFlight = _imageDownloadsInFlight[normalizedUrl];
    if (inFlight != null) return inFlight;

    late final Future<Uint8List?> tracked;
    tracked = _imageDownloadPool
        .run(() => _downloadImageBytesUncached(normalizedUrl))
        .then((bytes) {
      if (bytes != null && bytes.isNotEmpty) {
        _rememberImageBytes(normalizedUrl, bytes);
      }
      return bytes;
    }).whenComplete(() {
      if (identical(_imageDownloadsInFlight[normalizedUrl], tracked)) {
        _imageDownloadsInFlight.remove(normalizedUrl);
      }
    });
    _imageDownloadsInFlight[normalizedUrl] = tracked;
    return tracked;
  }

  void _rememberImageBytes(String url, Uint8List bytes) {
    final byteCount = bytes.lengthInBytes;
    if (imageByteCacheMaxEntries == 0 ||
        imageByteCacheMaxBytes == 0 ||
        byteCount > imageByteCacheMaxBytes) {
      return;
    }

    final previous = _imageByteCache.remove(url);
    if (previous != null) {
      _imageByteCacheSize -= previous.lengthInBytes;
    }
    while (_imageByteCache.isNotEmpty &&
        (_imageByteCache.length >= imageByteCacheMaxEntries ||
            _imageByteCacheSize + byteCount > imageByteCacheMaxBytes)) {
      final oldestUrl = _imageByteCache.keys.first;
      final oldest = _imageByteCache.remove(oldestUrl)!;
      _imageByteCacheSize -= oldest.lengthInBytes;
    }
    _imageByteCache[url] = bytes;
    _imageByteCacheSize += byteCount;
  }

  Future<Uint8List?> _downloadImageBytesUncached(String imageUrl) async {
    try {
      final injectedLoader = _imageLoader;
      if (injectedLoader != null) {
        return await injectedLoader(imageUrl);
      }
      final uri = Uri.tryParse(imageUrl);
      if (uri == null || !uri.hasScheme) return null;
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final contentType = response.headers['content-type'] ?? '';
      if (response.bodyBytes.isEmpty ||
          response.bodyBytes.length > 8 * 1024 * 1024) {
        return null;
      }
      if (contentType.isNotEmpty &&
          !contentType.startsWith('image/') &&
          !_looksLikeImageBytes(response.bodyBytes)) {
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('Product duplicate image download failed: $e');
      return null;
    }
  }

  bool _looksLikeImageBytes(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final isPng = bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    final isGif = bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
    final isWebp = bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return isPng || isJpeg || isGif || isWebp;
  }

  /// Downloads at most one catalog image for a candidate. The adjudicator
  /// receives a labeled source/candidate pair; a listing gallery is unnecessary
  /// for breaking a deterministic tie and would multiply latency and cost.
  Future<Uint8List?> _firstProductImageBytes(Product product) async {
    for (final url in _productImageUrls(product)) {
      final bytes = await _downloadImageBytes(url);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }
    return null;
  }

  List<String> _productImageUrls(Product product) {
    return [
      product.imageUrlOptimized,
      product.imageUrl,
      ...product.additionalImages,
    ].whereType<String>().map((value) => value.trim()).where((value) {
      return value.isNotEmpty;
    }).toList(growable: false);
  }

  String _traceIdForProbe(ProductDuplicateProbe probe) {
    final supplied = probe.traceId?.trim();
    if (supplied != null && supplied.isNotEmpty) return supplied;
    final receipt = probe.investigation?.receipt;
    final identityKey = <String?>[
      receipt?.listingId,
      receipt?.variantKey,
      probe.supplierListingId,
      probe.immutableVariantKey,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join('|');
    return ProductIdentityTrace.idFor(
      scope: 'ocr-product-match',
      rowKey: identityKey.isEmpty
          ? ProductIdentityTrace.digestText(probe.sourceTitle ?? probe.name)
          : identityKey,
      revision: receipt?.rowRevision ?? '0',
    );
  }

  void _traceCatalogCandidate(
    String traceId,
    _EvaluatedCandidate candidate, {
    required String bucket,
    required String? proposedLeafId,
  }) {
    final product = candidate.product;
    final match = candidate.match;
    ProductIdentityTrace.emit(
      traceId: traceId,
      event: 'catalog_match.candidate',
      sink: _traceSink,
      data: <String, Object?>{
        'bucket': bucket,
        'product_id': product.id,
        'sku': product.sku,
        'name': product.name,
        'category_id': product.categoryId,
        'category_name': product.categoryName,
        'proposed_leaf_id': proposedLeafId,
        'family_id': candidate.identity.resolvedFamilyId,
        'family_state': candidate.identity.familyState.name,
        'verdict': match.verdict.name,
        'score': match.score,
        'line_score': match.lineScore,
        'variant_agreement': match.variantAgreement,
        'variant_mismatch': match.variantMismatch,
        'review_only_family_scope': candidate.identity.isReviewOnlyFamilyScope,
        'category_missing': candidate.categoryMissing,
        'matched_models': match.matchedModelCodes.toList()..sort(),
        'gates': <Map<String, Object?>>[
          for (final gate in match.gates)
            <String, Object?>{
              'id': gate.id,
              'label': gate.label,
              'outcome': gate.outcome.name,
              'detail': gate.detail,
            },
        ],
        'reasons': match.reasons,
        'objections': match.objections,
      },
    );
  }

  /// Stable identity of an image regardless of the CDN transformation suffix
  /// AliExpress appends (`.jpg_640x640q90.jpg_.webp`).
  @visibleForTesting
  static String canonicalImageIdentity(String? imageUrl) =>
      canonicalProductImageIdentity(imageUrl);
}

class _EvaluatedCandidate {
  const _EvaluatedCandidate({
    required this.product,
    required this.identity,
    required this.match,
    this.categoryMissing = false,
  });

  final Product product;
  final CanonicalProductIdentity identity;
  final ProductIdentityMatch match;
  final bool categoryMissing;
}

class _AdjudicationOutcome {
  const _AdjudicationOutcome({
    required this.candidates,
    required this.state,
    this.reason,
    this.decision,
  });

  final List<ProductDuplicateCandidate> candidates;
  final ProductDuplicateAdjudicationState state;
  final String? reason;
  final AIProductMatchDecision? decision;
}

/// FIFO permit pool. A released permit is transferred directly to the oldest
/// waiter, so a newly-arriving task cannot jump the bound while it wakes up.
class _AsyncPermitPool {
  _AsyncPermitPool(this.maxConcurrent)
      : assert(maxConcurrent > 0, 'maxConcurrent must be positive.');

  final int maxConcurrent;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  int _active = 0;

  Future<T> run<T>(Future<T> Function() operation) async {
    await _acquire();
    try {
      return await operation();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.addLast(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    _active--;
  }
}
