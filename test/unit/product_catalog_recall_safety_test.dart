import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/models/product_duplicate_candidate.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart'
    as inv_service;
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_matcher_service.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_catalog_identity_index.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_profile.dart';

void main() {
  group('catalog recall stays behind the family gate', () {
    test('unknown family is review-only only inside the exact active leaf',
        () async {
      final service = _matcher(categories: _categories);

      final result = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas de freno Shimano B01S',
          categoryId: 'legacy-leaf',
          categoryName: 'Componentes / Revisión legado',
        ),
        products: <Product>[
          _product(
            id: 'same-leaf-unknown',
            sku: 'SKU-UNKNOWN',
            name: 'Shimano B01S orgánico',
            brand: 'Shimano',
            model: 'B01S',
            categoryId: 'legacy-leaf',
            categoryName: 'Componentes / Revisión legado',
          ),
          _product(
            id: 'known-wrong-family',
            sku: 'SKU-SADDLE',
            name: 'Asiento Shimano B01S',
            brand: 'Shimano',
            model: 'B01S',
            categoryId: 'legacy-leaf',
            categoryName: 'Componentes / Revisión legado',
          ),
          _product(
            id: 'other-leaf-unknown',
            sku: 'SKU-OTHER',
            name: 'Shimano B01S carbono',
            brand: 'Shimano',
            model: 'B01S',
            categoryId: 'other-leaf',
            categoryName: 'Componentes / Otra revisión',
          ),
        ],
      );

      expect(result.kind, ProductDuplicateDecisionKind.abstained);
      expect(result.recommendations, isEmpty);
      expect(result.operatorChoices, hasLength(1));
      final candidate = result.operatorChoices.single;
      expect(candidate.product.id, 'same-leaf-unknown');
      expect(candidate.matchTier, ProductDuplicateMatchTier.possible);
      expect(candidate.objections.join(' '), contains('categoría exacta'));
      expect(
        result.operatorChoices.map((item) => item.product.id),
        isNot(contains('known-wrong-family')),
      );
      expect(
        result.operatorChoices.map((item) => item.product.id),
        isNot(contains('other-leaf-unknown')),
      );
    });

    test('closure diagnostic counts structure without expected product data',
        () {
      final index = ProductCatalogIdentityIndex(
        categories: _categories,
        knownBrands: const <String>['Shimano'],
      );
      index.sync(<Product>[
        _product(
          id: 'resolved',
          sku: 'SKU-RESOLVED',
          name: 'Pastillas de freno Shimano',
        ),
        _product(
          id: 'leaf-review',
          sku: 'SKU-LEAF',
          name: 'Modelo ZX orgánico',
          categoryId: 'legacy-leaf',
          categoryName: 'Componentes / Revisión legado',
        ),
        _product(
          id: 'no-category',
          sku: 'SKU-NONE',
          name: 'Modelo QZ carbono',
        ),
        _product(
          id: 'parent-only',
          sku: 'SKU-PARENT',
          name: 'Modelo PX negro',
          categoryId: 'components',
          categoryName: 'Componentes',
        ),
      ]);

      final report = index.diagnoseClosure();

      expect(report.totalRows, 4);
      expect(report.resolvedRows, 1);
      expect(report.exactLeafReviewRows, 1);
      expect(report.unreachableRows, 2);
      expect(report.isClosed, isFalse);
      expect(
        report.unreachableEntries.map((entry) => entry.product.id),
        containsAll(<String>['no-category', 'parent-only']),
      );
    });

    test('structured selected variant outranks a title-parenthesis fallback',
        () async {
      final service = _matcher();
      final products = <Product>[
        _product(
          id: 'blue',
          sku: 'SKU-BLUE',
          name: 'Pastillas de freno Shimano B01S Azul',
          brand: 'Shimano',
          model: 'B01S',
        ),
        _product(
          id: 'red',
          sku: 'SKU-RED',
          name: 'Pastillas de freno Shimano B01S Rojo',
          brand: 'Shimano',
          model: 'B01S',
        ),
      ];

      final structured = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas de freno Shimano B01S',
          sourceTitle: 'Pastillas Shimano B01S (Red)',
          selectedVariant: 'Blue',
        ),
        products: products,
      );
      expect(structured.recommendations.single.product.id, 'blue');

      final fallback = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas de freno Shimano B01S',
          sourceTitle: 'Pastillas Shimano B01S (Red)',
        ),
        products: products,
      );
      expect(fallback.recommendations.single.product.id, 'red');
    });

    test('live AliExpress shape keeps selected colour out of line evidence',
        () async {
      final service = _matcher();
      final result = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Portabotellas ZTTO aluminio',
          description: 'Portabotellas ZTTO aluminio (BLACK)',
          sourceTitle: 'Portabotellas ZTTO aluminio (BLACK)',
          rawText: 'Portabotellas ZTTO aluminio (BLACK)\n'
              'VARIANT: BLACK\n'
              'VARIANT_KEY: sku:immutable-black\n'
              'ITEM_ID: 1005000000000000\n'
              'https://www.aliexpress.com/item/1005000000000000.html',
          selectedVariant: 'BLACK',
        ),
        products: <Product>[
          _product(
            id: 'black-cage',
            sku: 'SKU-BLACK',
            name: 'Portabotellas ZTTO aluminio negro',
            brand: 'ZTTO',
          ),
        ],
      );

      final profile = result.probeIdentity.profile;
      expect(profile.lineSpecs[PartSpecKind.colorVariant], isNull);
      expect(profile.variantSpecs[PartSpecKind.colorVariant], 'negro');
      expect(profile.specs[PartSpecKind.colorVariant], 'negro');
    });

    test('live selected rear is variant evidence, not line score evidence',
        () async {
      final service = _matcher();
      final result = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Freno hidráulico Shimano MT200',
          description:
              'Freno hidráulico Shimano MT200 delantero trasero (MT200 Right Rear)',
          sourceTitle:
              'Freno hidráulico Shimano MT200 delantero trasero (MT200 Right Rear)',
          rawText: 'Freno hidráulico Shimano MT200 delantero trasero '
              '(MT200 Right Rear)\nVARIANT: MT200 Right Rear',
          selectedVariant: 'MT200 Right Rear',
        ),
        products: <Product>[
          _product(
            id: 'rear-brake',
            sku: 'SKU-REAR',
            name: 'Freno hidráulico Shimano MT200 trasero',
            brand: 'Shimano',
            model: 'MT200',
          ),
        ],
      );

      final profile = result.probeIdentity.profile;
      expect(profile.lineSpecs[PartSpecKind.position], isNull);
      expect(profile.variantSpecs[PartSpecKind.position], 'rear');
      expect(profile.specs[PartSpecKind.position], 'rear');
    });
  });
}

