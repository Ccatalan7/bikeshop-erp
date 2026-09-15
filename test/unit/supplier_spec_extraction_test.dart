import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

/// Un solo mecanismo para todos los catálogos, y una compuerta que no confía.
///
/// Las filas son reales, de tres proveedores que escriben la misma válvula de
/// tres formas distintas. Lo que se prueba NO es que el modelo acierte —eso lo
/// decide el modelo— sino que **nada entre sin respaldo en el texto**: una
/// alucinación, un valor fuera del dominio o una lectura contradictoria se
/// caen acá, sin red y sin modelo.

const _fields = <SupplierNeedSearchField>[
  SupplierNeedSearchField(
    key: 'valve_type',
    label: 'Tipo de válvula',
    dataType: 'single_select',
    allowedValues: <Object>['presta', 'schrader', 'dunlop'],
  ),
  SupplierNeedSearchField(
    key: 'wheel_size',
    label: 'Tamaño de rueda',
    dataType: 'number',
    unit: 'mm',
  ),
];

/// Las tres escrituras reales del mismo dato, más las dos trampas.
const _rows = <SupplierSpecExtractionRow>[
  SupplierSpecExtractionRow(
    id: '10663',
    text: 'CAMARA 700 X 28/38C V/AUTO 48MM (28-5/8-1/4)',
  ),
  SupplierSpecExtractionRow(
    id: 'IM07371',
    text: 'CAMARA 26X1.75 2.20 VAL. AUTO 48MM. BUTYL RITECH',
  ),
  SupplierSpecExtractionRow(
    id: 'CM-000251',
    text: 'CAMARA ARO 700x35/38C A/V 48MM',
  ),
  SupplierSpecExtractionRow(
    id: '13164',
    text: 'CAMARA 700 X 25/38C V/DUNLOP 35MM AUTOMATICA',
  ),
  SupplierSpecExtractionRow(
    id: '18180',
    text: 'CAMARA SCOOTER 8-1/2 X 2 50/76-6.1 VALVULA SCHRADE',
  ),
];

Map<String, Object?> _row(String id, List<Map<String, Object?>> facts) =>
    <String, Object?>{'id': id, 'facts': facts};

Map<String, Object?> _fact(String field, Object value, String quote) =>
    <String, Object?>{'field': field, 'value': value, 'quote': quote};

SupplierSpecExtractionResult _verify(List<Map<String, Object?>> rows) =>
    verifySupplierSpecExtraction(
      fields: _fields,
      rows: _rows,
      response: <String, Object?>{'rows': rows},
    );

