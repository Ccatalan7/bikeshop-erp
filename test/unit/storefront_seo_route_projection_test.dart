import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import 'package:vinabike_erp/shared/utils/seo_helper.dart';
import '../support/library_source.dart';

void main() {
  test('system routes receive specific titles without competing SEO owners',
      () {
    expect(
      resolvePublicStoreSystemSeoTitle(
        path: '/carrito',
        storeName: 'Viñabike',
      ),
      'Carrito | Viñabike',
    );
    expect(
      resolvePublicStoreSystemSeoTitle(
        path: '/tienda/checkout',
        storeName: 'Viñabike',
      ),
      'Checkout | Viñabike',
    );
    expect(
      resolvePublicStoreSystemSeoTitle(
        path: '/terminos/',
        storeName: 'Viñabike',
      ),
      'Términos y condiciones | Viñabike',
    );
    expect(
      resolvePublicStoreSystemSeoTitle(
        path: '/',
        storeName: 'Viñabike',
      ),
      'Viñabike',
    );
    expect(
      resolvePublicStoreSystemSeoTitle(
        path: '/ruta-desconocida',
        storeName: 'Viñabike',
      ),
      'Viñabike',
    );
    expect(
      resolvePublicStoreSystemSeoTitle(
        path: '/privacidad',
        storeName: '',
      ),
      'Política de privacidad',
    );
  });

  test('routed page identity overrides a stale stacked router ancestor', () {
    final checkoutUri = resolvePublicStoreSeoUri(
      routerUri: Uri.parse('/carrito?from=header'),
      routePath: '/checkout',
    );

    expect(checkoutUri.path, '/checkout');
    expect(checkoutUri.queryParameters, {'from': 'header'});
    expect(
      resolvePublicStoreSystemSeoTitle(
        path: checkoutUri.path,
        storeName: 'Viñabike',
      ),
      'Checkout | Viñabike',
    );
    expect(
      projectStorefrontSeoRoute(
        checkoutUri,
        isErpMounted: false,
      ).canonicalPath,
      '/checkout',
    );
  });

  test('clean product and category routes remain indexable', () {
    for (final path in [
      '/productos/categoria/camaras',
      '/productos/camara-rbx/RBX-123',
    ]) {
      final projection = projectStorefrontSeoRoute(
        Uri.parse(path),
        isErpMounted: false,
      );
      expect(projection.canonicalPath, path);
      expect(projection.robots, 'index,follow');
    }
  });

  test('catalog query state canonicalizes to the clean noindex route', () {
    final projection = projectStorefrontSeoRoute(
      Uri.parse(
        '/productos/categoria/camaras?brand='
        '00000000-0000-4000-8000-000000000001&sort=price_asc&page=2',
      ),
      isErpMounted: false,
    );

    expect(projection.canonicalPath, '/productos/categoria/camaras');
    expect(projection.robots, 'noindex,follow');
  });

  test('direct category scope canonicalizes to the inclusive collection', () {
    final projection = projectStorefrontSeoRoute(
      Uri.parse(
        '/productos/categoria/cadenas?category_scope=direct',
      ),
      isErpMounted: false,
    );

    expect(projection.canonicalPath, '/productos/categoria/cadenas');
    expect(projection.robots, 'noindex,follow');
  });

  test('ERP, Preview and transactional routes are never indexed', () {
    final cases = <Uri>[
      Uri.parse('/tienda/productos/categoria/camaras?preview=true'),
      Uri.parse('/productos?edit=true'),
      Uri.parse('/carrito'),
      Uri.parse('/checkout'),
      Uri.parse('/auth/callback?code=oauth-code'),
      Uri.parse('/cuenta/pedidos'),
      Uri.parse('/pedido/ABC-1'),
    ];

    for (final uri in cases) {
      final projection = projectStorefrontSeoRoute(
        uri,
        isErpMounted: uri.path.startsWith('/tienda'),
      );
      expect(projection.robots, 'noindex,follow', reason: uri.toString());
    }
    expect(
      projectStorefrontSeoRoute(
        cases.first,
        isErpMounted: true,
      ).canonicalPath,
      '/productos/categoria/camaras',
    );
  });

  test('editor control can only further restrict effective indexability', () {
    final clean = Uri.parse('/productos/categoria/camaras');

    expect(
      projectStorefrontSeoRoute(
        clean,
        isErpMounted: false,
        ownerAllowsIndexing: false,
      ).robots,
      'noindex,follow',
    );
    expect(
      projectStorefrontSeoRoute(
        clean,
        isErpMounted: false,
        ownerIsPublished: false,
      ).robots,
      'noindex,follow',
    );
    expect(
      projectStorefrontSeoRoute(
        clean,
        isErpMounted: false,
        hasEligibleContent: false,
      ).robots,
      'noindex,follow',
    );
    expect(
      projectStorefrontSeoRoute(
        Uri.parse('/productos/categoria/camaras?q=29'),
        isErpMounted: false,
        ownerAllowsIndexing: true,
        ownerIsPublished: true,
        hasEligibleContent: true,
      ).robots,
      'noindex,follow',
    );
  });

  test('a withdrawn collection is noindex with the catalog root canonical', () {
    final projection = projectStorefrontSeoRoute(
      Uri.parse('/productos/categoria/pinones'),
      isErpMounted: false,
      ownerIsPublished: false,
      hasEligibleContent: false,
      unavailableCanonicalPath: '/productos',
    );

    expect(projection.canonicalPath, '/productos');
    expect(projection.robots, 'noindex,follow');
  });

  test('catalog roots follow the route namespace, never the type filter', () {
    expect(
      storefrontCatalogRootPath(
        '/productos/categoria/pinones',
      ),
      '/productos',
    );
    expect(
      storefrontCatalogRootPath(
        '/tienda/productos/categoria/pinones',
      ),
      '/productos',
    );
    expect(
      storefrontCatalogRootPath(
        '/servicios/categoria/mantencion',
      ),
      '/servicios',
    );

    final invalidSecondaryFilter = projectStorefrontSeoRoute(
      Uri.parse('/productos/categoria/pinones?type=service&sort=bogus'),
      isErpMounted: false,
      ownerIsPublished: false,
      hasEligibleContent: false,
      unavailableCanonicalPath: storefrontCatalogRootPath(
        '/productos/categoria/pinones',
      ),
    );
    expect(invalidSecondaryFilter.canonicalPath, '/productos');
    expect(invalidSecondaryFilter.robots, 'noindex,follow');

    // A secondary service filter may have produced a services-root
    // presentation in page state. Clearing a withdrawn product collection
    // must ignore that presentation and retain the path-owned namespace.
    expect(
      storefrontCatalogSelectionPath(
        currentPath: '/productos/categoria/pinones',
        hasSelectedCategory: false,
        publishedCategoryPath: '/servicios',
      ),
      '/productos',
    );
    expect(
      storefrontCatalogSelectionPath(
        currentPath: '/servicios/categoria/mantencion',
        hasSelectedCategory: false,
        publishedCategoryPath: '/productos',
      ),
      '/servicios',
    );
  });

  test('generic SEO never competes with catalog or product owners', () {
    for (final path in [
      '/productos',
      '/servicios',
      '/productos/categoria/camaras',
      '/tienda/servicios/categoria/mantencion',
    ]) {
      expect(isCatalogSeoManagedPath(path), isTrue, reason: path);
      expect(isProductDetailSeoManagedPath(path), isFalse, reason: path);
    }

    for (final path in [
      '/productos/camara-rbx/RBX-123',
      '/tienda/productos/camara-rbx/RBX-123',
      '/producto/legacy-id',
      '/shop/legacy-id',
    ]) {
      expect(isProductDetailSeoManagedPath(path), isTrue, reason: path);
      expect(isCatalogSeoManagedPath(path), isFalse, reason: path);
    }

    for (final path in ['/', '/contacto', '/pagina/nosotros']) {
      expect(isCatalogSeoManagedPath(path), isFalse, reason: path);
      expect(isProductDetailSeoManagedPath(path), isFalse, reason: path);
    }

    for (final path in [
      '/nosotros',
      '/envios',
      '/devoluciones',
      '/terminos',
      '/privacidad',
      '/tienda/privacidad',
    ]) {
      expect(isStaticPolicySeoManagedPath(path), isTrue, reason: path);
    }
    expect(isStaticPolicySeoManagedPath('/pagina/privacidad'), isFalse);

    for (final path in [
      '/pagina/nosotros',
      '/pagina/landing-verano',
      '/tienda/pagina/landing-verano',
    ]) {
      expect(isDynamicWebsitePageSeoManagedPath(path), isTrue, reason: path);
    }
    for (final path in ['/', '/pagina', '/pagina/', '/privacidad']) {
      expect(isDynamicWebsitePageSeoManagedPath(path), isFalse, reason: path);
    }
  });

  test('product detail owns robots for loading, missing and hydrated states',
      () {
    final source = File('lib/public_store/pages/product_detail_page.dart')
        .readAsStringSync();

    expect(source, contains('_updateUnavailableSeo(token);'));
    expect(source, contains('hasEligibleContent: false'));
    expect(source, contains('robots: routeProjection.robots'));
    expect(source, contains('buildPublicProductSeoDescription('));
    expect(source, contains("ogType: 'product'"));

    expect(
      projectStorefrontSeoRoute(
        Uri.parse('/tienda/productos/camara-rbx/RBX-123?preview=true'),
        isErpMounted: true,
        hasEligibleContent: true,
      ).robots,
      'noindex,follow',
    );
    expect(
      projectStorefrontSeoRoute(
        Uri.parse('/productos/no-existe/SKU-404'),
        isErpMounted: false,
        ownerIsPublished: false,
        hasEligibleContent: false,
      ).robots,
      'noindex,follow',
    );
  });

  test('policy pages project CMS metadata with a factual public fallback', () {
    final source = File('lib/public_store/pages/static_policy_page.dart')
        .readAsStringSync();

    expect(source, contains('loadPageWithBlocksResult('));
    expect(source, contains('originConfirmed: result.isOriginConfirmed'));
    expect(source, contains('originConfirmed: _originConfirmed'));
    expect(source, contains('page?.metaTitle'));
    expect(source, contains('page?.metaDescription'));
    expect(source, contains('page?.ogImageUrl'));
    expect(source, contains('_PublicPolicyView.contentSummary(_blocks)'));
    expect(
      source,
      contains('Esta página no tiene contenido público disponible en este '),
    );
    expect(
      source,
      contains(
        'ownerIsPublished: originConfirmed && page?.isPublished == true',
      ),
    );
    expect(source, contains('robots: routeProjection.robots'));
    expect(source, contains('_PublicPolicyUnavailableView'));
    expect(
      source.indexOf('if (!editProvider.isInEditorContext)'),
      lessThan(source.indexOf('if (_error != null)')),
      reason:
          'A public legal route must resolve to public or unavailable content '
          'before editor-only implementation errors are considered.',
    );

    final layout = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');
    expect(layout, contains('isStaticPolicySeoManagedPath(currentPath)'));
  });

  test(
      'hosting sends crawler-safe headers before private Flutter routes hydrate',
      () {
    final config = jsonDecode(File('firebase.json').readAsStringSync())
        as Map<String, dynamic>;
    final hosting = (config['hosting'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((entry) => entry['public'] == 'build/web_store');
    final headers = (hosting['headers'] as List).cast<Map<String, dynamic>>();

    for (final source in [
      '/carrito',
      '/checkout',
      '/cuenta',
      '/cuenta/**',
      '/pedido',
      '/pedido/**',
      '/auth/**',
      '/tienda',
      '/tienda/**',
    ]) {
      final matchingRules =
          headers.where((entry) => entry['source'] == source).toList();
      expect(matchingRules, hasLength(1), reason: source);
      final rule = matchingRules.single;
      final values = (rule['headers'] as List).cast<Map<String, dynamic>>();
      expect(
        values,
        anyElement(
          predicate<Map<String, dynamic>>(
            (header) =>
                header['key'] == 'X-Robots-Tag' &&
                header['value'] == 'noindex, nofollow, noarchive',
          ),
        ),
        reason: source,
      );
    }
  });

  test('compact page edits preserve the canonical social image', () {
    final source = File(
      'lib/modules/website/pages/page_management_page.dart',
    ).readAsStringSync();

    expect(source, contains('ogImageUrl: widget.page?.ogImageUrl'));
  });

  test('dynamic CMS pages own metadata after publication and content load', () {
    final source = File('lib/public_store/pages/dynamic_website_page.dart')
        .readAsStringSync();
    final layout = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');

    expect(source, contains('loadPageWithBlocksResult('));
    expect(source, contains('loadEditorPageWithBlocks('));
    expect(source, contains('loadResult.isAuthoritativelyMissing'));
    expect(
      source,
      contains('!editorRequested && loadResult.isOriginConfirmed'),
    );
    expect(source, contains('originConfirmed: false'));
    expect(source, contains('page?.metaTitle'));
    expect(source, contains('page?.metaDescription'));
    expect(source, contains('page?.ogImageUrl'));
    expect(source, contains('page?.metaKeywords'));
    expect(
      source,
      contains('ownerIsPublished: originConfirmed &&'),
    );
    expect(source, contains('hasEligibleContent: hasEligibleContent'));
    expect(source, contains('robots: routeProjection.robots'));
    expect(
      layout,
      contains('isDynamicWebsitePageSeoManagedPath(currentPath)'),
    );
  });

  test('public bootstrap preserves editor-owned SEO after hydration', () {
    final service = readLibrarySource('lib/modules/website/services/website_service.dart');
    final layout = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');

    expect(service, contains('unawaited(loadPagesForTenant(tenantId));'));
    expect(layout, contains("getSetting('seo_meta_title', '')"));
    expect(layout, contains("getSetting('seo_meta_description', '')"));
    expect(layout, contains("getSetting('seo_meta_keywords', '')"));
    expect(layout, contains('currentPage.metaKeywords'));
    expect(layout, contains('keywords: seoKeywords'));
  });
}
