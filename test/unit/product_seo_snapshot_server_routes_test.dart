import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

/// The build leaves out every snapshot under a route that `firebase.json`
/// hands to the HTML server: Hosting serves a static file before a rewrite,
/// so a snapshot there would hide the live page.
void main() {
  Map<String, dynamic> config(List<Map<String, dynamic>> rewrites) => {
        'hosting': [
          {'target': 'erp', 'public': 'build/web', 'rewrites': const []},
          {
            'target': 'store',
            'public': 'build/web_store',
            'rewrites': rewrites
          },
        ],
      };
  Map<String, dynamic> toServer(String source) => {
        'source': source,
        'run': {
          'serviceId': snapshots.seoStorefrontHtmlServiceId,
          'region': 'southamerica-east1',
        },
      };

  test('the repository config hands the product routes to the server', () {
    final routes = snapshots.SeoServerRenderedRoutes.fromFirebaseConfig(
      jsonDecode(File('firebase.json').readAsStringSync()),
    );
    for (final path in [
      '/productos',
      '/productos/',
      '/productos/categoria/frenos',
      '/productos/pastillas-shimano/1161022',
      '/productos/46a51a87-aa3a-430c-a6e1-af48c8d74541',
      '/producto/46a51a87-aa3a-430c-a6e1-af48c8d74541',
    ]) {
      expect(routes.owns(path), isTrue, reason: path);
    }
    for (final path in [
      '/',
      '/carrito',
      '/servicios',
      '/productosx',
      '/producto',
      '/tienda/producto/46a51a87-aa3a-430c-a6e1-af48c8d74541',
    ]) {
      expect(routes.owns(path), isFalse, reason: path);
    }
  });

  test('only the store target and only this service count', () {
    final routes = snapshots.SeoServerRenderedRoutes.fromFirebaseConfig(
      config([
        {'source': '/app/open', 'destination': '/app-open.html'},
        toServer('/productos'),
        {
          'source': '/otra/**',
          'run': {'serviceId': 'otro-servicio', 'region': 'x'},
        },
        {'source': '**', 'destination': '/index.html'},
      ]),
    );
    expect(routes.owns('/productos'), isTrue);
    expect(routes.owns('/productos/categoria/frenos'), isFalse);
    expect(routes.owns('/otra/ruta'), isFalse);
    expect(snapshots.SeoServerRenderedRoutes.none.isEmpty, isTrue);
  });

  test('a rewrite source it cannot read exactly fails the build', () {
    for (final source in ['/productos/*', '/productos/**/x', '**', 'x']) {
      expect(
        () => snapshots.SeoServerRenderedRoutes.fromFirebaseConfig(
          config([toServer(source)]),
        ),
        throwsA(isA<FormatException>()),
        reason: source,
      );
    }
  });

  test(
      'the validator trusts the server for its routes and rejects a file '
      'that would hide it', () async {
    final buildDir = await Directory.systemTemp.createTemp(
      'storefront-seo-server-routes-',
    );
    addTearDown(() async {
      if (await buildDir.exists()) await buildDir.delete(recursive: true);
    });
    await File('${buildDir.path}/index.html').writeAsString('''
<!doctype html>
<html>
<head>
  <link rel="canonical" href="https://taller-norte.example">
  <meta name="robots" content="index,follow">
  <script type="application/ld+json">
    {"@context":"https://schema.org","@type":"LocalBusiness","name":"Taller Norte"}
  </script>
</head>
<body><main><h1>Taller Norte</h1><a href="/productos/categoria/frenos">Frenos</a></main></body>
</html>
''');
    await File('${buildDir.path}/sitemap.xml').writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://taller-norte.example</loc></url>
  <url><loc>https://taller-norte.example/productos/bici-ruta/123</loc></url>
  <url><loc>https://taller-norte.example/contacto</loc></url>
</urlset>
''');
    final routes = snapshots.SeoServerRenderedRoutes.fromFirebaseConfig(
      config([toServer('/productos'), toServer('/productos/**')]),
    );

    Future<String> failures() async {
      try {
        await snapshots.validateGeneratedSeoArtifacts(
          buildDir: buildDir,
          storeUrl: 'https://taller-norte.example',
          staticTrustPagePaths: const {},
          serverRoutes: routes,
        );
      } on Object catch (error) {
        return error.toString();
      }
      fail('the fixture has no trust pages, so validation must fail');
    }

    // Trust pages are missing from the fixture; only the route lines matter.
    var report = await failures();
    expect(report, contains('/contacto aparece en sitemap.xml sin snapshot'));
    expect(report, isNot(contains('/productos/bici-ruta/123')));
    expect(report, isNot(contains('/productos/categoria/frenos')));

    await File('${buildDir.path}/productos/bici-ruta/123')
        .create(recursive: true);
    await File('${buildDir.path}/productos/index.html').create();
    report = await failures();
    expect(
      report,
      contains(
        '/productos/bici-ruta/123 es un archivo estático en una ruta del '
        'servidor HTML',
      ),
    );
    expect(
      report,
      contains('/productos es un archivo estático en una ruta del servidor'),
    );
  });
}