void main() {
  setUp(resetSupplierSpecReadingsCache);

  group('el contrato que se le manda al modelo', () {
    test('enumera el dominio, no formas de escribir', () {
      final prompt = buildSupplierSpecExtractionPrompt(
        fields: _fields,
        rows: _rows,
      );

      // Lo nuestro —los campos y sus valores— sí va en la instrucción.
      expect(prompt, contains('valve_type'));
      expect(prompt, contains('dunlop'));
      // Las filas van tal cual: son el material a leer.
      expect(prompt, contains('CAMARA 700 X 28/38C V/AUTO 48MM'));
      // Y se exige la cita, que es la compuerta.
      expect(prompt, contains('quote'));

      // **La instrucción no enseña a escribir una válvula.** Eso es lo que no
      // queremos mantener: si acá apareciera una lista de formas, cada
      // catálogo nuevo volvería a exigir una edición a mano.
      final instrucciones = prompt.substring(0, prompt.indexOf('Filas:'));
      for (final forma in <String>['V/AUTO', 'VAL.', 'A/V', 'V/FRANCESA']) {
        expect(
          instrucciones,
          isNot(contains(forma)),
          reason: 'la instrucción no puede enumerar «\$forma»',
        );
      }
    });
  });

  group('las tres escrituras entran por el mismo camino', () {
    test('`V/AUTO`, `VAL. AUTO` y `A/V` sin una regla por catálogo', () {
      final result = _verify(<Map<String, Object?>>[
        _row('10663', [_fact('valve_type', 'schrader', 'V/AUTO')]),
        _row('IM07371', [_fact('valve_type', 'schrader', 'VAL. AUTO')]),
        _row('CM-000251', [_fact('valve_type', 'schrader', 'A/V')]),
        _row('13164', [_fact('valve_type', 'dunlop', 'V/DUNLOP')]),
      ]);

      expect(result.factsFor('10663')['valve_type'], 'schrader');
      expect(result.factsFor('IM07371')['valve_type'], 'schrader');
      expect(result.factsFor('CM-000251')['valve_type'], 'schrader');
      expect(result.factsFor('13164')['valve_type'], 'dunlop');
      expect(result.rejected, isEmpty);
    });

    test('la cita queda para que el operador la juzgue', () {
      final result = _verify(<Map<String, Object?>>[
        _row('13164', [_fact('valve_type', 'dunlop', 'V/DUNLOP')]),
      ]);
      expect(result.readings['13164']!['valve_type']!.quote, 'V/DUNLOP');
    });

    test('una medida numérica también necesita respaldo', () {
      final result = _verify(<Map<String, Object?>>[
        _row('18180', [_fact('wheel_size', 8.5, '8-1/2 X 2')]),
      ]);
      expect(result.factsFor('18180')['wheel_size'], 8.5);
    });
  });

  group('el modelo nombra la pieza, y también hay que probarlo', () {
    SupplierSpecExtractionResult objeto(String head, Object? esLaBuscada) =>
        verifySupplierSpecExtraction(
          fields: _fields,
          rows: _rows,
          response: <String, Object?>{
            'rows': <Object?>[
              <String, Object?>{
                'id': '18180',
                'object': <String, Object?>{
                  'head': head,
                  'is_requested': esLaBuscada,
                },
                'facts': const <Object?>[],
              },
            ],
          },
        );

    test('el sustantivo copiado del texto se acepta', () {
      final result = objeto('CAMARA SCOOTER', false);
      expect(result.objects['18180']!.head, 'CAMARA SCOOTER');
      expect(result.objects['18180']!.isRequested, isFalse);
      // Y viaja con la fila, para que sobreviva al re-juicio y al guardado.
      final facts = result.factsFor('18180');
      expect(facts[kSupplierObjectHeadFact], 'CAMARA SCOOTER');
      expect(facts[kSupplierObjectIsRequestedFact], isFalse);
    });

    test('un sustantivo que no está en la fila se descarta', () {
      // La puerta de siempre: si el modelo inventa la pieza, no entra. Sin
      // esto, «esto es un motor de centro» sería indesmentible.
      final result = objeto('MOTOR DE CENTRO', true);
      expect(result.objects, isEmpty);
      expect(result.rejected.single, contains('no está en la fila'));
    });

    test('sin decir si es la buscada, no sirve de nada', () {
      final result = objeto('CAMARA SCOOTER', null);
      expect(result.objects, isEmpty);
      expect(result.rejected.single, contains('no dice si es la pieza'));
    });

    test('la pieza buscada va en la instrucción', () {
      final prompt = buildSupplierSpecExtractionPrompt(
        fields: _fields,
        rows: _rows,
        requestedObject: 'Motor de centro sellado con eje cuadrado',
      );
      expect(prompt, contains('Motor de centro sellado con eje cuadrado'));
      expect(prompt, contains('is_requested'));
    });
  });

  group('la compuerta: nada entra sin respaldo en el texto', () {
    test('una cita que no está en la fila se descarta', () {
      // El caso que hace peligroso a un modelo: completar la ficha con lo que
      // parece razonable. `13164` dice DUNLOP, no FRANCESA.
      final result = _verify(<Map<String, Object?>>[
        _row('13164', [_fact('valve_type', 'presta', 'V/FRANCESA')]),
      ]);

      expect(result.factsFor('13164'), isEmpty);
      expect(result.rejected.single, contains('la cita no está en la fila'));
    });

    test('un dato sin cita se descarta', () {
      final result = _verify(<Map<String, Object?>>[
        _row('10663', [_fact('valve_type', 'schrader', '')]),
      ]);
      expect(result.factsFor('10663'), isEmpty);
    });

    test('un valor fuera del dominio se descarta', () {
      // `AUTOMATICA` sí está en el texto, pero no es un tipo de válvula.
      final result = _verify(<Map<String, Object?>>[
        _row('13164', [_fact('valve_type', 'automatica', 'AUTOMATICA')]),
      ]);
      expect(result.factsFor('13164'), isEmpty);
      expect(result.rejected.single, contains('no es un valor permitido'));
    });

    test('un campo que nadie preguntó se descarta', () {
      final result = _verify(<Map<String, Object?>>[
        _row('10663', [_fact('material', 'butilo', 'CAMARA')]),
      ]);
      expect(result.factsFor('10663'), isEmpty);
      expect(result.rejected.single, contains('campo no pedido'));
    });

    test('una fila que no mandamos se descarta', () {
      final result = _verify(<Map<String, Object?>>[
        _row('99999', [_fact('valve_type', 'presta', 'V/FRANCESA')]),
      ]);
      expect(result.readings, isEmpty);
      expect(result.rejected.single, contains('fila desconocida'));
    });

    test('dos lecturas que se contradicen se anulan las dos', () {
      // Ambiguo no es lo mismo que desconocido, y ninguno se adivina.
      final result = _verify(<Map<String, Object?>>[
        _row('10663', [
          _fact('valve_type', 'schrader', 'V/AUTO'),
          _fact('valve_type', 'presta', '28-5/8-1/4'),
        ]),
      ]);
      expect(result.factsFor('10663'), isEmpty);
      expect(result.rejected.single, contains('se contradicen'));
    });

    test('lo que no vuelve, no consta: la ausencia se conserva', () {
      // Ninguna fila trae `wheel_size`. No se rellena con nada.
      final result = _verify(<Map<String, Object?>>[
        _row('10663', [_fact('valve_type', 'schrader', 'V/AUTO')]),
      ]);
      expect(result.factsFor('10663').containsKey('wheel_size'), isFalse);
      expect(result.factsFor('18180'), isEmpty);
    });

    test('una respuesta ilegible no produce ningún hecho', () {
      final result = verifySupplierSpecExtraction(
        fields: _fields,
        rows: _rows,
        response: 'el modelo se puso a conversar',
      );
      expect(result.readings, isEmpty);
      expect(result.rejected, isNotEmpty);
    });
  });

  group('cubre lo que ninguna regla anticipó', () {
    // Un proveedor que escribe la válvula SIN el marcador que conocemos. Es
    // exactamente el caso que hoy entra mudo y por lo tanto «cumpliendo».
    const inedito = SupplierPortalCatalogCandidate(
      code: 'X-1',
      name: 'CAMARA 700X28C TIPO FRANCES LARGO 60MM',
    );

    test('sin regla nueva, el modelo lo lee y la compuerta lo acepta',
        () async {
      final leidos = await readSupplierSpecsWithModel(
        fields: _fields,
        candidates: const <SupplierPortalCatalogCandidate>[inedito],
        extractor: (prompt) async {
          expect(prompt, contains('TIPO FRANCES'));
          return <String, Object?>{
            'rows': <Object?>[
              _row('X-1', [_fact('valve_type', 'presta', 'TIPO FRANCES')]),
            ],
          };
        },
      );

      expect(leidos.single.technicalFacts['valve_type'], 'presta');
    });

    test('un modelo lento no cuelga la búsqueda', () async {
      // **Atrapar la excepción no basta.** Con el Edge Runtime degradado la
      // llamada no falla: se demora, y con reintentos deja la búsqueda entera
      // con «Buscando…» en pantalla y el portal ya recorrido. Pasó de verdad
      // el 2026-08-30: la enumeración terminó y siguió esperando minutos por
      // una lectura que es opcional.
      final reloj = Stopwatch()..start();
      final leidos = await readSupplierSpecsWithModel(
        fields: _fields,
        candidates: const <SupplierPortalCatalogCandidate>[inedito],
        extractor: (_) => Completer<Object?>().future,
        deadline: const Duration(milliseconds: 120),
      );
      reloj.stop();

      expect(leidos.single.technicalFacts, isEmpty);
      expect(reloj.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('las mismas filas no se preguntan dos veces', () async {
      // El buscador prueba varios términos contra el MISMO nodo del catálogo:
      // cada intento devolvía las mismas filas y pagaba otra llamada de 20 s.
      var llamadas = 0;
      Future<List<SupplierPortalCatalogCandidate>> leer() =>
          readSupplierSpecsWithModel(
            fields: _fields,
            candidates: const <SupplierPortalCatalogCandidate>[inedito],
            extractor: (_) async {
              llamadas++;
              return <String, Object?>{
                'rows': <Object?>[
                  _row('X-1', [_fact('valve_type', 'presta', 'TIPO FRANCES')]),
                ],
              };
            },
          );

      final primera = await leer();
      final segunda = await leer();

      // Y el reuso no depende del orden: el mismo lote al revés es el mismo
      // lote. Con la llave atada al texto del prompt, esto volvía a llamar.
      final tercera = await readSupplierSpecsWithModel(
        fields: _fields.reversed.toList(),
        candidates: const <SupplierPortalCatalogCandidate>[inedito],
        extractor: (_) async => fail('el mismo lote no se vuelve a preguntar'),
      );
      expect(tercera.single.technicalFacts['valve_type'], 'presta');

      expect(llamadas, 1, reason: 'el segundo intento reusa la lectura');
      expect(primera.single.technicalFacts['valve_type'], 'presta');
      expect(segunda.single.technicalFacts['valve_type'], 'presta');
    });

    test('si el modelo se cae, la búsqueda sigue con lo que había', () async {
      // Cuota agotada, red, o el proveedor de IA abajo: se lee menos, nunca
      // se rompe la búsqueda ni se inventa un dato.
      final leidos = await readSupplierSpecsWithModel(
        fields: _fields,
        candidates: const <SupplierPortalCatalogCandidate>[inedito],
        extractor: (_) async => throw StateError('cuota agotada'),
      );

      expect(leidos.single.technicalFacts, isEmpty);
      expect(leidos.single.name, inedito.name, reason: 'la fila queda intacta');
    });

    test('lo inventado tampoco pasa por este camino', () async {
      final rechazos = <String>[];
      final leidos = await readSupplierSpecsWithModel(
        fields: _fields,
        candidates: const <SupplierPortalCatalogCandidate>[inedito],
        extractor: (_) async => <String, Object?>{
          'rows': <Object?>[
            _row('X-1', [_fact('valve_type', 'schrader', 'V/AUTO')]),
          ],
        },
        onRejected: rechazos.addAll,
      );

      expect(leidos.single.technicalFacts, isEmpty);
      expect(rechazos.single, contains('la cita no está en la fila'));
    });
  });

  group('el veredicto lo sigue calculando el código', () {
    test('los hechos leídos entran al calce sin tocar nada más', () {
      // El modelo lee; `tallySupplierNeedMatchesUnder` juzga. Con válvula
      // americana: la Dunlop contradice y la muda queda por verificar.
      final result = _verify(<Map<String, Object?>>[
        _row('10663', [_fact('valve_type', 'schrader', 'V/AUTO')]),
        _row('13164', [_fact('valve_type', 'dunlop', 'V/DUNLOP')]),
      ]);

      final matches = <SupplierNeedPortalMatch>[
        for (final row in <String>['10663', '13164', '18180'])
          SupplierNeedPortalMatch(
            candidate: SupplierPortalCatalogCandidate(code: row, name: row),
            state: SupplierNeedMatchState.possible,
            provenFields: const <String>['product_family'],
            missingFields: const <String>[],
            conflictingFields: const <String>[],
            observedFacts: result.factsFor(row),
          ),
      ];

      final tally = tallySupplierNeedMatchesUnder(
        matches: matches,
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'valve_type',
            operator: 'eq',
            values: <Object>['schrader'],
          ),
        ],
        fields: _fields,
      );

      expect(tally.confirmed, 1, reason: 'sólo la que el texto respalda');
      expect(tally.unverified, 1, reason: 'la que no dice nada');
    });
  });
}
