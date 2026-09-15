import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/services/supply_need_effective_criteria.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';

/// **La barra no puede negar lo que el editor y el feed ya saben.**
///
/// Con la ficha efectiva en pie, `Criterios` abría en `700c` y el feed filtraba
/// por él, pero la ranura de resumen seguía decidiendo con la ficha **guardada**
/// y mostraba «Solicitud directa». Tres superficies del mismo módulo contando
/// dos historias distintas sobre la misma necesidad.

const _fields = <SupplierNeedSearchField>[
  SupplierNeedSearchField(
    key: 'wheel_size',
    label: 'Tamaño de rueda',
    dataType: 'single_select',
    allowedValues: <Object>['700c', '650b'],
  ),
];

const _guardada = SupplyNeedCriteria(
  predicates: <SupplyNeedPredicate>[],
  categoryId: 'cat-tubes',
  categoryPath: 'Componentes / Ruedas / Cámaras',
  revisionNo: 1,
  technicalFamily: 'tube',
);

void main() {
  test('la condición que gobierna la ranura cambia con la ficha efectiva', () {
    // Es literalmente lo que la barra evalúa: `isNotEmpty` sobre la ficha con
    // que decide. Con la guardada da falso —y de ahí salía «Solicitud
    // directa»—; con la efectiva da verdadero.
    expect(_guardada.isNotEmpty, isFalse);

    final efectiva = effectiveSupplyNeedCriteria(
      stored: _guardada,
      texts: <String>['Cámaras 700'],
      fields: _fields,
    );
    expect(efectiva.isNotEmpty, isTrue);
    expect(efectiva.predicates.single.field, 'wheel_size');

    // Y una petición que no declara nada deja la ranura como estaba: el origen
    // sigue siendo lo único cierto que queda por decir.
    expect(
      effectiveSupplyNeedCriteria(
        stored: _guardada,
        texts: <String>['Cámaras para el taller'],
        fields: _fields,
      ).isNotEmpty,
      isFalse,
    );
  });

  test('y la barra decide con esa ficha, no con la guardada', () {
    // El defecto no era el cálculo: era **quién** lo consultaba. Un guard sobre
    // la fuente es lo que impide que alguien la devuelva a `_needCriteria` sin
    // que nada se ponga rojo.
    final page = File(
      'lib/modules/purchases/pages/intelligent_purchasing_workspace_page.dart',
    ).readAsStringSync();
    final barra = page.substring(page.indexOf('Widget _buildNeedBar() {'));
    final cuerpo = barra.substring(0, barra.indexOf('editing:'));

    expect(cuerpo, contains('_effectiveNeedCriteria(need)'));
    expect(cuerpo, contains('criteriaSummary: efectiva.isNotEmpty'));
    expect(cuerpo, contains('_criteriaSummaryLine(efectiva)'));
    expect(cuerpo, contains('onOpenCriteria: efectiva.isNotEmpty'));
    expect(cuerpo, isNot(contains('_criteriaSummaryLine(_needCriteria)')));
    expect(cuerpo, isNot(contains('criteriaSummary: _needCriteria')));
    expect(cuerpo, isNot(contains('onOpenCriteria: _needCriteria')));

    // Y el editor recibe la misma, no una copia paralela.
    expect(page, contains('criteria: _effectiveNeedCriteria(need)'));
  });
}
