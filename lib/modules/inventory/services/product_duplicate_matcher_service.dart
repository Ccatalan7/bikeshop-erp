import 'dart:math' as math;
import 'dart:typed_data';

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
      final metadataScore = _computeMetadataScore(probe, product);
      final semanticScore = semanticScores[product.id] ?? 0.0;
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
        hasImageProbe: hasImageProbe,
      );

      if (!_shouldKeepDuplicateCandidate(
        overallScore: overallScore,
        keywordScore: keywordScore,
        semanticScore: semanticScore,
        imageScore: imageScore,
        identityScore: identityScore,
        metadataScore: metadataScore,
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
          catalogSpecScore: catalogSpecScore,
        ),
      ));
    }

    candidates.sort((a, b) => b.overallScore.compareTo(a.overallScore));
    return candidates.take(limit).toList();
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

  Set<String> _inferProductFamilies(String value) {
    final text = ' ${_normalizeSimilarityText(value)} ';
    final families = <String>{};

    void addIf(String family, List<String> phrases) {
      for (final phrase in phrases) {
        final normalized = _normalizeSimilarityText(phrase);
        if (normalized.isEmpty) continue;
        if (text.contains(' $normalized ')) {
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
    addIf('cassette', const ['cassette', 'piñon', 'pinon', 'freewheel']);
    addIf('brake_rotor', const ['rotor', 'disco freno', 'disco de freno']);
    addIf('brake_pad', const ['pastilla', 'pastillas', 'brake pad']);
    addIf('brake_caliper', const ['caliper', 'calipers', 'herradura']);
    addIf('brake_lever', const ['manilla freno', 'brake lever']);
    addIf('hub', const ['maza', 'mazas', 'hub']);
    addIf('rim', const ['llanta', 'aro', 'rim']);
    addIf('spoke', const ['rayo', 'rayos', 'spoke']);
    addIf('tire', const ['neumatico', 'cubierta', 'tire', 'tyre']);
    addIf('tube', const ['camara', 'tube']);
    addIf('derailleur', const ['cambio', 'derailleur', 'desviador']);
    addIf('shifter', const ['manilla cambio', 'mando cambio', 'shifter']);
    addIf('fork', const ['horquilla', 'fork']);
    addIf('shock', const ['amortiguador', 'shock']);
    addIf('grip', const ['puño', 'punos', 'grip']);

    if (families.contains('bottom_bracket')) families.remove('crankset');
    if (families.contains('seatpost')) families.remove('saddle');
    if (families.contains('brake_rotor')) families.remove('brake_caliper');
    return families;
  }

  bool _hasHardFamilyConflict(
      Set<String> probeFamilies, Set<String> productFamilies) {
    if (probeFamilies.isEmpty || productFamilies.isEmpty) return false;
    return probeFamilies.intersection(productFamilies).isEmpty;
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
      if (contentType.isNotEmpty && !contentType.startsWith('image/')) {
        return null;
      }
      if (response.bodyBytes.isEmpty ||
          response.bodyBytes.length > 8 * 1024 * 1024) {
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('Product duplicate image download failed: $e');
      return null;
    }
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

  double _computeCatalogSpecScore(ProductDuplicateProbe probe, Product product) {
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
    final rightTokens = _extractSimilarityTokens(right).intersection(descriptors);
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
      if (_normalizeSimilarityText(categoryName) ==
          _normalizeSimilarityText(product.categoryName ?? '')) {
        score += 0.35;
      }
    }

    final brandName = probe.brandName;
    if (brandName != null && brandName.trim().isNotEmpty) {
      weight += 0.30;
      if (_normalizeSimilarityText(brandName) ==
          _normalizeSimilarityText(product.brand ?? '')) {
        score += 0.30;
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
    required bool hasImageProbe,
  }) {
    if (identityScore >= 1) return 1;
    if (catalogSpecScore >= 0.94) return 0.96;
    if (catalogSpecScore >= 0.86) return 0.90;
    final textScore = math.max(keywordScore, semanticScore);
    final imageWeight = hasImageProbe ? 0.42 : 0.08;
    final textWeight = hasImageProbe ? 0.41 : 0.70;
    const metadataWeight = 0.12;
    const identityWeight = 0.05;
    return (textScore * textWeight +
            imageScore * imageWeight +
            metadataScore * metadataWeight +
            identityScore * identityWeight)
        .clamp(0, 1)
        .toDouble();
  }

  bool _shouldKeepDuplicateCandidate({
    required double overallScore,
    required double keywordScore,
    required double semanticScore,
    required double imageScore,
    required double identityScore,
    required double metadataScore,
    required bool sameAliExpressFamily,
    required bool aliExpressTextMatch,
  }) {
    if (identityScore >= 1) return true;
    if (overallScore >= 0.58) return true;
    if (keywordScore >= 0.62) return true;
    if (semanticScore >= 0.72) return true;
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
    if (signals.isEmpty) signals.add('Coincidencia parcial');
    if (product.inventoryQty > 0) signals.add('Stock: ${product.inventoryQty}');
    return signals;
  }
}
