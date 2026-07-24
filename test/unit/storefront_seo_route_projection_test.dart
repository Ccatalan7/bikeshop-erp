import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/seo_helper.dart';

void main() {
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
  });

  test('product detail owns robots for loading, missing and hydrated states',
      () {
    final source = File('lib/public_store/pages/product_detail_page.dart')
        .readAsStringSync();

    expect(source, contains('_updateUnavailableSeo(token);'));
    expect(source, contains('hasEligibleContent: false'));
    expect(source, contains('robots: routeProjection.robots'));

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
}
