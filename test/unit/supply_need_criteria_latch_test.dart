import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/services/supply_need_criteria_latch.dart';

/// El orden real después de precisar una ficha.
///
/// `_loadDecision` lanza la lectura de criterios **sin esperarla** y sigue; el
/// juicio del feed guardado corre en ese mismo tramo. Si ese juicio lee el
/// último valor pintado, lee la ficha ANTERIOR — y como no está vacía, el
/// atajo «pídela sólo si falta» tampoco la corrige. La lista quedaba rotulada
/// con la ficha vieja hasta cambiar de necesidad y volver.

SupplyNeedCriteria _criteria(String valve, {required int revision}) =>
    SupplyNeedCriteria(
      predicates: <SupplyNeedPredicate>[
        SupplyNeedPredicate(
          field: 'valve_type',
          operator: 'eq',
          values: <Object>[valve],
        ),
      ],
      categoryId: 'category-tubes',
      revisionNo: revision,
    );

void main() {
  test('espera la lectura en vuelo en vez de leer la ficha pintada', () async {
    final latch = SupplyNeedCriteriaLatch();
    final pending = Completer<SupplyNeedCriteria>();
    final painted = _criteria('presta', revision: 3);

    // El orden de la secuencia: se lanza la lectura, y el juicio pregunta
    // ANTES de que llegue.
    latch.publish('need-1', pending.future);
    var resolved = false;
    final asked = latch
        .resolve(
      needId: 'need-1',
      painted: painted,
      fetch: () async => fail('no puede volver a pedirla: ya está en vuelo'),
    )
        .then((value) {
      resolved = true;
      return value;
    });

    await Future<void>.delayed(Duration.zero);
    expect(resolved, isFalse, reason: 'no puede contestar con la ficha vieja');

    pending.complete(_criteria('schrader', revision: 4));
    final criteria = await asked;

    expect(criteria.revisionNo, 4);
    expect(criteria.predicates.single.values, <Object>['schrader']);
  });

  test('sin nada en vuelo se usa lo pintado, sin pedir de nuevo', () async {
    final latch = SupplyNeedCriteriaLatch();
    var fetched = 0;

    final criteria = await latch.resolve(
      needId: 'need-1',
      painted: _criteria('presta', revision: 3),
      fetch: () async {
        fetched++;
        return SupplyNeedCriteria.empty;
      },
    );

    expect(criteria.revisionNo, 3);
    expect(fetched, 0, reason: 'una ficha ya pintada no se vuelve a pedir');
  });

  test('una necesidad recién abierta sí la pide', () async {
    final latch = SupplyNeedCriteriaLatch();
    var fetched = 0;

    final criteria = await latch.resolve(
      needId: 'need-1',
      painted: SupplyNeedCriteria.empty,
      fetch: () async {
        fetched++;
        return _criteria('schrader', revision: 4);
      },
    );

    expect(fetched, 1);
    expect(criteria.revisionNo, 4);
  });

  test('la lectura en vuelo de OTRA necesidad no se espera', () async {
    final latch = SupplyNeedCriteriaLatch();
    // Quedó colgada al cambiar de necesidad: esperarla congelaría la nueva.
    latch.publish('need-1', Completer<SupplyNeedCriteria>().future);

    final criteria = await latch.resolve(
      needId: 'need-2',
      painted: _criteria('presta', revision: 9),
      fetch: () async => fail('lo pintado de esta necesidad ya sirve'),
    );

    expect(criteria.revisionNo, 9);
  });

  test('si la lectura falla no se inventa una ficha', () async {
    final latch = SupplyNeedCriteriaLatch();
    latch.publish(
      'need-1',
      Future<SupplyNeedCriteria>.error(StateError('sin red')),
    );

    final criteria = await latch.resolve(
      needId: 'need-1',
      painted: _criteria('presta', revision: 3),
      fetch: () async => fail('lo pintado sigue siendo lo último cierto'),
    );

    expect(criteria.revisionNo, 3);
  });
}
