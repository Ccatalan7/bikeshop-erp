import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../support/library_source.dart';

void main() {
  test('checkout keeps internal exceptions out of customer-facing copy', () {
    final source =
        File('lib/public_store/pages/checkout_page.dart').readAsStringSync();
    final confirmation = File(
      'lib/public_store/pages/order_confirmation_page.dart',
    ).readAsStringSync();

    expect(
      source,
      isNot(contains("Text('Error al procesar pago con MercadoPago: \$e')")),
    );
    expect(
      source,
      isNot(contains("Text('Error al crear pedido: \$e')")),
    );
    expect(
      source,
      contains('Tu pedido ya quedó guardado.'),
    );
    expect(
      source,
      contains('No pudimos confirmar el resultado del intento.'),
    );
    expect(
      source,
      allOf(
        contains('recuperaremos '),
        contains('ese mismo pedido.'),
      ),
    );
    expect(
      source,
      isNot(contains('el carrito se mantiene intacto.')),
    );
    expect(
      confirmation,
      isNot(contains("Text('No pudimos reintentar el pago: \$error')")),
    );
    expect(
      confirmation,
      contains(
        "'No pudimos reintentar el pago. '"
        "\n            'Inténtalo nuevamente en unos minutos.'",
      ),
    );
  });

  test('checkout locks the original attempt until recovery finishes', () {
    final source =
        File('lib/public_store/pages/checkout_page.dart').readAsStringSync();
    final layout =
        readLibrarySource('lib/public_store/widgets/public_store_layout.dart');

    expect(source, contains('_submission.retryOriginalOrder()'));
    expect(source, contains('ignoring: _checkoutLocked'));
    expect(source, contains('CheckoutExitPhase.recoveringOrder'));
    expect(layout, contains('authorizeCheckoutExit'));
    // The pop lock moved to the canonical StorefrontNavigationGuardScope
    // boundary during the navigation-guard refactor; the layout consumes the
    // same checkout guard lease.
    final guardScope = File(
      'lib/public_store/widgets/storefront_navigation_guard_scope.dart',
    ).readAsStringSync();
    expect(guardScope, contains('final guardIsActive ='));
    expect(
      guardScope,
      contains('canPop: !guardIsActive || _allowPopOnce'),
    );
    expect(layout, contains('guard.isLocked'));
    expect(source, contains('REINTENTAR CONFIRMACIÓN'));
    expect(source, isNot(contains('cart.clear()')));
  });

  test('checkout introduction speaks to the customer, not the design system',
      () {
    final source =
        File('lib/public_store/pages/checkout_page.dart').readAsStringSync();

    expect(
      source,
      contains(
        "'Completa tus datos de contacto, elige la forma de entrega y '",
      ),
    );
    expect(
      source,
      contains(
        "'selecciona el medio de pago antes de confirmar tu pedido.'",
      ),
    );
    expect(
      source,
      isNot(contains('con el mismo lenguaje claro del resto de la tienda')),
    );
  });
}
