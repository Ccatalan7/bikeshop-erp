import '../models/brand_models.dart';
import '../models/category_models.dart';

/// Evidence used to explain a deterministic catalog semantic resolution.
enum ProductCatalogSemanticEvidenceKind {
  familyAlias,
  listingConsensus,
  listingConflict,
  categoryPath,
  explicitBrand,
  rejectedCategoryHint,
  rejectedBrandHint,
  unresolvedCategory,
  unresolvedBrand,
}

class ProductCatalogSemanticEvidence {
  const ProductCatalogSemanticEvidence({
    required this.kind,
    required this.detail,
  });

  final ProductCatalogSemanticEvidenceKind kind;
  final String detail;
}

/// One supplier row that needs catalog semantics before duplicate matching or
/// product creation.
///
/// AI-produced values are deliberately hints. They are never treated as proof
/// of a catalog category or brand.
class ProductCatalogSemanticInput {
  const ProductCatalogSemanticInput({
    required this.rowId,
    required this.rawTitle,
    this.supplierId,
    this.listingId,
    this.variantKey,
    this.variantLabel,
    this.componentTypeHint,
    this.categoryHint,
    this.brandHint,
    this.hintConfidence,
  });

  final String rowId;
  final String rawTitle;
  final String? supplierId;
  final String? listingId;
  final String? variantKey;
  final String? variantLabel;
  final String? componentTypeHint;
  final String? categoryHint;
  final String? brandHint;
  final double? hintConfidence;
}

class ProductCatalogSemanticResolution {
  const ProductCatalogSemanticResolution({
    required this.rowId,
    required this.family,
    required this.evidence,
    required this.confidence,
    this.supplierId,
    this.listingId,
    this.variantKey,
    this.variantLabel,
    this.category,
    this.brand,
    this.reviewReason,
  });

  final String rowId;
  final String? supplierId;
  final String? listingId;
  final String? variantKey;
  final String? variantLabel;
  final String family;
  final Category? category;
  final ProductBrand? brand;
  final List<ProductCatalogSemanticEvidence> evidence;
  final double confidence;
  final String? reviewReason;

  bool get requiresReview => reviewReason != null;
}

/// Canonical, pure owner for OCR/supplier-title catalog semantics.
///
/// It resolves only against the supplied tenant categories and real brand
/// catalog. Network, database and AI access belong to callers. Variants from
/// one supplier listing share semantics only when their independently inferred
/// known families agree. A mixed listing remains row-specific and requires
/// review instead of silently homogenizing unlike products.
class ProductCatalogSemanticResolver {
  ProductCatalogSemanticResolver({
    required Iterable<Category> categories,
    required Iterable<ProductBrand> brands,
  })  : _categories = List<Category>.unmodifiable(categories),
        _brands = List<ProductBrand>.unmodifiable(brands);

  final List<Category> _categories;
  final List<ProductBrand> _brands;

  static const String stemFamily = 'stem';
  static const String cranksetFamily = 'crankset';
  static const String valveAdapterFamily = 'valve_adapter';
  static const String tubelessValveFamily = 'tubeless_valve';
  static const String unknownFamily = 'unknown';

  static String canonicalizeDisplayName({
    required String name,
    required String family,
  }) {
    if (family != stemFamily) return name;
    return name.replaceFirst(
      RegExp(r'^(?:potencia|stem|tee)\b', caseSensitive: false),
      'Tee',
    );
  }

  static const Map<String, String> _categoryPathByFamily = {
    stemFamily: 'Componentes / Dirección / Tee',
    cranksetFamily: 'Componentes / Transmisión / Volantes / Volante',
    valveAdapterFamily: 'Accesorios / Adaptadores',
    tubelessValveFamily: 'Componentes / Ruedas / Tubeless / Válvula Tubeless',
  };

  // IXF is intentionally recognized even when the local brand table is
  // missing it. That produces an explicit review instead of accepting a
  // conflicting image/AI guess such as Shimano.
  static const Map<String, String> _knownExternalBrandAliases = {
    'ixf': 'IXF',
  };

  ProductCatalogSemanticResolution resolve(
    ProductCatalogSemanticInput input,
  ) {
    return resolveAll([input]).single;
  }

