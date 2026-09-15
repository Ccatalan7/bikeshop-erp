import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

/// **La petición entera, no unas raíces.**
///
/// La extracción determinista filtra por largo, descarta dígitos y absorbe
/// sintagmas. Cada filtro existe por una razón, pero juntos hacen desaparecer
/// exigencias antes de que nadie las lea: `gel` por corta, una condición
/// compuesta por quedar pegada a otra. Al lector se le da el texto tal como lo
/// escribió el taller y lo que los criterios ya cubren.
const _fields = <SupplierNeedSearchField>[
  SupplierNeedSearchField(
    key: 'grip_material',
    label: 'Material del puño',
    dataType: 'single_select',
    allowedValues: <Object>['Goma', 'Silicona'],
  ),
];

const _peticion =
    'Puños de gel con fijación por doble abrazadera y sin tapones';

List<SupplyNeedUnmodelledRequirement> _verify(
  Object? response, {
  List<String>? rejected,
  String request = _peticion,
}) =>
    verifySupplyNeedDiscoveredRequirements(
      requestText: request,
      response: response,
      rejected: rejected,
    );

String _respuesta(List<Map<String, Object?>> requirements) =>
    jsonEncode(<String, Object?>{'requirements': requirements});

void main() {
  test('una exigencia corta sobrevive porque la cita la sostiene', () {
    // `gel` tiene tres letras: la vía determinista la descarta por corta.
    final encontradas = _verify(_respuesta(<Map<String, Object?>>[
      <String, Object?>{'quote': 'de gel', 'required': true, 'scope': <String>[]},
    ]));
    expect(encontradas.single.term, 'gel');
    expect(encontradas.single.label, 'de gel');
    expect(encontradas.single.affirmed, isTrue);
  });

  test('una condición compuesta conserva su alcance', () {
    final encontradas = _verify(
      _respuesta(<Map<String, Object?>>[
        <String, Object?>{
          'quote': 'sello de goma a ambos lados',
          'required': true,
          'scope': <String>['ambos', 'lados'],
        },
      ]),
      request: 'Rodamientos con sello de goma a ambos lados',
    );
    expect(encontradas.single.scope, containsAll(<String>['ambos', 'lados']));
  });

  test('lo pedido ausente conserva su polaridad', () {
    final encontradas = _verify(_respuesta(<Map<String, Object?>>[
      <String, Object?>{
        'quote': 'sin tapones',
        'required': false,
        'scope': <String>[],
      },
    ]));
    expect(encontradas.single.affirmed, isFalse);
    expect(encontradas.single.term, 'tapones');
  });

  test('una exigencia que la petición no dice se rechaza', () {
    final rechazos = <String>[];
    final encontradas = _verify(
      _respuesta(<Map<String, Object?>>[
        <String, Object?>{
          'quote': 'con anillo de aluminio',
          'required': true,
          'scope': <String>[],
        },
      ]),
      rejected: rechazos,
    );
    expect(encontradas, isEmpty);
    expect(rechazos.single, contains('no está en la petición'));
  });

  test('sin decir la polaridad no se acepta', () {
    final rechazos = <String>[];
    expect(
      _verify(
        _respuesta(<Map<String, Object?>>[
          <String, Object?>{'quote': 'de gel', 'scope': <String>[]},
        ]),
        rejected: rechazos,
      ),
      isEmpty,
    );
    expect(rechazos.single, contains('presente o ausente'));
  });

  test('el prompt lleva el texto original y lo que la ficha ya cubre', () {
    final prompt = buildSupplyNeedRequirementDiscoveryPrompt(
      requestText: _peticion,
      fields: _fields,
      askedValues: const <String, List<Object>>{
        'grip_material': <Object>['Goma'],
      },
    );
    expect(prompt, contains('de gel'),
        reason: 'la petición entera, sin filtrar ni acortar');
    expect(prompt, contains('Material del puño'));
    expect(prompt, contains('Goma'),
        reason: 'y lo ya representado, para que no lo repita');
  });

  for (final caso in <String, Object?>{
    'sin respuesta': null,
    'ilegible': 'esto no es json',
    'sin la lista': '{"otras":[]}',
    'lista de otro tipo': '{"requirements":{}}',
    'lista vacía': '{"requirements":[]}',
  }.entries) {
    test('${caso.key}: cero exigencias y ninguna excepción', () {
      expect(_verify(caso.value), isEmpty);
    });
  }
}
