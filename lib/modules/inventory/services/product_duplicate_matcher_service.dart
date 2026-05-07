import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../ai_assistant/services/ai_service.dart';
import '../models/inventory_models.dart';
import '../models/product_duplicate_candidate.dart';
import 'inventory_service.dart' as inv_service;
import 'product_image_fingerprint_service.dart';

class ProductDuplicateProbe {
  const ProductDuplicateProbe({
    required this.name,
    this.description,
    this.sku,
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
  });

  final String name;
  final String? description;
  final String? sku;
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
}

class _BottomBracketSpec {
  const _BottomBracketSpec({
    required this.shellMm,
    required this.axleMm,
  });

  final double shellMm;
  final double axleMm;
}

class _ProductShapeProfile {
  const _ProductShapeProfile({
    required this.attributes,
    required this.exclusiveValues,
    required this.requiredAttributes,
  });

  final Set<String> attributes;
  final Map<String, String> exclusiveValues;
  final Set<String> requiredAttributes;

  bool get isEmpty =>
      attributes.isEmpty &&
      exclusiveValues.isEmpty &&
      requiredAttributes.isEmpty;
}

/// Per-candidate inputs needed to recompute `overallScore` after the
/// detailed image second-pass replaces the cheap fingerprint score.
/// Stored in a static cache keyed by the candidate identity so we don't
/// have to widen the public `ProductDuplicateCandidate` API.
class _DuplicateRescoreInputs {
  _DuplicateRescoreInputs({
    required this.product,
    required this.keywordScore,
    required this.semanticScore,
    required this.identityScore,
    required this.metadataScore,
    required this.catalogSpecScore,
    required this.shapeAttributeScore,
    required this.hasImageProbe,
  });

  final Product product;
  final double keywordScore;
  final double semanticScore;
  final double identityScore;
  final double metadataScore;
  final double catalogSpecScore;
  final double shapeAttributeScore;
  final bool hasImageProbe;

  // Bounded transient cache, populated and drained inside one
  // `findCandidates` call. Not used outside that scope.
  static final Map<ProductDuplicateCandidate, _DuplicateRescoreInputs> _cache =
      <ProductDuplicateCandidate, _DuplicateRescoreInputs>{};
}

class ProductDuplicateMatcherService {
  ProductDuplicateMatcherService({
    required inv_service.InventoryService inventoryService,
    AIAssistantService? aiAssistantService,
  })  : _inventoryService = inventoryService,
        _aiAssistantService = aiAssistantService ?? AIAssistantService();

  final inv_service.InventoryService _inventoryService;
  final AIAssistantService _aiAssistantService;

