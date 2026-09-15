import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart'
    as inv_service;
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_matcher_service.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_category_resolver.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_extractor.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_profile.dart';

const _terminalCategoryId = 'd965fdf6-f1e5-4664-92ba-487ad6622af9';
const _terminalCategoryPath =
    'Componentes / Fundas y piolas / Terminales y topes';

void main() {
  test('2025-12-02: cable-terminal row finds AE0340 without transmission noise',
      () async {
    final catalog = _readProducts();
    final categories = _readCategories();
    final knownBrands = catalog
        .map((product) => product.brand?.trim())
        .whereType<String>()
        .where((brand) => brand.isNotEmpty)
        .toSet();
    final categoryResolver = ProductCategoryResolver(categories: categories);
    final matcher = ProductDuplicateMatcherService(
      inventoryService: _FakeInventoryService(),
      categories: categories,
      knownBrands: knownBrands,
      enableVisualReading: false,
      enableMatchAdjudication: false,
      requireAIPrimaryInvestigation: false,
      persistComputedImageFingerprints: false,
    );

    final terminalCategory = categoryResolver.resolve(
      ProductIdentityExtractor.extract(
        ProductIdentityInput(
          name: 'Desviador trasero genérico ~ 500PCS',
          sourceTitle: _sourceTitle,
          variantText: '500PCS',
          knownBrands: knownBrands,
        ),
      ),
    );
    final result = await matcher.resolveCandidates(
      probe: const ProductDuplicateProbe(
        name: 'Desviador trasero genérico',
        sourceTitle: _sourceTitle,
        selectedVariant: '500PCS',
        categoryId: _terminalCategoryId,
        categoryName: _terminalCategoryPath,
        supplierName: 'AliExpress',
      ),
      products: catalog,
    );

    expect(
      catalog.where((product) => product.sku == 'AE0362'),
      everyElement(isNot(predicate<Product>((product) => product.isActive))),
      reason: 'el duplicado desactivado no puede volver al universo activo',
    );
    expect(terminalCategory.category?.id, _terminalCategoryId);
    expect(terminalCategory.category?.fullPath, _terminalCategoryPath);
    expect(result.probeIdentity.resolvedFamilyId, 'cable_end_cap');
    expect(
      result.probeIdentity.profile.specs[PartSpecKind.cableEndKind],
      'housing_ferrule',
    );
    expect(result.probeIdentity.category?.id, _terminalCategoryId);
    // Temporary trace retained in a failing assertion's reason while this
    // production-derived regression is being established.
    final rankedTrace = result.operatorChoices
        .take(10)
        .map(
          (candidate) =>
              '${candidate.product.sku}:${candidate.confidence.toStringAsFixed(2)}:'
              '${candidate.reasons.join('+')}:${candidate.objections.join('+')}',
        )
        .join(' | ');
    expect(result.recommendations, isNotEmpty);
    expect(
      result.recommendations.first.product.sku,
      'AE0340',
      reason: rankedTrace,
    );
    expect(
      result.operatorChoices.take(3).map((candidate) => candidate.product.sku),
      contains('AE0340'),
    );

    final normal = [
      ...result.recommendations,
      ...result.operatorChoices,
    ];
    expect(
      normal.where(
        (candidate) =>
            candidate.product.categoryName != null &&
            candidate.product.categoryName != 'Terminales y topes',
      ),
      isEmpty,
      reason: 'una ficha sin categoría puede quedar revisable, pero ninguna '
          'ficha archivada en otra categoría entra a la lista normal',
    );
    expect(
      normal.map((candidate) => candidate.product.sku),
      isNot(contains('AE0362')),
      reason: 'el duplicado inactivo no se debe mostrar',
    );
    expect(
      normal.where(
        (candidate) {
          final text = '${candidate.product.name} '
                  '${candidate.product.categoryName ?? ''}'
              .toLowerCase();
          return text.contains('desviador') ||
              text.contains('shifter') ||
              text.contains('palanca de cambio');
        },
      ),
      isEmpty,
      reason: 'un terminal de funda no admite productos de transmisión',
    );
  });
}

const _sourceTitle =
    'Marchas de freno para bicicleta de montaña y carretera, tapas de '
    'extremos de Cable exterior, Crimps, desviador de cambio, carcasa de '
    'punta de Cable, 100-500 piezas';

List<Product> _readProducts() {
  final snapshot = jsonDecode(
    File(
      'test/fixtures/ocr/catalog_identity_regression_fixture_2026_08_12.json',
    ).readAsStringSync(),
  ) as Map<String, dynamic>;
  return (snapshot['products'] as List)
      .cast<Map<String, dynamic>>()
      .map(Product.fromJson)
      .where((product) => product.isActive && !product.isService)
      .toList(growable: false);
}

List<Category> _readCategories() {
  final snapshot = jsonDecode(
    File(
      'test/fixtures/ocr/category_tree_regression_fixture_2026_08_12.json',
    ).readAsStringSync(),
  ) as Map<String, dynamic>;
  return (snapshot['categories'] as List)
      .cast<Map<String, dynamic>>()
      .map(Category.fromJson)
      .toList(growable: false);
}

class _FakeInventoryService implements inv_service.InventoryService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
