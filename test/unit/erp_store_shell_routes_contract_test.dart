import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El editor del sitio vive en el shell de la tienda montada en el ERP
/// (`PersistentEditorShell` alrededor de `PublicStoreLayout`). Una ruta de la
/// tienda que queda fuera de ese shell se dibuja sin la barra, las secciones,
/// el inspector ni la vista HTML.
///
/// El 2026-11-17 el dueño eligió «Guías del taller» en «Ir a página» y la
/// página apareció sola, con el lienzo sin controles: `/tienda/pagina/:slug`
/// seguía como ruta suelta desde la primera versión de la tienda.
void main() {
  final router = File('lib/shared/routes/app_router.dart').readAsStringSync();

  String storeShell() {
    final start = router.indexOf('StatefulShellRoute.indexedStack(');
    final end = router.indexOf('// Public store host fallback', start);
    expect(start, isNonNegative, reason: 'el shell de la tienda del ERP');
    expect(end, greaterThan(start));
    return router.substring(start, end);
  }

  test('una página del editor (/tienda/pagina/<slug>) se abre dentro del '
      'editor, con sus paneles', () {
    final shell = storeShell();
    expect(shell, contains("path: '/tienda/pagina/:slug'"));
    expect(shell, contains('DynamicWebsitePage(slug: slug)'));
    // go_router afirma al crear el router que una rama no parte en una ruta
    // con parámetro: sin `initialLocation` la app de prueba abre en «Algo
    // salió mal» (lo que pasó al primer intento, 2026-11-17).
    final branch = shell.substring(
      shell.lastIndexOf(
        'StatefulShellBranch(',
        shell.indexOf("path: '/tienda/pagina/:slug'"),
      ),
      shell.indexOf("path: '/tienda/pagina/:slug'"),
    );
    expect(
      branch,
      contains(r"initialLocation: '/tienda/pagina/$websiteGuidesIndexSlug'"),
    );
    // Una sola ruta: otra copia fuera del shell volvería a sacar los
    // controles a quien llegue por ella.
    expect("path: '/tienda/pagina/:slug'".allMatches(router), hasLength(1));
  });

  test('«Ir a página» y «Páginas» abren las páginas en esa ruta', () {
    final layout = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();
    expect(layout, contains(r"'/tienda/pagina/$slug'"));

    final pages = File(
      'lib/modules/website/pages/page_management_page.dart',
    ).readAsStringSync();
    expect(pages, contains(r"'/tienda/pagina/${page.slug}'"));
  });
}