  Future<List<ProductDuplicateCandidate>> findCandidates({
    required ProductDuplicateProbe probe,
    required List<Product> products,
    int limit = 6,
  }) async {
    final scopedProducts = _supplierScopedProducts(probe, products);
    final probeText = _buildProbeText(probe);
    final probeIntrinsicText = _buildProbeIntrinsicText(probe);
    final probeFamilies = _inferProductFamilies(probeIntrinsicText);
    final probeShapeProfile = _inferProductShapeProfile(
      probeIntrinsicText,
      probeFamilies,
    );
    final probeTokens = _extractSimilarityTokens(probeText);
    final probeFingerprint = await _resolveProbeFingerprint(probe);
    final hasImageProbe = probeFingerprint != null ||
        _normalizeImageIdentity(probe.imageUrl).isNotEmpty;

    final productsById = <String, Product>{
      for (final product in products)
        if (product.id != null) product.id!: product,
    };
    final candidatesById = <String, Product>{
      for (final product in scopedProducts)
        if (product.id != null) product.id!: product,
    };
    final semanticScores = <String, double>{};
    final catalogSpecScores = <String, double>{};

    if (probeFamilies.any(_narrowFamilies.contains)) {
      for (final product in products) {
        if (product.id == null || !product.isActive || product.isService) {
          continue;
        }
        final productFamilies = _inferProductFamilies(
          _buildProductSimilarityText(product),
        );
        if (probeFamilies.intersection(productFamilies).isNotEmpty) {
          candidatesById[product.id!] = product;
        }
      }
    }

    for (final product in products) {
      if (product.id == null || !product.isActive || product.isService) {
        continue;
      }
      final catalogSpecScore = _computeCatalogSpecScore(probe, product);
      if (catalogSpecScore >= 0.78) {
        catalogSpecScores[product.id!] = catalogSpecScore;
        candidatesById[product.id!] = product;
      }
    }

    if (probeText.trim().length >= 12) {
      final vector = await _aiAssistantService.generateEmbedding(probeText);
      if (vector != null) {
        try {
          final semanticMatches =
              await _inventoryService.searchProductsSemantic(
            vector,
            threshold: 0.65,
            limit: 12,
          );
          for (final result in semanticMatches) {
            final id = result['id']?.toString();
            if (id == null || id.isEmpty) continue;
            final product = productsById[id];
            if (product == null || !product.isActive || product.isService) {
              continue;
            }
            final similarity =
                (((result['similarity'] as num?)?.toDouble() ?? 0).clamp(0, 1))
                    .toDouble();
            semanticScores[id] = math.max(semanticScores[id] ?? 0, similarity);
            candidatesById[id] = product;
          }
        } catch (e) {
          debugPrint('Product duplicate semantic search failed: $e');
        }
      }
    }

    final candidates = <ProductDuplicateCandidate>[];
    for (final product in candidatesById.values) {
      if (!product.isActive || product.isService) continue;
      final productText = _buildProductSimilarityText(product);
      final productFamilies = _inferProductFamilies(productText);
      final productShapeProfile = _inferProductShapeProfile(
        productText,
        productFamilies,
      );
      final productTokens = _extractSimilarityTokens(productText);
      final baseKeywordScore = _computeKeywordScore(probeTokens, productTokens);
      final aliExpressScore = _computeAliExpressScore(
        probe,
        product,
        probeTokens,
        productTokens,
      );
      final catalogSpecScore = catalogSpecScores[product.id] ?? 0.0;
      final keywordScore = math.max(
        math.max(baseKeywordScore, aliExpressScore),
        catalogSpecScore,
      );
      final identityScore = _computeIdentityScore(probe, product);
      final familyConflict = _hasHardFamilyConflict(
        probeFamilies,
        productFamilies,
      );
      if (familyConflict && identityScore < 1) {
        continue;
      }
      if (_hasHardShapeProfileConflict(
            probeShapeProfile,
            productShapeProfile,
          ) &&
          identityScore < 1) {
        continue;
      }
      // Soft category gate: when the probe carries a confident category and
      // the candidate's category is set but completely unrelated (no shared
      // word, no substring), drop it unless image/identity is already strong.
      // Avoids "buscar parecidos" surfacing pastillas when probe is cassette.
      if (identityScore < 1 &&
          probe.categoryName != null &&
          probe.categoryName!.trim().isNotEmpty &&
          (product.categoryName ?? '').trim().isNotEmpty) {
        final probeCat = _normalizeSimilarityText(probe.categoryName!);
        final productCat = _normalizeSimilarityText(product.categoryName!);
        if (probeCat.isNotEmpty &&
            productCat.isNotEmpty &&
            probeCat != productCat &&
            !productCat.contains(probeCat) &&
            !probeCat.contains(productCat)) {
          final probeCatTokens =
              probeCat.split(' ').where((t) => t.length >= 4).toSet();
          final productCatTokens =
              productCat.split(' ').where((t) => t.length >= 4).toSet();
          if (probeCatTokens.isNotEmpty &&
              productCatTokens.isNotEmpty &&
              probeCatTokens.intersection(productCatTokens).isEmpty) {
            // No category overlap at all. Require an image-based or catalog
            // spec match to keep this candidate.
            if (catalogSpecScore < 0.86) {
              // Will be re-evaluated below; mark with a sentinel by skipping
              // unless the image score (computed next) is strong enough.
              // Compute image score now so we can decide.
              final earlyImageScore = await _computeImageScore(
                probe,
                probeFingerprint,
                product,
                allowRemoteFingerprint: false,
              );
              if (earlyImageScore < 0.7) {
                continue;
              }
            }
          }
        }
      }
      final metadataScore = _computeMetadataScore(probe, product);
      final semanticScore = semanticScores[product.id] ?? 0.0;
      final shapeAttributeScore = _computeShapeAttributeScore(
        probeShapeProfile,
        productShapeProfile,
      );
      final sameAliExpressFamily =
          _sameAliExpressSupplierFamily(probe, product);
      final aliExpressTextMatch = aliExpressScore >= 0.48;
      final allowRemoteImageFingerprint = probeFingerprint != null &&
          (identityScore > 0 ||
              keywordScore >= 0.08 ||
              metadataScore >= 0.20 ||
              _sameAliExpressSupplierFamily(probe, product));
      final imageScore = await _computeImageScore(
        probe,
        probeFingerprint,
        product,
        allowRemoteFingerprint: allowRemoteImageFingerprint,
      );

      final overallScore = _combineDuplicateScores(
        keywordScore: keywordScore,
        semanticScore: semanticScore,
        imageScore: imageScore,
        identityScore: identityScore,
        metadataScore: metadataScore,
        catalogSpecScore: catalogSpecScore,
        shapeAttributeScore: shapeAttributeScore,
        hasImageProbe: hasImageProbe,
      );

      if (!_shouldKeepDuplicateCandidate(
        overallScore: overallScore,
        keywordScore: keywordScore,
        semanticScore: semanticScore,
        imageScore: imageScore,
        identityScore: identityScore,
        metadataScore: metadataScore,
        shapeAttributeScore: shapeAttributeScore,
        sameAliExpressFamily: sameAliExpressFamily,
        aliExpressTextMatch: aliExpressTextMatch,
      )) {
        continue;
      }

      candidates.add(ProductDuplicateCandidate(
        product: product,
        overallScore: overallScore,
        keywordScore: keywordScore,
        semanticScore: semanticScore,
        imageScore: imageScore,
        aiTypeScore: 0,
        identityScore: identityScore,
        metadataScore: metadataScore,
        hasProductImage: _productImageUrls(product).isNotEmpty,
        signals: _buildDuplicateSignals(
          product,
          keywordScore: keywordScore,
          semanticScore: semanticScore,
          imageScore: imageScore,
          identityScore: identityScore,
          metadataScore: metadataScore,
          shapeAttributeScore: shapeAttributeScore,
          catalogSpecScore: catalogSpecScore,
        ),
      ));
      _DuplicateRescoreInputs._cache[candidates.last] = _DuplicateRescoreInputs(
        product: product,
        keywordScore: keywordScore,
        semanticScore: semanticScore,
        identityScore: identityScore,
        metadataScore: metadataScore,
        catalogSpecScore: catalogSpecScore,
        shapeAttributeScore: shapeAttributeScore,
        hasImageProbe: hasImageProbe,
      );
    }

    candidates.sort((a, b) => b.overallScore.compareTo(a.overallScore));

    // ============================================================
    // SECOND PASS: detailed shape/color similarity on top candidates.
    // The basic stored fingerprint is an 8x8 average/difference hash plus
    // mean RGB. For two centered objects on a white background (typical
    // product photos), it cannot tell apart different shapes or distinguish
    // "black thing" vs "silver thing" — the dHash sees the same "darker
    // center, brighter edges" gradient. The detailed scorer adds silhouette
    // IoU + edge layout + color layout from raw bytes, which is what the
    // user actually expects when they click "Buscar parecidos".
    // ============================================================
    if (hasImageProbe && candidates.isNotEmpty) {
      await _upgradeTopCandidatesWithDetailedImage(
        probe: probe,
        candidates: candidates,
        topK: math.max(limit * 3, 18),
      );
      candidates.sort((a, b) => b.overallScore.compareTo(a.overallScore));
      await _upgradeTopCandidatesWithDetailedImage(
        probe: probe,
        candidates: candidates,
        topK: limit,
        onlyMissingDebug: true,
      );
      candidates.sort((a, b) => b.overallScore.compareTo(a.overallScore));
    }
    // Drop scoring-input cache entries for candidates we are about to
    // expose, to keep memory bounded.
    for (final c in candidates) {
      _DuplicateRescoreInputs._cache.remove(c);
    }
    return candidates.take(limit).toList();
  }

