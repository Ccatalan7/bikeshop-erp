import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_surfaces.dart';

/// **No se vuelve a banderas paralelas.**
///
/// El Asistente de compras navegaba con cinco booleanos independientes
/// (`_showScenarios`, `_selectingBasket`, `_selectedNeed`, `_openSupplierId`,
/// `_returnToScenarios`) escritos a mano en más de treinta lugares. Nada
/// garantizaba que una combinación existiera de verdad y dos caminos al mismo
/// escenario dejaban cromos distintos.
///
/// Esta es una prueba estructural sobre el archivo: las pruebas de
/// comportamiento fijan lo que se ve, pero no impiden que alguien vuelva a
/// declarar un campo paralelo «sólo para este caso». Es barata y dice
/// exactamente qué está prohibido y por qué.
void main() {
  final page = File(
    'lib/modules/purchases/pages/intelligent_purchasing_workspace_page.dart',
  );

  test('la navegación del módulo no vuelve a tener banderas paralelas', () {
    final source = page.readAsStringSync();
    for (final campo in const <String>[
      'bool _showScenarios',
      'bool _selectingBasket',
      'bool _returnToScenarios',
      'String? _openSupplierId',
      'SupplyNeed? _selectedNeed;',
    ]) {
      expect(
        source.contains(campo),
        isFalse,
        reason: 'La navegación se deriva de `PurchaseFocus`; `$campo` sería un '
            'segundo dueño que puede contradecirlo.',
      );
    }
  });

  test('el foco tiene una sola puerta de escritura', () {
    final source = page.readAsStringSync();
    expect(
      source.contains('set _focus(PurchaseFocus value)'),
      isTrue,
      reason: 'El campo es privado y se escribe sólo por su setter, que acota '
          'la etapa al foco nuevo.',
    );
    // El campo respaldo se toca en su propio setter y en ningún otro lugar.
    expect(
      '_focusValue'.allMatches(source).length,
      3,
      reason: 'declaración, getter y setter: cualquier cuarto uso es una '
          'escritura que se saltó la puerta.',
    );
  });

  test('el módulo no conoce el despachador de destinos ni Inventario', () {
    final source = page.readAsStringSync();
    for (final fuga in const <String>[
      'ai_assistant_destination.dart',
      'inventory_service.dart',
      'applyExternalSearch',
      'openRouteInWorkspace',
    ]) {
      expect(
        source.contains(fuga),
        isFalse,
        reason: 'Una tarjeta dentro del flujo dedicado es evidencia, nunca una '
            'salida a otro módulo; `$fuga` reabriría esa puerta.',
      );
    }
  });

  group('la pila del foco se conserva por identidad', () {
    test(
        'selección → comparación → proveedor → cerrar → comparación → volver '
        '→ selección → salir → foco previo', () {
      // Se entra con una necesidad abierta.
      const previo = PurchaseNeedFocus('need-a');

      // 1. Armar canasta: recuerda de dónde salió.
      final seleccion = PurchaseBasketFocus.resolve(
        const <String>['need-a', 'need-b'],
        scenarios: false,
        from: previo,
      );
      expect(seleccion.isSelectingBasket, isTrue);
      expect(seleccion.showsScenarios, isFalse);
      expect(seleccion.needId, isNull, reason: 'una canasta no tiene una');

      // 2. Comparar.
      final comparacion = seleccion.comparing(true);
      expect(comparacion.showsScenarios, isTrue);
      expect(comparacion.needIds, seleccion.needIds);

      // 3. Abrir la ficha de un proveedor: se monta SOBRE la comparación.
      final conProveedor = PurchaseSupplierFocus(
        supplierId: 'sup-1',
        under: comparacion,
      );
      expect(conProveedor.openSupplierId, 'sup-1');
      // El trabajo de abajo sigue mandando el cromo.
      expect(conProveedor.showsScenarios, isTrue);
      expect(conProveedor.basketNeedIds, comparacion.needIds);

      // 4. Cerrar el proveedor devuelve exactamente la comparación.
      expect(conProveedor.under, same(comparacion));
      expect(conProveedor.parent, same(comparacion));

      // 5. Volver desde la comparación: la selección, con las mismas líneas.
      final volvio = comparacion.parent;
      expect(volvio, isA<PurchaseBasketFocus>());
      final seleccionDeVuelta = volvio! as PurchaseBasketFocus;
      expect(seleccionDeVuelta.showsScenarios, isFalse);
      expect(seleccionDeVuelta.needIds, comparacion.needIds);

      // 6. Salir de la canasta devuelve lo que había antes de armarla.
      expect(seleccionDeVuelta.parent, same(previo));
      expect(previo.parent, isNull,
          reason: 'la raíz no vuelve a ninguna parte');
    });

    test('precisar una línea desde la comparación vuelve a la comparación', () {
      final comparacion = PurchaseBasketFocus.resolve(
        const <String>['need-a', 'need-c'],
        scenarios: true,
      );
      final linea = PurchaseNeedFocus('need-c', from: comparacion);
      expect(linea.needId, 'need-c');
      expect(linea.showsScenarios, isFalse, reason: 'la superficie cambió');
      expect(linea.parent, same(comparacion));
    });

    test('una canasta de menos de dos no queda en una comparación imposible',
        () {
      final comparacion = PurchaseBasketFocus.resolve(
        const <String>['need-a', 'need-b'],
        scenarios: true,
      );
      final unaSola = comparacion.withNeeds(const <String>['need-a']);
      expect(unaSola.needIds, <String>{'need-a'});
      expect(
        unaSola.scenarios,
        isFalse,
        reason: 'la regla vive en el tipo, no en cada camino que quita líneas',
      );
      expect(unaSola.canCompare, isFalse);
    });

    test('la canasta no acepta más de ocho líneas', () {
      final grande = PurchaseBasketFocus.resolve(
        List<String>.generate(12, (index) => 'need-$index'),
        scenarios: true,
      );
      expect(grande.needIds, hasLength(PurchaseBasketFocus.basketMaxNeeds));
    });
  });
}
