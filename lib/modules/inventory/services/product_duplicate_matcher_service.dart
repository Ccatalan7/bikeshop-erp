import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../ai_assistant/services/ai_service.dart';
import '../models/inventory_models.dart';
import '../models/product_duplicate_candidate.dart';
import 'inventory_service.dart' as inv_service;
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
    this.model,
    this.rawText,
    this.categoryName,
    this.brandName,
    this.supplierId,
    this.supplierName,
    this.imageUrl,
    this.imageBytes,
    this.imageFileName,
    this.price,
    this.cost,
    this.supplierListingId,
    this.confirmedProductId,
    this.sourceTitle,
  });

  final String name;
  final String? description;
  final String? sku;
  final String? model;
  final String? rawText;
  final String? categoryName;
  final String? brandName;
  final String? supplierId;
  final String? supplierName;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final String? imageFileName;
  final double? price;
  final double? cost;

  /// Supplier listing identity (an AliExpress `itemId`), when known.
  final String? supplierListingId;

  /// A product the operator already confirmed for this exact listing variant.
  final String? confirmedProductId;

  /// The supplier's own title, when [name] is an AI rewrite of it.
  final String? sourceTitle;
}

typedef ProductDuplicateImageLoader = Future<Uint8List?> Function(String url);

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
/// The work now happens in three separable, pure pieces: an extractor that
/// turns prose into typed evidence, an index that remembers that evidence and
/// returns a bounded shortlist, and a matcher that eliminates before it ranks.
/// This class owns only the parts that need the network: the catalog, the
/// image bytes, and one visual reading per line.
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
    Map<String, List<String>> categoryAncestry = const {},
    this.enableVisualReading = true,
    this.enableMatchAdjudication = true,
    this.persistComputedImageFingerprints = true,
    this.imageByteCacheMaxEntries = _defaultImageByteCacheMaxEntries,
    this.imageByteCacheMaxBytes = _defaultImageByteCacheMaxBytes,
  })  : assert(imageByteCacheMaxEntries >= 0),
        assert(imageByteCacheMaxBytes >= 0),
        _inventoryService = inventoryService,
        _aiAssistantService = aiAssistantService,
        _imageLoader = imageLoader,
        _visualReadingService = visualReadingService ??
            ProductVisualReadingService(
              aiAssistantService: aiAssistantService,
            ),
        _index = ProductCatalogIdentityIndex(
          knownBrands: knownBrands,
          categoryAncestry: categoryAncestry,
        ),
        _matcher = ProductIdentityMatcher(categoryAncestry: categoryAncestry),
        _knownBrands = List<String>.unmodifiable(knownBrands);

  final inv_service.InventoryService _inventoryService;
  final AIAssistantService? _aiAssistantService;
  final ProductDuplicateImageLoader? _imageLoader;
  final ProductVisualReadingService _visualReadingService;
  final ProductCatalogIdentityIndex _index;
  final ProductIdentityMatcher _matcher;
  final List<String> _knownBrands;

  /// Whether the invoice photo may be read once per line to recover a family
  /// the text never states.
  final bool enableVisualReading;

  /// Whether the model may choose among the survivors when the engine is not
  /// already certain. Off in tests that measure the deterministic engine.
  final bool enableMatchAdjudication;

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

  /// How far below the engine's leader a model pick may still be accepted.
  ///
  /// Inside this band the engine has no real preference and the model's
  /// reading decides; outside it, the ordering was already decided by
  /// evidence.
  static const double adjudicationTieBand = 0.10;

  /// Adjudication calls spent so far, for the cost gate.
  int _adjudications = 0;
  int get adjudicationCalls => _adjudications;

  /// Lets the model choose among the survivors when the engine is unsure.
  ///
  /// The engine is better at cutting fifteen hundred products down and at
  /// refusing what physically cannot fit. It is worse at knowing what a thing
  /// *is* when the word is missing from its dictionary — and supplier Spanish
  /// is larger than any dictionary. So the two are split by what each is good
  /// at, and this runs only where the engine has no decisive answer.
  Future<List<ProductDuplicateCandidate>> _adjudicate({
    required ProductDuplicateProbe probe,
    required List<ProductDuplicateCandidate> candidates,
  }) async {
    final ai = _aiAssistantService;
    if (ai == null || candidates.length < 2) return candidates;
    // Deterministic identity needs no opinion, and a shared manufacturer model
    // code is already decisive.
    if (candidates.first.matchTier == ProductDuplicateMatchTier.exact ||
        candidates.first.matchTier == ProductDuplicateMatchTier.strong) {
      return candidates;
    }

    final byId = <String, ProductDuplicateCandidate>{};
    final options = <AIProductMatchOption>[];
    for (final candidate in candidates) {
      final sku = candidate.product.sku.trim();
      if (sku.isEmpty || byId.containsKey(sku)) continue;
      byId[sku] = candidate;
      options.add(AIProductMatchOption(
        id: sku,
        name: candidate.product.name,
        brand: candidate.product.brand,
        category: candidate.product.categoryName,
        note: candidate.objections.isEmpty
            ? candidate.reasons.join(' · ')
            : candidate.objections.join(' · '),
      ));
    }
    if (options.length < 2) return candidates;

    _adjudications++;
    final decision = await ai.adjudicateProductMatch(
      invoiceTitle: probe.sourceTitle?.trim().isNotEmpty == true
          ? probe.sourceTitle!
          : probe.name,
      supplierCode: probe.sku,
      invoiceBrand: probe.brandName,
      options: options,
      imageBytes: probe.imageBytes,
    );
    if (decision == null || !decision.hasChoice) return candidates;
    final chosen = byId[decision.productId!];
    if (chosen == null) return candidates;

    // The choice reorders and explains; it never promotes a row a gate ruled
    // out, and it never invents one.
    if (chosen.isRuledOut) return candidates;

    // The model breaks ties. It does not overrule a ranking that is already
    // clear.
    //
    // Measured on AE150626: the engine had the right product at 0.64 —
    // `Herradura de Tiro Lateral ZTTO ASA 2.5D`, same brand and same model as
    // the invoice — and the model promoted a V-brake noodle sitting at 0.37.
    // Letting an opinion outrank a decided ordering makes the answer worse,
    // which is the opposite of why the step exists. Where the engine is
    // undecided the candidates sit close together, and there the model's
    // reading is exactly what is missing.
    final leader = candidates.first.confidence;
    if (chosen.confidence < leader - adjudicationTieBand) return candidates;
    final reason = decision.reason;
    final promoted = ProductDuplicateCandidate(
      product: chosen.product,
      matchTier: chosen.matchTier,
      confidence: chosen.confidence,
      reasons: <String>[
        if (reason != null && reason.isNotEmpty) reason,
        ...chosen.reasons,
      ],
      objections: chosen.objections,
      gates: chosen.gates,
      variantMismatch: chosen.variantMismatch,
      hasProductImage: chosen.hasProductImage,
      matchedModelCodes: chosen.matchedModelCodes,
    );
    return <ProductDuplicateCandidate>[
      promoted,
      for (final candidate in candidates)
        if (!identical(candidate, chosen)) candidate,
    ];
  }

  Future<List<ProductDuplicateCandidate>> findCandidates({
    required ProductDuplicateProbe probe,
    required List<Product> products,
    int limit = 6,
    ProductDuplicateShortlistScope scope =
        ProductDuplicateShortlistScope.recommendation,
  }) async {
    _index.sync(products);

    // The photo is read for EVERY product that has one, not only when the text
    // failed to name a family.
    //
    // Gating vision on `familyId == null` meant a wrong-but-non-null family
    // skipped the image entirely — and a wrong family is the ordinary output
    // of a relational word. `Herradura de freno` is a bracket whose title
    // names the system it serves; the head-noun reader answered `freno`, the
    // gate saw a non-null answer, and the only evidence that could have
    // corrected it was never consulted.
    //
    // The cost stays bounded because the reading is keyed by canonical image
    // identity: one model call per distinct image, cached across lines and
    // across invoices, and never one per candidate.
    var profile = _buildProbeProfile(probe);
    if (enableVisualReading && _visualReadingService.isAvailable) {
      final reading = await _readProbeImage(probe);
      if (reading.isUseful) {
        profile = profile.withVisualReading(
          visualFamilyId: reading.familyId,
          visualTerms: reading.terms,
          visualConfidence: reading.confidence,
        );
      }
    }

    final probeListingIds = _extractSupplierListingIds(probe);
    final probeImageIdentity = canonicalImageIdentity(probe.imageUrl);
    final probeSku = _normalizeCode(probe.sku);
    final probeFingerprint = await _probeFingerprint(probe);

    final shortlist = _index.retrieve(
      profile,
      identityCodes: <String>{
        if (probe.sku != null) probe.sku!,
        ...probeListingIds,
      },
      imageIdentity: probeImageIdentity,
    );
    if (shortlist.isEmpty) return const <ProductDuplicateCandidate>[];

    final evaluated = <_EvaluatedCandidate>[];
    final ruledOut = <_EvaluatedCandidate>[];
    final probeFamily = profile.effectiveFamilyId;
    for (final product in shortlist) {
      final candidateProfile = _index.profileOfProduct(product);
      final match = _matcher.evaluate(
        probe: profile,
        candidate: candidateProfile,
        deterministic: _deterministicEvidenceFor(
          product,
          probeSku: probeSku,
          probeListingIds: probeListingIds,
          probeImageIdentity: probeImageIdentity,
          probeFingerprint: probeFingerprint,
          confirmedProductId: probe.confirmedProductId,
        ),
      );
      if (!match.isRejected) {
        evaluated.add(_EvaluatedCandidate(product: product, match: match));
        continue;
      }
      // Ruled out, but the same kind of object. The operator may be looking at
      // it because the specification this engine read is the thing that is
      // wrong.
      final sameFamily = probeFamily != null &&
          candidateProfile.effectiveFamilyId == probeFamily;
      if (sameFamily) {
        ruledOut.add(_EvaluatedCandidate(product: product, match: match));
      }
    }

    final shown = IdentityShortlistPolicy(limit: limit)
        .apply(evaluated, (candidate) => candidate.match);

    final offered = <_EvaluatedCandidate>[
      ...shown,
      if (scope == ProductDuplicateShortlistScope.operatorChoice) ...[
        // Everything else that survived retrieval and the family test, ranked.
        // The row's floor is deliberately not applied here: the operator opened
        // this list precisely because the row's single answer was not enough.
        ...evaluated.where((candidate) => !shown.contains(candidate)),
        ...(ruledOut
          ..sort(
              (left, right) => right.match.score.compareTo(left.match.score))),
      ],
    ];

    final built = <ProductDuplicateCandidate>[
      for (final candidate in offered.take(
        scope == ProductDuplicateShortlistScope.operatorChoice
            ? math.max(limit, 24)
            : limit,
      ))
        ProductDuplicateCandidate(
          product: candidate.product,
          matchTier: candidate.match.isRejected
              ? ProductDuplicateMatchTier.ruledOut
              : _tierFor(candidate.match.verdict),
          confidence: candidate.match.score,
          reasons: candidate.match.reasons,
          objections: candidate.match.objections,
          gates: candidate.match.gates,
          variantMismatch: candidate.match.variantMismatch,
          hasProductImage: _productImageUrls(candidate.product).isNotEmpty,
          matchedModelCodes: candidate.match.matchedModelCodes,
        ),
    ];

    if (!enableMatchAdjudication) return built;
    return _adjudicate(probe: probe, candidates: built);
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
    return ProductIdentityExtractor.extract(
      ProductIdentityInput(
        name: probe.name,
        description: probe.description,
        sourceTitle: probe.sourceTitle,
        rawText: probe.rawText,
        brandHint: probe.brandName,
        modelHint: probe.model,
        categoryPath: probe.categoryName,
        knownBrands: _knownBrands,
      ),
    );
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
    required String probeSku,
    required Set<String> probeListingIds,
    required String probeImageIdentity,
    required ProductImageFingerprint? probeFingerprint,
    required String? confirmedProductId,
  }) {
    final confirmed =
        confirmedProductId != null && confirmedProductId == product.id;

    // The internal catalog SKU is globally unique and deterministic. A supplier
    // listing id is not: one AliExpress listing routinely holds several colours,
    // so it establishes the listing family, never the exact variant.
    final sameSku =
        probeSku.isNotEmpty && _normalizeCode(product.sku) == probeSku;

    final sameListing = probeListingIds.isNotEmpty &&
        probeListingIds
            .intersection(_extractSupplierListingIdsFromProduct(product))
            .isNotEmpty;

    // The same photograph is the same product, whatever URL it arrived by.
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
  /// The threshold is deliberately high: this is *identity* evidence and it
  /// short-circuits every gate, so «parecida» is not enough. Two different
  /// parts photographed on the same white background score well below it;
  /// the same picture re-hosted scores at or above it.
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

  List<String> _productImageUrls(Product product) {
    return [
      product.imageUrlOptimized,
      product.imageUrl,
      ...product.additionalImages,
    ].whereType<String>().map((value) => value.trim()).where((value) {
      return value.isNotEmpty;
    }).toList(growable: false);
  }

  /// Stable identity of an image regardless of the CDN transformation suffix
  /// AliExpress appends (`.jpg_640x640q90.jpg_.webp`).
  @visibleForTesting
  static String canonicalImageIdentity(String? imageUrl) =>
      canonicalProductImageIdentity(imageUrl);
}

class _EvaluatedCandidate {
  const _EvaluatedCandidate({required this.product, required this.match});

  final Product product;
  final ProductIdentityMatch match;
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
