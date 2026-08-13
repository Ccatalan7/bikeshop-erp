import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart'
    as inv_service;
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_matcher_service.dart';

const _tenantId = 'tenant-test';
const _adapterCategoryId = '47b4e4e2-df85-481e-b4a8-f362c4912630';
const _legacyTijaCategoryId = '9a055a2e-25cc-46a3-b30a-7311936914e6';
const _legacySouvenirCategoryId = 'ec840c98-11a5-454e-8083-494a1e91b613';

void main() {
  late List<Product> sanitizedCatalog;

  setUpAll(() {
    final snapshot = jsonDecode(
      File(
        'test/fixtures/ocr/catalog_identity_regression_fixture_2026_08_12.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
    sanitizedCatalog = (snapshot['products'] as List)
        .cast<Map<String, dynamic>>()
        .map(Product.fromJson)
        .map((product) => product.copyWith(tenantId: _tenantId))
        .toList(growable: false);
  });

  test('2024-12-17: AE0274 gana en catálogo completo y no aparece un sillín',
      () async {
    final correctedCatalog = sanitizedCatalog.map((product) {
      if (product.sku != 'AE0266' && product.sku != 'AE0274') return product;
      return product.copyWith(
        categoryId: _adapterCategoryId,
        categoryName: 'Adaptadores de tija',
      );
    }).toList(growable: false);
    final result = await _matcher().resolveCandidates(
      probe: _liveProbe,
      products: correctedCatalog,
    );

    expect(result.probeIdentity.resolvedFamilyId, 'seatpost_shim');
    expect(result.probeIdentity.category?.label,
        'accesorios / asientos / adaptadores de tija');
    expect(result.recommendations, isNotEmpty);
    expect(result.recommendations.first.product.sku, 'AE0274');
    expect(
      result.recommendations.map((candidate) => candidate.product.sku),
      isNot(contains('AE0266')),
      reason: '28.6↔27.2 es otra variante física',
    );
    expect(
      <String>{
        for (final candidate in result.operatorChoices)
          candidate.product.categoryName ?? '',
      },
      everyElement('Adaptadores de tija'),
      reason: 'el overlay no puede volver a ofrecer sillines',
    );
    expect(result.categoryConflicts, isEmpty);
  });

  test('el catálogo histórico mal archivado aísla AE0274 como conflicto',
      () async {
    final historicalCatalog = sanitizedCatalog.map((product) {
      if (product.sku == 'AE0266') {
        return product.copyWith(
          categoryId: _legacyTijaCategoryId,
          categoryName: 'Tija',
        );
      }
      if (product.sku == 'AE0274') {
        return product.copyWith(
          categoryId: _legacySouvenirCategoryId,
          categoryName: 'Souvenirs',
        );
      }
      return product;
    }).toList(growable: false);
    final result = await _matcher().resolveCandidates(
      probe: _liveProbe,
      products: historicalCatalog,
    );

    expect(result.recommendations, isEmpty);
    expect(result.operatorChoices, isEmpty);
    expect(
      result.categoryConflicts.map((candidate) => candidate.product.sku),
      contains('AE0274'),
      reason: 'un gold mal archivado se muestra aparte; no se reemplaza por '
          'un asiento de la categoría seleccionada',
    );
  });
}

ProductDuplicateMatcherService _matcher() => ProductDuplicateMatcherService(
      inventoryService: _FakeInventoryService(),
      categories: _categories,
      knownBrands: const <String>['MUQZI'],
      enableVisualReading: false,
      enableMatchAdjudication: false,
      requireAIPrimaryInvestigation: false,
      persistComputedImageFingerprints: false,
    );

const _liveProbe = ProductDuplicateProbe(
  name: 'Adaptador tija MUQZI 27.2-30.0 100mm',
  sourceTitle: 'MUQZI-Cuña de sillín de 100mm de largo, adaptador de tubo de '
      'poste de asiento, 22,2, 25,4, 27,2, 31,8, 33,9, 28,6, 30,4 a 30,9, '
      '30, 31,6, 31,8, 33,9, 34,9, 36 (27.2-30.0)',
  categoryId: _adapterCategoryId,
  categoryName: 'Accesorios / Asientos / Adaptadores de tija',
  brandName: 'MUQZI',
  supplierName: 'AliExpress',
  supplierListingId: '1005006641856329',
  cost: 3031,
);

final _categories = <Category>[
  Category(
    id: '164e46a9-3bfc-47d9-85ff-e911d96adacd',
    tenantId: _tenantId,
    name: 'Accesorios',
    fullPath: 'Accesorios',
  ),
  Category(
    id: '7f348bb9-047f-481f-a90b-9b07bebbbd58',
    tenantId: _tenantId,
    name: 'Asientos',
    fullPath: 'Accesorios / Asientos',
    parentId: '164e46a9-3bfc-47d9-85ff-e911d96adacd',
    level: 1,
  ),
  Category(
    id: '8cc6a550-6784-4fb3-8392-b7ac9c68b8ad',
    tenantId: _tenantId,
    name: 'Asiento',
    fullPath: 'Accesorios / Asientos / Asiento',
    parentId: '7f348bb9-047f-481f-a90b-9b07bebbbd58',
    level: 2,
  ),
  Category(
    id: '9a055a2e-25cc-46a3-b30a-7311936914e6',
    tenantId: _tenantId,
    name: 'Tija',
    fullPath: 'Accesorios / Asientos / Tija',
    parentId: '7f348bb9-047f-481f-a90b-9b07bebbbd58',
    level: 2,
  ),
  Category(
    id: _adapterCategoryId,
    tenantId: _tenantId,
    name: 'Adaptadores de tija',
    fullPath: 'Accesorios / Asientos / Adaptadores de tija',
    parentId: '7f348bb9-047f-481f-a90b-9b07bebbbd58',
    level: 2,
  ),
  Category(
    id: 'ec840c98-11a5-454e-8083-494a1e91b613',
    tenantId: _tenantId,
    name: 'Souvenirs',
    fullPath: 'Accesorios / Souvenirs',
    parentId: '164e46a9-3bfc-47d9-85ff-e911d96adacd',
    level: 1,
  ),
];

class _FakeInventoryService implements inv_service.InventoryService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
