import '../../models/category_models.dart';
import '../../models/inventory_models.dart';
import 'product_category_resolver.dart';
import 'product_identity_extractor.dart';
import 'product_identity_profile.dart';
import 'product_visual_reading.dart';

/// Whether the available sources establish one exact object family.
enum CanonicalProductFamilyState { resolved, unknown, conflicting }

/// An exact tenant category reference used to scope ordinary recommendations.
///
/// Category is primarily placement, not identity. A uniquely typed leaf may
/// fill a genuinely missing family, but it never becomes a competing family,
/// never overrules a title/photo and an ambiguous leaf supplies no family.
class CanonicalCategoryAuthority {
  const CanonicalCategoryAuthority({
    required this.path,
    this.id,
    this.isActiveLeaf = false,
  });

  final String? id;
  final List<String> path;

  /// Whether the tenant tree proves this is an active leaf rather than a broad
  /// system/ancestor. A path supplied without the tree is useful for display
  /// and conflict checks, but is not enough to recover a missing object family.
  final bool isActiveLeaf;

  bool get isUsable => (id?.isNotEmpty ?? false) || path.isNotEmpty;

  String get label => path.isEmpty ? (id ?? '') : path.join(' / ');

  bool matches(CanonicalCategoryAuthority other) {
    final leftId = id;
    final rightId = other.id;
    if (leftId != null && rightId != null) return leftId == rightId;
    if (path.isEmpty || other.path.isEmpty) return false;
    return _samePath(path, other.path);
  }

  /// Whether this selected category contains [other]. A selected ancestor is a
  /// valid scope for any descendant shelf in the tenant tree.
  bool scopes(CanonicalCategoryAuthority other) {
    if (matches(other)) return true;
    if (path.isEmpty || other.path.length < path.length) return false;
    for (var index = 0; index < path.length; index++) {
      if (path[index] != other.path[index]) return false;
    }
    return true;
  }

