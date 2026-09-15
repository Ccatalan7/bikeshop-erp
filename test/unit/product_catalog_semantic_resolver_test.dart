import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/brand_models.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/services/product_catalog_semantic_resolver.dart';

void main() {
  group('ProductCatalogSemanticResolver', () {
    test('maps tee, potencia and stem to the canonical Tee full path', () {
      final resolver = _resolver();

      for (final title in const [
        'Tee WAKE 31.8mm negra',
        'Potencia WAKE 31.8mm morada',
        'MTB stem WAKE 31.8mm blue',
        'WAKE-vástago ligero de aleación para bicicleta de montaña 31,8mm',
      ]) {
        final result = resolver.resolve(
          ProductCatalogSemanticInput(rowId: title, rawTitle: title),
        );

        expect(result.family, ProductCatalogSemanticResolver.stemFamily);
        expect(
          result.category?.fullPath,
          'Componentes / Dirección / Tee',
        );
        expect(result.category?.id, 'category-tee');
        expect(result.brand?.name, 'Wake');
        expect(result.requiresReview, isFalse);
      }
    });

    test('normalizes stem aliases to the same shop-facing name', () {
      expect(
        ProductCatalogSemanticResolver.canonicalizeDisplayName(
          name: 'Potencia WAKE 31.8mm morada',
          family: ProductCatalogSemanticResolver.stemFamily,
        ),
        'Tee WAKE 31.8mm morada',
      );
      expect(
        ProductCatalogSemanticResolver.canonicalizeDisplayName(
          name: 'Stem WAKE 31.8mm azul',
          family: ProductCatalogSemanticResolver.stemFamily,
        ),
        'Tee WAKE 31.8mm azul',
      );
      expect(
        ProductCatalogSemanticResolver.canonicalizeDisplayName(
          name: 'Rotor Shimano RT56',
          family: ProductCatalogSemanticResolver.cranksetFamily,
        ),
        'Rotor Shimano RT56',
      );
    });

    test('normalizes the translated stem without broad false hits', () {
      final resolver = _resolver();
      final stem = resolver.resolve(const ProductCatalogSemanticInput(
        rowId: 'wake-purple',
        rawTitle:
            'WAKE-vástago ligero de aleación para bicicleta de montaña 31,8mm Purple',
      ));

      expect(stem.family, ProductCatalogSemanticResolver.stemFamily);
      expect(
        ProductCatalogSemanticResolver.canonicalizeDisplayName(
          name: 'Potencia WAKE 31.8mm morada',
          family: stem.family,
        ),
        'Tee WAKE 31.8mm morada',
      );

      for (final title in const [
        'Vástago de asiento para bicicleta 27.2 mm',
        'Vástago de horquilla para bicicleta 28.6 mm',
      ]) {
        final result = resolver.resolve(
          ProductCatalogSemanticInput(rowId: title, rawTitle: title),
        );
        expect(result.family, ProductCatalogSemanticResolver.unknownFamily);
      }
    });

    test('same listing variants share semantics and retain their variant', () {
      final results = _resolver().resolveAll(const [
        ProductCatalogSemanticInput(
          rowId: 'black',
          supplierId: 'ali',
          listingId: '100500-stem',
          variantKey: 'black-45mm',
          variantLabel: 'Negro / 45 mm',
          rawTitle: 'Tee WAKE 31.8mm negra',
          categoryHint: 'Tee',
          brandHint: 'Wake',
        ),
        ProductCatalogSemanticInput(
          rowId: 'purple',
          supplierId: 'ali',
          listingId: '100500-stem',
          variantKey: 'purple-45mm',
          variantLabel: 'Morado / 45 mm',
          rawTitle: 'Potencia WAKE 31.8mm morada',
          categoryHint: 'Potencias',
          brandHint: 'Wake',
        ),
      ]);

      expect(results, hasLength(2));
      expect(results.map((row) => row.family).toSet(), {'stem'});
      expect(
        results.map((row) => row.category?.id).toSet(),
        {'category-tee'},
      );
      expect(results.map((row) => row.brand?.id).toSet(), {'brand-wake'});
      expect(results[0].variantKey, 'black-45mm');
      expect(results[0].variantLabel, 'Negro / 45 mm');
      expect(results[1].variantKey, 'purple-45mm');
      expect(results[1].variantLabel, 'Morado / 45 mm');
      expect(
        results.first.evidence.any(
          (item) =>
              item.kind == ProductCatalogSemanticEvidenceKind.listingConsensus,
        ),
        isTrue,
      );
    });

    test('mixed listing families stay row-specific and require review', () {
      final resolver = _resolver(
        additionalBrands: [_brand('brand-ixf', 'IXF')],
      );
      final results = resolver.resolveAll(const [
        ProductCatalogSemanticInput(
          rowId: 'stem',
          supplierId: 'ali',
          listingId: 'mixed-listing',
          variantKey: 'wake-purple',
          variantLabel: 'WAKE morada',
          rawTitle: 'Tee WAKE 31.8mm morada',
        ),
        ProductCatalogSemanticInput(
          rowId: 'crankset',
          supplierId: 'ali',
          listingId: 'mixed-listing',
          variantKey: 'ixf-36t',
          variantLabel: 'IXF 36T',
          rawTitle: 'Volante IXF 104BCD 170mm 36T compatible con Shimano/SRAM',
        ),
      ]);

      expect(results[0].family, ProductCatalogSemanticResolver.stemFamily);
      expect(results[0].category?.id, 'category-tee');
      expect(results[0].brand?.id, 'brand-wake');
      expect(results[0].variantKey, 'wake-purple');
      expect(results[1].family, ProductCatalogSemanticResolver.cranksetFamily);
      expect(results[1].category?.id, 'category-crankset');
      expect(results[1].brand?.id, 'brand-ixf');
      expect(results[1].variantKey, 'ixf-36t');
      expect(results.every((row) => row.requiresReview), isTrue);
      expect(
        results.every(
          (row) => row.evidence.any(
            (item) =>
                item.kind == ProductCatalogSemanticEvidenceKind.listingConflict,
          ),
        ),
        isTrue,
      );
      expect(
        results.every(
          (row) => row.evidence.every(
            (item) =>
                item.kind !=
                ProductCatalogSemanticEvidenceKind.listingConsensus,
          ),
        ),
        isTrue,
      );
    });

    test('Presta/FV to Schrader/AV adapters resolve to Adaptadores', () {
      final resolver = _resolver();

      for (final title in const [
        'Adaptador Presta a Schrader',
        'Adaptador FV a AV de latón',
        'Adaptador de válvula convertidor F/V a A/V 10 pcs',
        'Adapter Schrader to Presta',
        'Adaptador de válvula Presta a Schrader',
      ]) {
        final result = resolver.resolve(
          ProductCatalogSemanticInput(
            rowId: title,
            rawTitle: title,
            categoryHint: 'Válvula Tubeless',
          ),
        );

        expect(
          result.family,
          ProductCatalogSemanticResolver.valveAdapterFamily,
        );
        expect(result.category?.id, 'category-adapters');
        expect(result.category?.fullPath, 'Accesorios / Adaptadores');
        expect(result.category?.name, isNot('Válvula Tubeless'));
        expect(result.requiresReview, isFalse);
        expect(
          result.evidence.any(
            (item) =>
                item.kind ==
                ProductCatalogSemanticEvidenceKind.rejectedCategoryHint,
          ),
          isTrue,
        );
      }
    });

    test('never infers tubeless valve without an explicit tubeless token', () {
      final resolver = _resolver();
      final ordinaryValve = resolver.resolve(
        const ProductCatalogSemanticInput(
          rowId: 'valve',
          rawTitle: 'Válvula Presta 60mm',
          categoryHint: 'Válvula Tubeless',
        ),
      );
      final tubelessValve = resolver.resolve(
        const ProductCatalogSemanticInput(
          rowId: 'tubeless',
          rawTitle: 'Válvula tubeless Presta 60mm',
        ),
      );

      expect(
          ordinaryValve.family, ProductCatalogSemanticResolver.unknownFamily);
      expect(ordinaryValve.category, isNull);
      expect(ordinaryValve.requiresReview, isTrue);
      expect(
        tubelessValve.family,
        ProductCatalogSemanticResolver.tubelessValveFamily,
      );
      expect(tubelessValve.category?.id, 'category-tubeless-valve');
    });

    test('explicit IXF rejects compatible Shimano/SRAM and stays unresolved',
        () {
      final result = _resolver().resolve(
        const ProductCatalogSemanticInput(
          rowId: 'ixf',
          rawTitle: 'Volante IXF 104BCD 170mm 36T compatible con Shimano/SRAM',
          brandHint: 'Shimano',
          categoryHint: 'Volantes',
          hintConfidence: 0.94,
        ),
      );

      expect(result.family, ProductCatalogSemanticResolver.cranksetFamily);
      expect(result.category?.id, 'category-crankset');
      expect(result.brand, isNull);
      expect(result.requiresReview, isTrue);
      expect(result.reviewReason, contains('IXF'));
      expect(result.reviewReason, isNot(contains('Shimano')));
      expect(
        result.evidence.any(
          (item) =>
              item.kind == ProductCatalogSemanticEvidenceKind.explicitBrand &&
              item.detail == 'IXF',
        ),
        isTrue,
      );
      expect(
        result.evidence.any(
          (item) =>
              item.kind ==
                  ProductCatalogSemanticEvidenceKind.rejectedBrandHint &&
              item.detail.contains('Shimano') &&
              item.detail.contains('IXF'),
        ),
        isTrue,
      );
    });

    test('selects IXF when it exists in the real brand catalog', () {
      final resolver = _resolver(
        additionalBrands: [_brand('brand-ixf', 'IXF')],
      );

      final result = resolver.resolve(
        const ProductCatalogSemanticInput(
          rowId: 'ixf',
          rawTitle: 'Volante IXF 104BCD 170mm 36T compatible con Shimano/SRAM',
          brandHint: 'Shimano',
        ),
      );

      expect(result.brand?.id, 'brand-ixf');
      expect(result.brand?.name, 'IXF');
      expect(result.requiresReview, isFalse);
    });

    test('ENLEE explícito vence al origen CHINA de la opción', () {
      final resolver = _resolver(
        additionalBrands: [
          _brand('brand-enlee', 'ENLEE'),
          _brand('brand-china', 'China'),
        ],
      );

      final result = resolver.resolve(
        const ProductCatalogSemanticInput(
          rowId: 'enlee-cr2',
          rawTitle: 'ENLEE Pedal CNC aleación de aluminio (CR-2 black, CHINA)',
          brandHint: 'China',
        ),
      );

      expect(result.brand?.id, 'brand-enlee');
      expect(result.brand?.name, 'ENLEE');
      expect(
        result.evidence.any(
          (item) =>
              item.kind ==
                  ProductCatalogSemanticEvidenceKind.rejectedBrandHint &&
              item.detail.contains('China') &&
              item.detail.contains('ENLEE'),
        ),
        isTrue,
      );
    });

    test('CHINA nunca se acepta como fabricante explícito', () {
      final result = _resolver(
        additionalBrands: [_brand('brand-china', 'China')],
      ).resolve(
        const ProductCatalogSemanticInput(
          rowId: 'origin-only',
          rawTitle: 'Pedal CNC (black, CHINA)',
          brandHint: 'China',
        ),
      );

      expect(result.brand, isNull);
      expect(
        result.evidence.any(
          (item) =>
              item.kind == ProductCatalogSemanticEvidenceKind.explicitBrand &&
              item.detail.toLowerCase() == 'china',
        ),
        isFalse,
      );
    });

    test('maps the productive IXF platos y bielas title to crankset', () {
      final resolver = _resolver(
        additionalBrands: [_brand('brand-ixf', 'IXF')],
      );

      final result = resolver.resolve(
        const ProductCatalogSemanticInput(
          rowId: 'ixf-bielas',
          rawTitle:
              'IXF-platos y bielas para bicicleta 104BCD 170mm 36T compatible con SHIMANO/SRAM',
          brandHint: 'Shimano',
        ),
      );

      expect(result.family, ProductCatalogSemanticResolver.cranksetFamily);
      expect(result.category?.id, 'category-crankset');
      expect(
        result.category?.fullPath,
        'Componentes / Transmisión / Volantes / Volante',
      );
      expect(result.brand?.id, 'brand-ixf');
      expect(result.brand?.name, 'IXF');
      expect(result.requiresReview, isFalse);
      expect(
        result.evidence.any(
          (item) =>
              item.kind ==
                  ProductCatalogSemanticEvidenceKind.rejectedBrandHint &&
              item.detail.contains('Shimano') &&
              item.detail.contains('IXF'),
        ),
        isTrue,
      );
    });

    test('requires the canonical category id and full path, not just its name',
        () {
      final categories = _categories()
          .where((category) => category.id != 'category-tee')
          .toList();
      final resolver = ProductCatalogSemanticResolver(
        categories: categories,
        brands: [_brand('brand-wake', 'Wake')],
      );

      final result = resolver.resolve(
        const ProductCatalogSemanticInput(
          rowId: 'stem',
          rawTitle: 'Potencia WAKE 31.8mm',
          categoryHint: 'Tee',
        ),
      );

      expect(result.family, ProductCatalogSemanticResolver.stemFamily);
      expect(result.category, isNull);
      expect(result.requiresReview, isTrue);
      expect(result.reviewReason, contains('Componentes / Dirección / Tee'));
    });

    test('accepts a unique real category hint without inventing a path', () {
      final result = _resolver().resolve(
        const ProductCatalogSemanticInput(
          rowId: 'rotor',
          rawTitle: 'Rotor de freno Shimano RT56 160mm 6 pernos',
          categoryHint: 'Rotores',
          brandHint: 'Shimano',
        ),
      );

      expect(result.category?.id, 'category-rotors');
      expect(result.category?.fullPath, 'Componentes / Frenos / Rotores');
      expect(result.brand?.id, 'brand-shimano');
    });
  });
}

