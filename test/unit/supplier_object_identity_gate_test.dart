import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

/// **Falta de prueba de calce no es «otra clase de pieza».**
///
/// Corrida real de RBX del 2026-08-31, recibo
/// `22006b7e-8f8a-406f-a71d-af988d662a75`: diez filas, todas con
/// `supplier_object_head = PASTILLA FRENO DISCO` y `matches_requested_object =
/// false`. El lector recibía la petición completa como «pieza buscada», así que
/// contestaba **compatibilidad** en el campo de **identidad**; y ese booleano
/// vencía al extractor y al vocabulario, mataba las diez por `product_family` y
/// —como la compuerta corta antes de mirar predicados— vaciar todos los
/// criterios seguía dando 0 de 10.

const _peticion = 'Pastillas para frenos Shimano BR-MT200, de resina y sin '
    'aletas de refrigeración';

const _fields = <SupplierNeedSearchField>[
  SupplierNeedSearchField(
    key: 'brake_system',
    label: 'Sistema de Freno',
    dataType: 'single_select',
    allowedValues: <Object>['Shimano', 'SRAM', 'Tektro', 'Magura'],
  ),
  SupplierNeedSearchField(
    key: 'compound_type',
    label: 'Compuesto',
    dataType: 'single_select',
    allowedValues: <Object>['Metálico', 'Orgánico', 'Semi-Metálico'],
  ),
];

SupplierNeedPortalAdapter _adapter() =>
    SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
      'version': 1,
      'generic_family_search': true,
      'result_schema': <String, dynamic>{
        'columns': <String, dynamic>{
          'code': <String>['c'],
          'name': <String>['n'],
          'price': <String>['p'],
        },
      },
      'catalog_route': <String, dynamic>{
        'url_template': 'http://x/{node}{page}{page_size}',
        'page_size': 50,
      },
    });

SupplierNeedSearchPlan _plan({
  List<SupplierNeedSearchPredicate> predicates =
      const <SupplierNeedSearchPredicate>[],
  String description = _peticion,
}) =>
    buildSupplierNeedSearchPlan(
      request: SupplierNeedSearchRequest(
        needId: 'need-pastillas',
        description: description,
        categoryId: 'cat-pastillas',
        categoryPath: 'Componentes / Frenos / Pastillas',
        technicalFamily: 'brake_pad',
        fields: _fields,
        predicates: predicates,
      ),
      adapter: _adapter(),
      maxLength: 20,
    )!;

/// Una fila tal como la dejó la lectura real: head citado y veredicto en falso.
SupplierPortalCatalogCandidate _fila(
  String code,
  String name, {
  String head = 'PASTILLA FRENO DISCO',
  bool isRequested = false,
}) =>
    SupplierPortalCatalogCandidate(
      code: code,
      name: name,
      priceNet: 5000,
      rowText: name,
      technicalFacts: <String, Object?>{
        kSupplierObjectHeadFact: head,
        kSupplierObjectIsRequestedFact: isRequested,
      },
    );

/// Las diez filas del recibo real.
List<SupplierPortalCatalogCandidate> _corridaRbx() =>
    <SupplierPortalCatalogCandidate>[
      _fila('17977', 'PASTILLA FRENO DISCO A10YS TEKTRO'),
      _fila('10587', 'PASTILLA FRENO DISCO BP-10/SP-10'),
      _fila('16466', 'PASTILLA FRENO DISCO BP-52 SHIMANO XTR 2011'),
      _fila('2005', 'PASTILLA FRENO DISCO BR-555 SHIMANO'),
      _fila('8479', 'PASTILLA FRENO DISCO CLARA/LOUISE MAGURA'),
      _fila('14176', 'PASTILLA FRENO DISCO D40.11 TEKTRO'),
      _fila('10679', 'PASTILLA FRENO DISCO DBP-01 HAYES/PROMAX'),
      _fila('10684', 'PASTILLA FRENO DISCO DBP-11 AVID'),
      _fila('16403', 'PASTILLA FRENO DISCO DBP-23 ZOOM'),
      _fila('10699', 'PASTILLA FRENO DISCO DBP-40 HAYES STROKER RYDE'),
    ];

