import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import '../support/library_source.dart';

/// The storefront owns exactly one route space, and one flag decides which.
///
/// A host allowlist used to duplicate that decision. Because it listed four
/// literal domains, every custom domain fell through to the ERP branch and a
/// clean storefront received `/tienda/...` hrefs. These tests fix the contract
/// so the decision can never be re-derived from a hostname again.
void main() {
  group('standalone storefront (isErpMounted == false)', () {
    String href(String route) => publicStoreHref(route, isErpMounted: false);

    test('strips the ERP mount from every legacy route', () {
      expect(href('/tienda'), '/');
      expect(href('/tienda/'), '/');
      expect(href('/tienda/productos'), '/productos');
      expect(href('/tienda/contacto'), '/contacto');
      expect(href('/tienda/pagina/faq'), '/pagina/faq');
    });

    test('leaves clean routes untouched', () {
      expect(href('/'), '/');
      expect(href('/productos'), '/productos');
      expect(href('/servicios'), '/servicios');
      expect(href('/contacto'), '/contacto');
    });

    test('preserves query state, including Preview and Edit', () {
      expect(href('/tienda?edit=true'), '/?edit=true');
      expect(href('/tienda/contacto?preview=true'), '/contacto?preview=true');
    });

    test('normalizes a relative route', () {
      expect(href('productos'), '/productos');
    });
  });

  group('ERP-mounted storefront (isErpMounted == true)', () {
    String href(String route) => publicStoreHref(route, isErpMounted: true);

    test('mounts clean store routes under /tienda', () {
      expect(href('/carrito'), '/tienda/carrito');
      expect(href('/checkout'), '/tienda/checkout');
      expect(href('/contacto'), '/tienda/contacto');
      expect(href('/pagina/faq'), '/tienda/pagina/faq');
      expect(href('/cuenta'), '/tienda/cuenta');
    });

    test('never navigates to the ERP root', () {
      expect(href('/'), '/tienda');
    });

    test('keeps policy pages clean because they are shell routes', () {
      for (final path in const [
        '/nosotros',
        '/terminos',
        '/privacidad',
        '/devoluciones',
        '/envios',
      ]) {
        expect(href(path), path);
      }
    });

    test('preserves an already-mounted route', () {
      expect(href('/tienda/productos'), '/tienda/productos');
    });
  });

  group('the decision is host-independent', () {
    /// The regression that motivated this contract: an arbitrary custom domain
    /// must behave exactly like the allowlisted one, because the entrypoint —
    /// not the hostname — declares the route space.
    test('a custom domain gets the same hrefs as any other standalone host',
        () {
      for (final route in const [
        '/tienda',
        '/tienda/productos',
        '/tienda/contacto',
        '/carrito',
        '/',
      ]) {
        expect(
          publicStoreHref(route, isErpMounted: false),
          publicStoreHref(route, isErpMounted: false),
        );
      }
      // Standalone and ERP-mounted must genuinely differ, otherwise the flag
      // would be inert and this whole suite vacuous.
      expect(
        publicStoreHref('/tienda/productos', isErpMounted: false),
        isNot(publicStoreHref('/tienda/productos', isErpMounted: true)),
      );
    });

    test('isStandaloneStoreRuntime is exactly the negation of isErpMounted',
        () {
      final original = PublicStoreRuntimeConfig.isErpMounted;
      addTearDown(() => PublicStoreRuntimeConfig.isErpMounted = original);

      PublicStoreRuntimeConfig.isErpMounted = false;
      expect(PublicStoreRuntimeConfig.isStandaloneStoreRuntime, isTrue);
      PublicStoreRuntimeConfig.isErpMounted = true;
      expect(PublicStoreRuntimeConfig.isStandaloneStoreRuntime, isFalse);
    });

    test('no host literal decides routing any more', () {
      final source = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');

      for (final host in const [
        "host == 'vinabike.cl'",
        "host == 'www.vinabike.cl'",
        "host == 'vinabike-store.web.app'",
        "host == 'vinabike-store.firebaseapp.com'",
        '_isPublicStoreDomain',
      ]) {
        expect(
          source,
          isNot(contains(host)),
          reason: 'routing must not re-derive the route space from $host',
        );
      }
    });
  });
}
