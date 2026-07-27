import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/pages/product_catalog_page.dart';

void main() {
  group('catalog pagination bounds', () {
    test('keeps an in-range requested page', () {
      expect(
        resolveCatalogPageFromTotalCount(
          requestedPage: 3,
          pageSize: 20,
          totalCount: 553,
        ),
        3,
      );
    });

    test('clamps an excessive faceted page to the real final page', () {
      expect(
        resolveCatalogPageFromTotalCount(
          requestedPage: 99,
          pageSize: 20,
          totalCount: 553,
        ),
        28,
      );
    });

    test('normalizes empty and non-positive page requests to page one', () {
      expect(
        resolveCatalogPageFromTotalCount(
          requestedPage: 8,
          pageSize: 20,
          totalCount: 0,
        ),
        1,
      );
      expect(
        resolveCatalogPageFromTotalCount(
          requestedPage: 0,
          pageSize: 20,
          totalCount: 553,
        ),
        1,
      );
    });
  });
}
