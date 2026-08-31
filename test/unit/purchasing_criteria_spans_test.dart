import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

import 'purchasing_independent_review_test.dart' as qa;

/// **El modelo dice DÓNDE, no QUÉ.**
///
/// Los criterios salen de la petición, pero al guardarlos se pierde con qué
/// palabras los escribió el operador. Que el lector señale ese tramo es lo que
/// evita exigir la palabra literal por segunda vez; y que sólo pueda señalar un
/// criterio **que ya existe con ese mismo valor** es lo que impide que una
/// asociación equivocada borre un requisito real.
const _fields = <SupplierNeedSearchField>[
  SupplierNeedSearchField(
    key: 'compound_type',
    label: 'Compuesto',
    dataType: 'single_select',
    allowedValues: <Object>['Orgánico', 'Metálico'],
  ),
  SupplierNeedSearchField(
    key: 'pad_finned',
    label: 'Con Aletas de Calor',
    dataType: 'boolean',
  ),
];

/// **Una palabra que ningún diccionario nuestro conoce, a propósito.** Si el
/// caso se escribiera con «resina», la lista de equivalencias lo resolvería y
/// no demostraría nada nuevo. `kevlar` es vocabulario real de pastillas y no
/// está en ninguna lista: sólo el lector puede decir que ahí está escrito el
/// compuesto que el operador pidió.
const _peticion = 'Pastillas para frenos Shimano, de kevlar y sin aletas';

SupplyNeedCriteriaSpans _verify({
  required Object? response,
  Map<String, List<Object>> asked = const <String, List<Object>>{
    'compound_type': <Object>['Orgánico'],
  },
  String request = _peticion,
}) =>
    verifySupplyNeedCriteriaSpans(
      requestText: request,
      fields: _fields,
      askedValues: asked,
      response: response,
    );

Object _respuesta(String field, Object? value, String quote,
        {String relation = 'same'}) =>
    <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'id': 'peticion',
          'facts': <Object?>[
            <String, Object?>{
              'field': field,
              'value': value,
              'quote': quote,
              'relation': relation,
            },
          ],
        },
      ],
    };

