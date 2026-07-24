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
    final productForm = File(
      'lib/modules/inventory/pages/product_form_page.dart',
    ).readAsStringSync();

    expect(feed, contains('projectPublicCommerceProduct(product'));
    expect(feed, isNot(contains('product.website_merchant_mpn, product.sku')));
    expect(sharedFeed,
        contains('mpn: firstNonEmpty(product.website_merchant_mpn)'));
    expect(sharedFeed, contains('missing_product_identifiers'));
    expect(
      snapshots,
      contains('PublicCommerceProductProjection.fromJson'),
    );
    expect(
      snapshots,
      isNot(contains("if (gtin == null && productSku.isNotEmpty) 'mpn'")),
    );
    expect(
      productForm,
      isNot(contains("_existingProduct?.brand,\n        'Vinabike'")),
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
    final publicInventory = File(
      'lib/public_store/services/public_inventory_service.dart',
    ).readAsStringSync();
    final snapshots =
        File('scripts/generate_product_seo_snapshots.dart').readAsStringSync();
    final projection = File(
      'lib/public_store/models/public_commerce_product_projection.dart',
    ).readAsStringSync();

    expect(
        detailPage, contains("_structuredDataScriptId = 'seo-product-jsonld'"));
    expect(detailPage, contains('_commerceProjection(product)'));
    expect(detailPage, contains("'name': commerce.title"));
    expect(detailPage, contains("'availability': commerce.availability"));
    expect(detailPage, contains('_categoryTrail.last.fullPath'));
    expect(
        detailPage, contains('for (final category in breadcrumbCategories)'));
    expect(projection, contains('product.websiteMerchantDescription'));
    expect(projection, contains('product.websiteMerchantBrand'));
    expect(projection, contains('product.websiteMerchantMpn'));
    expect(publicInventory, contains('website_seo_title'));
    expect(publicInventory, contains('website_seo_description'));
    expect(publicInventory, contains('website_merchant_title'));
    expect(publicInventory, contains('website_merchant_description'));
    expect(publicInventory, contains('full_path,parent_id,level,description'));
    expect(publicInventory, contains('show_on_website,sort_order'));
    expect(snapshots, contains('commerce: commerce'));
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

    expect(feed, contains('projectPublicCommerceProduct(product'));
    expect(feed, isNot(contains('.gt("price", 0)')));
    expect(feed, contains('.rpc("get_public_products"'));
    expect(feed, contains('p_product_ids: feedCandidates'));
    expect(feed, contains('.merchant_eligible'));
    expect(feed, contains('resolvedBrand: resolveMerchantBrand'));
    expect(feed, isNot(contains('brand = storeName')));
    expect(feed, isNot(contains('while (description.length < 150)')));
    expect(feed, isNot(contains('category_name || "Ciclismo"')));
    expect(feed, isNot(contains('fixExcessiveCaps')));
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
    expect(diagnostics, contains('projectPublicCommerceProduct'));
    expect(diagnostics, contains('product_brands'));
    expect(diagnostics, contains('get_product_available_quantities'));
    expect(diagnostics, contains('.rpc(\n    "get_public_products"'));
    expect(
      diagnostics,
      contains('Las reglas actuales del catálogo web no mantienen una landing'),
    );
    expect(diagnostics, contains('missing_product_identifiers'));
  });

  test('linked brand identity is active and tenant-safe in every consumer', () {
    final live = File(
      'lib/public_store/services/public_inventory_service.dart',
    ).readAsStringSync();
    final snapshots = File(
      'scripts/generate_product_seo_snapshots.dart',
    ).readAsStringSync();
    final feed = File(
      'supabase/functions/google-merchant-feed/index.ts',
    ).readAsStringSync();
    final diagnostics = File(
      'supabase/functions/google-product-diagnostics/index.ts',
    ).readAsStringSync();

    expect(live, contains(".select('id,name,tenant_id,is_active')"));
    expect(live, contains("row['is_active'] != true"));
    expect(snapshots, contains("'is_active': 'eq.true'"));
    expect(snapshots, contains("row['is_active'] == true"));
    expect(feed, contains('.eq("is_active", true)'));
    expect(
      feed,
      contains('.or(`tenant_id.eq.\${tenantId},tenant_id.is.null`)'),
    );
    expect(diagnostics, contains('.eq("is_active", true)'));
    expect(
      diagnostics,
      contains('.or(`tenant_id.eq.\${data.tenant_id},tenant_id.is.null`)'),
    );
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