  List<ProductCatalogSemanticResolution> resolveAll(
    Iterable<ProductCatalogSemanticInput> inputs,
  ) {
    final rows = List<ProductCatalogSemanticInput>.from(inputs);
    if (rows.isEmpty) return const [];

    final groups = <String, List<ProductCatalogSemanticInput>>{};
    for (final row in rows) {
      final listingId = row.listingId?.trim();
      final key = listingId == null || listingId.isEmpty
          ? 'row:${row.rowId}'
          : 'listing:${row.supplierId?.trim() ?? ''}:$listingId';
      groups.putIfAbsent(key, () => []).add(row);
    }

    final byRowId = <String, ProductCatalogSemanticResolution>{};
    for (final group in groups.values) {
      final independentlyKnownFamilies = group
          .map((row) => _inferFamily(_normalize(row.rawTitle)))
          .where((family) => family != unknownFamily)
          .toSet();

      if (group.length > 1 && independentlyKnownFamilies.length > 1) {
        final conflictingFamilies = independentlyKnownFamilies.toList()..sort();
        final conflictDetail =
            'Familias incompatibles en la publicación: ${conflictingFamilies.join(', ')}';
        final conflictReason =
            'La publicación mezcla familias incompatibles (${conflictingFamilies.join(', ')}); revisa esta variante.';
        for (final row in group) {
          final semantics = _resolveGroup([row]);
          byRowId[row.rowId] = _buildRowResolution(
            row,
            semantics,
            extraEvidence: ProductCatalogSemanticEvidence(
              kind: ProductCatalogSemanticEvidenceKind.listingConflict,
              detail: conflictDetail,
            ),
            extraReviewReason: conflictReason,
            confidencePenalty: 0.12,
          );
        }
        continue;
      }

      // A listing consensus needs at least one independently known family.
      // With no family evidence, resolve each row honestly instead of sharing
      // a category or brand merely because the listing identifier matches.
      if (group.length > 1 && independentlyKnownFamilies.isEmpty) {
        for (final row in group) {
          byRowId[row.rowId] = _buildRowResolution(
            row,
            _resolveGroup([row]),
          );
        }
        continue;
      }

      final semantics = _resolveGroup(group);
      for (final row in group) {
        byRowId[row.rowId] = _buildRowResolution(row, semantics);
      }
    }

    return rows.map((row) => byRowId[row.rowId]!).toList(growable: false);
  }

  ProductCatalogSemanticResolution _buildRowResolution(
    ProductCatalogSemanticInput row,
    _GroupResolution semantics, {
    ProductCatalogSemanticEvidence? extraEvidence,
    String? extraReviewReason,
    double confidencePenalty = 0,
  }) {
    final evidence = extraEvidence == null
        ? semantics.evidence
        : List<ProductCatalogSemanticEvidence>.unmodifiable([
            ...semantics.evidence,
            extraEvidence,
          ]);
    final reviewReasons = <String>{
      if (semantics.reviewReason != null) semantics.reviewReason!,
      if (extraReviewReason != null) extraReviewReason,
    };
    return ProductCatalogSemanticResolution(
      rowId: row.rowId,
      supplierId: row.supplierId,
      listingId: row.listingId,
      variantKey: row.variantKey,
      variantLabel: row.variantLabel,
      family: semantics.family,
      category: semantics.category,
      brand: semantics.brand,
      evidence: evidence,
      confidence:
          (semantics.confidence - confidencePenalty).clamp(0, 1).toDouble(),
      reviewReason: reviewReasons.isEmpty ? null : reviewReasons.join(' '),
    );
  }