  Future<void> _upgradeTopCandidatesWithDetailedImage({
    required ProductDuplicateProbe probe,
    required List<ProductDuplicateCandidate> candidates,
    required int topK,
    bool onlyMissingDebug = false,
  }) async {
    // Resolve probe bytes once.
    Uint8List? probeBytes = probe.imageBytes;
    if (probeBytes == null) {
      final probeUrl = probe.imageUrl?.trim();
      if (probeUrl != null && probeUrl.isNotEmpty) {
        probeBytes = await _downloadImageBytes(probeUrl);
      }
    }
    if (probeBytes == null || probeBytes.isEmpty) {
      _markImageDebugUnavailable(
        candidates,
        topK: topK,
        reason: 'probe raw no disponible',
        onlyMissingDebug: onlyMissingDebug,
      );
      return;
    }

    final upgradeTargets = candidates.take(topK).toList();
    final replacements = <int, ProductDuplicateCandidate>{};

    // Run downloads/vision in parallel but bound concurrency by Future.wait on
    // the display band (typically 12).
    final detailedFutures = <Future<void>>[];
    for (var i = 0; i < upgradeTargets.length; i++) {
      final candidate = upgradeTargets[i];
      if (onlyMissingDebug && candidate.imageDebugSignals.isNotEmpty) {
        continue;
      }
      final urls = _productImageUrls(candidate.product);
      if (urls.isEmpty) {
        _replaceCandidateAt(
          candidates,
          candidate,
          _copyCandidateWithImageDebug(
            candidate,
            const ['dbg sin imagen catalogo'],
          ),
        );
        continue;
      }
      detailedFutures.add(() async {
        final productBytes = await _downloadImageBytes(urls.first);
        if (productBytes == null || productBytes.isEmpty) {
          _replaceCandidateAt(
            candidates,
            candidate,
            _copyCandidateWithImageDebug(
              candidate,
              const ['dbg imagen catalogo no descargable'],
            ),
          );
          return;
        }
        final debug =
            ProductImageFingerprintService.detailedSimilarityDebugFromBytes(
          probeBytes!,
          productBytes,
        );
        if (debug == null) {
          _replaceCandidateAt(
            candidates,
            candidate,
            _copyCandidateWithImageDebug(
              candidate,
              const ['dbg imagen no decodificable'],
            ),
          );
          return;
        }
        final aiComparison =
            await _aiAssistantService.compareProductImagesForDuplicate(
          probeImageBytes: probeBytes,
          candidateImageBytes: productBytes,
          probeName: probe.name,
          candidateName: candidate.product.name,
          candidateBrand: candidate.product.brand,
          candidateCategory: candidate.product.categoryName,
        );
        // Trust the detailed score directly. Earlier we blended it with
        // the cheap fingerprint score, but that floored the result and
        // pulled visually-different parts back up: a derailleur hanger
        // with no real shape overlap was scoring 63% only because the
        // cheap aHash/dHash agreed (both "centered dark thing on white").
        // The detailed scorer already has its own shape-mismatch cap and
        // strong-shape boost, so its raw output is what we want here.
        final basic = candidate.imageScore;
        final visualScore = aiComparison == null
            ? debug.score
            : (aiComparison.samePartScore * 0.72 + debug.score * 0.28)
                .clamp(0, 1)
                .toDouble();

        final inputs = _DuplicateRescoreInputs._cache[candidate];
        if (inputs == null) {
          _replaceCandidateAt(
            candidates,
            candidate,
            _copyCandidateWithImageDebug(
              candidate,
              const ['dbg scorer sin cache'],
            ),
          );
          return;
        }
        final aiRejectsVisualMatch = aiComparison != null &&
            aiComparison.confidence >= 0.55 &&
            aiComparison.samePartScore < 0.55;
        final suppressSemantic =
            (debug.shapeMismatchCapApplied || aiRejectsVisualMatch) &&
                inputs.keywordScore <= 0.30 &&
                inputs.identityScore < 1;
        final effectiveSemanticScore = suppressSemantic
            ? math.min(inputs.semanticScore, 0.15)
            : inputs.semanticScore;
        final newOverall = _combineDuplicateScores(
          keywordScore: inputs.keywordScore,
          semanticScore: effectiveSemanticScore,
          imageScore: visualScore,
          identityScore: inputs.identityScore,
          metadataScore: inputs.metadataScore,
          catalogSpecScore: inputs.catalogSpecScore,
          shapeAttributeScore: inputs.shapeAttributeScore,
          hasImageProbe: inputs.hasImageProbe,
        );
        final upgraded = ProductDuplicateCandidate(
          product: candidate.product,
          overallScore: newOverall,
          keywordScore: candidate.keywordScore,
          semanticScore: effectiveSemanticScore,
          imageScore: visualScore,
          aiTypeScore: aiComparison?.samePartScore ?? candidate.aiTypeScore,
          identityScore: candidate.identityScore,
          metadataScore: candidate.metadataScore,
          hasProductImage: candidate.hasProductImage,
          signals: candidate.signals,
          imageDebugSignals: _buildImageDebugSignals(
            cheapScore: basic,
            debug: debug,
            aiComparison: aiComparison,
            semanticSuppressed: suppressSemantic,
          ),
        );
        final idx = candidates.indexOf(candidate);
        if (idx >= 0) replacements[idx] = upgraded;
        _DuplicateRescoreInputs._cache[upgraded] = inputs;
        _DuplicateRescoreInputs._cache.remove(candidate);
      }());
    }

    await Future.wait(detailedFutures);
    replacements.forEach((idx, upgraded) {
      candidates[idx] = upgraded;
    });
  }

  void _markImageDebugUnavailable(
    List<ProductDuplicateCandidate> candidates, {
    required int topK,
    required String reason,
    required bool onlyMissingDebug,
  }) {
    for (final candidate in candidates.take(topK).toList()) {
      if (onlyMissingDebug && candidate.imageDebugSignals.isNotEmpty) continue;
      _replaceCandidateAt(
        candidates,
        candidate,
        _copyCandidateWithImageDebug(candidate, ['dbg $reason']),
      );
    }
  }

  void _replaceCandidateAt(
    List<ProductDuplicateCandidate> candidates,
    ProductDuplicateCandidate previous,
    ProductDuplicateCandidate replacement,
  ) {
    final idx = candidates.indexOf(previous);
    if (idx < 0) return;
    final inputs = _DuplicateRescoreInputs._cache[previous];
    if (inputs != null) {
      _DuplicateRescoreInputs._cache[replacement] = inputs;
      _DuplicateRescoreInputs._cache.remove(previous);
    }
    candidates[idx] = replacement;
  }

  ProductDuplicateCandidate _copyCandidateWithImageDebug(
    ProductDuplicateCandidate candidate,
    List<String> imageDebugSignals,
  ) {
    return ProductDuplicateCandidate(
      product: candidate.product,
      overallScore: candidate.overallScore,
      keywordScore: candidate.keywordScore,
      semanticScore: candidate.semanticScore,
      imageScore: candidate.imageScore,
      aiTypeScore: candidate.aiTypeScore,
      identityScore: candidate.identityScore,
      metadataScore: candidate.metadataScore,
      hasProductImage: candidate.hasProductImage,
      signals: candidate.signals,
      imageDebugSignals: imageDebugSignals,
    );
  }

  List<String> _buildImageDebugSignals({
    required double cheapScore,
    required ProductImageSimilarityDebug debug,
    required AIProductVisualComparison? aiComparison,
    required bool semanticSuppressed,
  }) {
    String pct(double value) => '${(value * 100).round()}%';

    return <String>[
      'dbg cheap ${pct(cheapScore)}',
      'final ${pct(debug.score)}',
      'shape ${pct(debug.silhouetteScore)}',
      'profile ${pct(debug.radialShapeScore)}',
      'contour ${pct(debug.contourShapeScore)}',
      'fg ${pct(debug.foregroundShapeScore)}',
      'iou ${pct(debug.overlapShapeScore)}',
      'edge ${pct(debug.edgeScore)}',
      'fg color ${pct(debug.foregroundColorScore)}',
      'color ${pct(debug.colorLayoutScore)}',
      'center ${pct(debug.centerGridScore)}',
      'full ${pct(debug.fullGridScore)}',
      'aspect ${pct(debug.aspectScore)}',
      if (aiComparison != null) 'AI same ${pct(aiComparison.samePartScore)}',
      if (aiComparison != null) 'AI shape ${pct(aiComparison.shapeScore)}',
      if (aiComparison != null) 'AI color ${pct(aiComparison.colorScore)}',
      if (aiComparison != null) 'AI conf ${pct(aiComparison.confidence)}',
      if (aiComparison != null)
        aiComparison.componentTypeMatch ? 'AI tipo ok' : 'AI tipo no',
      if (aiComparison?.reason != null && aiComparison!.reason!.isNotEmpty)
        'AI: ${aiComparison.reason}',
      if (debug.shapeBoostApplied) 'boost',
      if (debug.shapeMismatchCapApplied) 'cap',
      if (semanticSuppressed) 'sem cap',
    ];
  }

