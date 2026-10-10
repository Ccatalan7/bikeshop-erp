import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A workshop service is booked, never put in a cart, in both stores
/// (HTML since 2026-10-08, the Flutter page since 2026-10-10): a service
/// «A cotizar» at $0 reached the Flutter page with a cart button the
/// checkout then refused.
void main() {
  test('the Flutter service page books and declares a Service', () {
    final page = File('lib/public_store/pages/product_detail_page.dart')
        .readAsStringSync();

    expect(page, contains('_buildServiceBooking()'));
    expect(page, contains('buildPublicServiceStructuredData('));
    expect(page, contains('priceMode: product.websitePriceMode'));
    expect(
      page,
      contains(
          '_product!.productType == ProductType.service) {\n      return;'),
      reason: '_addToCart refuses a service',
    );
  });

  test('both stores name the price as the catalog marks it', () {
    final html = File('services/storefront_html/lib/src/product_page_view.dart')
        .readAsStringSync();
    final flutter = File('lib/public_store/pages/product_detail_page.dart')
        .readAsStringSync();

    expect(
        html, contains('catalogHeroPriceLabel(c.price, mode: page.priceMode)'));
    expect(html, contains('catalogPriceLabel(c.price, mode: page.priceMode)'));
    expect(flutter, contains('mode: _product?.websitePriceMode'));
  });
}
