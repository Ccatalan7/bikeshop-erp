import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart'
    as inv_service;
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_matcher_service.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/canonical_product_identity_resolver.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_category_resolver.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_extractor.dart';

/// Executable regression oracle from the read-only AliExpress audit plus every
/// subsequently opened unseen row after diagnosis.
///
/// This intentionally starts from the observed invoice fields and the real
/// production category tree. It must never inject the gold product's category:
/// doing that made the old replay green while the real OCR flow categorized a
/// phone holder as `Manubrio` and a hydraulic assembly as `Calipers`.
void main() {
  test('48 diagnosed rows replay against the current complete catalog',
      () async {
    final audit = _readJson(
      'test/fixtures/ocr/aliexpress_identity_audit_2026_08_11.json',
    );
    final catalog = _readJson(
      'test/fixtures/ocr/catalog_identity_regression_fixture_2026_08_12.json',
    );
    final rows = (audit['rows'] as List).cast<Map<String, dynamic>>();
    final products = (catalog['products'] as List)
        .cast<Map<String, dynamic>>()
        .map(Product.fromJson)
        .toList(growable: false);
    final bySku = <String, Product>{
      for (final product in products) product.sku: product
    };
    final categories = _readCategories();
    final resolver = CanonicalProductIdentityResolver(
      categories: categories,
      knownBrands: products
          .map((product) => product.brand?.trim())
          .whereType<String>()
          .where((brand) => brand.isNotEmpty)
          .toSet(),
    );
    final categoryResolver = ProductCategoryResolver(categories: categories);
    final matcher = ProductDuplicateMatcherService(
      inventoryService: _FakeInventoryService(),
      categories: categories,
      knownBrands: products
          .map((product) => product.brand?.trim())
          .whereType<String>()
          .where((brand) => brand.isNotEmpty)
          .toSet(),
      enableVisualReading: false,
      enableMatchAdjudication: false,
      requireAIPrimaryInvestigation: false,
      persistComputedImageFingerprints: false,
    );

    var clearRows = 0;
    var top1 = 0;
    var top3 = 0;
    var noExistsCorrect = 0;
    var ambiguousCovered = 0;
    final failures = <String>[];
    final top1Misses = <String>[];

    for (final row in rows) {
      final expected = row['expected'] as Map<String, dynamic>;
      final observed = row['observed'] as Map<String, dynamic>;
      final outcome = expected['outcome'] as String;
      final title = row['source_title'] as String;
      final cleanedName = observed['cleaned_name'] as String;
      final expectedSkus = <String>{
        ...((expected['catalog_skus'] as List?) ?? const <dynamic>[])
            .map((value) => value.toString()),
        ...((expected['candidate_catalog_skus'] as List?) ?? const <dynamic>[])
            .map((value) => value.toString()),
      };
      final observedCategory = _effectiveCategory(
        categories: categories,
        resolver: categoryResolver,
        name: cleanedName,
        sourceTitle: title,
        selectedVariant: row['selected_variant'] as String?,
        brandName: observed['brand_name'] as String?,
        observedCategoryName: observed['category_name'] as String?,
        knownBrands: products
            .map((product) => product.brand?.trim())
            .whereType<String>()
            .where((brand) => brand.isNotEmpty),
      );
      final result = await matcher.resolveCandidates(
        probe: ProductDuplicateProbe(
          name: cleanedName,
          sourceTitle: title,
          selectedVariant: row['selected_variant'] as String?,
          categoryId: observedCategory?.id,
          categoryName: observed['category_name'] as String?,
          brandName: observed['brand_name'] as String?,
          supplierListingId: row['listing_id'] as String?,
          cost: (row['unit_cost'] as num?)?.toDouble(),
        ),
        products: products,
      );
      final ranked = result.recommendations
          .map((candidate) => candidate.product.sku)
          .toList(growable: false);
      final operatorRanked = result.operatorChoices
          .map((candidate) => candidate.product.sku)
          .toList(growable: false);
      final admitted = <String>{
        ...ranked,
        ...operatorRanked,
        for (final candidate in result.categoryConflicts) candidate.product.sku,
      };

      if (outcome == 'no_exists') {
        if (result.recommendations.isEmpty) {
          noExistsCorrect++;
        } else {
          failures
              .add('${row['id']}: no existe -> ${ranked.take(3).join(',')}');
        }
        continue;
      }

      if (outcome == 'ambiguous') {
        if (operatorRanked.take(3).any(expectedSkus.contains)) {
          ambiguousCovered++;
        } else {
          failures.add(
            '${row['id']}: ambiguo sin gold top-3 -> '
            '${operatorRanked.take(3).join(',')}',
          );
        }
        continue;
      }

      if (expected['cardinality'] == 'product_set') {
        final visible = operatorRanked.take(8).toSet();
        if (!visible.containsAll(expectedSkus)) {
          failures.add(
            '${row['id']}: set ${expectedSkus.join('+')} -> '
            '${operatorRanked.take(8).join(',')}',
          );
        }
        continue;
      }

      clearRows++;
      if (ranked.isNotEmpty && expectedSkus.contains(ranked.first)) {
        top1++;
      } else {
        top1Misses.add(
          '${row['id']}:${expectedSkus.join('/')}->'
          '${result.recommendations.take(3).map((candidate) => '${candidate.product.sku}:${candidate.confidence.toStringAsFixed(3)}:${candidate.reasons.join('+')}:${candidate.objections.join('+')}').join(',')}; '
          'operator=${operatorRanked.take(3).join(',')}; '
          'conflicts=${result.categoryConflicts.take(3).map((item) => item.product.sku).join(',')}; '
          'probe=${_identitySummary(result.probeIdentity)}',
        );
      }
      final goldNormalTop3 = operatorRanked.take(3).any(expectedSkus.contains);
      final goldCatalogConflict = result.categoryConflicts
          .any((candidate) => expectedSkus.contains(candidate.product.sku));
      if (goldNormalTop3 || goldCatalogConflict) top3++;
      final goldAdmitted = admitted.any(expectedSkus.contains);
      final goldInTop3 = goldNormalTop3 || goldCatalogConflict;
      if (!goldAdmitted || !goldInTop3) {
        final gold = expectedSkus
            .map((sku) => bySku[sku])
            .whereType<Product>()
            .map(resolver.resolveCatalogProduct)
            .map(_identitySummary)
            .join(' | ');
        final top = result.recommendations
            .take(3)
            .map((candidate) =>
                '${candidate.product.sku}:${candidate.confidence.toStringAsFixed(2)}:'
                '${candidate.reasons.join('+')}:'
                '${candidate.objections.join('+')}')
            .join(' | ');
        final goldCandidates = result.operatorChoices
            .where((candidate) => expectedSkus.contains(candidate.product.sku))
            .map((candidate) =>
                '${candidate.product.sku}:${candidate.confidence.toStringAsFixed(2)}:'
                '${candidate.reasons.join('+')}:'
                '${candidate.objections.join('+')}')
            .join(' | ');
        final goldConflicts = result.categoryConflicts
            .where((candidate) => expectedSkus.contains(candidate.product.sku))
            .map((candidate) =>
                '${candidate.product.sku}:${candidate.confidence.toStringAsFixed(2)}:'
                '${candidate.reasons.join('+')}:'
                '${candidate.objections.join('+')}')
            .join(' | ');
        failures.add(
          '${row['id']}: ${goldAdmitted ? 'gold fuera de top-3' : 'gold ausente'} '
          '${expectedSkus.join('/')} -> '
          '${ranked.take(3).join(',')} '
          '[probe ${_identitySummary(result.probeIdentity)}; gold $gold; '
          'top $top; gold-candidate $goldCandidates; '
          'gold-conflict $goldConflicts]',
        );
      }
    }

    // Kept in the failure message so a regression gives one compact, useful
    // report instead of 48 independent assertion cascades.
    // Five rows are intentionally text-insoluble in this no-image/no-alias
    // replay: two same-listing variants and three legacy off-category/generic
    // catalog conflicts. They must remain admitted/top-3 or abstained; an
    // arbitrary text-only top-1 would be less safe than this explicit ceiling.
    final minimumDeterministicTop1 = clearRows - 5;
    final summary = 'top1=$top1/$clearRows top3=$top3/$clearRows '
        'ambiguos=$ambiguousCovered/3 no_existe=$noExistsCorrect/2\n'
        'top1-misses=${top1Misses.join(' | ')}';
    expect(rows, hasLength(48));
    expect(products, hasLength(1555));
    expect(noExistsCorrect, 2, reason: '$summary\n${failures.join('\n')}');
    expect(ambiguousCovered, 3, reason: '$summary\n${failures.join('\n')}');
    expect(top3, clearRows, reason: '$summary\n${failures.join('\n')}');
    // This deterministic replay disables vision and aliases, so it measures
    // admission first and refuses to pretend image/listing-provenance ties are
    // text-solvable. Runtime closure below owns those evidence-bearing rows.
    expect(
      top1,
      greaterThanOrEqualTo(minimumDeterministicTop1),
      reason: '$summary\n${failures.join('\n')}',
    );
  });

  test('observed categories keep every gold in an explicit safe scope',
      () async {
    final audit = _readJson(
      'test/fixtures/ocr/aliexpress_identity_audit_2026_08_11.json',
    );
    final catalog = _readJson(
      'test/fixtures/ocr/catalog_identity_regression_fixture_2026_08_12.json',
    );
    final rows = (audit['rows'] as List).cast<Map<String, dynamic>>();
    final products = (catalog['products'] as List)
        .cast<Map<String, dynamic>>()
        .map(Product.fromJson)
        .toList(growable: false);
    final categories = _readCategories();
    final knownBrands = products
        .map((product) => product.brand?.trim())
        .whereType<String>()
        .where((brand) => brand.isNotEmpty)
        .toSet();
    final resolver = CanonicalProductIdentityResolver(
      categories: categories,
      knownBrands: knownBrands,
    );
    final matcher = ProductDuplicateMatcherService(
      inventoryService: _FakeInventoryService(),
      categories: categories,
      knownBrands: knownBrands,
      enableVisualReading: false,
      enableMatchAdjudication: false,
      requireAIPrimaryInvestigation: false,
      persistComputedImageFingerprints: false,
    );
    final categoriesByLeaf = <String, List<Category>>{};
    for (final category in categories) {
      categoriesByLeaf
          .putIfAbsent(
            ProductIdentityExtractor.normalize(category.name),
            () => <Category>[],
          )
          .add(category);
    }

    var knownRowsRecalled = 0;
    var ambiguousSetsComplete = 0;
    var noExistsAbstained = 0;
    final failures = <String>[];

    for (final row in rows) {
      final expected = row['expected'] as Map<String, dynamic>;
      final observed = row['observed'] as Map<String, dynamic>;
      final expectedSkus = <String>{
        ...((expected['catalog_skus'] as List?) ?? const <dynamic>[])
            .map((value) => value.toString()),
        ...((expected['candidate_catalog_skus'] as List?) ?? const <dynamic>[])
            .map((value) => value.toString()),
      };
      final observedCategoryName = observed['category_name'] as String?;
      final categoryMatches = observedCategoryName == null
          ? const <Category>[]
          : categoriesByLeaf[
                  ProductIdentityExtractor.normalize(observedCategoryName)] ??
              const <Category>[];
      final observedCategory =
          categoryMatches.length == 1 ? categoryMatches.single : null;
      final result = await matcher.resolveCandidates(
        probe: ProductDuplicateProbe(
          name: observed['cleaned_name'] as String,
          sourceTitle: row['source_title'] as String,
          selectedVariant: row['selected_variant'] as String?,
          categoryId: observedCategory?.id,
          categoryName: observedCategoryName,
          brandName: observed['brand_name'] as String?,
          supplierListingId: row['listing_id'] as String?,
          cost: (row['unit_cost'] as num?)?.toDouble(),
        ),
        products: products,
      );
      final scopedSkus = <String>{
        for (final candidate in result.recommendations) candidate.product.sku,
        for (final candidate in result.operatorChoices) candidate.product.sku,
        for (final candidate in result.categoryConflicts) candidate.product.sku,
      };

      final outcome = expected['outcome'] as String;
      if (outcome == 'no_exists') {
        if (result.kind == ProductDuplicateDecisionKind.abstained &&
            result.recommendations.isEmpty) {
          noExistsAbstained++;
        } else {
          failures.add('${row['id']}: no existente no se abstuvo');
        }
        continue;
      }
      if (outcome == 'ambiguous') {
        if (scopedSkus.containsAll(expectedSkus)) {
          ambiguousSetsComplete++;
        } else {
          failures.add(
            '${row['id']}: ambiguo perdió '
            '${expectedSkus.difference(scopedSkus).join(',')}',
          );
        }
        continue;
      }
      if (scopedSkus.containsAll(expectedSkus)) {
        knownRowsRecalled++;
      } else {
        failures.add(
          '${row['id']}: perdió ${expectedSkus.difference(scopedSkus).join(',')}',
        );
      }

      final probeCategory = result.probeIdentity.category;
      for (final candidate in result.operatorChoices) {
        final candidateCategory =
            resolver.resolveCatalogProduct(candidate.product).category;
        if (probeCategory != null &&
            candidateCategory != null &&
            !probeCategory.scopes(candidateCategory)) {
          failures.add(
            '${row['id']}: ${candidate.product.sku} se mezcló desde otra categoría',
          );
        }
      }
    }

    final summary = 'recall=$knownRowsRecalled/43 '
        'ambiguos=$ambiguousSetsComplete/3 '
        'no_existe_abstiene=$noExistsAbstained/2';
    expect(knownRowsRecalled, 43, reason: '$summary\n${failures.join('\n')}');
    expect(
      ambiguousSetsComplete,
      3,
      reason: '$summary\n${failures.join('\n')}',
    );
    expect(
      noExistsAbstained,
      2,
      reason: '$summary\n${failures.join('\n')}',
    );
    expect(failures, isEmpty, reason: '$summary\n${failures.join('\n')}');
  });

  test('catalog regression fixture contains no private production fields', () {
    final catalog = _readJson(
      'test/fixtures/ocr/catalog_identity_regression_fixture_2026_08_12.json',
    );
    expect(catalog['source'], 'sanitized_product_identity_regression_fixture');
    expect(
      catalog['privacy'],
      <String, dynamic>{
        'synthetic_record_ids': true,
        'synthetic_tenant_id': true,
        'monetary_values_zeroed': true,
        'supplier_fields_omitted': true,
        'image_fields_omitted': true,
      },
    );
    final products = (catalog['products'] as List).cast<Map<String, dynamic>>();
    expect(products, hasLength(1555));
    const forbiddenKeys = <String>{
      'supplier_id',
      'supplier_name',
      'supplier_code',
      'image_url',
    };
    for (final product in products) {
      expect(product['id'], startsWith('fixture-product-'));
      expect(product['tenant_id'], 'fixture-tenant');
      expect(product['price'], 0);
      expect(product['cost'], 0);
      expect(product.keys.toSet().intersection(forbiddenKeys), isEmpty);
    }
  });
}