void main() {
  test('señala el tramo cuando corrobora el criterio vigente', () {
    final leido = _verify(
      response: _respuesta('compound_type', 'Orgánico', 'de kevlar'),
    );
    expect(leido.spans, <String>['de kevlar']);
    expect(leido.rejected, isEmpty);
  });

  test('una cita que no está en la petición no vale', () {
    final leido = _verify(
      response: _respuesta('compound_type', 'Orgánico', 'compuesto orgánico'),
    );
    expect(leido.spans, isEmpty);
    expect(leido.rejected.single, contains('no está en la petición'));
  });

  test('no puede cubrir un campo que nadie está preguntando', () {
    final leido = _verify(
      response: _respuesta('pad_finned', false, 'sin aletas'),
    );
    expect(leido.spans, isEmpty);
    expect(leido.rejected.single, contains('nadie pregunta'));
  });

  test('una cita literal y un valor permitido no bastan: el valor tiene que '
      'ser el que el operador pidió', () {
    final leido = _verify(
      response: _respuesta('compound_type', 'Metálico', 'de kevlar'),
    );
    expect(leido.spans, isEmpty);
    expect(leido.rejected.single, contains('no es el que el operador pidió'));
  });

  test('un criterio que contradice la petición no queda cubierto', () {
    // El texto dice «sin aletas» y el criterio guardado quedó al revés. La
    // exigencia tiene que sobrevivir para poder contradecir una fila con
    // aletas, en vez de desaparecer sin que nadie lo note.
    final leido = _verify(
      asked: const <String, List<Object>>{'pad_finned': <Object>[true]},
      response: _respuesta('pad_finned', false, 'sin aletas'),
    );
    expect(leido.spans, isEmpty);
    expect(leido.rejected.single, contains('no es el que el operador pidió'));
  });

  test('el booleano se compara como booleano, no como texto', () {
    final leido = _verify(
      asked: const <String, List<Object>>{'pad_finned': <Object>[false]},
      response: _respuesta('pad_finned', 'false', 'sin aletas'),
    );
    expect(leido.spans, <String>['sin aletas']);
  });

  test('sin modelo no se cubre nada y nadie se cae', () {
    expect(_verify(response: null).spans, isEmpty);
    expect(_verify(response: 'no es json').spans, isEmpty);
    expect(_verify(response: '{"rows":[]}').spans, isEmpty);
  });

  test('el tramo remite la exigencia a su criterio, y no la completa', () {
    // Sin el tramo, «kevlar» es una exigencia que la fila no dice con esa
    // palabra y la deja pendiente. Con el tramo, se juzga como criterio.
    SupplierNeedPortalMatch judge({required List<String> spans}) =>
        matchSupplierNeedCandidates(
          buildSupplierNeedSearchPlan(
            request: SupplierNeedSearchRequest(
              needId: 'spans',
              description: _peticion,
              categoryId: 'brake-pads',
              categoryPath: 'Componentes / Frenos / Pastillas',
              technicalFamily: 'brake_pad',
              fields: _fields,
              predicates: const <SupplierNeedSearchPredicate>[
                SupplierNeedSearchPredicate(
                  field: 'compound_type',
                  operator: 'eq',
                  values: <Object>['Orgánico'],
                ),
                SupplierNeedSearchPredicate(
                  field: 'pad_finned',
                  operator: 'eq',
                  values: <Object>[false],
                ),
              ],
              criteriaSpans: spans,
            ),
            adapter: qa.planFor('Pastillas').adapter,
            maxLength: 20,
          )!,
          <SupplierPortalCatalogCandidate>[
            const SupplierPortalCatalogCandidate(
              code: 'fila',
              name: 'PASTILLA ORGANICA PARA FRENOS SHIMANO SIN ALETAS',
              rowText: 'PASTILLA ORGANICA PARA FRENOS SHIMANO SIN ALETAS',
              priceNet: 1000,
              technicalFacts: <String, Object?>{
                'compound_type': 'Orgánico',
                'pad_finned': false,
                kSupplierObjectHeadFact: 'PASTILLA',
                kSupplierFactQuotesFact: <String, Object?>{
                  'compound_type': 'ORGANICA',
                  'pad_finned': 'SIN ALETAS',
                },
              },
            ),
          ],
        ).single;

    expect(
      judge(spans: const <String>[]).missingFields,
      contains(kRequestedPropertyField),
      reason: 'sin el tramo, «kevlar» se exige literal y queda pendiente',
    );
    // **La frontera del producto.** Con el tramo, «kevlar» deja de exigirse
    // como palabra suelta —se juzga el criterio que la representa—, pero la
    // fibra sigue sin demostrarla nadie: una equivalencia que sostiene sólo el
    // modelo puede recomendar, no declarar cumplimiento completo.
    final conTramo = judge(spans: const <String>['de kevlar']);
    expect(conTramo.state, isNot(SupplierNeedMatchState.exact));
    expect(conTramo.missingFields, contains(kRequestedPropertyField));
    expect(
      conTramo.provenFields,
      containsAll(<String>['compound_type', 'pad_finned']),
      reason: 'y los criterios sí demostrados se conservan demostrados',
    );
  });

  test('una cita correcta de OTRO campo no descarga éste', () {
    // Los tres controles anteriores lo aceptaban: «sin aletas» está en la
    // petición y `Orgánico` es el valor pedido. Pero la cita nombra el campo de
    // las aletas, así que descargarla habría borrado esa exigencia.
    final leido = _verify(
      response: _respuesta('compound_type', 'Orgánico', 'sin aletas'),
    );
    expect(leido.spans, isEmpty);
    expect(leido.rejected.single, contains('nombra el campo'));
  });

  test('una familia más amplia no demuestra lo específico', () {
    // `Orgánico` contiene al kevlar, pero no lo dice. Descargar el tramo
    // dejaría el compuesto demostrado y la fibra sin demostrar, con la fila
    // presentada como cumplimiento completo.
    final leido = _verify(
      response: _respuesta(
        'compound_type',
        'Orgánico',
        'de kevlar',
        relation: 'narrower',
      ),
    );
    expect(leido.spans, isEmpty);
    expect(leido.rejected.single, contains('más amplio'));
  });

  test('sin respuesta sobre el alcance del valor, no se descarga', () {
    final leido = _verify(
      response: _respuesta('compound_type', 'Orgánico', 'de kevlar',
          relation: ''),
    );
    expect(leido.spans, isEmpty);
    expect(leido.rejected.single, contains('no dice si'));
  });
}
