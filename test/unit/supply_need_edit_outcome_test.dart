import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supply_need_refinement_editor.dart';

/// Precisar la ficha no puede borrar lo que el formulario no muestra.
///
/// Es el mismo defecto que teníamos con la cantidad, un nivel más adentro: el
/// servidor reemplaza los predicados técnicos con lo que se le mande, así que
/// todo criterio que el editor no dibuje y no arrastre desaparece en silencio.

SupplyNeedPredicate _predicate(String field, Object value) =>
    SupplyNeedPredicate(
      field: field,
      operator: 'eq',
      values: <Object>[value],
    );

void main() {
  group('igualdad semántica de la ficha', () {
    test('un entero del JSON y el mismo número del formulario son iguales', () {
      // `29` llega del JSON como entero y vuelve del TextField como `29.0`.
      // Comparados como texto son distintos; como medida son el mismo.
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[_predicate('spoke_holes', 29)],
          <SupplyNeedPredicate>[_predicate('spoke_holes', 29.0)],
        ),
        isTrue,
      );
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[_predicate('spoke_holes', 29)],
          <SupplyNeedPredicate>[_predicate('spoke_holes', '29')],
        ),
        isTrue,
      );
    });

    test('un cambio real de número sigue siendo un cambio', () {
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[_predicate('spoke_holes', 29)],
          <SupplyNeedPredicate>[_predicate('spoke_holes', 32)],
        ),
        isFalse,
      );
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[_predicate('width_mm', 2.0)],
          <SupplyNeedPredicate>[_predicate('width_mm', 2.5)],
        ),
        isFalse,
      );
    });

    test('dos identificadores textuales distintos NO son el mismo número', () {
      // El registro guarda estos campos unas veces como número y otras como
      // cadena. Canonicalizar cada valor por su cuenta convertía «001» en 1 y
      // dejaba pasar una edición real como si no existiera.
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[_predicate('spoke_holes', '001')],
          <SupplyNeedPredicate>[_predicate('spoke_holes', '1')],
        ),
        isFalse,
      );
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[_predicate('valve_length_mm', '48')],
          <SupplyNeedPredicate>[_predicate('valve_length_mm', '48.0')],
        ),
        isFalse,
        reason: 'entre cadenas manda el texto, no la aritmética',
      );
      // Y con un número de un lado sí se parsea: es el ida y vuelta del
      // formulario, no una comparación entre dos identificadores.
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[_predicate('spoke_holes', 1)],
          <SupplyNeedPredicate>[_predicate('spoke_holes', '001')],
        ),
        isTrue,
      );
    });

    test('el orden de los valores importa en un rango', () {
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[
            const SupplyNeedPredicate(
              field: 'width_mm',
              operator: 'between',
              values: <Object>[2, 5],
            ),
          ],
          <SupplyNeedPredicate>[
            const SupplyNeedPredicate(
              field: 'width_mm',
              operator: 'between',
              values: <Object>[5, 2],
            ),
          ],
        ),
        isFalse,
      );
    });

    test('el operador es parte de la ficha', () {
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[
            const SupplyNeedPredicate(
              field: 'width_mm',
              operator: 'eq',
              values: <Object>[2],
            ),
          ],
          <SupplyNeedPredicate>[
            const SupplyNeedPredicate(
              field: 'width_mm',
              operator: 'gte',
              values: <Object>[2],
            ),
          ],
        ),
        isFalse,
      );
    });

    test('lo que no es número se compara tal cual', () {
      // Aflojar esto escondería una edición real.
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[_predicate('wheel_size', '700c')],
          <SupplyNeedPredicate>[_predicate('wheel_size', '700C')],
        ),
        isFalse,
      );
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[_predicate('wheel_size', '700c')],
          <SupplyNeedPredicate>[_predicate('wheel_size', '700c')],
        ),
        isTrue,
      );
    });

    test('un campo repetido a un solo lado no puede pasar por igual', () {
      // `left = [a, a]` contra `right = [a, b]`: mismo largo, `right` único, y
      // los dos `a` resolvían al mismo par mientras `b` no se comparaba nunca.
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[
            _predicate('wheel_size', '700c'),
            _predicate('wheel_size', '700c'),
          ],
          <SupplyNeedPredicate>[
            _predicate('wheel_size', '700c'),
            _predicate('valve_type', 'presta'),
          ],
        ),
        isFalse,
      );
      // Y al revés, para que la comprobación no dependa del orden en que se
      // reciban las dos listas.
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[
            _predicate('wheel_size', '700c'),
            _predicate('valve_type', 'presta'),
          ],
          <SupplyNeedPredicate>[
            _predicate('wheel_size', '700c'),
            _predicate('wheel_size', '700c'),
          ],
        ),
        isFalse,
      );
      // Un duplicado idéntico en ambos lados tampoco se declara igual: no se
      // puede afirmar sobre una ficha que ya viene mal formada.
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[
            _predicate('wheel_size', '700c'),
            _predicate('wheel_size', '700c'),
          ],
          <SupplyNeedPredicate>[
            _predicate('wheel_size', '700c'),
            _predicate('wheel_size', '700c'),
          ],
        ),
        isFalse,
      );
    });

    test('agregar o quitar un criterio es un cambio', () {
      expect(
        supplyNeedPredicatesEqual(
          <SupplyNeedPredicate>[_predicate('wheel_size', '700c')],
          <SupplyNeedPredicate>[
            _predicate('wheel_size', '700c'),
            _predicate('valve_type', 'presta'),
          ],
        ),
        isFalse,
      );
    });
  });

  test('un criterio que el template no expone viaja igual', () {
    final result = carryForwardUnexpressedPredicates(
      drafted: <SupplyNeedPredicate>[_predicate('valve_type', 'presta')],
      current: <SupplyNeedPredicate>[
        _predicate('wheel_size', '700c'),
        _predicate('valve_type', 'schrader'),
      ],
      expressibleFields: <String>{'valve_type'},
    );

    expect(
      result.map((predicate) => predicate.field),
      containsAll(<String>['valve_type', 'wheel_size']),
    );
    // El que sí se puede editar toma el valor nuevo, no el anterior.
    expect(
      result
          .firstWhere((predicate) => predicate.field == 'valve_type')
          .values
          .single,
      'presta',
    );
  });

  test('quitar un criterio que el formulario SÍ muestra sí lo quita', () {
    // Vaciar un campo visible es una decisión del operador, no una omisión.
    final result = carryForwardUnexpressedPredicates(
      drafted: const <SupplyNeedPredicate>[],
      current: <SupplyNeedPredicate>[_predicate('valve_type', 'presta')],
      expressibleFields: <String>{'valve_type'},
    );

    expect(result, isEmpty);
  });

  test('no duplica un campo que ya venía dibujado', () {
    final result = carryForwardUnexpressedPredicates(
      drafted: <SupplyNeedPredicate>[_predicate('wheel_size', '650b')],
      current: <SupplyNeedPredicate>[_predicate('wheel_size', '700c')],
      expressibleFields: const <String>{},
    );

    expect(result.length, 1);
    expect(result.single.values.single, '650b');
  });
}
