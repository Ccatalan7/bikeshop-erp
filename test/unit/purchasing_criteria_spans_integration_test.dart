import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/services/supply_need_effective_criteria.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

import 'purchasing_independent_review_test.dart' as qa;

/// **La cadena completa, con el lector inyectado.**
///
/// La app arma la consulta del proveedor en un solo lugar: ficha efectiva,
/// lectura de tramos, plan y juicio del feed. Acá se recorre esa misma cadena
/// con un lector de mentira, para fijar que los tramos llegan hasta el
/// veredicto y que cada modo de fallo degrada donde corresponde.
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
  // Un campo de la ficha por el que nadie está preguntando: sirve para fijar
  // que no se le pide al lector cubrir lo que no es criterio.
  SupplierNeedSearchField(
    key: 'rotor_mount_type',
    label: 'Montaje del disco',
    dataType: 'single_select',
    allowedValues: <Object>['Centerlock', '6 pernos'],
  ),
];

const _peticion = 'Pastillas para frenos Shimano, de kevlar y sin aletas';

const _criterios = SupplyNeedCriteria(
  predicates: <SupplyNeedPredicate>[
    SupplyNeedPredicate(
      field: 'compound_type',
      operator: 'eq',
      values: <Object>['Orgánico'],
    ),
    SupplyNeedPredicate(
      field: 'pad_finned',
      operator: 'eq',
      values: <Object>[false],
    ),
  ],
  categoryId: 'cat-pastillas',
  categoryPath: 'Componentes / Frenos / Pastillas',
  revisionNo: 1,
);

String _respuesta(String quote, {String relation = 'same'}) =>
    jsonEncode(<String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'id': 'peticion',
          'facts': <Object?>[
            <String, Object?>{
              'field': 'compound_type',
              'value': 'Orgánico',
              'quote': quote,
              'relation': relation,
            },
          ],
        },
      ],
    });

/// El mismo orden que sigue la página al armar la consulta.
Future<SupplierNeedPortalMatch> _judge({
  required SupplierSpecExtractor extractor,
  List<String>? prompts,
}) async {
  final efectiva = effectiveSupplyNeedCriteria(
    stored: _criterios,
    texts: <String>[_peticion],
    fields: _fields,
    templateTechnicalFamily: 'brake_pad',
  );
  final askedValues = <String, List<Object>>{
    for (final predicate in efectiva.predicates)
      if (predicate.field.trim().isNotEmpty && predicate.values.isNotEmpty)
        predicate.field.trim(): predicate.values,
  };
  final tramos = await readSupplyNeedCriteriaSpansWithModel(
    requestText: _peticion,
    fields: _fields,
    askedValues: askedValues,
    extractor: (prompt) {
      prompts?.add(prompt);
      return extractor(prompt);
    },
  );
  final plan = buildSupplierNeedSearchPlan(
    request: SupplierNeedSearchRequest(
      needId: 'need-spans',
      description: _peticion,
      categoryId: efectiva.categoryId,
      categoryPath: efectiva.categoryPath,
      technicalFamily: 'brake_pad',
      fields: _fields,
      criteriaSpans: tramos.spans,
      predicates: <SupplierNeedSearchPredicate>[
        for (final predicate in efectiva.predicates)
          SupplierNeedSearchPredicate(
            field: predicate.field,
            operator: predicate.operator,
            values: predicate.values,
          ),
      ],
    ),
    adapter: qa.planFor('Pastillas').adapter,
    maxLength: 20,
  )!;
  return matchSupplierNeedCandidates(plan, <SupplierPortalCatalogCandidate>[
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
  ]).single;
}