  static bool _samePath(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

/// One canonical reading shared by category scoping and duplicate matching.
class CanonicalProductIdentity {
  const CanonicalProductIdentity({
    required this.profile,
    required this.familyState,
    required this.familyHypotheses,
    required this.categoryFamilyHypotheses,
    required this.resolvedFamilyId,
    required this.category,
    this.isReviewOnlyFamilyScope = false,
    this.reviewScopeReason,
  });

  final ProductIdentityProfile profile;
  final CanonicalProductFamilyState familyState;
  final Set<String> familyHypotheses;

  /// Families that can legitimately occupy the selected leaf. Empty means the
  /// category is absent, is an ancestor/system node, or has no taxonomy
  /// mapping. More than one means the leaf is ambiguous and cannot decide the
  /// family by itself.
  final Set<String> categoryFamilyHypotheses;
  final String? resolvedFamilyId;
  final CanonicalCategoryAuthority? category;

  /// True only when the catalog row did not establish its own family and was
  /// admitted for operator review through a safe category scope.
  ///
  /// This provenance is deliberately carried on the identity: callers must
  /// never turn category-scoped recall into an automatic recommendation.
  final bool isReviewOnlyFamilyScope;
  final String? reviewScopeReason;

  /// Narrow legacy shelves where the category may disambiguate a deliberately
  /// generic catalog name. Keep this explicit: allowing every shared leaf did
  /// the opposite and reclassified unrelated pumps, truing stands and cutters
  /// as tubeless repair kits merely because all lived under `Herramientas`.
  static const List<Set<String>> _safeCategoryOnlyContextGroups = <Set<String>>[
    <String>{'stem_spacer', 'cassette_spacer'},
  ];

  bool get hasResolvedFamily =>
      familyState == CanonicalProductFamilyState.resolved &&
      resolvedFamilyId != null;

  /// Narrows an otherwise unknown catalog row using the already-resolved
  /// probe family and the row's own ambiguous category leaf.
  ///
  /// This is contextual evidence, not a rewrite: a textual/visual family is
  /// never changed, and a category that does not explicitly allow [familyId]
  /// cannot admit the row. It exists for sparse legacy rows such as
  /// `Espaciador Genérico` whose shared `Espaciadores` shelf covers both
  /// headset and cassette spacers.
  CanonicalProductIdentity? contextualizedFor(String familyId) {
    if (hasResolvedFamily) {
      return resolvedFamilyId == familyId ? this : null;
    }
    final categoryOnlyContextIsSafe = _safeCategoryOnlyContextGroups.any(
      (group) =>
          group.length == categoryFamilyHypotheses.length &&
          group.containsAll(categoryFamilyHypotheses),
    );
    if (familyState != CanonicalProductFamilyState.unknown ||
        !categoryFamilyHypotheses.contains(familyId) ||
        (!profile.familyCandidates.contains(familyId) &&
            !categoryOnlyContextIsSafe)) {
      return null;
    }
    return _asReviewOnlyFamilyScope(
      familyId,
      'La ficha no identifica el tipo de pieza; la categoría sólo permite '
      'mostrarla para revisión.',
    );
  }

  /// Safely admits an unknown-family catalog row for one resolved probe.
  ///
  /// A resolved candidate of another family is always eliminated. An unknown
  /// candidate is reviewable only when either the existing narrow canonical
  /// category rule supports the probe family, or both sides point to the exact
  /// same active leaf in the tenant tree. A shared parent/ancestor is never
  /// enough: `Herramientas` containing two rows does not make them the same
  /// object.
  CanonicalProductIdentity? contextualizedForProbe(
    CanonicalProductIdentity probe,
  ) {
    final familyId = probe.resolvedFamilyId;
    if (!probe.hasResolvedFamily || familyId == null) return null;
    if (hasResolvedFamily) {
      return resolvedFamilyId == familyId ? this : null;
    }
    if (familyState != CanonicalProductFamilyState.unknown) return null;

    final canonicalScope = contextualizedFor(familyId);
    if (canonicalScope != null) return canonicalScope;

    final probeCategory = probe.category;
    final candidateCategory = category;
    final sameActiveLeaf = probeCategory != null &&
        candidateCategory != null &&
        probeCategory.isActiveLeaf &&
        candidateCategory.isActiveLeaf &&
        probeCategory.matches(candidateCategory);
    if (!sameActiveLeaf) return null;

    return _asReviewOnlyFamilyScope(
      familyId,
      'La ficha no identifica el tipo de pieza; se muestra sólo porque está '
      'en la categoría exacta ${candidateCategory.label}.',
    );
  }

  CanonicalProductIdentity _asReviewOnlyFamilyScope(
    String familyId,
    String reason,
  ) {
    return CanonicalProductIdentity(
      profile: profile,
      familyState: CanonicalProductFamilyState.resolved,
      familyHypotheses: <String>{familyId},
      categoryFamilyHypotheses: categoryFamilyHypotheses,
      resolvedFamilyId: familyId,
      category: category,
      isReviewOnlyFamilyScope: true,
      reviewScopeReason: reason,
    );
  }
}

/// Pure authority for reconciling textual, visual and tenant-category evidence.
///
/// The extractor remains the vocabulary owner. This resolver adds the rule the
/// old `effectiveFamilyId` could not express: a useful photo that disagrees with
/// the title is a conflict, not permission to replace the textual family.
class CanonicalProductIdentityResolver {
  CanonicalProductIdentityResolver({
    Iterable<Category> categories = const <Category>[],
    Iterable<String> knownBrands = const <String>[],
    Map<String, List<String>> categoryAncestry = const <String, List<String>>{},
  })  : _categories = List<Category>.unmodifiable(categories),
        _knownBrands = List<String>.unmodifiable(knownBrands),
        _categoryAncestry = Map<String, List<String>>.unmodifiable(
          categoryAncestry,
        ) {
    final parentIds = <String>{};
    for (final category in _categories) {
      final parentId = category.parentId?.trim();
      if (parentId != null && parentId.isNotEmpty) parentIds.add(parentId);
    }
    _parentCategoryIds.addAll(parentIds);
    for (final category in _categories) {
      final id = category.id?.trim();
      if (id != null && id.isNotEmpty && category.isActive) {
        _categoryById[id] = category;
      }
      if (!category.isActive) continue;
      final path = _normalizePath(category.fullPath);
      if (path.isEmpty) continue;
      final key = path.join('/');
      if (!_categoryByPath.containsKey(key)) {
        _categoryByPath[key] = category;
      } else {
        _categoryByPath[key] = null;
      }
    }
  }

  static const double visualFamilyEvidenceFloor =
      ProductIdentityProfile.visualMinimumConfidence;

  final List<Category> _categories;
  final List<String> _knownBrands;
  final Map<String, List<String>> _categoryAncestry;
  final Map<String, Category> _categoryById = <String, Category>{};
  final Map<String, Category?> _categoryByPath = <String, Category?>{};
  final Set<String> _parentCategoryIds = <String>{};

  CanonicalProductIdentity resolve(
    ProductIdentityInput input, {
    ProductVisualReading reading = ProductVisualReading.empty,
    String? categoryId,
    String? categoryPath,
  }) {
    final profile = ProductIdentityExtractor.extract(
      ProductIdentityInput(
        name: input.name,
        description: input.description,
        sourceTitle: input.sourceTitle,
        variantText: input.variantText,
        rawText: input.rawText,
        brandHint: input.brandHint,
        brandIsAsserted: input.brandIsAsserted,
        modelHint: input.modelHint,
        categoryPath: categoryPath ?? input.categoryPath,
        knownBrands:
            input.knownBrands.isEmpty ? _knownBrands : input.knownBrands,
      ),
    );
    return resolveProfile(
      profile,
      reading: reading,
      categoryId: categoryId,
      categoryPath: categoryPath ?? input.categoryPath,
    );
  }

  CanonicalProductIdentity resolveProfile(
    ProductIdentityProfile profile, {
    ProductVisualReading reading = ProductVisualReading.empty,
    String? categoryId,
    String? categoryPath,
  }) {
    if (reading.isUseful) {
      profile = profile.withVisualReading(
        visualFamilyId: reading.familyId,
        visualTerms: reading.terms,
        visualConfidence: reading.confidence,
      );
    }
    final category = resolveCategory(id: categoryId, path: categoryPath);
    final categoryFamilies = _familiesForLeaf(category);
    final textFamily = profile.familyId;
    final visualFamily = reading.familyId != null &&
            reading.confidence >= visualFamilyEvidenceFloor
        ? reading.familyId
        : null;
    final visualCorroboratesText =
        ProductIdentityProfile.visualFamilyCorroboratesText(
      textFamilyId: textFamily,
      visualFamilyId: visualFamily,
    );
    final hypotheses = <String>{
      if (textFamily != null) textFamily,
      if (visualFamily != null &&
          !visualCorroboratesText &&
          !profile.supplierTitleFamilyIsAuthoritative)
        visualFamily,
    };
    if (hypotheses.isEmpty && categoryFamilies.length == 1) {
      hypotheses.add(categoryFamilies.single);
    }

    final CanonicalProductFamilyState familyState;
    final String? resolvedFamilyId;
    if (hypotheses.isEmpty) {
      familyState = CanonicalProductFamilyState.unknown;
      resolvedFamilyId = null;
    } else if (hypotheses.length == 1) {
      familyState = CanonicalProductFamilyState.resolved;
      resolvedFamilyId = hypotheses.single;
    } else {
      familyState = CanonicalProductFamilyState.conflicting;
      resolvedFamilyId = null;
    }

    return CanonicalProductIdentity(
      profile: profile,
      familyState: familyState,
      familyHypotheses: Set<String>.unmodifiable(hypotheses),
      categoryFamilyHypotheses: Set<String>.unmodifiable(categoryFamilies),
      resolvedFamilyId: resolvedFamilyId,
      category: category,
    );
  }

  CanonicalProductIdentity resolveCatalogProduct(Product product) {
    final category = resolveCategory(
      id: product.categoryId,
      path: product.categoryName,
    );
    final categoryPath = category?.label ?? product.categoryName;
    return resolve(
      ProductIdentityInput(
        name: product.name,
        description: <String?>[
          product.description,
          product.model,
          product.manufacturerSku,
          if (product.tags.isNotEmpty) product.tags.join(' '),
        ]
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .join(' '),
        brandHint: product.brand,
        brandIsAsserted: true,
        modelHint: product.model ?? product.manufacturerSku,
        categoryPath: categoryPath,
        knownBrands: _knownBrands,
      ),
      categoryId: product.categoryId,
      categoryPath: categoryPath,
    );
  }

  CanonicalCategoryAuthority? resolveCategory({String? id, String? path}) {
    final normalizedId = id?.trim();
    if (normalizedId != null && normalizedId.isNotEmpty) {
      final category = _categoryById[normalizedId];
      return CanonicalCategoryAuthority(
        id: normalizedId,
        path: category == null
            ? _expandedPath(path)
            : _normalizePath(category.fullPath),
        isActiveLeaf:
            category != null && !_parentCategoryIds.contains(normalizedId),
      );
    }

    final expanded = _expandedPath(path);
    if (expanded.isEmpty) return null;
    final category = _categoryByPath[expanded.join('/')];
    if (_categoryByPath.containsKey(expanded.join('/')) && category == null) {
      return null;
    }
    return CanonicalCategoryAuthority(
      id: category?.id?.trim(),
      path: expanded,
      isActiveLeaf: category != null &&
          !_parentCategoryIds.contains(category.id?.trim() ?? ''),
    );
  }

  Set<String> _familiesForLeaf(CanonicalCategoryAuthority? category) {
    if (category == null || category.path.isEmpty) return const <String>{};

    // A selected ancestor is useful as a retrieval scope, but it describes a
    // system rather than one exact kind of object. Only real active leaves may
    // contribute typed family evidence.
    final categoryId = category.id?.trim();
    if (categoryId == null ||
        categoryId.isEmpty ||
        !_categoryById.containsKey(categoryId) ||
        _parentCategoryIds.contains(categoryId)) {
      return const <String>{};
    }

    final leaf = category.path.last;
    final families = <String>{};
    for (final entry
        in ProductCategoryResolver.canonicalLeavesByFamily.entries) {
      if (entry.value.any(
        (alias) => ProductIdentityExtractor.normalize(alias) == leaf,
      )) {
        families.add(entry.key);
      }
    }
    return families;
  }

  List<String> _expandedPath(String? value) {
    final normalized = _normalizePath(value);
    if (normalized.length != 1) return normalized;
    final expanded = _categoryAncestry[normalized.single];
    if (expanded != null && expanded.isNotEmpty) return expanded;

    // A bare leaf is authoritative only when the tenant tree makes it unique.
    final matching = _categories.where((category) {
      if (!category.isActive) return false;
      return ProductIdentityExtractor.normalize(category.name) ==
          normalized.single;
    }).toList(growable: false);
    if (matching.length != 1) return const <String>[];
    return _normalizePath(matching.single.fullPath);
  }

  static List<String> _normalizePath(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return const <String>[];
    return trimmed
        .split('/')
        .map(ProductIdentityExtractor.normalize)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }
}