List<SupplierNeedPortalMatch> _juzgar(
  SupplierNeedSearchPlan plan,
  List<SupplierPortalCatalogCandidate> filas,
) =>
    matchSupplierNeedCandidates(plan, filas);

void main() {
  group('el head citado manda sobre el veredicto del modelo', () {
    test('las diez de RBX dejan de morir por familia', () {
      final matches = _juzgar(_plan(), _corridaRbx());
      expect(matches.length, 10);
      for (final match in matches) {
        expect(
          match.conflictingFields,
          isNot(contains('product_family')),
          reason: match.candidate.name,
        );
      }
      expect(
        matches.where((m) => m.state == SupplierNeedMatchState.conflict),
        isEmpty,
      );
    });

    test('pero ninguna es exacta sólo por ser pastilla', () {
      // La petición nombra `BR-MT200` y ninguna fila lo trae: el requisito
      // queda pendiente y ninguna puede declararse cumplida.
      final matches = _juzgar(
        _plan(predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'brake_system',
            operator: 'eq',
            values: <Object>['Shimano'],
          ),
        ]),
        _corridaRbx(),
      );
      for (final match in matches) {
        expect(match.missingFields, contains(kCompatibilityRequirementField),
            reason: match.candidate.name);
        expect(match.state, isNot(SupplierNeedMatchState.exact),
            reason: match.candidate.name);
      }
    });

    test('y una fila que SÍ trae la referencia la prueba', () {
      final matches = _juzgar(
        _plan(),
        <SupplierPortalCatalogCandidate>[
          _fila('900', 'PASTILLA FRENO DISCO RESINA PARA BR-MT200 B01S'),
        ],
      );
      expect(matches.single.provenFields,
          contains(kCompatibilityRequirementField));
    });
  });

  group('la exclusión real de otras piezas se conserva', () {
    test('una cubeta, unas bielas y un freno completo siguen fuera', () {
      // El head los delata con la palabra del propio proveedor, citada. Antes
      // esto lo sostenía el veredicto del modelo; ahora, una cita.
      final matches = _juzgar(_plan(), <SupplierPortalCatalogCandidate>[
        _fila('1', 'CUBETA MOTOR 34.8 DERECHO', head: 'CUBETA'),
        _fila('2', 'BIELAS Y EJE MOTOR ALUMINIO', head: 'BIELAS'),
        _fila('3', 'FRENO COMPLETO SHIMANO BR-MT200 HIDRAULICO', head: 'FRENO'),
        _fila('4', 'MANGUERA HIDRAULICA SHIMANO', head: 'MANGUERA'),
      ]);
      for (final match in matches) {
        expect(match.conflictingFields, contains('product_family'),
            reason: match.candidate.name);
      }
    });

    test('un patín de V-Brake es la MISMA familia, y se separa por spec', () {
      // La taxonomía canónica agrupa pastilla, zapata y patín en `brake_pad`:
      // `patin` está entre sus heads. Excluirlo por identidad sería inventar
      // una familia que el dominio no tiene. Lo que lo separa de una pastilla
      // de disco es `brake_type`, que es una spec y se lee de su nombre.
      const conTipo = SupplierNeedSearchField(
        key: 'brake_type',
        label: 'Tipo de Freno',
        dataType: 'single_select',
        allowedValues: <Object>[
          'Disco Hidráulico',
          'Disco Mecánico',
          'V-Brake'
        ],
      );
      final plan = buildSupplierNeedSearchPlan(
        request: const SupplierNeedSearchRequest(
          needId: 'need-pastillas',
          description: _peticion,
          categoryId: 'cat-pastillas',
          categoryPath: 'Componentes / Frenos / Pastillas',
          technicalFamily: 'brake_pad',
          fields: <SupplierNeedSearchField>[conTipo],
          predicates: <SupplierNeedSearchPredicate>[
            SupplierNeedSearchPredicate(
              field: 'brake_type',
              operator: 'eq',
              values: <Object>['Disco Hidráulico'],
            ),
          ],
        ),
        adapter: _adapter(),
        maxLength: 20,
      )!;
      final patin = _juzgar(plan, <SupplierPortalCatalogCandidate>[
        _fila('5', 'PATIN V-BRAKE 70MM', head: 'PATIN'),
      ]).single;
      expect(patin.conflictingFields, isNot(contains('product_family')),
          reason: 'sigue siendo la misma familia');
      expect(patin.conflictingFields, contains('brake_type'),
          reason: 'y su propio nombre dice que es de V-Brake');
    });

    test('un freno completo que dice BR-MT200 no pasa por pastilla', () {
      // Traer la referencia no convierte una pieza en otra: la identidad se
      // juzga antes, y por el sustantivo.
      final matches = _juzgar(_plan(), <SupplierPortalCatalogCandidate>[
        _fila('3', 'FRENO COMPLETO SHIMANO BR-MT200', head: 'FRENO'),
      ]);
      expect(matches.single.state, SupplierNeedMatchState.conflict);
    });
  });

  group('el refiltrado deja de estar congelado', () {
    test('sin criterios, las diez quedan a la vista para revisar', () {
      // Antes: 0 de 10 incluso con todos los criterios vacíos, porque la
      // compuerta cortaba aguas arriba de los predicados.
      final matches = _juzgar(_plan(), _corridaRbx());
      final tally = tallySupplierNeedMatchesUnder(
        matches: matches,
        predicates: const <SupplierNeedSearchPredicate>[],
        fields: _fields,
      );
      expect(tally.total, 10);
      expect(tally.confirmed, 0, reason: 'sin criterios nada está probado');
    });

    test('y cambiar Shimano por Tektro cambia el conjunto', () {
      // **El conjunto, no el conteo.** Los dos dan 7 por coincidencia; lo que
      // importa es que sobrevivan filas distintas.
      final conShimano = judgeSupplierNeedMatchesUnder(
        matches: _juzgar(_plan(), _corridaRbx()),
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'brake_system',
            operator: 'eq',
            values: <Object>['Shimano'],
          ),
        ],
        fields: _fields,
      ).map((v) => v.match.candidate.code).toSet();
      final conTektro = judgeSupplierNeedMatchesUnder(
        matches: _juzgar(_plan(), _corridaRbx()),
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'brake_system',
            operator: 'eq',
            values: <Object>['Tektro'],
          ),
        ],
        fields: _fields,
      ).map((v) => v.match.candidate.code).toSet();
      expect(conShimano, isNot(conTektro));
      expect(conShimano, contains('16466'), reason: 'BP-52 SHIMANO XTR');
      expect(conShimano, isNot(contains('17977')), reason: 'A10YS TEKTRO');
      expect(conTektro, contains('17977'));
      expect(conTektro, isNot(contains('16466')));
    });
  });

  group('una lectura YA guardada también se rescata', () {
    test('el rematch de un snapshot viejo revive las diez', () {
      // No basta con que una búsqueda nueva salga mejor: la corrida guardada
      // trae el booleano en `technicalFacts`, y el rejuicio la vuelve a leer.
      final vieja = SupplierNeedPortalSearchSnapshot(
        query: 'pastilla',
        status: SupplierNeedPortalSearchStatus.completed,
        checkedAt: DateTime.utc(2026, 8, 31, 1, 0, 41),
        matches: _juzgar(_plan(), _corridaRbx()),
        operationKey: 'recibo-22006b7e',
      );
      final rejuzgada = rematchSupplierNeedPortalSnapshot(_plan(), vieja);
      expect(rejuzgada.relevantMatches.length, 10);
      expect(rejuzgada.operationKey, 'recibo-22006b7e');
      for (final match in rejuzgada.matches) {
        expect(match.conflictingFields, isNot(contains('product_family')));
      }
    });
  });
}