ProductCatalogSemanticResolver _resolver({
  List<ProductBrand> additionalBrands = const [],
}) {
  return ProductCatalogSemanticResolver(
    categories: _categories(),
    brands: [
      _brand('brand-wake', 'Wake'),
      _brand('brand-shimano', 'Shimano'),
      _brand('brand-sram', 'SRAM'),
      ...additionalBrands,
    ],
  );
}

List<Category> _categories() => [
      _category(
        'category-tee-wrong-path',
        'Tee',
        'Accesorios / Tee',
      ),
      _category(
        'category-tee',
        'Tee',
        'Componentes / Dirección / Tee',
      ),
      _category(
        'category-adapters',
        'Adaptadores',
        'Accesorios / Adaptadores',
      ),
      _category(
        'category-brake-adapters',
        'Adaptadores',
        'Componentes / Frenos / Adaptadores',
      ),
      _category(
        'category-crankset',
        'Volante',
        'Componentes / Transmisión / Volantes / Volante',
      ),
      _category(
        'category-tubeless-valve',
        'Válvula Tubeless',
        'Componentes / Ruedas / Tubeless / Válvula Tubeless',
      ),
      _category(
        'category-rotors',
        'Rotores',
        'Componentes / Frenos / Rotores',
      ),
    ];

Category _category(String id, String name, String fullPath) {
  return Category(
    id: id,
    tenantId: 'tenant',
    name: name,
    fullPath: fullPath,
  );
}

ProductBrand _brand(String id, String name) {
  return ProductBrand(
    id: id,
    tenantId: 'tenant',
    name: name,
  );
}