void main() {
  setUp(resetSupplyNeedCriteriaSpansCache);

  test('se le pasa la petición del operador y el valor que pidió', () async {
    final prompts = <String>[];
    await _judge(
      extractor: (_) async => _respuesta('de kevlar'),
      prompts: prompts,
    );
    expect(prompts, hasLength(1));
    expect(prompts.single, contains('de kevlar'),
        reason: 'la petición entera, no un resumen');
    expect(prompts.single, contains('compound_type'));
    expect(prompts.single, contains('Orgánico'),
        reason: 'el valor pedido viaja: es la corroboración, no un adorno');
    expect(prompts.single, contains('relation'));
    expect(prompts.single, contains('pad_finned'),
        reason: 'los dos criterios vigentes viajan');
    expect(prompts.single, isNot(contains('rotor_mount_type')),
        reason: 'un campo sin criterio no se pregunta: el lector no puede '
            'cubrir lo que nadie pidió');
  });

  test('el tramo verificado llega hasta el veredicto', () async {
    final match = await _judge(extractor: (_) async => _respuesta('de kevlar'));
    expect(match.missingFields, contains(kRequestedPropertyField),
        reason: 'la fibra sigue sin demostrarse; el tramo sólo evita exigir la '
            'palabra dos veces');
    expect(match.provenFields, contains('compound_type'));
  });

  test('la misma petición no se lee dos veces', () async {
    final prompts = <String>[];
    await _judge(extractor: (_) async => _respuesta('de kevlar'), prompts: prompts);
    await _judge(extractor: (_) async => _respuesta('de kevlar'), prompts: prompts);
    expect(prompts, hasLength(1),
        reason: 'refinar vuelve a armar la consulta; el texto no cambió');
  });

  for (final caso in <String, SupplierSpecExtractor>{
    'sin modelo': (_) async => throw StateError('sin cuota'),
    'respuesta ilegible': (_) async => 'esto no es json',
    'respuesta vacía': (_) async => '{"rows":[]}',
    'cita inventada': (_) async => _respuesta('compuesto orgánico'),
    'familia más amplia': (_) async =>
        _respuesta('de kevlar', relation: 'narrower'),
  }.entries) {
    test('${caso.key}: la exigencia se conserva, no se inventa', () async {
      final match = await _judge(extractor: caso.value);
      expect(match.state, isNot(SupplierNeedMatchState.exact),
          reason: 'sin un tramo sostenido, «kevlar» sigue sin demostrarse');
      expect(match.missingFields, contains(kRequestedPropertyField));
      expect(match.provenFields, containsAll(<String>['compound_type', 'pad_finned']),
          reason: 'y lo que sí se demostró se conserva demostrado');
    });
  }

  test('lo que esta verificación NO impide, y hasta dónde llega el daño',
      () async {
    // **Un modelo puede responder `same` cuando no lo es**, y nada de lo que
    // verificamos lo detecta: la cita es real, el valor es el pedido, el tramo
    // no nombra otro campo. Por eso la frontera no la pone la detección sino el
    // producto: una equivalencia que sostiene sólo el modelo **remite** la
    // exigencia a su criterio y nunca la completa.
    final match = await _judge(extractor: (_) async => _respuesta('de kevlar'));
    expect(match.state, isNot(SupplierNeedMatchState.exact),
        reason: 'una inferencia no convierte una fibra no demostrada en '
            'cumplimiento completo');

    // **Pero el daño está acotado, y eso sí se puede demostrar.** Descargar un
    // tramo sólo remite la exigencia al criterio que la representa; NO puede
    // dar por demostrado ese criterio. Con la misma respuesta del modelo y una
    // fila que no prueba el compuesto, la fila sigue sin ser exacta.
    resetSupplyNeedCriteriaSpansCache();
    final efectiva = effectiveSupplyNeedCriteria(
      stored: _criterios,
      texts: <String>[_peticion],
      fields: _fields,
      templateTechnicalFamily: 'brake_pad',
    );
    final tramos = await readSupplyNeedCriteriaSpansWithModel(
      requestText: _peticion,
      fields: _fields,
      askedValues: <String, List<Object>>{
        for (final predicate in efectiva.predicates)
          predicate.field.trim(): predicate.values,
      },
      extractor: (_) async => _respuesta('de kevlar'),
    );
    expect(tramos.spans, isNotEmpty);
    final sinPrueba = matchSupplierNeedCandidates(
      buildSupplierNeedSearchPlan(
        request: SupplierNeedSearchRequest(
          needId: 'need-spans',
          description: _peticion,
          categoryId: efectiva.categoryId,
          categoryPath: efectiva.categoryPath,
          technicalFamily: 'brake_pad',
          fields: _fields,
          criteriaSpans: tramos.spans,
          predicates: <SupplierNeedSearchPredicate>[
            for (final predicate in efectiva.predicates)
              SupplierNeedSearchPredicate(
                field: predicate.field,
                operator: predicate.operator,
                values: predicate.values,
              ),
          ],
        ),
        adapter: qa.planFor('Pastillas').adapter,
        maxLength: 20,
      )!,
      <SupplierPortalCatalogCandidate>[
        const SupplierPortalCatalogCandidate(
          code: 'sin-compuesto',
          name: 'PASTILLA PARA FRENOS SHIMANO SIN ALETAS',
          rowText: 'PASTILLA PARA FRENOS SHIMANO SIN ALETAS',
          priceNet: 1000,
          technicalFacts: <String, Object?>{
            'pad_finned': false,
            kSupplierObjectHeadFact: 'PASTILLA',
            kSupplierFactQuotesFact: <String, Object?>{
              'pad_finned': 'SIN ALETAS',
            },
          },
        ),
      ],
    ).single;
    expect(sinPrueba.state, isNot(SupplierNeedMatchState.exact));
    expect(sinPrueba.missingFields, contains('compound_type'),
        reason: 'un tramo aceptado remite la exigencia al criterio; jamás lo '
            'da por demostrado');
  });
}
