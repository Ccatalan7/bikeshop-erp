import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_erp/modules/website/services/website_destination_audit_service.dart';

void main() {
  test('category product counts distinguish direct products from descendants',
      () {
    final counts = WebsiteCategoryProductCounts.fromRows(
      categories: const [
        {
          'id': 'transmission',
          'parent_id': null,
          'is_active': true,
        },
        {
          'id': 'chains',
          'parent_id': 'transmission',
          'is_active': true,
        },
        {
          'id': 'chain-guides',
          'parent_id': 'chains',
          'is_active': true,
        },
        {
          'id': 'retired-guides',
          'parent_id': 'chains',
          'is_active': false,
        },
      ],
      markedProducts: const [
        {'category_id': 'transmission'},
        {'category_id': 'chains'},
        {'category_id': 'chains'},
        {'category_id': 'chain-guides'},
        {'category_id': 'chain-guides'},
        {'category_id': 'chain-guides'},
        {'category_id': 'retired-guides'},
      ],
    );

    expect(
      counts.countFor(
        'chains',
        WebsiteCatalogCategoryScope.direct,
      ),
      2,
    );
    expect(
      counts.countFor(
        'chains',
        WebsiteCatalogCategoryScope.subtree,
      ),
      5,
    );
    expect(
      counts.countFor(
        'transmission',
        WebsiteCatalogCategoryScope.subtree,
      ),
      6,
    );
    expect(
      counts.countFor(
        'retired-guides',
        WebsiteCatalogCategoryScope.direct,
      ),
      0,
    );
  });
}
