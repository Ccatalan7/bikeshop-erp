import '../../models/category_models.dart';
import '../../models/inventory_models.dart';
import 'product_identity_extractor.dart';
import 'product_image_identity.dart';
import 'product_identity_profile.dart';

/// A profile cache plus posting lists over the catalog.
///
/// Two problems it exists to solve, both measured against the real 1555-product
/// production catalog on 2026-08-09:
///
/// * the previous matcher re-derived every product's family and tokens **once
///   per invoice line**, so a seven-line invoice paid for eleven thousand
///   extractions; and
/// * it then scored every product against every line, so the work grew with
///   the catalog even though at most a few dozen products can plausibly be the
///   purchased part.
///
/// Profiles are built once and reused; retrieval returns a bounded shortlist
/// selected by shared identity evidence, never the whole catalog.
class ProductCatalogIdentityIndex {
  ProductCatalogIdentityIndex({
    Iterable<String> knownBrands = const <String>[],
    Map<String, List<String>> categoryAncestry = const {},
    this.maxShortlist = 120,
  })  : _knownBrands = List<String>.unmodifiable(knownBrands),
        categoryAncestry = Map<String, List<String>>.unmodifiable(
          categoryAncestry,
        );

  final List<String> _knownBrands;

  /// Normalized leaf category name → full path segments.
  final Map<String, List<String>> categoryAncestry;

  /// Upper bound on how many products one line may be scored against.
  final int maxShortlist;

  /// A token whose posting list is longer than this says nothing useful about
  /// identity (`bicicleta`, `negro`) and is not indexed for retrieval.
  static const int _maxDescriptorPostings = 60;

  final Map<String, _IndexedProduct> _byKey = <String, _IndexedProduct>{};
  final Map<String, List<String>> _byFamily = <String, List<String>>{};
  final Map<String, List<String>> _byBrand = <String, List<String>>{};
  final Map<String, List<String>> _byModel = <String, List<String>>{};
  final Map<String, List<String>> _bySpec = <String, List<String>>{};
  final Map<String, List<String>> _byDescriptor = <String, List<String>>{};
  final Map<String, List<String>> _bySupplierCode = <String, List<String>>{};
  final Map<String, List<String>> _byImageIdentity = <String, List<String>>{};

  int get length => _byKey.length;

  /// Builds the leaf-name → full-path map the matcher needs.
  ///
  /// A product row stores only its leaf category name (`Corta Cadena`), while
  /// the AI hint and the operator's selector speak in ancestors
  /// (`Herramientas`). Without this map those two never agreed and a tool
  /// could not be recognized as belonging to the tools branch.
  ///
  /// A leaf name that exists under more than one parent is **omitted**:
  /// `Adaptadores` lives under `Accesorios`, under `Componentes / Frenos` and
  /// under `Viñabike`, so the row alone cannot say which one it means, and
  /// guessing would let a brake adapter agree with a valve adapter.
  static Map<String, List<String>> buildCategoryAncestry(
    Iterable<Category> categories,
  ) {
    final byLeaf = <String, Set<String>>{};
    final paths = <String, List<String>>{};
    for (final category in categories) {
      final leaf = ProductIdentityExtractor.normalize(category.name);
      if (leaf.isEmpty) continue;
      final segments = category.fullPath
          .split('/')
          .map(ProductIdentityExtractor.normalize)
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
      if (segments.isEmpty) continue;
      (byLeaf[leaf] ??= <String>{}).add(segments.join('/'));
      paths[leaf] = segments;
    }
    return <String, List<String>>{
      for (final entry in byLeaf.entries)
        if (entry.value.length == 1) entry.key: paths[entry.key]!,
    };
  }

