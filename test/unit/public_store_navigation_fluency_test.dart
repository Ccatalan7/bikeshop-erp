import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('standalone storefront keeps routed layouts outside a nested shell', () {
    final router = File(
      'lib/public_store/routes/public_store_router.dart',
    ).readAsStringSync();

    expect(router, isNot(contains('ShellRoute(')));
    expect(router, contains('_buildPageNoScroll'));
    expect(
      RegExp(r'child: PublicStoreLayout\(').allMatches(router),
      hasLength(2),
    );
  });

  test('sticky scrolling rebuilds only the header and home stays soft-routed',
      () {
    final layout = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();
    final stickyStateStart = layout.indexOf('class _StickyHeaderScaffoldState');
    final onScrollStart = layout.indexOf(
      'void _onScroll() {',
      stickyStateStart,
    );
    final restoreStart = layout.indexOf(
      'void _restoreScrollForRoute({',
      onScrollStart,
    );
    final onScrollBody = layout.substring(onScrollStart, restoreStart);

    expect(onScrollBody, contains('_headerScrollOffset.value = offset'));
    expect(onScrollBody, isNot(contains('setState(')));
    expect(layout, contains('ValueListenableBuilder<double>'));
    expect(
      RegExp(
        r'_restoreScrollForRoute\(targetOffset: 0\)',
      ).allMatches(layout),
      hasLength(2),
    );
    expect(
      layout,
      contains(
        'kIsWeb && forceHomeRefresh && isHomeTarget && !isEditMode',
      ),
    );
    expect(layout, contains('web.window.location.reload()'));
    expect(layout, contains('web.window.location.assign(target)'));
  });

  test('a cache miss keeps prior catalog geometry but disables stale cards',
      () {
    final catalog = File(
      'lib/public_store/pages/product_catalog_page.dart',
    ).readAsStringSync();

    expect(catalog, contains('bool _isShowingPreviousResults = false'));
    expect(
      catalog,
      contains('absorbing: _isShowingPreviousResults'),
    );
    expect(
      catalog,
      contains('excluding: _isShowingPreviousResults'),
    );
  });

  test('product detail navigation always queues destination scroll reset', () {
    final layout = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();
    final resetStart = layout.indexOf(
      'final shouldResetTargetScroll =',
    );
    final currentRouteCheck = layout.indexOf(
      'if (current == target)',
      resetStart,
    );
    final resetContract = layout.substring(resetStart, currentRouteCheck);

    expect(
      resetContract,
      contains('_shouldResetScrollForPublicStoreNav(targetPath)'),
    );
    expect(resetContract, contains('requestScrollToTop(target)'));
    expect(
      resetContract,
      contains('requestScrollToTopForPath(targetPath)'),
    );
    expect(
      layout,
      contains("!normalized.startsWith('/productos/categoria/')"),
    );
  });

  test('related products prefetch data, snapshots, and images', () {
    final detail = File(
      'lib/public_store/pages/product_detail_page.dart',
    ).readAsStringSync();

    expect(
      detail,
      contains('CatalogPagePrefetchCache<PublicProductPage>'),
    );
    expect(detail, contains('_relatedPageCache.load('));
    expect(
      detail,
      contains('primeProductSnapshotForNavigation('),
    );
    expect(detail, contains('precacheImage(NetworkImage(url), context)'));

    final parallelWarmStart = detail.indexOf(
      'final seededProduct = _product;',
    );
    final authoritativeLookupStart = detail.indexOf(
      '// Load the product - support both UUID and SKU-based lookups',
    );
    expect(parallelWarmStart, greaterThan(0));
    expect(parallelWarmStart, lessThan(authoritativeLookupStart));
  });

  test('active homepage product surfaces use gapless inventory SWR', () {
    final home = File(
      'lib/public_store/pages/public_home_page.dart',
    ).readAsStringSync();
    final renderer = File(
      'lib/modules/website/widgets/website_block_renderer.dart',
    ).readAsStringSync();

    for (final source in [home, renderer]) {
      expect(
        source,
        contains('addListener(_handlePublicInventoryInvalidated)'),
      );
      expect(
        source,
        contains('removeListener(_handlePublicInventoryInvalidated)'),
      );
      expect(source, contains('TickerMode.of(context)'));
      expect(source, contains('_inventoryRevalidationPending = true'));
    }

    expect(
      home,
      contains('_loadFeaturedProductsOnce(forceRefresh: true)'),
    );
    expect(renderer, contains('_loadProducts(preserveVisible: true)'));
    expect(renderer, contains('_usesParentFeaturedProducts'));
    expect(renderer, contains('preserveVisible: !ownerChanged'));
    expect(home, contains('...product.toJson()'));
    expect(renderer, contains('...product.toJson()'));
  });
}
