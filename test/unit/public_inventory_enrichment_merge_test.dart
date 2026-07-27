import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';

void main() {
  test('parallel product enrichment merges by id and preserves base order', () {
    final merged = mergePublicProductEnrichmentRows(
      baseRows: const [
        {
          'id': 'product-b',
          'name': 'Base B',
          'brand': 'legacy',
          'website_name': 'Base website B',
          'tax_rate': null,
        },
        {
          'id': 'product-a',
          'name': 'Base A',
        },
      ],
      enrichmentLayers: const [
        [
          {'id': 'product-a', 'name': 'Base A', 'tax_rate': 0.19},
          {
            'id': 'product-b',
            'name': 'Base B',
            'brand': 'legacy',
            'website_name': 'Base website B',
            'tax_rate': 0,
          },
        ],
        [
          {
            'id': 'product-b',
            'name': 'Base B',
            'brand': 'legacy',
            'website_name': 'Public B',
            'tax_rate': null,
            'is_set': true,
          },
          {'id': 'unrelated', 'is_set': true},
        ],
        [
          {
            'id': 'product-b',
            'name': 'Base B',
            'brand': 'Canonical B',
            'website_name': 'Base website B',
            'tax_rate': null,
          },
        ],
      ],
    );

    expect(merged.map((row) => row['id']), ['product-b', 'product-a']);
    expect(
      merged.first,
      containsPair('brand', 'Canonical B'),
    );
    expect(merged.first, containsPair('tax_rate', 0));
    expect(merged.first, containsPair('is_set', true));
    expect(merged.first, containsPair('website_name', 'Public B'));
    expect(merged.last, containsPair('tax_rate', 0.19));
    expect(merged.last, isNot(contains('is_set')));
  });

  test('rows without ids remain in their original position', () {
    final merged = mergePublicProductEnrichmentRows(
      baseRows: const [
        {'name': 'Legacy row'},
        {'id': 'product-a', 'name': 'Product A'},
      ],
      enrichmentLayers: const [
        [
          {'id': 'product-a', 'brand': 'Brand A'},
        ],
      ],
    );

    expect(merged.first, {'name': 'Legacy row'});
    expect(merged.last, containsPair('brand', 'Brand A'));
  });
}
