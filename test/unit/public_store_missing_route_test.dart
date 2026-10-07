import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vinabike_erp/public_store/routes/public_store_router.dart';

/// Una URL que la tienda no conoce mostraba la pantalla de error de go_router
/// en inglés, con el `index,follow` y la canónica de la portada: Google la
/// leía como otra copia de la portada. Ahora cae en una ruta comodín que va
/// última y muestra «Página no encontrada» con `noindex`.
void main() {
  const catchAll = '/:rutaInexistente(.*)';

  late GoRouter router;
  setUp(() => router = PublicStoreRouter.createRouter());
  tearDown(() => router.dispose());

  String matchedPath(String location) {
    final match = router.configuration.findMatch(Uri.parse(location));
    return (match.last.route as GoRoute).path;
  }

  test('el comodín es la última ruta', () {
    final routes = router.configuration.routes.whereType<GoRoute>().toList();
    expect(routes.last.path, catchAll);
  });

  test('una URL inventada, corta o profunda, cae en el comodín', () {
    expect(matchedPath('/esta-pagina-no-existe'), catchAll);
    expect(matchedPath('/productos/a/b/c/d'), catchAll);
  });

  test('una ruta montada del ERP bajo /tienda se redirige, no se pierde', () {
    expect(matchedPath('/tienda/productos/categoria/camaras'),
        '/tienda/:resto(.*)');
    expect(matchedPath('/tienda/productos/cadena-kmc/10266'),
        '/tienda/:resto(.*)');
  });

  // `/cuenta/mensajes` dibujaba una lista de chats vieja, distinta del
  // centro de chats; ahora sus enlaces llegan al centro (2026-10-07).
  testWidgets('los enlaces viejos del chat llegan al centro de chats',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    for (final (from, to) in [
      ('/cuenta/mensajes', '/cuenta/chats'),
      ('/cuenta/mensajes/c-1', '/cuenta/chats/c-1'),
      ('/tienda/cuenta/mensajes', '/cuenta/chats'),
      ('/tienda/cuenta/mensajes/c-1', '/cuenta/chats/c-1'),
    ]) {
      final redirected = await router.configuration.redirect(
        context,
        router.configuration.findMatch(Uri.parse(from)),
        redirectHistory: [],
      );
      expect(redirected.uri.toString(), to, reason: from);
    }
  });

  test('las rutas de la tienda no caen en el comodín', () {
    for (final location in [
      '/',
      '/productos',
      '/servicios',
      '/contacto',
      '/nosotros',
      '/carrito',
      '/checkout',
      '/cuenta',
      '/pagina/nosotros',
      '/productos/cadena-kmc/10266',
    ]) {
      expect(matchedPath(location), isNot(catchAll), reason: location);
    }
  });
}
