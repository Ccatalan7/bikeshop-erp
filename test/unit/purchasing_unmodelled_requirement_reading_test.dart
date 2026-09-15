import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

import 'purchasing_independent_review_test.dart' as qa;

/// **Lo que la ficha no sabe nombrar, el proveedor a veces sí lo dice.**
///
/// «A ambos lados» y «de kevlar» no son campos de ninguna plantilla, así que
/// hoy sólo se prueban si la palabra aparece literal en la fila. Preguntárselo
/// al lector convierte un pendiente perpetuo en un veredicto — pero con una
/// asimetría deliberada: puede descartar con evidencia, no puede completar.
const _rows = <SupplierSpecExtractionRow>[
  SupplierSpecExtractionRow(
    id: 'abierto',
    text: 'RODAMIENTO PARA MAZA 6902 ABIERTO SIN SELLOS',
  ),
  SupplierSpecExtractionRow(
    id: 'doble',
    text: 'RODAMIENTO 6902 2RS DOBLE SELLO DE GOMA',
  ),
];

Object _respuesta(List<Map<String, Object?>> requirements, {String id = 'doble'}) =>
    jsonEncode(<String, Object?>{
      'rows': <Object?>[
        <String, Object?>{'id': id, 'requirements': requirements},
      ],
    });

Map<String, Map<String, SupplierRequirementFinding>> _leer(
  Object? response, {
  List<String>? rejected,
}) =>
    verifySupplierRequirementReadings(
      rows: _rows,
      requirements: const <SupplyNeedUnmodelledRequirement>[
        SupplyNeedUnmodelledRequirement(
          term: 'sell',
          affirmed: true,
          scope: <String>[],
        ),
      ],
      response: response,
      rejected: rejected,
    );

void main() {
  test('la petición publica lo que ninguna ficha puede expresar', () {
    final plan = buildSupplierNeedSearchPlan(
      request: const SupplierNeedSearchRequest(
        needId: 'rodamientos',
        description:
            'Rodamientos sellados 6902 para mazas con sello de goma a ambos lados',
        categoryId: 'cat-rodamientos',
        categoryPath: 'Componentes / Ruedas / Rodamientos',
        technicalFamily: 'bearing',
        fields: <SupplierNeedSearchField>[
          SupplierNeedSearchField(
            key: 'bearing_application',
            label: 'Aplicación del Rodamiento',
            dataType: 'single_select',
            allowedValues: <Object>['Maza', 'Dirección'],
          ),
        ],
        predicates: <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'bearing_application',
            operator: 'eq',
            values: <Object>['Maza'],
          ),
        ],
      ),
      adapter: qa.planFor('Pastillas').adapter,
      maxLength: 20,
    )!;
    final exigencias = supplyNeedUnmodelledRequirements(plan);
    // «Rodamientos sellados» y «sello de goma a ambos lados» son dos
    // exigencias distintas del mismo texto: la segunda lleva su alcance.
    expect(exigencias.map((r) => r.term), containsAll(<String>['sell', 'sello']));
    expect(exigencias.every((r) => r.affirmed), isTrue);
    final conAlcance = exigencias.firstWhere((r) => r.scope.isNotEmpty);
    expect(conAlcance.scope, containsAll(<String>['ambo', 'lado']),
        reason: 'el alcance viaja con la exigencia: no es lo mismo un sello '
            'que un sello a ambos lados');
  });

  test('el proveedor puede contradecirla, y con su propia cita', () {
    final lecturas = _leer(_respuesta(
      <Map<String, Object?>>[
        <String, Object?>{
          'term': 'sell',
          'meets': false,
          'quote': 'ABIERTO SIN SELLOS',
        },
      ],
      id: 'abierto',
    ));
    expect(lecturas['abierto']!['sell']!.reading,
        SupplierRequirementReading.contradicts);
  });

  test('cumplirla es una recomendación, nunca un cumplimiento', () {
    final lecturas = _leer(_respuesta(<Map<String, Object?>>[
      <String, Object?>{
        'term': 'sell',
        'meets': true,
        'quote': 'DOBLE SELLO DE GOMA',
      },
    ]));
    expect(lecturas['doble']!['sell']!.reading,
        SupplierRequirementReading.suggests,
        reason: 'que el modelo lo concluya no lo demuestra');
  });

  test('una cita que no está en esa fila no vale', () {
    final rechazos = <String>[];
    final lecturas = _leer(
      _respuesta(<Map<String, Object?>>[
        <String, Object?>{
          'term': 'sell',
          'meets': false,
          'quote': 'SIN SELLOS',
        },
      ]),
      rejected: rechazos,
    );
    expect(lecturas, isEmpty,
        reason: 'ese texto es de la otra fila; acá sería un rechazo inventado');
    expect(rechazos.single, contains('no está en la fila'));
  });

  test('un negativo que el texto citado no sostiene es duda, no descarte', () {
    // La cita es real y habla de la pieza, pero no dice nada de sellos. Que el
    // modelo concluya que no cumple no puede borrar una fila que quizás sirve.
    final lecturas = _leer(_respuesta(<Map<String, Object?>>[
      <String, Object?>{
        'term': 'sell',
        'meets': false,
        'quote': 'RODAMIENTO 6902',
      },
    ]));
    expect(lecturas['doble']!['sell']!.reading,
        SupplierRequirementReading.suggestsAgainst);
  });

  test('una exigencia que nadie pidió no se lee', () {
    final rechazos = <String>[];
    final lecturas = _leer(
      _respuesta(<Map<String, Object?>>[
        <String, Object?>{
          'term': 'cromado',
          'meets': false,
          'quote': 'DOBLE SELLO DE GOMA',
        },
      ]),
      rejected: rechazos,
    );
    expect(lecturas, isEmpty);
    expect(rechazos.single, contains('no pedida'));
  });

  for (final caso in <String, Object?>{
    'sin respuesta': null,
    'ilegible': 'esto no es json',
    'rows como objeto': '{"rows":{"id":"doble"}}',
    'requirements como objeto': '{"rows":[{"id":"doble","requirements":{}}]}',
    'fila ajena': '{"rows":[{"id":"otra","requirements":[]}]}',
    'meets ausente': '{"rows":[{"id":"doble","requirements":[{"term":"sell"}]}]}',
  }.entries) {
    test('${caso.key}: cero lecturas y ninguna excepción', () {
      expect(_leer(caso.value), isEmpty);
    });
  }
}