  List<Product> _supplierScopedProducts(
    ProductDuplicateProbe probe,
    List<Product> products,
  ) {
    final supplierId = probe.supplierId?.trim();
    final supplierName = probe.supplierName;
    if ((supplierId == null || supplierId.isEmpty) &&
        (supplierName == null || supplierName.trim().isEmpty)) {
      return products;
    }

    final isAliExpress =
        _inventoryService.isAliExpressSupplierName(supplierName);
    final scoped = products.where((product) {
      if (isAliExpress) {
        return _inventoryService.isAliExpressSupplierName(product.supplierName);
      }
      if (supplierId != null && supplierId.isNotEmpty) {
        return product.supplierId == supplierId;
      }
      return (product.supplierName ?? '').trim().toLowerCase() ==
          supplierName!.trim().toLowerCase();
    }).toList();

    return scoped.length >= 5 ? scoped : products;
  }

  String _buildProbeText(ProductDuplicateProbe probe) {
    return [
      probe.name,
      probe.sku,
      probe.description,
      probe.rawText,
      probe.categoryName,
      probe.brandName,
      probe.supplierName,
      _normalizeFileNameHint(probe.imageFileName),
      _normalizeFileNameHint(probe.imageUrl),
      if ((probe.price ?? 0) > 0) 'precio ${probe.price!.toStringAsFixed(0)}',
      if ((probe.cost ?? 0) > 0) 'costo ${probe.cost!.toStringAsFixed(0)}',
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
  }

  String _buildProbeIntrinsicText(ProductDuplicateProbe probe) {
    return [
      probe.name,
      probe.sku,
      probe.description,
      probe.rawText,
      probe.supplierName,
      _normalizeFileNameHint(probe.imageFileName),
      _normalizeFileNameHint(probe.imageUrl),
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
  }

  String _buildProductSimilarityText(Product product) {
    return [
      product.name,
      product.sku,
      product.supplierCode,
      product.description,
      product.categoryName,
      product.brand,
      product.model,
      product.manufacturer,
      product.manufacturerSku,
      product.supplierName,
      ...product.tags,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
  }

  String _normalizeFileNameHint(String? fileName) {
    if (fileName == null || fileName.trim().isEmpty) return '';
    return fileName
        .replaceAll(RegExp(r'\.[^.]+$'), '')
        .replaceAll(RegExp(r'[_\-]+'), ' ');
  }

  String _normalizeSimilarityText(String value) {
    final lower = value.toLowerCase();
    final withoutAccents = lower
        .replaceAll(RegExp(r'[áàäâã]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöôõ]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll('ñ', 'n');
    return withoutAccents
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // Families that, when present on the probe, REQUIRE the candidate to share
  // at least one family. Used by the hard-conflict gate to refuse falling back
  // to "unknown product family => allow" behaviour for narrow component types
  // that frequently get confused with adjacent components (e.g. derailleur
  // hangers vs derailleurs, pulleys vs derailleurs, cable+housing vs brakes).
  static const Set<String> _narrowFamilies = {
    'derailleur_hanger',
    'pulley',
    'chainring',
    'cable_housing',
    'brake_pad',
    'brake_rotor',
    'brake_caliper',
    'brake_lever',
    'helmet',
    'light',
    'lock',
    'bell',
    'mirror',
    'bottle_cage',
    'bottle',
    'phone_mount',
    'bag',
    'fender',
    'kickstand',
    'rack',
    'tube',
    'tire',
    'spoke',
    'grip',
    'pedal',
    'saddle',
    'seatpost',
    'stem',
    'handlebar',
    'headset',
    'fork',
    'shock',
    'chain',
    'cassette',
    'hub',
    'rim',
  };

  Set<String> _inferProductFamilies(String value) {
    final normalized = ' ${_normalizeSimilarityText(value)} ';
    final families = <String>{};

    // Whole-token matcher: matches " foo " exactly, no plural / derivative.
    void addIf(String family, List<String> phrases) {
      for (final phrase in phrases) {
        final p = _normalizeSimilarityText(phrase);
        if (p.isEmpty) continue;
        if (normalized.contains(' $p ')) {
          families.add(family);
          return;
        }
      }
    }

    // Stem matcher: matches the phrase at a word start, allowing plural /
    // gender / derivative endings (so "desviador" hits "desviadores",
    // "cambio" hits "cambiador" / "cambiadores", "pastilla" hits
    // "pastillas", etc). Use this for short Spanish stems where exact
    // whole-token matching misses real product names.
    void addStem(String family, List<String> stems) {
      for (final stem in stems) {
        final s = _normalizeSimilarityText(stem);
        if (s.isEmpty) continue;
        if (normalized.contains(' $s')) {
          families.add(family);
          return;
        }
      }
    }

    addIf('bottom_bracket', const [
      'bottom bracket',
      'soporte inferior',
      'movimiento central',
      'movimento central',
      'pedalier',
      'caja de motor',
      'eje de motor',
      'ejes de motor',
      'motor sellado',
      'motor cuadrado',
      'motor bsa',
      'bsa 68',
      'bb iso',
      'bb jis',
      'bb bsa',
      'bb30',
      'pf30',
      'pressfit',
      'hollowtech',
      'cuadrado jis',
      'jis cuadrado',
      'square taper',
    ]);
    addIf('seatpost', const [
      'tija',
      'tubo sillin',
      'tubo de sillin',
      'seatpost',
      'seat post',
      'poste asiento',
      'cano asiento',
    ]);
    addIf('saddle', const ['sillin', 'saddle', 'asiento']);
    addIf('stem', const ['potencia', 'stem', 'tee']);
    addIf('handlebar', const ['manubrio', 'manillar', 'handlebar']);
    addIf('headset', const ['juego direccion', 'direccion', 'headset']);
    addIf('crankset', const ['biela', 'bielas', 'crankset', 'crank arm']);
    addIf('pedal', const ['pedal', 'pedales']);
    addIf('chain', const ['cadena', 'chain']);
    addStem('cassette',
        const ['cassette', 'casete', 'piñon', 'pinon', 'freewheel']);
    addStem('brake_rotor', const ['rotor', 'disco freno', 'disco de freno']);
    addStem('brake_pad', const ['pastilla', 'brake pad', 'brake-pad']);
    addStem('brake_caliper', const ['caliper', 'herradura']);
    addStem('brake_lever', const ['manilla freno', 'brake lever']);
    addStem('hub', const ['maza', 'hub']);
    addStem('rim', const ['llanta', 'aro', 'rim']);
    addStem('spoke', const ['rayo', 'spoke']);
    addStem('tire', const ['neumatico', 'cubierta', 'tire', 'tyre']);
    addStem('tube', const ['camara', 'tube']);
    // Derailleur stems: "cambio", "cambiador(es)", "desviador(es)", "derailleur".
    addStem('derailleur', const ['cambiador', 'desviador', 'derailleur']);
    addStem('shifter', const ['manilla cambio', 'mando cambio', 'shifter']);
    addStem('derailleur_hanger', const [
      'percha',
      'postiza',
      'patilla cambio',
      'patilla de cambio',
      'gancho cambio',
      'gancho de cambio',
      'derailleur hanger',
      'rear hanger',
      'mech hanger',
      'rd hanger',
      'dropout hanger',
      'hanger cambio',
    ]);
    // "hanger" alone is ambiguous in English — only treat as a hanger if no
    // other stronger family is present yet.
    if (families.isEmpty && normalized.contains(' hanger')) {
      families.add('derailleur_hanger');
    }
    addStem('pulley', const [
      'polea',
      'pulley',
      'jockey wheel',
      'roldana',
    ]);
    addStem('chainring', const [
      'plato',
      'chainring',
      'chain ring',
      'narrow wide',
    ]);
    addIf('cable_housing', const [
      'piola',
      'piolas',
      'funda',
      'fundas',
      'cable freno',
      'cable cambio',
      'cable de freno',
      'cable de cambio',
      'housing',
      'inner wire',
      'cable interior',
    ]);
    addIf('helmet', const ['casco', 'helmet']);
    addIf('light', const ['luz', 'foco', 'lampara', 'light', 'headlight']);
    addIf('lock', const ['candado', 'lock', 'cadena candado']);
    addIf('bell', const ['timbre', 'bell']);
    addIf('mirror', const ['espejo', 'mirror']);
    addIf('bottle_cage', const [
      'portabidon',
      'porta bidon',
      'porta botella',
      'portabotella',
      'portacaramagiola',
      'porta caramagiola',
      'soporte botella',
      'soporte de botella',
      'soporte para botella',
      'soporte para botella de agua',
      'soporte bidon',
      'soporte de bidon',
      'soporte para bidon',
      'bottle cage',
      'water bottle cage',
    ]);
    addIf('bottle', const ['bidon', 'botella', 'water bottle']);
    addIf('phone_mount', const [
      'soporte celular',
      'soporte de celular',
      'soporte telefono',
      'soporte de telefono',
      'porta celular',
      'portacelular',
      'phone mount',
      'phone holder',
    ]);
    addIf('bag', const ['alforja', 'bolso', 'mochila', 'pannier', 'bag']);
    addIf('fender', const ['barrofango', 'guardabarro', 'fender', 'mudguard']);
    addIf('kickstand', const ['pata bicicleta', 'pie bicicleta', 'kickstand']);
    addIf('rack', const ['parrilla', 'portaequipaje', 'rear rack', 'rack']);
    addIf('fork', const ['horquilla', 'fork']);
    addIf('shock', const ['amortiguador', 'shock']);
    addIf('grip', const ['puño', 'punos', 'grip']);

    if (families.contains('bottom_bracket')) families.remove('crankset');
    if (families.contains('seatpost')) families.remove('saddle');
    if (families.contains('brake_rotor')) families.remove('brake_caliper');
    // A derailleur HANGER is a frame mount, not a derailleur. The text almost
    // always contains "cambio" / "desviador" because it describes which
    // derailleur it supports, so we must drop the noisy `derailleur` family
    // (and `pulley`, since the same descriptors apply) when we are confident
    // the item is actually a hanger.
    if (families.contains('derailleur_hanger')) {
      families.remove('derailleur');
      families.remove('pulley');
      families.remove('shifter');
    }
    // Pulleys ("poleas", "roldanas") are a wear part for derailleurs, not the
    // derailleur itself. Same narrowing rule.
    if (families.contains('pulley')) {
      families.remove('derailleur');
    }
    // Cable / housing kits often mention "cambio" or "freno" — narrow them.
    if (families.contains('cable_housing')) {
      families.remove('derailleur');
      families.remove('shifter');
      families.remove('brake_caliper');
      families.remove('brake_lever');
    }
    // Bottle cage vs bottle: keep the cage when both fire.
    if (families.contains('bottle_cage')) families.remove('bottle');
    if (families.contains('phone_mount')) families.remove('bottle_cage');
    return families;
  }

  bool _hasHardFamilyConflict(
    Set<String> probeFamilies,
    Set<String> productFamilies,
  ) {
    if (probeFamilies.isEmpty) return false;
    // If the probe expresses a narrow family (hanger, brake pad, rotor,
    // saddle, etc.), require the candidate to share at least one family.
    // Empty/unknown candidate family is treated as a conflict in that mode,
    // because unknown broad fallback is what creates noisy suggestions.
    final probeIsNarrow = probeFamilies.any(_narrowFamilies.contains);
    if (probeIsNarrow) {
      if (productFamilies.isEmpty) return true;
      return probeFamilies.intersection(productFamilies).isEmpty;
    }
    if (productFamilies.isEmpty) return false;
    return probeFamilies.intersection(productFamilies).isEmpty;
  }

  _ProductShapeProfile _inferProductShapeProfile(
    String value,
    Set<String> families,
  ) {
    final normalized = ' ${_normalizeSimilarityText(value)} ';
    final attributes = <String>{};
    final exclusiveValues = <String, String>{};
    final requiredAttributes = <String>{};

    bool hasAny(Iterable<String> phrases) {
      for (final phrase in phrases) {
        final p = _normalizeSimilarityText(phrase);
        if (p.isNotEmpty && normalized.contains(' $p ')) return true;
      }
      return false;
    }

    void setExclusive(
      String group,
      String value, {
      bool required = false,
    }) {
      final attribute = '$group:$value';
      exclusiveValues[group] = value;
      attributes.add(attribute);
      if (required) requiredAttributes.add(attribute);
    }

    void addAttribute(String attribute) {
      attributes.add(attribute);
    }

    final hasNarrowFamily = families.any(_narrowFamilies.contains);

    if (hasNarrowFamily &&
        hasAny(const [
          'redonda',
          'redondo',
          'redondas',
          'redondos',
          'round',
          'rounded',
          'circular',
          'circulares',
        ])) {
      setExclusive('form', 'round');
    }

    if (hasNarrowFamily &&
        hasAny(const [
          'rectangular',
          'rectangulo',
          'rectangle',
          'square',
          'cuadrada',
          'cuadrado',
        ])) {
      setExclusive('form', 'rectangular');
    }

    if (hasNarrowFamily &&
        hasAny(const [
          'largo',
          'larga',
          'long',
          'slim',
          'estrecho',
          'estrecha',
        ])) {
      setExclusive('form', 'long_narrow');
    }

    if (hasAny(const [
      'extensor',
      'extension',
      'extender',
      'prolongador',
      'prolongacion',
      'goatlink',
      'goat link',
      'roadlink',
      'road link',
      '50t',
      '50 t',
      '52t',
      '52 t',
      'oou',
    ])) {
      if (families.contains('derailleur_hanger')) {
        setExclusive('hanger_kind', 'extender', required: true);
      } else {
        addAttribute('extension_shape');
      }
    }

    if (families.contains('brake_pad')) {
      if (hasAny(const [
        'ms 11c',
        'ms11c',
        'redonda',
        'redondo',
        'redondas',
        'redondos',
        'round',
        'rounded',
        'circular',
        'circulares',
      ])) {
        setExclusive('brake_pad_style', 'disc_round');
        setExclusive('form', 'round');
      }

      if (hasAny(const [
        'v brake',
        'vbrake',
        'vbrakes',
        'rim brake',
        'patin v brake',
        'patines v brake',
        'zapata v brake',
        'zapatas v brake',
        'cantilever',
      ])) {
        setExclusive('brake_pad_style', 'rim_block');
        setExclusive('brake_pad_platform', 'rim');
        setExclusive('form', 'long_narrow');
      }

      if (hasAny(const [
        'patin electrico',
        'scooter',
        'electric scooter',
        'e scooter',
      ])) {
        setExclusive('brake_pad_style', 'scooter');
        setExclusive('brake_pad_platform', 'scooter');
      }

      if (hasAny(const [
        'ds 02s',
        'ds02s',
        'ds 06s',
        'ds06s',
      ])) {
        setExclusive('brake_pad_style', 'disc_rectangular');
        setExclusive('form', 'rectangular');
      }

      if (hasAny(const [
        '4 pistones',
        'cuatro pistones',
        '4 piston',
        'four piston',
        'ds 15s',
        'ds15s',
      ])) {
        setExclusive('brake_pad_caliper_class', 'four_piston');
      }
    }

    if (families.contains('brake_rotor')) {
      final rotorDiameter = _firstFiniteToken(
        normalized,
        const ['140', '160', '180', '200', '203', '220'],
        suffix: 'mm',
      );
      if (rotorDiameter != null) {
        setExclusive('rotor_diameter_mm', rotorDiameter);
      }
      setExclusive('form', 'round');
    }

    if (families.intersection(const {'tire', 'tube', 'rim'}).isNotEmpty) {
      final wheelSize = _firstFiniteToken(
        normalized,
        const ['12', '16', '20', '24', '26', '27 5', '275', '29', '700'],
      );
      if (wheelSize != null) {
        setExclusive(
          'wheel_size',
          wheelSize == '27 5' || wheelSize == '275' ? '27.5' : wheelSize,
        );
      }
      if (hasAny(const ['presta', 'francesa', 'fv'])) {
        setExclusive('valve_type', 'presta');
      }
      if (hasAny(const ['schrader', 'americana', 'auto', 'av'])) {
        setExclusive('valve_type', 'schrader');
      }
    }

    if (families.contains('seatpost')) {
      final diameter = _firstFiniteToken(
        normalized,
        const ['25 4', '27 2', '28 6', '30 9', '31 6', '34 9'],
        suffix: 'mm',
      );
      if (diameter != null) {
        setExclusive('seatpost_diameter_mm', diameter.replaceAll(' ', '.'));
      }
    }

    return _ProductShapeProfile(
      attributes: attributes,
      exclusiveValues: exclusiveValues,
      requiredAttributes: requiredAttributes,
    );
  }

  String? _firstFiniteToken(
    String normalized,
    List<String> values, {
    String? suffix,
  }) {
    for (final value in values) {
      final escaped = RegExp.escape(value).replaceAll(r'\ ', r'\s*');
      final suffixPattern =
          suffix == null ? '' : r'\s*' + RegExp.escape(suffix);
      final pattern = RegExp(r'\b' + escaped + suffixPattern + r'\b');
      if (pattern.hasMatch(normalized)) return value;
    }
    return null;
  }

  bool _hasHardShapeProfileConflict(
    _ProductShapeProfile probeProfile,
    _ProductShapeProfile productProfile,
  ) {
    if (probeProfile.isEmpty) return false;
    for (final requiredAttribute in probeProfile.requiredAttributes) {
      if (!productProfile.attributes.contains(requiredAttribute)) return true;
    }
    for (final entry in probeProfile.exclusiveValues.entries) {
      final productValue = productProfile.exclusiveValues[entry.key];
      if (productValue != null && productValue != entry.value) return true;
    }
    return false;
  }

  double _computeShapeAttributeScore(
    _ProductShapeProfile probeProfile,
    _ProductShapeProfile productProfile,
  ) {
    if (probeProfile.isEmpty || productProfile.isEmpty) return 0;

    final sharedAttributes =
        probeProfile.attributes.intersection(productProfile.attributes);
    final sharedExclusiveGroups = probeProfile.exclusiveValues.keys.where(
      (group) =>
          productProfile.exclusiveValues[group] ==
          probeProfile.exclusiveValues[group],
    );

    if (sharedAttributes.isEmpty && sharedExclusiveGroups.isEmpty) return 0;

    if (probeProfile.requiredAttributes
        .intersection(productProfile.requiredAttributes)
        .isNotEmpty) {
      return 0.92;
    }

    final exclusiveContainment = sharedExclusiveGroups.length /
        math.max(
            1,
            math.min(
              probeProfile.exclusiveValues.length,
              productProfile.exclusiveValues.length,
            ));
    final attributeContainment = sharedAttributes.length /
        math.max(
            1,
            math.min(
              probeProfile.attributes.length,
              productProfile.attributes.length,
            ));
    final score = exclusiveContainment * 0.72 + attributeContainment * 0.28;
    return score.clamp(0, 0.88).toDouble();
  }

  Set<String> _extractSimilarityTokens(String value) {
    const stopWords = {
      'de',
      'del',
      'la',
      'el',
      'los',
      'las',
      'un',
      'una',
      'para',
      'por',
      'con',
      'and',
      'the',
      'for',
      'bike',
      'bicycle',
      'mtb',
      'road',
      'color',
      'size',
      'sku',
      'item',
      'id',
      'china',
      'chile',
      'clp',
      'aliexpress',
      'marketplace',
      'unidades',
    };
    final tokens = _normalizeSimilarityText(value)
        .split(' ')
        .where((token) => token.length >= 2 && !stopWords.contains(token))
        .toSet();

    const colorSynonyms = {
      'black': ['negro'],
      'negro': ['black'],
      'blue': ['azul'],
      'azul': ['blue'],
      'red': ['rojo'],
      'rojo': ['red'],
      'golden': ['dorado'],
      'gold': ['dorado'],
      'dorado': ['golden', 'gold'],
      'purple': ['morado', 'purpura'],
      'morado': ['purple', 'purpura'],
      'purpura': ['purple', 'morado'],
    };
    for (final token in List<String>.from(tokens)) {
      final synonyms = colorSynonyms[token];
      if (synonyms != null) tokens.addAll(synonyms);
    }
    return tokens;
  }

  double _computeKeywordScore(Set<String> left, Set<String> right) {
    if (left.isEmpty || right.isEmpty) return 0;
    final intersection = left.intersection(right).length;
    final union = left.union(right).length;
    if (union == 0) return 0;
    final jaccard = intersection / union;
    final containment = intersection / math.min(left.length, right.length);
    return (jaccard * 0.55 + containment * 0.45).clamp(0, 1).toDouble();
  }

  Future<ProductImageFingerprint?> _resolveProbeFingerprint(
    ProductDuplicateProbe probe,
  ) async {
    if (probe.imageBytes != null) {
      return ProductImageFingerprintService.fromBytes(probe.imageBytes!);
    }

    final imageUrl = probe.imageUrl?.trim();
    if (imageUrl == null || imageUrl.isEmpty) return null;
    final bytes = await _downloadImageBytes(imageUrl);
    if (bytes == null) return null;
    return ProductImageFingerprintService.fromBytes(bytes);
  }

  Future<double> _computeImageScore(ProductDuplicateProbe probe,
      ProductImageFingerprint? probeFingerprint, Product product,
      {required bool allowRemoteFingerprint}) async {
    final probeImageKey = _normalizeImageIdentity(probe.imageUrl);
    final productImageKeys = _productImageUrls(product)
        .map(_normalizeImageIdentity)
        .where((value) => value.isNotEmpty)
        .toSet();

    if (probeImageKey.isNotEmpty && productImageKeys.contains(probeImageKey)) {
      return 1;
    }

    if (probeFingerprint == null) return 0;

    final productFingerprint =
        ProductImageFingerprint.fromStorageJson(product.imageFingerprint);
    if (productFingerprint == null) {
      if (!allowRemoteFingerprint) return 0;
      return _computeAndStoreProductImageScore(probeFingerprint, product);
    }

    return ProductImageFingerprintService.similarity(
      probeFingerprint,
      productFingerprint,
    );
  }

  Future<double> _computeAndStoreProductImageScore(
    ProductImageFingerprint probeFingerprint,
    Product product,
  ) async {
    final productId = product.id;
    if (productId == null) return 0;
    final urls = _productImageUrls(product);
    if (urls.isEmpty) return 0;

    final bytes = await _downloadImageBytes(urls.first);
    if (bytes == null) return 0;
    final productFingerprint = ProductImageFingerprintService.fromBytes(bytes);
    if (productFingerprint == null) return 0;

    await _inventoryService.storeProductImageFingerprint(
      productId: productId,
      imageFingerprint: productFingerprint.toStorageJson(),
    );

    return ProductImageFingerprintService.similarity(
      probeFingerprint,
      productFingerprint,
    );
  }

  Future<Uint8List?> _downloadImageBytes(String imageUrl) async {
    try {
      final uri = Uri.tryParse(imageUrl.trim());
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

  String _normalizeImageIdentity(String? imageUrl) {
    if (imageUrl == null || imageUrl.trim().isEmpty) return '';
    final uri = Uri.tryParse(imageUrl.trim());
    if (uri == null) return imageUrl.trim().toLowerCase();
    final normalizedPath = uri.path.replaceAll(
      RegExp(r'_(\d+)x\d+[^/]*$'),
      '',
    );
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      path: normalizedPath,
    ).toString();
  }

  bool _sameAliExpressSupplierFamily(
    ProductDuplicateProbe probe,
    Product product,
  ) {
    final supplierName = probe.supplierName;
    if (supplierName == null || supplierName.trim().isEmpty) return false;
    return _inventoryService.isAliExpressSupplierName(supplierName) &&
        _inventoryService.isAliExpressSupplierName(product.supplierName);
  }

  double _computeIdentityScore(ProductDuplicateProbe probe, Product product) {
    final entrySku = _normalizeSimilarityText(probe.sku ?? '');
    final productSku = _normalizeSimilarityText(product.sku);
    final supplierCode = _normalizeSimilarityText(product.supplierCode ?? '');

    final sharedAliExpressIds =
        _extractAliExpressItemIds(_buildProbeText(probe)).intersection(
            _extractAliExpressItemIds(_buildProductSimilarityText(product)));
    if (sharedAliExpressIds.isNotEmpty) return 1;

    if (entrySku.isEmpty) return 0;
    final productIds = {productSku, supplierCode}.where((v) => v.isNotEmpty);
    if (productIds.contains(entrySku)) return 1;
    return 0;
  }

  double _computeAliExpressScore(
    ProductDuplicateProbe probe,
    Product product,
    Set<String> probeTokens,
    Set<String> productTokens,
  ) {
    final sameFamily = _sameAliExpressSupplierFamily(probe, product);
    final probeLooksAliExpress = _looksLikeAliExpressProbe(probe);
    if (!sameFamily && !probeLooksAliExpress) return 0;

    final sharedIds = _extractAliExpressItemIds(_buildProbeText(probe))
        .intersection(
            _extractAliExpressItemIds(_buildProductSimilarityText(product)));
    if (sharedIds.isNotEmpty) return 1;

    if (probeTokens.isEmpty || productTokens.isEmpty) return 0;
    final sharedCount = probeTokens.intersection(productTokens).length;
    if (sharedCount < 3) return 0;

    final productContainment = sharedCount / productTokens.length;
    final probeContainment = sharedCount / probeTokens.length;
    final score = productContainment * 0.72 + probeContainment * 0.28;
    return score.clamp(0, 1).toDouble();
  }

  double _computeCatalogSpecScore(
      ProductDuplicateProbe probe, Product product) {
    final probeText = _buildProbeIntrinsicText(probe);
    final productText = _buildProductSimilarityText(product);
    final probeSpec = _extractBottomBracketSpec(probeText);
    final productSpec = _extractBottomBracketSpec(productText);
    if (probeSpec == null || productSpec == null) return 0;

    final sameShell = (probeSpec.shellMm - productSpec.shellMm).abs() <= 0.6;
    final sameAxle = (probeSpec.axleMm - productSpec.axleMm).abs() <= 0.6;
    if (!sameShell || !sameAxle) return 0;

    var score = 0.78;
    if (_inferProductFamilies(probeText).contains('bottom_bracket') &&
        _inferProductFamilies(productText).contains('bottom_bracket')) {
      score += 0.08;
    }
    if (_hasCompatibleBrandAlias(probeText, productText)) {
      score += 0.10;
    }
    if (_bottomBracketDescriptorOverlap(probeText, productText) >= 2) {
      score += 0.04;
    }
    return score.clamp(0, 1).toDouble();
  }

  _BottomBracketSpec? _extractBottomBracketSpec(String value) {
    final text = value
        .toLowerCase()
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[^a-z0-9.×x]+'), ' ');
    final match = RegExp(
      r'\b(\d{2,3})\s*(?:x|×)\s*(\d{2,3}(?:\.\d+)?)\s*(?:mm)?\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;

    final shell = double.tryParse(match.group(1) ?? '');
    final axle = double.tryParse(match.group(2) ?? '');
    if (shell == null || axle == null) return null;
    return _BottomBracketSpec(shellMm: shell, axleMm: axle);
  }

  bool _hasCompatibleBrandAlias(String left, String right) {
    final leftBrands = _brandAliases(left);
    final rightBrands = _brandAliases(right);
    if (leftBrands.isEmpty || rightBrands.isEmpty) return false;
    return leftBrands.intersection(rightBrands).isNotEmpty;
  }

  Set<String> _brandAliases(String value) {
    final text = ' ${_normalizeSimilarityText(value)} ';
    final aliases = <String>{};
    if (text.contains(' ztto ') || text.contains(' zitto ')) {
      aliases.add('ztto');
    }
    for (final brand in const ['neco', 'shimano', 'vp', 'lebycle', 'ozono']) {
      if (text.contains(' $brand ')) aliases.add(brand);
    }
    return aliases;
  }

  int _bottomBracketDescriptorOverlap(String left, String right) {
    const descriptors = {
      'motor',
      'sellado',
      'eje',
      'bsa',
      'iso',
      'jis',
      'cuadrado',
      'square',
      'taper',
    };
    final leftTokens = _extractSimilarityTokens(left).intersection(descriptors);
    final rightTokens =
        _extractSimilarityTokens(right).intersection(descriptors);
    return leftTokens.intersection(rightTokens).length;
  }

  bool _looksLikeAliExpressProbe(ProductDuplicateProbe probe) {
    final text = _normalizeSimilarityText(_buildProbeText(probe));
    return text.contains('ae ') ||
        text.contains('item id') ||
        text.contains('aliexpress') ||
        text.contains('ali express');
  }

  Set<String> _extractAliExpressItemIds(String value) {
    final ids = <String>{};
    final patterns = [
      RegExp(r'item\s*id\s*:?\s*(\d{8,})', caseSensitive: false),
      RegExp(r'itemId=(\d{8,})', caseSensitive: false),
      RegExp(r'/item/(\d{8,})', caseSensitive: false),
      RegExp(r'productId=(\d{8,})', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(value)) {
        final id = match.group(1);
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  double _computeMetadataScore(ProductDuplicateProbe probe, Product product) {
    var score = 0.0;
    var weight = 0.0;

    final categoryName = probe.categoryName;
    if (categoryName != null && categoryName.trim().isNotEmpty) {
      weight += 0.35;
      final probeCat = _normalizeSimilarityText(categoryName);
      final productCat = _normalizeSimilarityText(product.categoryName ?? '');
      if (probeCat.isNotEmpty && productCat.isNotEmpty) {
        if (probeCat == productCat) {
          score += 0.35;
        } else if (productCat.contains(probeCat) ||
            probeCat.contains(productCat)) {
          // Fuzzy contains: AI says "pastillas" vs catalog "pastillas freno".
          score += 0.25;
        } else {
          // Word overlap (>=1 meaningful token).
          final probeTokens =
              probeCat.split(' ').where((t) => t.length >= 4).toSet();
          final productTokens =
              productCat.split(' ').where((t) => t.length >= 4).toSet();
          if (probeTokens.intersection(productTokens).isNotEmpty) {
            score += 0.15;
          }
        }
      }
    }

    final brandName = probe.brandName;
    if (brandName != null && brandName.trim().isNotEmpty) {
      weight += 0.30;
      final probeBrand = _normalizeSimilarityText(brandName);
      final productBrand = _normalizeSimilarityText(product.brand ?? '');
      if (probeBrand.isNotEmpty && productBrand.isNotEmpty) {
        if (probeBrand == productBrand) {
          score += 0.30;
        } else if (productBrand.contains(probeBrand) ||
            probeBrand.contains(productBrand)) {
          score += 0.20;
        }
      }
    }

    final supplierName = probe.supplierName;
    if (supplierName != null && supplierName.trim().isNotEmpty) {
      weight += 0.10;
      final sameSupplier = _normalizeSimilarityText(supplierName) ==
          _normalizeSimilarityText(product.supplierName ?? '');
      final sameAliExpressFamily =
          _inventoryService.isAliExpressSupplierName(supplierName) &&
              _inventoryService.isAliExpressSupplierName(product.supplierName);
      if (sameSupplier) {
        score += 0.10;
      } else if (sameAliExpressFamily) {
        score += 0.025;
      }
    }

    if ((probe.price ?? 0) > 0 && product.price > 0) {
      weight += 0.15;
      final ratio = math.min(probe.price!, product.price) /
          math.max(probe.price!, product.price);
      score += ratio.clamp(0, 1) * 0.15;
    }

    if ((probe.cost ?? 0) > 0 && product.cost > 0) {
      weight += 0.10;
      final ratio = math.min(probe.cost!, product.cost) /
          math.max(probe.cost!, product.cost);
      score += ratio.clamp(0, 1) * 0.10;
    }

    if (weight == 0) return 0;
    return score / weight;
  }

  double _combineDuplicateScores({
    required double keywordScore,
    required double semanticScore,
    required double imageScore,
    required double identityScore,
    required double metadataScore,
    required double catalogSpecScore,
    required double shapeAttributeScore,
    required bool hasImageProbe,
  }) {
    if (identityScore >= 1) return 1;
    if (shapeAttributeScore >= 0.90 &&
        math.max(keywordScore, metadataScore) >= 0.25) {
      return 0.90;
    }
    if (catalogSpecScore >= 0.94) return 0.96;
    if (catalogSpecScore >= 0.86) return 0.90;
    final textScore = math.max(keywordScore, semanticScore);
    // When we actually have an image to compare, the image carries more real
    // "is this the same physical part" signal than Spanish keyword overlap
    // on AliExpress titles. Bias the combiner toward image evidence.
    final imageWeight = hasImageProbe ? 0.55 : 0.08;
    final textWeight = hasImageProbe ? 0.28 : 0.70;
    const metadataWeight = 0.10;
    const shapeAttributeWeight = 0.08;
    const identityWeight = 0.05;
    var total = textScore * textWeight +
        imageScore * imageWeight +
        metadataScore * metadataWeight +
        shapeAttributeScore * shapeAttributeWeight +
        identityScore * identityWeight;
    // Tiebreaker boost: when text similarity is strong (>=0.5) AND metadata
    // (which folds in category/brand match) is also strong (>=0.4), nudge
    // the score up. This rewards literal "same family + same name pattern"
    // matches so they outrank visually-similar-but-textually-unrelated
    // candidates in the same category. Capped at +0.06.
    if (textScore >= 0.5 && metadataScore >= 0.4) {
      final boost = math.min(0.06, (textScore - 0.5) * 0.20 + 0.02);
      total += boost;
    }
    return total.clamp(0, 1).toDouble();
  }

  bool _shouldKeepDuplicateCandidate({
    required double overallScore,
    required double keywordScore,
    required double semanticScore,
    required double imageScore,
    required double identityScore,
    required double metadataScore,
    required double shapeAttributeScore,
    required bool sameAliExpressFamily,
    required bool aliExpressTextMatch,
  }) {
    if (identityScore >= 1) return true;
    if (overallScore >= 0.58) return true;
    if (keywordScore >= 0.62) return true;
    if (semanticScore >= 0.72) return true;
    if (shapeAttributeScore >= 0.90 && overallScore >= 0.42) return true;
    if (sameAliExpressFamily && keywordScore >= 0.48) return true;
    if (sameAliExpressFamily && semanticScore >= 0.62) return true;
    if (sameAliExpressFamily && overallScore >= 0.46 && metadataScore >= 0.08) {
      return true;
    }
    if (aliExpressTextMatch && overallScore >= 0.44) return true;
    if (imageScore >= 0.90) return true;
    if (imageScore >= 0.80 && math.max(keywordScore, semanticScore) >= 0.12) {
      return true;
    }
    return false;
  }

  List<String> _buildDuplicateSignals(
    Product product, {
    required double keywordScore,
    required double semanticScore,
    required double imageScore,
    required double identityScore,
    required double metadataScore,
    required double shapeAttributeScore,
    required double catalogSpecScore,
  }) {
    final signals = <String>[];
    if (identityScore >= 1) signals.add('SKU/código proveedor coincide');
    if (catalogSpecScore >= 0.78) signals.add('Medida/familia coinciden');
    if (keywordScore >= 0.62) signals.add('Nombre muy parecido');
    if (semanticScore >= 0.72) signals.add('Descripción semántica parecida');
    if (imageScore >= 0.90) {
      signals.add('Imagen coincide');
    } else if (imageScore >= 0.78) {
      signals.add('Imagen parecida');
    }
    if (metadataScore >= 0.8) signals.add('Categoría/marca coinciden');
    if (shapeAttributeScore >= 0.8) signals.add('Forma/estándar coincide');
    if (signals.isEmpty) signals.add('Coincidencia parcial');
    if (product.inventoryQty > 0) signals.add('Stock: ${product.inventoryQty}');
    return signals;
  }
}