Category? _effectiveCategory({
  required List<Category> categories,
  required ProductCategoryResolver resolver,
  required String name,
  required String sourceTitle,
  required String? selectedVariant,
  required String? brandName,
  required String? observedCategoryName,
  required Iterable<String> knownBrands,
}) {
  final selected = selectedVariant?.trim();
  final profile = ProductIdentityExtractor.extract(
    ProductIdentityInput(
      name: selected == null || selected.isEmpty ? name : '$name ~ $selected',
      description: sourceTitle,
      sourceTitle: sourceTitle,
      brandHint: brandName,
      knownBrands: knownBrands,
    ),
  );
  final objectCategory = resolver.resolve(profile).category;
  if (objectCategory != null) return objectCategory;
  return _uniqueLeaf(categories, observedCategoryName);
}

String _identitySummary(CanonicalProductIdentity identity) {
  final profile = identity.profile;
  return 'family=${identity.resolvedFamilyId ?? '-'} '
      'text=${profile.familyId ?? '-'} '
      'category=${identity.categoryFamilyHypotheses.join('/')} '
      'brand=${profile.assertedBrand ?? '-'} '
      'models=${profile.primaryModelCodes.join('/')} '
      'specs=${profile.specs.entries.map((entry) => '${entry.key.name}:${entry.value}').join(',')}';
}

Map<String, dynamic> _readJson(String path) {
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

List<Category> _readCategories() {
  final snapshot = _readJson(
    'test/fixtures/ocr/category_tree_regression_fixture_2026_08_12.json',
  );
  return (snapshot['categories'] as List)
      .cast<Map<String, dynamic>>()
      .map(Category.fromJson)
      .toList(growable: false);
}

Category? _uniqueLeaf(List<Category> categories, String? name) {
  if (name == null || name.trim().isEmpty) return null;
  final normalized = ProductIdentityExtractor.normalize(name);
  final parentIds = categories
      .map((category) => category.parentId)
      .whereType<String>()
      .toSet();
  final matches = categories
      .where(
        (category) =>
            !parentIds.contains(category.id) &&
            ProductIdentityExtractor.normalize(category.name) == normalized,
      )
      .toList(growable: false);
  return matches.length == 1 ? matches.single : null;
}

class _FakeInventoryService implements inv_service.InventoryService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
