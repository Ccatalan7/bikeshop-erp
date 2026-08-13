import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/brand_models.dart';
import 'package:vinabike_erp/modules/inventory/services/product_catalog_semantic_resolver.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_extractor.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_matcher.dart';

void main() {
  const applicatorTitle =
      '2/5/10pcs 30/60/100/120ML Squeeze Bottle for Sauce Plastic '
      'Squirt Container Refillable Bottle with Cap for Kitchen Glue Container';
  final squirt = ProductBrand(
    id: 'brand-squirt',
    tenantId: 'tenant-test',
    name: 'Squirt',
  );

  ProductCatalogSemanticResolver resolver() =>
      ProductCatalogSemanticResolver(categories: const [], brands: [squirt]);

  test('taxonomy phrase cannot be re-read as Squirt maker or compatibility',
      () {
    final probe = ProductIdentityExtractor.extract(
      const ProductIdentityInput(
        name: 'Botella aplicadora 120ml',
        sourceTitle: applicatorTitle,
        variantText: '10pcs of 120ML',
        brandHint: 'Squirt',
        knownBrands: <String>['Squirt'],
      ),
    );

    expect(probe.familyId, 'applicator_bottle');
    expect(probe.assertedBrand, isNull);
    expect(probe.compatibilityBrands, isNot(contains('squirt')));

    final unrelatedMaker = ProductIdentityExtractor.extract(
      const ProductIdentityInput(
        name: 'Botella aplicadora 120ml',
        brandHint: 'ZTTO',
        brandIsAsserted: true,
        knownBrands: <String>['Squirt', 'ZTTO'],
      ),
    );
    final match = const ProductIdentityMatcher().evaluate(
      probe: probe,
      candidate: unrelatedMaker,
    );
    expect(match.objections.join(' '), isNot(contains('Squirt')));
    expect(match.isRejected, isFalse);
  });

  test('semantic resolver rejects both applicator hint forms', () {
    for (final title in const <String>[
      'Botella aplicadora 120ml',
      applicatorTitle,
    ]) {
      final result = resolver().resolve(
        ProductCatalogSemanticInput(
          rowId: title,
          rawTitle: title,
          brandHint: 'Squirt',
        ),
      );

      expect(result.brand, isNull, reason: title);
      expect(
        result.evidence.any(
          (item) =>
              item.kind == ProductCatalogSemanticEvidenceKind.explicitBrand &&
              item.detail.toLowerCase() == 'squirt',
        ),
        isFalse,
        reason: title,
      );
      expect(
        result.evidence.any(
          (item) =>
              item.kind == ProductCatalogSemanticEvidenceKind.rejectedBrandHint,
        ),
        isTrue,
        reason: title,
      );
    }
  });

  test('real Squirt product remains an asserted manufacturer control', () {
    const title = 'Liquido Antipinchazos Squirt Seal Beadblock 1litro';
    final profile = ProductIdentityExtractor.extract(
      const ProductIdentityInput(
        name: title,
        sourceTitle: title,
        knownBrands: <String>['Squirt'],
      ),
    );
    final result = resolver().resolve(
      const ProductCatalogSemanticInput(
        rowId: 'squirt-seal',
        rawTitle: title,
        brandHint: 'Squirt',
      ),
    );

    expect(profile.assertedBrand, 'squirt');
    expect(profile.compatibilityBrands, isNot(contains('squirt')));
    expect(result.brand?.id, 'brand-squirt');
    expect(result.brand?.name, 'Squirt');
  });
}