  /// Rebuilds only what changed. A product keeps its profile while its
  /// identity-bearing fields are untouched, which is what makes a second
  /// invoice in the same session almost free.
  void sync(List<Product> products) {
    final live = <String>{};
    var structureChanged = false;

    for (final product in products) {
      if (!product.isActive || product.isService) continue;
      final key = _keyOf(product);
      live.add(key);
      final signature = _signatureOf(product);
      final existing = _byKey[key];
      if (existing != null && existing.signature == signature) {
        existing.product = product;
        continue;
      }
      _byKey[key] = _IndexedProduct(
        key: key,
        product: product,
        signature: signature,
        profile: _profileOf(product),
      );
      structureChanged = true;
    }

    final removed = _byKey.keys.where((key) => !live.contains(key)).toList();
    for (final key in removed) {
      _byKey.remove(key);
      structureChanged = true;
    }

    if (structureChanged) _rebuildPostings();
  }

  ProductIdentityProfile profileOfProduct(Product product) {
    final cached = _byKey[_keyOf(product)];
    if (cached != null && cached.signature == _signatureOf(product)) {
      return cached.profile;
    }
    return _profileOf(product);
  }

  ProductIdentityProfile? profileForKey(String key) => _byKey[key]?.profile;

  Product? productForKey(String key) => _byKey[key]?.product;

  /// The bounded shortlist for one probe.
  ///
  /// A product enters only through evidence that could make it the same
  /// object: a supplier code, a model code, its family combined with a brand
  /// or a decisive measurement, or — when the family is small enough to scan —
  /// the family itself.
  List<Product> retrieve(
    ProductIdentityProfile probe, {
    Iterable<String> identityCodes = const <String>[],
    String? imageIdentity,
  }) {
    final scores = <String, int>{};

    void addAll(Iterable<String>? keys, int weight) {
      if (keys == null) return;
      for (final key in keys) {
        scores[key] = (scores[key] ?? 0) + weight;
      }
    }

    // Deterministic evidence first, and unconditionally: a shared SKU, a shared
    // supplier listing or the same photo must reach the matcher even when the
    // two titles have nothing in common.
    for (final code in identityCodes) {
      final normalized = code.trim().toLowerCase();
      if (normalized.isEmpty) continue;
      addAll(_bySupplierCode[normalized], 100);
    }
    if (imageIdentity != null && imageIdentity.isNotEmpty) {
      addAll(_byImageIdentity[imageIdentity], 100);
    }

    for (final code in probe.modelCodes) {
      addAll(_byModel[code], 40);
    }

    final family = probe.effectiveFamilyId;
    final familyKeys = family == null ? null : _byFamily[family];

    if (familyKeys != null) {
      final brand = probe.assertedBrand;
      if (brand != null) {
        final brandKeys = _byBrand[brand];
        if (brandKeys != null) {
          addAll(familyKeys.toSet().intersection(brandKeys.toSet()), 30);
        }
      }
      for (final entry in probe.specs.entries) {
        if (entry.key == PartSpecKind.colorVariant) continue;
        final specKeys = _bySpec['${entry.key.name}=${entry.value}'];
        if (specKeys == null) continue;
        addAll(familyKeys.toSet().intersection(specKeys.toSet()), 12);
      }
      // A family that fits inside the shortlist is scanned whole: refusing a
      // real candidate because retrieval was too clever is worse than scoring
      // a few dozen extra products with a pure function.
      if (familyKeys.length <= maxShortlist) {
        addAll(familyKeys, 8);
      }
    }

    final brand = probe.assertedBrand;
    if (brand != null) addAll(_byBrand[brand], 6);

    for (final token in probe.descriptorTokens) {
      addAll(_byDescriptor[token], 1);
    }

    if (scores.isEmpty) return const <Product>[];

    final ranked = scores.keys.toList()
      ..sort((left, right) {
        final byScore = scores[right]!.compareTo(scores[left]!);
        if (byScore != 0) return byScore;
        return left.compareTo(right);
      });

    return <Product>[
      for (final key in ranked.take(maxShortlist))
        if (_byKey[key] != null) _byKey[key]!.product,
    ];
  }

