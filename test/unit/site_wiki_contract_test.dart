import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El wiki del sitio (docs/wiki/sitio-web) es el mapa de la tienda y del
/// editor. Una ruta pública, un evento de GA4, una página de administración
/// del sitio o una función del sitio no nacen sin nombrarse en el wiki: así no
/// queda como una carpeta paralela que se olvida (dueño, 2026-10-03). Vale
/// igual para Claude y para Codex porque corre en el gate de cada publicación.
void main() {
  String read(String path) => File(path).readAsStringSync();
  String page(String name) => read('docs/wiki/sitio-web/paginas/$name.md');

  test('every public store route is in the routes page', () {
    final router = read('lib/public_store/routes/public_store_router.dart');
    final routes = RegExp(r"path: *'(/[^']*)'")
        .allMatches(router)
        .map((match) => match.group(1)!)
        // `/tienda/*` repite la tienda dentro del ERP y se documenta como
        // familia; los comodines no son rutas que alguien escriba.
        .where((route) =>
            !route.startsWith('/tienda') &&
            !route.contains(r'$') &&
            !route.contains('('))
        .toSet();
    expect(routes, isNotEmpty);
    final wiki = page('rutas-y-navegacion');
    final missing = routes.where((route) => !wiki.contains('`$route`')).toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason: 'Agrega la ruta a la tabla de '
          'docs/wiki/sitio-web/paginas/rutas-y-navegacion.md.',
    );
  });

  test('every GA4 event the store sends is in the measurement page', () {
    final events = RegExp(r"_track\('([a-z_]+)'")
        .allMatches(read('lib/public_store/services/ga4_commerce_events.dart'))
        .map((match) => match.group(1)!)
        .toSet();
    expect(events, isNotEmpty);
    final wiki = page('medicion');
    final missing = events.where((event) => !wiki.contains('`$event`')).toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason: 'Describe el evento en docs/wiki/sitio-web/paginas/medicion.md.',
    );
  });

  test('every site administration page is in the editor page', () {
    final pages = Directory('lib/modules/website/pages')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.dart'))
        .toSet();
    expect(pages, isNotEmpty);
    final wiki = page('editor-del-sitio');
    final missing = pages.where((name) => !wiki.contains('`$name`')).toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason: 'Agrega la página a la tabla de rutas del ERP en '
          'docs/wiki/sitio-web/paginas/editor-del-sitio.md.',
    );
  });

  test('every site Edge Function is in the system map', () {
    final site = RegExp(
      r'^(google-|mercadopago-|website-|dispatch-storefront|'
      r'send-transactional-order|resend-transactional)',
    );
    final functions = Directory('supabase/functions')
        .listSync()
        .whereType<Directory>()
        .map((dir) => dir.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .where(site.hasMatch)
        .toSet();
    expect(functions, isNotEmpty);
    final wiki = page('mapa-del-sistema');
    final missing =
        functions.where((name) => !wiki.contains('`$name`')).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason: 'Agrega la función a la tabla de Edge Functions de '
          'docs/wiki/sitio-web/paginas/mapa-del-sistema.md.',
    );
  });

  test('the wiki index links every page', () {
    final index = read('docs/wiki/sitio-web/index.md');
    final missing = Directory('docs/wiki/sitio-web/paginas')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.md'))
        .where((name) => !index.contains('paginas/$name'))
        .toList()
      ..sort();
    expect(missing, isEmpty);
  });
}
