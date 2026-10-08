import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_public_core/public_store/seo/storefront_html_routes.dart';

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

  test(
      'the repository config hands the product, services and information '
      'routes and the home to the server', () {
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
      // The information pages (phase 2a, 2026-10-05).
      '/nosotros',
      '/envios',
      '/devoluciones',
      '/terminos',
      '/privacidad',
      // The home (phase 2b): Flutter enters by app.html.
      '/',
      // The services catalog and its categories (phase 2d).
      '/servicios',
      '/servicios/categoria/mantencion',
      // The contact page (phase 2e).
      '/contacto',
      // The cart and its lines (phase 3a).
      '/carrito',
      '/carrito/lineas',
      // The checkout and its lines (phase 3b).
      '/checkout',
      '/checkout/lineas',
      // The order page and its summary (phase 3c).
      '/pedido/46a51a87-aa3a-430c-a6e1-af48c8d74541',
      '/pedido/resumen.pdf',
      // The portal's reading pages and their content (phase 4a).
      '/cuenta',
      '/cuenta/pedidos',
      '/cuenta/servicios',
      '/cuenta/bicicletas',
      '/cuenta/vista',
      '/cuenta/archivo',
      // The profile, the addresses and where they save (phase 4b).
      '/cuenta/perfil',
      '/cuenta/direcciones',
      '/cuenta/accion',
      // The way in (phase 4c).
      '/cuenta/login',
      // The editor's own pages (phase 5a).
      '/pagina/arriendo',
      // The ERP's old mount, redirected (2026-10-08): no snapshot there.
      '/tienda',
      '/tienda/producto/46a51a87-aa3a-430c-a6e1-af48c8d74541',
    ]) {
      expect(routes.owns(path), isTrue, reason: path);
    }
    for (final path in [
      '/app.html',
      '/checkoutx',
      '/pedido',
      '/carritox',
      '/cuenta/loginx',
      '/cuenta/chats',
      '/cuenta/chats/46a51a87-aa3a-430c-a6e1-af48c8d74541',
      '/cuenta/perfilx',
      '/serviciosx',
      '/productosx',
      '/producto',
      '/nosotros/equipo',
      '/contacto/x',
      '/pagina',
      '/paginax',
    ]) {
      expect(routes.owns(path), isFalse, reason: path);
    }
    // Every other path reaches it too (its 404 and old addresses), but no
    // snapshot or static file belongs to that catch-all.
    expect(routes.servesTheRest, isTrue);
  });

  test(
      'Flutter keeps only the chats, the Android download and the way back '
      'from Auth; Hosting hands the server everything else', () {
    // Until 2026-10-08 `**` loaded Flutter: an unknown address answered 200
    // with the app, and `/tienda/...` redirected only in the browser.
    final config = jsonDecode(File('firebase.json').readAsStringSync()) as Map;
    final store = (config['hosting'] as List)
        .cast<Map>()
        .firstWhere((entry) => entry['target'] == 'store');
    final rewrites = (store['rewrites'] as List).cast<Map>();
    String answer(String path) {
      for (final rewrite in rewrites) {
        final source = rewrite['source'] as String;
        final matches = source == '**' ||
            source == path ||
            (source.endsWith('/**') &&
                path.startsWith(source.substring(0, source.length - 2)));
        if (!matches) continue;
        final run = rewrite['run'] as Map?;
        return run != null
            ? run['serviceId'] as String
            : '${rewrite['destination']}';
      }
      return 'none';
    }

    for (final path in [
      '/auth/callback',
      '/cuenta/chats',
      '/cuenta/chats/46a51a87-aa3a-430c-a6e1-af48c8d74541',
      '/cuenta/descargas/android',
    ]) {
      expect(answer(path), '/${snapshots.seoFlutterEntryFileName}',
          reason: path);
    }
    for (final path in [
      '/no-existe',
      '/buscar',
      '/tienda',
      '/tienda/productos',
      '/cuenta/mensajes',
      '/cuenta/mensajes/x',
      '/cuenta/descargas',
      '/productos',
    ]) {
      expect(answer(path), snapshots.seoStorefrontHtmlServiceId, reason: path);
    }
    expect(rewrites.last['source'], '**');
  });

  test('Flutter leaves for exactly the routes Firebase hands the server', () {
    final config = jsonDecode(File('firebase.json').readAsStringSync()) as Map;
    final store = (config['hosting'] as List)
        .cast<Map>()
        .firstWhere((entry) => entry['target'] == 'store');
    final sources = [
      for (final rewrite in (store['rewrites'] as List).cast<Map>())
        if ((rewrite['run'] as Map?)?['serviceId'] ==
                snapshots.seoStorefrontHtmlServiceId &&
            rewrite['source'] != '/_html/**' &&
            rewrite['source'] != '**')
          rewrite['source'] as String,
    ];
    // A route opened to the server and not listed here would keep Flutter's
    // in-app copy for visitors coming from the cart or the portal.
    expect(sources.toSet(), storefrontHtmlRouteSources.toSet());
    for (final path in [
      '/',
      '/productos',
      '/productos/categoria/frenos',
      '/producto/46a51a87-aa3a-430c-a6e1-af48c8d74541',
      '/servicios',
      '/contacto',
      '/carrito',
      '/carrito/lineas',
      '/checkout',
      '/checkout/lineas',
      '/pedido/46a51a87-aa3a-430c-a6e1-af48c8d74541',
      '/cuenta',
      '/cuenta/servicios',
      '/cuenta/perfil',
      '/cuenta/direcciones',
      '/cuenta/login',
      '/pagina/arriendo',
    ]) {
      expect(storefrontHtmlServes(path), isTrue, reason: path);
    }
    for (final path in [
      '/pedido',
      '/auth/callback',
      '/cuenta/chats',
      '/carritox',
      '/checkoutx',
    ]) {
      expect(storefrontHtmlServes(path), isFalse, reason: path);
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
    for (final source in ['/productos/*', '/productos/**/x', 'x']) {
      expect(
        () => snapshots.SeoServerRenderedRoutes.fromFirebaseConfig(
          config([toServer(source)]),
        ),
        throwsA(isA<FormatException>()),
        reason: source,
      );
    }
    // A catch-all counts only as the last rule: before another one it would
    // hide it.
    expect(
      () => snapshots.SeoServerRenderedRoutes.fromFirebaseConfig(
        config([toServer('**'), toServer('/productos')]),
      ),
      throwsA(isA<FormatException>()),
    );
    final last = snapshots.SeoServerRenderedRoutes.fromFirebaseConfig(
      config([toServer('/productos'), toServer('**')]),
    );
    expect(last.servesTheRest, isTrue);
    expect(last.owns('/productos'), isTrue);
    expect(last.owns('/main.dart.js'), isFalse);
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
    // Without the rewrite, an information page needs its snapshot.
    expect(report, contains('/nosotros no tiene snapshot'));
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

  test(
      'an information page the server draws needs no snapshot, and one left '
      'there would hide it', () async {
    final buildDir = await Directory.systemTemp.createTemp(
      'storefront-seo-server-policies-',
    );
    addTearDown(() async {
      if (await buildDir.exists()) await buildDir.delete(recursive: true);
    });
    final routes = snapshots.SeoServerRenderedRoutes.fromFirebaseConfig(
      config([
        for (final slug in [
          'nosotros',
          'envios',
          'devoluciones',
          'terminos',
          'privacidad',
          // The services catalog (phase 2d) and the contact page (2e): the
          // generator stops writing them.
          'servicios',
          'contacto',
        ])
          toServer('/$slug'),
      ]),
    );
    Future<String> report() async {
      try {
        await snapshots.validateGeneratedSeoArtifacts(
          buildDir: buildDir,
          storeUrl: 'https://taller-norte.example',
          staticTrustPagePaths: const {'/nosotros'},
          serverRoutes: routes,
        );
      } on Object catch (error) {
        return error.toString();
      }
      return '';
    }

    var failures = await report();
    for (final slug in ['nosotros', 'envios', 'privacidad']) {
      expect(failures, isNot(contains('/$slug no tiene snapshot')));
    }
    await File('${buildDir.path}/nosotros').writeAsString('<html></html>');
    failures = await report();
    expect(
      failures,
      contains('/nosotros es un archivo estático en una ruta del servidor'),
    );
    await File('${buildDir.path}/servicios').writeAsString('<html></html>');
    expect(
      await report(),
      contains('/servicios es un archivo estático en una ruta del servidor'),
    );
    await File('${buildDir.path}/contacto').writeAsString('<html></html>');
    expect(
      await report(),
      contains('/contacto es un archivo estático en una ruta del servidor'),
    );
  });

  test(
      'with the home on the server, Flutter enters by app.html and a root '
      'index.html would hide the home', () async {
    final buildDir = await Directory.systemTemp.createTemp(
      'storefront-seo-server-home-',
    );
    addTearDown(() async {
      if (await buildDir.exists()) await buildDir.delete(recursive: true);
    });
    final repository =
        jsonDecode(File('firebase.json').readAsStringSync()) as Map;
    final store = (repository['hosting'] as List)
        .cast<Map>()
        .singleWhere((entry) => entry['target'] == 'store');
    // Flutter's own routes enter by app.html (the catch-all went to the
    // server on 2026-10-08).
    expect(
      (store['rewrites'] as List).cast<Map>().where(
            (rewrite) =>
                rewrite['destination'] ==
                '/${snapshots.seoFlutterEntryFileName}',
          ),
      isNotEmpty,
    );
    final routes = snapshots.SeoServerRenderedRoutes.fromFirebaseConfig(
      config([toServer('/')]),
    );
    Future<String> report() async {
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
      return '';
    }

    expect(
      await report(),
      isNot(contains('/ es un archivo estático')),
    );
    await File('${buildDir.path}/index.html').writeAsString('<html></html>');
    expect(
      await report(),
      contains('/ es un archivo estático en una ruta del servidor'),
    );
  });
}