  ProductIdentityProfile _profileOf(Product product) {
    return ProductIdentityExtractor.extract(
      ProductIdentityInput(
        name: product.name,
        description: <String?>[
          product.description,
          product.model,
          product.manufacturerSku,
          if (product.tags.isNotEmpty) product.tags.join(' '),
        ].whereType<String>().where((value) => value.trim().isNotEmpty).join(
              ' ',
            ),
        brandHint: product.brand,
        // The catalog's brand column is the shop's own statement about who
        // made the product, not a reading of somebody else's title.
        brandIsAsserted: true,
        modelHint: product.model ?? product.manufacturerSku,
        categoryPath: product.categoryName,
        knownBrands: _knownBrands,
      ),
    );
  }

  void _rebuildPostings() {
    _byFamily.clear();
    _byBrand.clear();
    _byModel.clear();
    _bySpec.clear();
    _byDescriptor.clear();
    _bySupplierCode.clear();
    _byImageIdentity.clear();

    final descriptorDraft = <String, List<String>>{};

    for (final indexed in _byKey.values) {
      final profile = indexed.profile;
      final key = indexed.key;

      final family = profile.effectiveFamilyId;
      if (family != null) {
        (_byFamily[family] ??= <String>[]).add(key);
      }
      final brand = profile.assertedBrand;
      if (brand != null) {
        (_byBrand[brand] ??= <String>[]).add(key);
      }
      for (final code in profile.modelCodes) {
        (_byModel[code] ??= <String>[]).add(key);
      }
      for (final entry in profile.specs.entries) {
        if (entry.key == PartSpecKind.colorVariant) continue;
        (_bySpec['${entry.key.name}=${entry.value}'] ??= <String>[]).add(key);
      }
      for (final token in profile.descriptorTokens) {
        (descriptorDraft[token] ??= <String>[]).add(key);
      }
      // Every code that can name this product, plus every listing id and image
      // hiding inside those codes. Deterministic identity has to be reachable
      // even when the two names share no word at all: a re-titled catalog row
      // and its invoice line often do not.
      for (final code in <String?>[
        indexed.product.sku,
        indexed.product.supplierCode,
        indexed.product.manufacturerSku,
      ]) {
        final normalized = code?.trim().toLowerCase();
        if (normalized == null || normalized.isEmpty) continue;
        (_bySupplierCode[normalized] ??= <String>[]).add(key);
      }
      for (final listingId in supplierListingIdsIn(<String?>[
        indexed.product.supplierCode,
        indexed.product.manufacturerSku,
        indexed.product.description,
      ])) {
        (_bySupplierCode[listingId.toLowerCase()] ??= <String>[]).add(key);
      }
      for (final url in <String?>[
        indexed.product.imageUrlOptimized,
        indexed.product.imageUrl,
        ...indexed.product.additionalImages,
      ]) {
        final identity = canonicalProductImageIdentity(url);
        if (identity.isEmpty) continue;
        (_byImageIdentity[identity] ??= <String>[]).add(key);
      }
    }

    for (final entry in descriptorDraft.entries) {
      if (entry.value.length > _maxDescriptorPostings) continue;
      _byDescriptor[entry.key] = entry.value;
    }
  }

  static String _keyOf(Product product) =>
      product.id ?? '${product.sku} ${product.name}';

  static String _signatureOf(Product product) => <String>[
        product.name,
        product.description ?? '',
        product.brand ?? '',
        product.model ?? '',
        product.manufacturerSku ?? '',
        product.categoryName ?? '',
        product.supplierCode ?? '',
        product.tags.join(','),
      ].join('');
}

class _IndexedProduct {
  _IndexedProduct({
    required this.key,
    required this.product,
    required this.signature,
    required this.profile,
  });

  final String key;
  Product product;
  final String signature;
  final ProductIdentityProfile profile;
}
