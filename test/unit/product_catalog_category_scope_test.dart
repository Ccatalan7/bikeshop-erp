import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_erp/public_store/pages/product_catalog_page.dart';

void main() {
  test('direct scope sends only the selected category to catalog consumers',
      () {
    expect(
      resolveCatalogCategoryIdsForScope(
        selectedCategoryId: 'chains',
        scope: WebsiteCatalogCategoryScope.direct,
        subtreeCategoryIds: const {'chains', 'chain-guides'},
      ),
      {'chains'},
    );
  });

  test('subtree scope preserves the selected category and descendants', () {
    expect(
      resolveCatalogCategoryIdsForScope(
        selectedCategoryId: 'chains',
        scope: WebsiteCatalogCategoryScope.subtree,
        subtreeCategoryIds: const {'chain-guides'},
      ),
      {'chains', 'chain-guides'},
    );
  });
}
