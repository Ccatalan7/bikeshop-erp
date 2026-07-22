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

  test('storefront fallback is visible to users without bot-only hidden copy',
      () {
    final generatedIndex = File('web/index.html').readAsStringSync();
    final indexTemplate = File('scripts/sync_seo_index.sh').readAsStringSync();

    for (final source in [generatedIndex, indexTemplate]) {
      expect(source, contains('<noscript id="storefront-nojs-fallback">'));
      expect(source, contains('<main class="storefront-nojs-fallback">'));
      expect(source, isNot(contains('Merchant Center bots')));
      expect(source, isNot(contains('class="sr-only"')));
      expect(source, isNot(contains('.sr-only')));
    }
  });

  test('direct and hydrated product pages expose one aligned Product entity',
      () {
    final detailPage = File('lib/public_store/pages/product_detail_page.dart')
        .readAsStringSync();
    final snapshots =
        File('scripts/generate_product_seo_snapshots.dart').readAsStringSync();

    expect(
        detailPage, contains("_structuredDataScriptId = 'seo-product-jsonld'"));
    expect(detailPage, contains('product.websiteDescription'));
    expect(detailPage, contains('product.websiteMerchantBrand'));
    expect(detailPage, contains('product.websiteMerchantMpn'));
    expect(detailPage, contains('if (structuredBrandName.isNotEmpty)'));
    expect(snapshots, contains('description: baseProductDescription'));
    expect(snapshots, contains('_fetchPublicProductAvailability'));
    expect(snapshots, contains('publicAvailability.containsKey'));
    expect(snapshots, contains('outDir.deleteSync(recursive: true)'));
    expect(snapshots, contains('Disponibilidad: agotado'));
    expect(snapshots, isNot(contains('Disponibilidad: consultar stock')));
    expect(
      snapshots,
      isNot(contains("gtin == null ? 'Genérico'")),
    );
  });

  test('Merchant feed uses effective price and public sellable availability',
      () {
    final feed = File(
      'supabase/functions/google-merchant-feed/index.ts',
    ).readAsStringSync();

    expect(feed, contains('resolveMerchantPrice(product)'));
    expect(feed, isNot(contains('.gt("price", 0)')));
    expect(feed, contains('.rpc("get_public_products"'));
    expect(feed, contains('p_product_ids: feedCandidates'));
    expect(
        feed, contains('resolveMerchantAvailability(product) === "in_stock"'));
    expect(feed, contains('resolveMerchantBrand(p, brandsMap)'));
    expect(feed, contains('isVerifiableMerchantBrand'));
    expect(feed, isNot(contains('brand = storeName')));
  });

  test('in-app Merchant diagnostics mirrors feed eligibility gates', () {
    final diagnostics = File(
      'supabase/functions/google-product-diagnostics/index.ts',
    ).readAsStringSync();

    expect(diagnostics, contains('show_on_website'));
    expect(diagnostics, contains('product_type'));
    expect(diagnostics, contains('website_price'));
    expect(diagnostics, contains('website_image_url_optimized'));
    expect(diagnostics, contains('website_merchant_brand'));
    expect(diagnostics, contains('isVerifiableMerchantBrand'));
    expect(diagnostics, contains('product_brands'));
    expect(diagnostics, contains('get_product_available_quantities'));
  });

  test('shipping scope is consistently limited to Chile continental', () {
    final publicSources = [
      'lib/public_store/pages/product_detail_page.dart',
      'lib/public_store/pages/cart_page.dart',
      'lib/public_store/widgets/public_store_layout.dart',
      'supabase/functions/google-merchant-feed/index.ts',
      'scripts/generate_product_seo_snapshots.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(publicSources, contains('Chile continental'));
    expect(publicSources.toLowerCase(), isNot(contains('todo chile')));
    expect(publicSources.toLowerCase(), isNot(contains('todo el país')));
    expect(publicSources, isNot(contains('OfferShippingDetails')));
    expect(publicSources, isNot(contains("'shippingDetails'")));
  });

  test('policy renderer converts legacy escaped line breaks to paragraphs', () {
    final policyPage = File(
      'lib/public_store/pages/static_policy_page.dart',
    ).readAsStringSync();

    expect(policyPage, contains(".replaceAll(r'\\n', '\\n')"));
  });
}