final List<Category> _categories = <Category>[
  Category(
    id: 'components',
    tenantId: 'tenant-test',
    name: 'Componentes',
    fullPath: 'Componentes',
  ),
  Category(
    id: 'legacy-leaf',
    tenantId: 'tenant-test',
    name: 'Revisión legado',
    fullPath: 'Componentes / Revisión legado',
    parentId: 'components',
    level: 1,
  ),
  Category(
    id: 'other-leaf',
    tenantId: 'tenant-test',
    name: 'Otra revisión',
    fullPath: 'Componentes / Otra revisión',
    parentId: 'components',
    level: 1,
  ),
];

ProductDuplicateMatcherService _matcher({
  Iterable<Category> categories = const <Category>[],
}) {
  return ProductDuplicateMatcherService(
    inventoryService: _FakeInventoryService(),
    categories: categories,
    knownBrands: const <String>['Shimano'],
    enableVisualReading: false,
    enableMatchAdjudication: false,
    requireAIPrimaryInvestigation: false,
    persistComputedImageFingerprints: false,
  );
}

Product _product({
  required String id,
  required String sku,
  required String name,
  String? brand,
  String? model,
  String? categoryId,
  String? categoryName,
}) {
  return Product(
    id: id,
    tenantId: 'tenant-test',
    sku: sku,
    name: name,
    brand: brand,
    model: model,
    categoryId: categoryId,
    categoryName: categoryName,
    price: 1000,
    cost: 500,
  );
}

class _FakeInventoryService implements inv_service.InventoryService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