  _GroupResolution _resolveGroup(List<ProductCatalogSemanticInput> rows) {
    final rawTitles = rows
        .map((row) => row.rawTitle.trim())
        .where((title) => title.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final rawText = rawTitles.join(' | ');
    final normalized = _normalize(rawText);
    final evidence = <ProductCatalogSemanticEvidence>[];
    final reviewReasons = <String>[];

    final family = _inferFamily(normalized);
    if (family == unknownFamily) {
      reviewReasons.add('No se pudo determinar la familia del producto.');
    } else {
      evidence.add(ProductCatalogSemanticEvidence(
        kind: ProductCatalogSemanticEvidenceKind.familyAlias,
        detail: '$family desde el título original',
      ));
    }
    if (rows.length > 1 && rows.first.listingId?.trim().isNotEmpty == true) {
      evidence.add(ProductCatalogSemanticEvidence(
        kind: ProductCatalogSemanticEvidenceKind.listingConsensus,
        detail:
            '${rows.length} variantes comparten la publicación ${rows.first.listingId!.trim()}',
      ));
    }

    Category? category;
    final expectedPath = _categoryPathByFamily[family];
    if (expectedPath != null) {
      category = _categoryByFullPath(expectedPath);
      if (category == null) {
        evidence.add(ProductCatalogSemanticEvidence(
          kind: ProductCatalogSemanticEvidenceKind.unresolvedCategory,
          detail: expectedPath,
        ));
        reviewReasons.add(
          'No existe la categoría canónica "$expectedPath" en el catálogo.',
        );
      } else {
        evidence.add(ProductCatalogSemanticEvidence(
          kind: ProductCatalogSemanticEvidenceKind.categoryPath,
          detail: '${category.id ?? 'sin-id'} · ${category.fullPath}',
        ));
      }
    }

    final categoryHints = rows
        .map((row) => row.categoryHint?.trim())
        .whereType<String>()
        .where((hint) => hint.isNotEmpty)
        .toSet();
    if (category == null && expectedPath == null) {
      for (final hint in categoryHints) {
        final normalizedHint = _normalize(hint);
        if (normalizedHint.contains('tubeless') &&
            family != tubelessValveFamily) {
          evidence.add(ProductCatalogSemanticEvidence(
            kind: ProductCatalogSemanticEvidenceKind.rejectedCategoryHint,
            detail: '$hint sin evidencia explícita tubeless',
          ));
          continue;
        }
        final matches = _categoriesForHint(hint);
        if (matches.length == 1) {
          category = matches.single;
          evidence.add(ProductCatalogSemanticEvidence(
            kind: ProductCatalogSemanticEvidenceKind.categoryPath,
            detail: '${category.id ?? 'sin-id'} · ${category.fullPath}',
          ));
          break;
        }
        if (matches.length > 1) {
          evidence.add(ProductCatalogSemanticEvidence(
            kind: ProductCatalogSemanticEvidenceKind.rejectedCategoryHint,
            detail: '$hint coincide con ${matches.length} rutas',
          ));
          reviewReasons.add(
            'La categoría sugerida "$hint" existe en más de una ruta.',
          );
        }
      }
    }
    if (category != null) {
      for (final hint in categoryHints) {
        if (!_categoryHintMatches(hint, category)) {
          evidence.add(ProductCatalogSemanticEvidence(
            kind: ProductCatalogSemanticEvidenceKind.rejectedCategoryHint,
            detail: '$hint ≠ ${category.fullPath}',
          ));
        }
      }
    }

    final explicitBrandName = _explicitBrandName(rawText);
    ProductBrand? brand;
    if (explicitBrandName != null) {
      brand = _brandByName(explicitBrandName);
      evidence.add(ProductCatalogSemanticEvidence(
        kind: ProductCatalogSemanticEvidenceKind.explicitBrand,
        detail: explicitBrandName,
      ));
      if (brand == null) {
        evidence.add(ProductCatalogSemanticEvidence(
          kind: ProductCatalogSemanticEvidenceKind.unresolvedBrand,
          detail: explicitBrandName,
        ));
        reviewReasons.add(
          'La marca "$explicitBrandName" está explícita, pero no existe en el catálogo de marcas.',
        );
      }
    }

    final brandHints = rows
        .map((row) => row.brandHint?.trim())
        .whereType<String>()
        .where((hint) => hint.isNotEmpty)
        .toSet();
    for (final hint in brandHints) {
      final matchesExplicit = explicitBrandName != null &&
          _normalize(hint) == _normalize(explicitBrandName);
      if (!matchesExplicit) {
        evidence.add(ProductCatalogSemanticEvidence(
          kind: ProductCatalogSemanticEvidenceKind.rejectedBrandHint,
          detail: explicitBrandName == null
              ? '$hint sin evidencia explícita de fabricante'
              : '$hint contradice $explicitBrandName',
        ));
      }
    }

    var confidence = family == unknownFamily ? 0.20 : 0.72;
    if (category != null) confidence += 0.16;
    if (brand != null) confidence += 0.10;
    if (explicitBrandName != null && brand == null) confidence -= 0.12;
    if (rows.length > 1) confidence += 0.02;
    confidence = confidence.clamp(0, 1).toDouble();

    return _GroupResolution(
      family: family,
      category: category,
      brand: brand,
      evidence: List<ProductCatalogSemanticEvidence>.unmodifiable(evidence),
      confidence: confidence,
      reviewReason:
          reviewReasons.isEmpty ? null : reviewReasons.toSet().join(' '),
    );
  }

  String _inferFamily(String normalized) {
    final isAdapter = _hasAny(normalized, const [
      'adaptador',
      'adapter',
      'conversor',
      'converter',
    ]);
    final hasPresta = _hasAny(normalized, const [
      'presta',
      'fv',
      'vf',
      'f v',
      'v f',
      'francesa',
      'french valve',
    ]);
    final hasSchrader = _hasAny(normalized, const [
      'schrader',
      'av',
      'va',
      'a v',
      'v a',
      'americana',
      'auto valve',
    ]);
    if (isAdapter && hasPresta && hasSchrader) return valveAdapterFamily;

    final hasTubeless = _hasAny(normalized, const ['tubeless', 'sin camara']);
    final hasValve = _hasAny(normalized, const ['valvula', 'valve']);
    if (hasTubeless && hasValve) return tubelessValveFamily;

    final isHandlebarStem = _hasAny(
      normalized,
      const ['tee', 'potencia', 'stem'],
    );
    final isSupplierTranslatedStem = _hasAny(normalized, const ['vastago']) &&
        _hasAny(
          normalized,
          const ['manillar', 'handlebar', '31 8mm'],
        );
    if (isHandlebarStem || isSupplierTranslatedStem) {
      return stemFamily;
    }
    if (_hasAny(
      normalized,
      const ['volante', 'crankset', 'pedivela', 'biela', 'bielas'],
    )) {
      return cranksetFamily;
    }
    return unknownFamily;
  }

  Category? _categoryByFullPath(String fullPath) {
    final target = _normalizePath(fullPath);
    for (final category in _categories) {
      if (category.id == null || category.id!.trim().isEmpty) continue;
      if (_normalizePath(category.fullPath) == target) return category;
    }
    return null;
  }

  List<Category> _categoriesForHint(String hint) {
    final targetPath = _normalizePath(hint);
    final targetName = _normalize(hint);
    return _categories.where((category) {
      if (category.id == null || category.id!.trim().isEmpty) return false;
      return _normalizePath(category.fullPath) == targetPath ||
          _normalize(category.name) == targetName;
    }).toList(growable: false);
  }

  ProductBrand? _brandByName(String name) {
    final target = _normalize(name);
    for (final brand in _brands) {
      if (brand.id == null || brand.id!.trim().isEmpty) continue;
      if (_normalize(brand.name) == target) return brand;
    }
    return null;
  }

  String? _explicitBrandName(String rawText) {
    final withoutCompatibility = _stripCompatibilityClaims(rawText);
    final aliases = <String, String>{
      for (final brand in _brands)
        if (brand.name.trim().isNotEmpty) _normalize(brand.name): brand.name,
      ..._knownExternalBrandAliases,
    };
    final normalized = ' ${_normalize(withoutCompatibility)} ';
    final matches = aliases.entries
        .where((entry) => normalized.contains(' ${entry.key} '))
        .toList(growable: false)
      ..sort((left, right) => right.key.length.compareTo(left.key.length));
    return matches.isEmpty ? null : matches.first.value;
  }

  String _stripCompatibilityClaims(String value) {
    return value.replaceAll(
      RegExp(
        r'\b(?:compatible(?:\s+con)?|compatibility\s+with|works\s+with|para|for)\b[^,;|()]*',
        caseSensitive: false,
      ),
      ' ',
    );
  }

  bool _categoryHintMatches(String hint, Category category) {
    final normalizedHint = _normalizePath(hint);
    return normalizedHint == _normalizePath(category.fullPath) ||
        normalizedHint == _normalize(category.name);
  }

  bool _hasAny(String normalized, Iterable<String> phrases) {
    final haystack = ' $normalized ';
    for (final phrase in phrases) {
      final needle = _normalize(phrase);
      if (needle.isNotEmpty && haystack.contains(' $needle ')) return true;
    }
    return false;
  }

  String _normalizePath(String value) {
    return value
        .split('/')
        .map(_normalize)
        .where((part) => part.isNotEmpty)
        .join(' / ');
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâã]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöôõ]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _GroupResolution {
  const _GroupResolution({
    required this.family,
    required this.category,
    required this.brand,
    required this.evidence,
    required this.confidence,
    required this.reviewReason,
  });

  final String family;
  final Category? category;
  final ProductBrand? brand;
  final List<ProductCatalogSemanticEvidence> evidence;
  final double confidence;
  final String? reviewReason;
}
