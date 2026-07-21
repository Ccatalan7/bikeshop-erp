import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('storefront and feed never reinterpret retailer SKU as MPN', () {
    final feed = File(
      'supabase/functions/google-merchant-feed/index.ts',
    ).readAsStringSync();
    final sharedFeed = File(
      'supabase/functions/_shared/google_merchant_feed.ts',
    ).readAsStringSync();
    final snapshots = File(
      'scripts/generate_product_seo_snapshots.dart',
    ).readAsStringSync();

    expect(feed, contains('resolveMerchantIdentifiers(product)'));
    expect(feed, contains('resolveMerchantAvailability(product)'));
    expect(feed, isNot(contains('product.website_merchant_mpn, product.sku')));
    expect(sharedFeed,
        contains('mpn: firstNonEmpty(product.website_merchant_mpn)'));
    expect(snapshots, contains("product['website_merchant_mpn']"));
    expect(
      snapshots,
      isNot(contains("if (gtin == null && productSku.isNotEmpty) 'mpn'")),
    );
  });

  test('unknown identifiers and product categories are not guessed', () {
    final feed = File(
      'supabase/functions/google-merchant-feed/index.ts',
    ).readAsStringSync();

    expect(feed, isNot(contains('<g:identifier_exists>false')));
    expect(
      feed,
      isNot(contains(
          'firstNonEmpty(product.website_google_product_category, "3618")')),
    );
  });

  test(
      'StoreBot can inspect cart and checkout while private routes stay blocked',
      () {
    final sourceRobots = File('web/robots.txt').readAsStringSync();
    final generatedRobots =
        File('scripts/generate_product_seo_snapshots.dart').readAsStringSync();

    for (final robots in [sourceRobots, generatedRobots]) {
      expect(robots, isNot(contains('Disallow: /checkout')));
      expect(robots, isNot(contains('Disallow: /carrito')));
      expect(robots, contains('Disallow: /cuenta/'));
      expect(robots, contains('Disallow: /pedido/'));
    }
  });
}
