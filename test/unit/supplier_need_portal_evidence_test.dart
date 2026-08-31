import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/services/supply_need_criteria_latch.dart';
import 'package:vinabike_erp/modules/purchases/services/supply_need_effective_criteria.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

/// Lo que el proveedor **dice**, separado de lo que **calla**.
///
/// Corrida real de RBX del 2026-08-29 (`camara`, 35 filas leídas, 18 de la
/// familia). Con un criterio de válvula americana el asistente imprimía «8
/// cumplen»; el operador contó a mano y sólo 3 filas lo declaraban. Las otras
/// cinco sobrevivían por **no publicar el dato**, y dos de ellas ni siquiera
/// eran candidatas: dos cámaras Dunlop y una de scooter aro 8½.
///
/// Estas pruebas usan los nombres y códigos tal como los escribe el catálogo,
/// porque el defecto vivía en la escritura del proveedor —`V/DUNLOP`,
/// `V/FRANC.`, `8-1/2 X 2`— y una fixture redactada por nosotros lo habría
/// declarado verde.

const String _routeTemplate =
    'http://www.rburgos.cl/sitio/aplicaciones/catalogo.asp'
    '?url=cat_sel_cf.asp&url1=cat_sel_sf.asp&folio=0'
    '&Clasificacion2={node}&paginaabsoluta={page}&tamanopagina={page_size}';

SupplierNeedPortalAdapter _adapter() =>
    SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
      'version': 1,
      'generic_family_search': true,
      'result_schema': <String, dynamic>{
        'columns': <String, dynamic>{
          'code': <String>['Código'],
          'name': <String>['Descripción'],
          'price': <String>['Valor'],
        },
        'no_result_phrases': <String>['No hay ningún producto que mostrar'],
      },
      'catalog_route': <String, dynamic>{
        'url_template': _routeTemplate,
        'page_size': 50,
      },
    });

const List<SupplierNeedSearchField> _fields = <SupplierNeedSearchField>[
  SupplierNeedSearchField(
    key: 'wheel_size',
    label: 'Tamaño de rueda',
    dataType: 'single_select',
    allowedValues: <Object>['700c'],
  ),
  SupplierNeedSearchField(
    key: 'valve_type',
    label: 'Tipo de válvula',
    dataType: 'single_select',
    allowedValues: <Object>['presta', 'schrader'],
  ),
];

const SupplierNeedSearchPredicate _wheel700 = SupplierNeedSearchPredicate(
  field: 'wheel_size',
  operator: 'eq',
  values: <Object>['700c'],
);

SupplierNeedSearchPlan _plan(List<SupplierNeedSearchPredicate> predicates) =>
    buildSupplierNeedSearchPlan(
      request: SupplierNeedSearchRequest(
        needId: 'need-rbx-tubes',
        description: 'Cámaras aro 700 para reposición del taller',
        categoryId: 'category-tubes',
        categoryPath: 'Componentes / Ruedas / Cámaras',
        technicalFamily: 'tube',
        fields: _fields,
        predicates: predicates,
      ),
      adapter: _adapter(),
      maxLength: 15,
    )!;

/// Las 18 filas de la familia, con el nombre exacto del catálogo.
const Map<String, String> _feed = <String, String>{
  '10093': 'CAMARA AUTO SELLANTE700 X 20 a 23 V/FRANCESA 48mm',
  '10663': 'CAMARA 700 X 28/38C V/AUTO 48MM (28-5/8-1/4)',
  '10664': 'CAMARA 700 X 28/38C V/DUNLOP 40MM (28-5/8-1/4)',
  '10666': 'CAMARA AUTOSELLANTE 700 X 19/25C V/FRANCESA',
  '12183': 'CAMARA 700 X 18/25C V/FRANCESA 80MM',
  '13164': 'CAMARA 700 X 25/38C V/DUNLOP 35MM AUTOMATICA',
  '13322': 'CAMARA 700 X 28/38C V/FRANCESA 48MM (28-5/8-1/4)',
  '14473': 'CAMARA 700 X 18/25C V/AUTO 60MM',
  '17569': 'CAMARA AUTOSELLANTE 700 X 19/25C V/FRANC. 48mm',
  '18180': 'CAMARA SCOOTER 8-1/2 X 2 50/76-6.1 VALVULA SCHRADE',
  '18186': 'CAMARA 700 X 38/45C V/FRANCESA 48MM (28-5/8-1/4)',
  '18187': 'CAMARA 700 X 38/45C V/FRANCESA 60MM (28-5/8-1/4)',
  '18335': 'CAMARA 700 X 38/45C V/AMERICANA 48MM (28-5/8-1/4)',
  '3151': 'CAMARA 700 X 19/20/23C V/FRANCESA 48MM',
  '5122': 'CAMARA 700 X 18/25C V/FRANCESA 33M caja',
  '6912': 'CAMARA 700 X 18/25C V/FRANCESA 48MM CAJA',
  '6913': 'CAMARA 700 X 18/25C V/FRANCESA 60MM',
  '7043': 'CAMARA 700 X 20C V/FRANCESA 48mm CAJA',
};

List<SupplierPortalCatalogCandidate> _candidates() => _feed.entries
    .map((entry) => SupplierPortalCatalogCandidate(
          code: entry.key,
          name: entry.value,
          priceNet: 2240,
          // La fila cruda tal como se guardó: el texto completo y la
          // procedencia del nodo por el que entró.
          rowText: 'RBX · CAMARAS RUTA · ${entry.key}',
          technicalFacts: const <String, Object?>{'catalog_node': '171'},
        ))
    .toList(growable: false);

List<SupplierNeedPortalMatch> _matchesUnder(
  List<SupplierNeedSearchPredicate> predicates,
) =>
    matchSupplierNeedCandidates(_plan(predicates), _candidates());

Object? _valveOf(List<SupplierNeedPortalMatch> matches, String code) => matches
    .firstWhere((match) => match.candidate.code == code)
    .observedFacts['valve_type'];

/// El catálogo publica el tamaño a veces como texto (`'700'`) y a veces como
/// número, según por qué lectura entró. Lo que se afirma es la medida.
double? _wheelOf(List<SupplierNeedPortalMatch> matches, String code) {
  final raw = matches
      .firstWhere((match) => match.candidate.code == code)
      .observedFacts['wheel_size'];
  return raw == null ? null : double.tryParse(raw.toString());
}

void main() {
  const schrader = <SupplierNeedSearchPredicate>[
    _wheel700,
    SupplierNeedSearchPredicate(
      field: 'valve_type',
      operator: 'eq',
      values: <Object>['schrader'],
    ),
  ];
  // Sin el criterio de rueda: mide sólo la lectura de válvula.
  const schraderOnly = <SupplierNeedSearchPredicate>[
    SupplierNeedSearchPredicate(
      field: 'valve_type',
      operator: 'eq',
      values: <Object>['schrader'],
    ),
  ];
  const presta = <SupplierNeedSearchPredicate>[
    _wheel700,
    SupplierNeedSearchPredicate(
      field: 'valve_type',
      operator: 'eq',
      values: <Object>['presta'],
    ),
  ];

  group('la válvula la escribe el proveedor pegada a `V/`', () {
    test('las tres formas de decir americana, y ninguna más', () {
      final matches = _matchesUnder(schrader);

      expect(_valveOf(matches, '10663'), 'schrader', reason: 'V/AUTO');
      expect(_valveOf(matches, '14473'), 'schrader', reason: 'V/AUTO');
      expect(_valveOf(matches, '18335'), 'schrader', reason: 'V/AMERICANA');

      // `AUTO SELLANTE` es un sellante y `AUTOMATICA` un adjetivo: ninguno
      // convierte la fila en americana. Éste era el atajo que sumaba filas.
      expect(_valveOf(matches, '10093'), 'presta', reason: 'AUTO SELLANTE');
      expect(_valveOf(matches, '13164'), 'dunlop', reason: 'AUTOMATICA');
    });

    test('Dunlop es un tercer tipo, no otro nombre de la americana', () {
      final matches = _matchesUnder(schrader);
      expect(_valveOf(matches, '10664'), 'dunlop');
      expect(_valveOf(matches, '13164'), 'dunlop');
    });

    test('la abreviatura del catálogo también es evidencia', () {
      // `V/FRANC.` es la misma válvula que `V/FRANCESA`; leerla sólo entera
      // dejaba la fila muda y por lo tanto «cumpliendo» cualquier criterio.
      expect(_valveOf(_matchesUnder(presta), '17569'), 'presta');
    });
  });

  group('cada proveedor escribe la válvula distinto', () {
    // Filas reales leídas el 2026-08-29 de los catálogos públicos de
    // Droppbike (WooCommerce) y Derman (PrestaShop). Sin esto, un proveedor
    // nuevo entra mudo: ninguna fila contradice nada y todas «cumplen».
    Object? valveOf(String name) {
      final matches = matchSupplierNeedCandidates(
        _plan(schraderOnly),
        <SupplierPortalCatalogCandidate>[
          SupplierPortalCatalogCandidate(code: 'x', name: name),
        ],
      );
      return matches.single.observedFacts['valve_type'];
    }

    test('Droppbike escribe `VAL. AUTO`, con punto', () {
      expect(
        valveOf('CAMARA 26X1.75 2.20 VAL. AUTO 48MM. BUTYL RITECH'),
        'schrader',
      );
      expect(
        valveOf('CAMARA 700X28 38C BUTYL VAL. FRANCESA 60MM. RITECH'),
        'presta',
      );
    });

    test('Derman escribe `F/V`: la abreviatura sola es el tipo', () {
      expect(valveOf('CAMARA ARO 700X25/35C F/V 60MM PANARACER'), 'presta');
    });

    test('buscar «camara» en Derman trae cámaras de seguridad', () {
      // El buscador del proveedor es un índice, no una autoridad: devuelve
      // CCTV, fundas de iPhone y cables HDMI. Las tira la familia, no la
      // medida — y por eso una familia no demostrada no puede cumplir.
      final matches = matchSupplierNeedCandidates(
        _plan(schraderOnly),
        <SupplierPortalCatalogCandidate>[
          const SupplierPortalCatalogCandidate(
            code: 'MW23-09-213',
            name: 'MICROFONO AMBIENTAL ACTIVO PARA DVR Y CAMARAS DE '
                'SEGURIDAD CCTV - ALTA SENSIBILIDAD DERMAN',
          ),
          const SupplierPortalCatalogCandidate(
            code: 'QK-1',
            name: 'SOPORTE DE CAMARA PARA AUTO CON VENTOSA DE ALTA SUCCION',
          ),
        ],
      );

      final tally = tallySupplierNeedMatchesUnder(
        matches: matches,
        predicates: schraderOnly,
        fields: _fields,
      );
      expect(tally.confirmed, 0, reason: 'ninguna es una cámara de bicicleta');
      // `SOPORTE ... PARA AUTO` no puede volverse americana por decir `auto`.
      expect(
        matches
            .firstWhere((match) => match.candidate.code == 'QK-1')
            .observedFacts['valve_type'],
        isNull,
      );
    });
  });

  group('Derman: filas reales del catálogo PrestaShop', () {
    // Leídas el 2026-08-29 de https://derman.cl buscando «camara 700».
    // Derman abrevia la válvula sin palabra detrás: `F/V` y `A/V`.
    List<SupplierNeedPortalMatch> derman(
      List<SupplierNeedSearchPredicate> predicates,
    ) =>
        matchSupplierNeedCandidates(
          _plan(predicates),
          const <SupplierPortalCatalogCandidate>[
            SupplierPortalCatalogCandidate(
              code: 'PANARACER-70025/35',
              name: 'CAMARA ARO 700X25/35C F/V 60MM PANARACER',
              priceNet: 7900,
            ),
            SupplierPortalCatalogCandidate(
              code: 'CM-000251',
              name: 'CAMARA ARO 700x35/38C A/V 48MM',
              priceNet: 4900,
            ),
            SupplierPortalCatalogCandidate(
              code: 'JN-700C',
              name: 'CUBRE LLANTA ARO 700"X20MM JOGON-PAK JN-700C',
              priceNet: 2900,
            ),
          ],
        );

    test('la abreviatura sola dice el tipo, y son distintos', () {
      final matches = derman(schraderOnly);
      Object? valve(String code) => matches
          .firstWhere((match) => match.candidate.code == code)
          .observedFacts['valve_type'];

      expect(valve('PANARACER-70025/35'), 'presta', reason: 'F/V');
      expect(valve('CM-000251'), 'schrader', reason: 'A/V');
    });

    test('un cubre llanta 700 no es una cámara 700', () {
      // Mide 700 y sobreviviría a cualquier criterio de rueda. Lo elimina la
      // familia, que es exactamente para lo que está.
      final tally = tallySupplierNeedMatchesUnder(
        matches: derman(schrader),
        predicates: schrader,
        fields: _fields,
      );
      expect(tally.confirmed, 1, reason: 'sólo la cámara A/V');
      expect(tally.unverified, 0);

      final quedan = <String>{
        for (final match in derman(schrader))
          if (match.state != SupplierNeedMatchState.conflict)
            match.candidate.code,
      };
      expect(quedan, <String>{'CM-000251'});
      expect(quedan, isNot(contains('JN-700C')), reason: 'es un cubre llanta');
    });
  });

  group('una rueda de scooter no es una rueda 700', () {
    test('la fracción de pulgada se lee del texto crudo', () {
      expect(_wheelOf(_matchesUnder(schrader), '18180'), 8.5);
    });

    test('la equivalencia en pulgadas del final del nombre no la confunde', () {
      // `(28-5/8-1/4)` acompaña a casi toda cámara 700 y no es su rueda.
      final matches = _matchesUnder(schrader);
      for (final code in <String>['10663', '13322', '18186', '18335']) {
        expect(_wheelOf(matches, code), 700.0, reason: 'código $code');
      }
    });
  });

  group('una familia no demostrada no asciende a cumplida', () {
    test('con todas las medidas probadas sigue siendo por verificar', () {
      // El matcher real reparte `product_family` en probada, contradicha o
      // pendiente. Una fila cuyo objeto no se reconoció no es `exact`, y el
      // conteo no puede rotularla como si lo fuera: son las mismas medidas
      // sobre un objeto que no sabemos cuál es.
      const sinFamilia = SupplierNeedPortalMatch(
        candidate: SupplierPortalCatalogCandidate(
          code: '99001',
          name: 'REPUESTO 700 X 28C V/AUTO 48MM',
        ),
        state: SupplierNeedMatchState.possible,
        provenFields: <String>['wheel_size', 'valve_type'],
        missingFields: <String>['product_family'],
        conflictingFields: <String>[],
        observedFacts: <String, Object?>{
          'wheel_size': 700,
          'valve_type': 'schrader',
        },
      );
      const conFamilia = SupplierNeedPortalMatch(
        candidate: SupplierPortalCatalogCandidate(
          code: '10663',
          name: 'CAMARA 700 X 28/38C V/AUTO 48MM',
        ),
        state: SupplierNeedMatchState.exact,
        provenFields: <String>[
          'product_family',
          'wheel_size',
          'valve_type',
        ],
        missingFields: <String>[],
        conflictingFields: <String>[],
        observedFacts: <String, Object?>{
          'wheel_size': 700,
          'valve_type': 'schrader',
        },
      );

      final tally = tallySupplierNeedMatchesUnder(
        matches: <SupplierNeedPortalMatch>[sinFamilia, conFamilia],
        predicates: schrader,
        fields: _fields,
      );

      expect(tally.confirmed, 1, reason: 'sólo la que sí es una cámara');
      expect(tally.unverified, 1, reason: 'la otra queda, pero por verificar');
      // El conteo no puede decir algo que el estado de la fila desmiente.
      expect(sinFamilia.state, isNot(SupplierNeedMatchState.exact));
    });
  });

  group('un veredicto guardado caduca, la evidencia no', () {
    test('la misma ficha, con el lector de hoy, cambia el juicio', () {
      // El caso real del 2026-08-29: la búsqueda quedó guardada con el juicio
      // del lector de ese momento —cinco filas «falta confirmar»— y respondía
      // a la revisión vigente. Como respondía, el cliente la mostraba tal
      // cual, así que arreglar el lector no cambiaba nada en pantalla hasta
      // que alguien tocara la ficha o buscara de nuevo.
      final guardado = SupplierNeedPortalSearchSnapshot(
        query: 'camara',
        status: SupplierNeedPortalSearchStatus.completed,
        checkedAt: DateTime.utc(2026, 8, 28, 10),
        matches: <SupplierNeedPortalMatch>[
          for (final entry in _feed.entries)
            SupplierNeedPortalMatch(
              candidate: SupplierPortalCatalogCandidate(
                code: entry.key,
                name: entry.value,
              ),
              // El juicio viejo: nadie contradecía, todo quedaba pendiente.
              state: SupplierNeedMatchState.possible,
              provenFields: const <String>['product_family'],
              missingFields: const <String>['valve_type'],
              conflictingFields: const <String>[],
              observedFacts: const <String, Object?>{},
            ),
        ],
        coverage: const SupplierNeedPortalCoverage(
          method: SupplierNeedCoverageMethod.taxonomy,
          isComplete: true,
          limit: SupplierNeedCoverageLimit.enumerated,
          nodeLabels: <String>['CAMARAS RUTA'],
          nodesAvailable: 1,
          nodesPlanned: 1,
          nodesCompleted: 1,
          rowsObserved: 18,
          rowsUnique: 18,
          rowsPersisted: 18,
        ),
        searchRevisionNo: 4,
        currentRevisionNo: 4,
      );

      // Responde a la revisión vigente: por eso se reusaba tal cual.
      expect(guardado.answersCurrentRevision, isTrue);
      expect(
        tallySupplierNeedMatchesUnder(
          matches: guardado.matches,
          predicates: schrader,
          fields: _fields,
        ),
        const SupplierNeedMatchTally(confirmed: 0, unverified: 18),
        reason: 'el juicio guardado no sabía leer ninguna válvula',
      );

      // Volver a juzgar la MISMA evidencia con el lector de hoy.
      final aldia = rematchSupplierNeedPortalSnapshot(
        _plan(schrader),
        guardado,
      );
      final tally = tallySupplierNeedMatchesUnder(
        matches: aldia.matches,
        predicates: schrader,
        fields: _fields,
      );

      expect(tally.confirmed, 3);
      expect(tally.unverified, 0, reason: 'ya ninguna queda «por confirmar»');
      expect(aldia.rowLabel, '3 exactos');
      // Y la lectura sigue siendo la de ayer: no se volvió al portal.
      expect(aldia.checkedAt, DateTime.utc(2026, 8, 28, 10));
    });
  });

  group('la ficha nueva se juzga sobre el feed ya leído', () {
    test('reevaluar no vuelve al portal ni pierde lo que se leyó', () {
      final checkedAt = DateTime.utc(2026, 8, 29, 6, 39, 49);
      const coverage = SupplierNeedPortalCoverage(
        method: SupplierNeedCoverageMethod.taxonomy,
        isComplete: true,
        limit: SupplierNeedCoverageLimit.enumerated,
        nodeLabels: <String>['CAMARAS RUTA'],
        nodesAvailable: 1,
        nodesPlanned: 1,
        nodesCompleted: 1,
        pagesFetched: 2,
        rowsObserved: 35,
        rowsUnique: 35,
        rowsPersisted: 35,
      );
      // Lo leído sólo con el criterio de rueda, tal como quedó guardado.
      final stored = SupplierNeedPortalSearchSnapshot(
        query: 'camara',
        status: SupplierNeedPortalSearchStatus.completed,
        checkedAt: checkedAt,
        matches: _matchesUnder(const <SupplierNeedSearchPredicate>[_wheel700]),
        sourceUrl: 'https://rbx/cat?Clasificacion2=171',
        coverage: coverage,
        searchRevisionNo: 3,
        currentRevisionNo: 4,
      );

      final rejudged = rematchSupplierNeedPortalSnapshot(
        _plan(schrader),
        stored,
      );

      // El hecho de haber consultado no cambia; cambia contra qué se juzga.
      expect(rejudged.query, 'camara');
      expect(rejudged.sourceUrl, 'https://rbx/cat?Clasificacion2=171');
      expect(rejudged.checkedAt, checkedAt);
      expect(rejudged.coverage.rowsUnique, 35);
      expect(rejudged.coverage.rowsPersisted, 35);
      expect(rejudged.coverage.isComplete, isTrue);
      expect(rejudged.coverage.nodeLabels, <String>['CAMARAS RUTA']);
      expect(rejudged.searchRevisionNo, 3, reason: 'con qué ficha se leyó');
      expect(rejudged.currentRevisionNo, 4);
      // El veredicto pasa a responder la ficha vigente: eso es lo único que
      // cambia, y es justamente lo que estaba quedando en la anterior.
      expect(rejudged.evaluatedRevisionNo, 4);
      expect(rejudged.answersCurrentRevision, isTrue);

      // Las filas crudas COMPLETAS, sin volver al portal. El ORDEN sí puede
      // cambiar: con un criterio nuevo el ranking es otro, y eso es correcto.
      expect(rejudged.matches, hasLength(stored.matches.length));
      Map<String, SupplierPortalCatalogCandidate> byCode(
        SupplierNeedPortalSearchSnapshot snapshot,
      ) =>
          <String, SupplierPortalCatalogCandidate>{
            for (final match in snapshot.matches)
              match.candidate.code: match.candidate,
          };
      final before = byCode(stored);
      final after = byCode(rejudged);
      expect(after.keys.toSet(), before.keys.toSet());
      for (final code in before.keys) {
        expect(after[code]!.name, before[code]!.name, reason: code);
        expect(after[code]!.rowText, before[code]!.rowText, reason: code);
        expect(after[code]!.priceNet, before[code]!.priceNet, reason: code);
        expect(
          after[code]!.technicalFacts,
          before[code]!.technicalFacts,
          reason: 'la procedencia de la fila no se recalcula: $code',
        );
      }

      final tally = tallySupplierNeedMatchesUnder(
        matches: rejudged.matches,
        predicates: schrader,
        fields: _fields,
      );
      expect(tally.confirmed, 3);
      expect(tally.unverified, 0);
    });
  });

  group('RBX: pedir un motor de centro no puede traer bielas', () {
    // Filas reales del portal de RBX el 2026-08-30, pidiendo «eje sellado».
    // Las nueve entraron al listado porque dicen «MOTOR», y el operador se
    // quedó con ocho «falta confirmar» que ni siquiera eran lo que pidió.
    const pedalier = SupplierNeedSearchRequest(
      needId: 'need-bb',
      description: 'Motor de centro sellado con eje cuadrado',
      categoryId: 'category-bb',
      technicalFamily: 'bottom_bracket',
      fields: <SupplierNeedSearchField>[],
      predicates: <SupplierNeedSearchPredicate>[],
    );

    List<SupplierNeedPortalMatch> filas() => matchSupplierNeedCandidates(
          buildSupplierNeedSearchPlan(
            request: pedalier,
            adapter: _adapter(),
            maxLength: 15,
          )!,
          const <SupplierPortalCatalogCandidate>[
            SupplierPortalCatalogCandidate(
              code: 'C31G',
              name: 'BIELAS Y EJE MOTOR ALUMINIO B.M.X. C31G 175mm',
              technicalFacts: <String, Object?>{
                kSupplierObjectHeadFact: 'BIELAS',
                kSupplierObjectIsRequestedFact: false,
              },
            ),
            SupplierPortalCatalogCandidate(
              code: 'C19GW',
              name: 'BIELAS Y EJE MOTOR Cr-Mo B.M.X. C19GW-2P 175mm',
              technicalFacts: <String, Object?>{
                kSupplierObjectHeadFact: 'BIELAS',
                kSupplierObjectIsRequestedFact: false,
              },
            ),
            SupplierPortalCatalogCandidate(
              code: 'CUB348',
              name: 'CUBETA MOTOR 34.8 DER-DERECHO CROMADA',
              // Lo que el lector con modelo dejó verificado contra el texto:
              // el proveedor la nombra CUBETA, y una cubeta no es un motor de
              // centro. Ninguna lista escrita a mano conocía esta pieza.
              technicalFacts: <String, Object?>{
                kSupplierObjectHeadFact: 'CUBETA',
                kSupplierObjectIsRequestedFact: false,
              },
            ),
          ],
        );

    test('una biela con la palabra «motor» no es un motor de centro', () {
      // Lo que las descarta es que el proveedor las nombra BIELAS en su propio
      // texto y el lector copió ese sustantivo verificado. Ninguna lista
      // escrita a mano conocía estas piezas.
      final bielas = filas().where(
        (match) => match.candidate.name.startsWith('BIELAS'),
      );
      expect(bielas, hasLength(2));
      for (final match in bielas) {
        expect(
          match.provenFields,
          isNot(contains('product_family')),
          reason: 'no puede darse por probada la familia en '
              '«${match.candidate.name}»',
        );
      }
    });

    test('ninguna de las tres se cuenta como cumplida', () {
      final tally = tallySupplierNeedMatchesUnder(
        matches: filas(),
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'bb_construction',
            operator: 'eq',
            values: <Object>['sealed'],
          ),
        ],
      );
      expect(tally.confirmed, 0);
    });

    test('una cubeta tampoco es un motor de centro', () {
      // **Sin una sola línea de lista.** El extractor canónico no conoce
      // `CUBETA`; lo que la descarta es que el proveedor la nombró así en su
      // propio texto y el lector lo copió verificado. La misma mecánica sirve
      // para cualquier pieza que nadie anticipó.
      final cubeta = filas().firstWhere(
        (match) => match.candidate.name.startsWith('CUBETA'),
      );
      expect(cubeta.provenFields, isNot(contains('product_family')));
    });
  });

  group('sin el lector con modelo, la identidad canónica igual protege', () {
    test('el extractor reconoce otra pieza y el vocabulario ya no la rescata',
        () {
      // **El vocabulario rescata el silencio, no corrige al extractor.** Sin la
      // lectura del modelo, `BIELAS Y EJE MOTOR` pasaba por decir «motor»: era
      // el costo conocido de no tener IA. Ya no: el extractor canónico la
      // reconoce como `crankset` y eso contradice.
      //
      // El cuidado que costó 26 de 27 cámaras el 2026-08-30 sigue puesto, y
      // ahora explícito: las familias sólo se comparan cuando **las dos son
      // ids canónicos**. Un adaptador puede rotular la suya con una etiqueta
      // propia, y un desacuerdo de etiquetas no es evidencia de otra pieza. El
      // vocabulario sigue rescatando cuando el extractor no reconoció nada.
      final sinLector = matchSupplierNeedCandidates(
        buildSupplierNeedSearchPlan(
          request: const SupplierNeedSearchRequest(
            needId: 'need-bb',
            description: 'Motor de centro sellado con eje cuadrado',
            categoryId: 'category-bb',
            technicalFamily: 'bottom_bracket',
            fields: <SupplierNeedSearchField>[],
            predicates: <SupplierNeedSearchPredicate>[],
          ),
          adapter: _adapter(),
          maxLength: 15,
        )!,
        const <SupplierPortalCatalogCandidate>[
          SupplierPortalCatalogCandidate(
            code: 'C31G',
            name: 'BIELAS Y EJE MOTOR ALUMINIO B.M.X. C31G 175mm',
          ),
        ],
      );

      expect(
        sinLector.single.conflictingFields,
        contains('product_family'),
        reason: 'bielas no son un motor de centro, lo diga o no la IA',
      );
      expect(sinLector.single.provenFields, isNot(contains('product_family')));
    });
  });

  group('el conteo separa lo probado de lo que nadie verificó', () {
    test('americana: exactamente 3 confirmadas, y ni scooter ni Dunlop', () {
      final matches = _matchesUnder(schrader);
      final tally = tallySupplierNeedMatchesUnder(
        matches: matches,
        predicates: schrader,
        fields: _fields,
      );

      // El número que el asistente imprimía era 8. Sólo tres filas lo dicen.
      expect(tally.confirmed, 3);
      expect(tally.unverified, 0);
      expect(tally.total, 3);

      final surviving = <String>{
        for (final match in matches)
          if (match.state != SupplierNeedMatchState.conflict)
            match.candidate.code,
      };
      expect(surviving, <String>{'10663', '14473', '18335'});
      expect(surviving, isNot(contains('18180')), reason: 'scooter aro 8½');
      expect(surviving, isNot(contains('10664')), reason: 'Dunlop');
      expect(surviving, isNot(contains('13164')), reason: 'Dunlop');
    });

    test('francesa: las doce que lo declaran, ninguna por relleno', () {
      final tally = tallySupplierNeedMatchesUnder(
        matches: _matchesUnder(presta),
        predicates: presta,
        fields: _fields,
      );
      expect(tally.confirmed, 12);
      expect(tally.unverified, 0);
    });

    test('un criterio que el catálogo no publica no lo cumple nadie', () {
      // El material no aparece en ningún nombre. La fila no se rechaza —eso
      // sería inventar una contradicción— pero tampoco cumple.
      const withMaterial = <SupplierNeedSearchPredicate>[
        ...schrader,
        SupplierNeedSearchPredicate(
          field: 'material',
          operator: 'eq',
          values: <Object>['butilo'],
        ),
      ];
      final tally = tallySupplierNeedMatchesUnder(
        matches: _matchesUnder(schrader),
        predicates: withMaterial,
        fields: _fields,
      );
      expect(tally.confirmed, 0, reason: 'nadie publica el material');
      expect(tally.unverified, 3, reason: 'siguen siendo candidatas');
    });
  });

  group('la secuencia después de guardar criterios', () {
    test('la lista queda juzgada con la ficha nueva, sin ir al portal',
        () async {
      // Lo guardado se leyó con la ficha anterior: sólo el aro.
      final checkedAt = DateTime.utc(2026, 8, 29, 6, 39, 49);
      final stored = SupplierNeedPortalSearchSnapshot(
        query: 'camara',
        status: SupplierNeedPortalSearchStatus.completed,
        checkedAt: checkedAt,
        matches: _matchesUnder(const <SupplierNeedSearchPredicate>[_wheel700]),
        coverage: const SupplierNeedPortalCoverage(
          method: SupplierNeedCoverageMethod.taxonomy,
          isComplete: true,
          limit: SupplierNeedCoverageLimit.enumerated,
          nodeLabels: <String>['CAMARAS RUTA'],
          nodesAvailable: 1,
          nodesPlanned: 1,
          nodesCompleted: 1,
          pagesFetched: 2,
          rowsObserved: 18,
          rowsUnique: 18,
          rowsPersisted: 18,
        ),
        searchRevisionNo: 3,
        currentRevisionNo: 3,
      );
      expect(stored.rowLabel, '17 exactos');
      expect(stored.optionsSummaryLabel, contains('17 opciones exactas'));

      // El operador precisa la válvula. `_loadDecision` lanza la lectura de
      // criterios SIN esperarla, y el juicio del feed corre en ese mismo
      // tramo: acá la lectura todavía no llegó.
      final latch = SupplyNeedCriteriaLatch();
      final reading = Completer<SupplyNeedCriteria>();
      latch.publish('need-rbx-tubes', reading.future);

      const pintada = SupplyNeedCriteria(
        predicates: <SupplyNeedPredicate>[
          SupplyNeedPredicate(
            field: 'wheel_size',
            operator: 'eq',
            values: <Object>['700c'],
          ),
        ],
        categoryId: 'category-tubes',
        revisionNo: 3,
      );

      var portalVisits = 0;
      final judged = latch
          .resolve(
        needId: 'need-rbx-tubes',
        painted: pintada,
        fetch: () async => fail('la lectura ya está en vuelo'),
      )
          .then((criteria) {
        // Así arma la página la pregunta: con la ficha resuelta, nunca con la
        // pintada.
        final plan = _plan(criteria.predicates
            .map((predicate) => SupplierNeedSearchPredicate(
                  field: predicate.field,
                  operator: predicate.operator,
                  values: predicate.values,
                ))
            .toList(growable: false));
        portalVisits++; // sólo cuenta que se armó el juicio, no una consulta
        return rematchSupplierNeedPortalSnapshot(plan, stored);
      });

      // La ficha nueva llega después de que el juicio ya preguntó.
      reading.complete(const SupplyNeedCriteria(
        predicates: <SupplyNeedPredicate>[
          SupplyNeedPredicate(
            field: 'wheel_size',
            operator: 'eq',
            values: <Object>['700c'],
          ),
          SupplyNeedPredicate(
            field: 'valve_type',
            operator: 'eq',
            values: <Object>['schrader'],
          ),
        ],
        categoryId: 'category-tubes',
        revisionNo: 4,
      ));
      final rejudged = await judged;

      // El rótulo pasa a responder la ficha nueva, no la anterior.
      expect(rejudged.rowLabel, '3 exactos');
      expect(rejudged.optionsSummaryLabel, contains('3 opciones exactas'));
      expect(rejudged.optionsSummaryLabel, isNot(contains('17')));

      final tally = tallySupplierNeedMatchesUnder(
        matches: rejudged.matches,
        predicates: schrader,
        fields: _fields,
      );
      expect(tally.confirmed, 3);
      expect(tally.unverified, 0);
      expect(
        <String>{
          for (final match in rejudged.matches)
            if (match.state != SupplierNeedMatchState.conflict)
              match.candidate.code,
        },
        <String>{'10663', '14473', '18335'},
      );

      // Las filas son las guardadas y la lectura es la misma: no hubo portal.
      expect(rejudged.checkedAt, checkedAt);
      expect(rejudged.matches, hasLength(stored.matches.length));
      expect(portalVisits, 1, reason: 'se juzgó una vez, sin volver a leer');
    });
  });
  _pruebasDeAcarreo();
  _pruebasDeFichaEfectiva();
}

/// Las filas que la corrida real del **2026-08-30** dejó a la vista en RBX:
/// 25 de las 27 leídas —las otras dos ya contradecían la familia y no se
/// muestran—. Los nombres van tal como los escribe el catálogo, con sus
/// abreviaturas y su puntuación, porque el filtro se juega justo ahí.
const Map<String, String> _corrida20260830 = <String, String>{
  '14475': 'CAMARA 26 X 1.3/8 V/AUTO 33MM',
  '16710': 'CAMARA 27.5 X 1.25/1.50 AV48 EN CAJA',
  '10873': 'CAMARA 28 X 1.5/8 - 1/4VALVULA AUTO (27X1.1/4)',
  '1032': 'CAMARA 28 X 1.5/8 V/ DUNLOP EN CAJA',
  '16771': 'CAMARA 28 x 1.1/2 VALVULA DUNLOP',
  '14473': 'CAMARA 700 X 18/25C V/AUTO 60MM',
  '5122': 'CAMARA 700 X 18/25C V/FRANCESA 33M caja',
  '6912': 'CAMARA 700 X 18/25C V/FRANCESA 48MM CAJA',
  '6913': 'CAMARA 700 X 18/25C V/FRANCESA 60MM',
  '12183': 'CAMARA 700 X 18/25C V/FRANCESA 80MM',
  '3151': 'CAMARA 700 X 19/20/23C V/FRANCESA 48MM',
  '7043': 'CAMARA 700 X 20C V/FRANCESA 48mm CAJA',
  '13164': 'CAMARA 700 X 25/38C V/DUNLOP 35MM AUTOMATICA',
  '10663': 'CAMARA 700 X 28/38C V/AUTO 48MM (28-5/8-1/4)',
  '10664': 'CAMARA 700 X 28/38C V/DUNLOP 40MM (28-5/8-1/4)',
  '13322': 'CAMARA 700 X 28/38C V/FRANCESA 48MM (28-5/8-1/4)',
  '18335': 'CAMARA 700 X 38/45C V/AMERICANA 48MM (28-5/8-1/4)',
  '18186': 'CAMARA 700 X 38/45C V/FRANCESA 48MM (28-5/8-1/4)',
  '18187': 'CAMARA 700 X 38/45C V/FRANCESA 60MM (28-5/8-1/4)',
  '10093': 'CAMARA AUTO SELLANTE700 X 20 a 23 V/FRANCESA 48mm',
  '17569': 'CAMARA AUTOSELLANTE 700 X 19/25C V/FRANC. 48mm',
  '10666': 'CAMARA AUTOSELLANTE 700 X 19/25C V/FRANCESA',
  '18207': 'CAMARA CARRETILLA 350 X 8 A/V TR87',
  '18308': 'CAMARA SCOOTER 10 X 2.125 VALVULA SCHRADER CURVA 9',
  '18180': 'CAMARA SCOOTER 8-1/2 X 2 50/76-6.1 VALVULA SCHRADE',
};

List<SupplierPortalCatalogCandidate> _candidatos20260830() =>
    _corrida20260830.entries
        .map((entry) => SupplierPortalCatalogCandidate(
              code: entry.key,
              name: entry.value,
              priceNet: 2100,
              rowText: 'RBX · ${entry.key} · ${entry.value}',
              technicalFacts: const <String, Object?>{'catalog_node': '171'},
            ))
        .toList(growable: false);

/// La lectura tal como quedó: recorrida, juzgada… y **sin recibo**.
SupplierNeedPortalSearchSnapshot _lecturaEfimera() {
  final plan = _plan(const <SupplierNeedSearchPredicate>[]);
  return SupplierNeedPortalSearchSnapshot(
    query: 'camara',
    status: SupplierNeedPortalSearchStatus.completed,
    checkedAt: DateTime.utc(2026, 8, 30, 3, 52),
    matches: matchSupplierNeedCandidates(plan, _candidatos20260830()),
    sourceUrl: 'https://portal.rburgos.cl/',
    coverage: const SupplierNeedPortalCoverage(
      method: SupplierNeedCoverageMethod.taxonomy,
      isComplete: false,
      limit: SupplierNeedCoverageLimit.maxNodes,
      nodesAvailable: 6,
      nodesPlanned: 2,
      nodesCompleted: 2,
      rowsObserved: 27,
      rowsUnique: 27,
    ),
    searchRevisionNo: 1,
    currentRevisionNo: 1,
    evaluatedRevisionNo: 1,
    operationKey: 'test-run',
  );
}

/// **Precisar conserva el feed aunque el recibo no se haya guardado.**
///
/// El 2026-08-30 una corrida real recorrió el portal de RBX entero, leyó 27
/// filas y su recibo murió en un 504 del gateway. Al guardar `wheel_size =
/// 700c`, la página recargaba las lecturas **sólo desde la base**, no
/// encontraba nada y RBX volvía a «sin consultar»: minutos de navegación real
/// borrados de la pantalla por un fallo de transporte que no es del proveedor.
void _pruebasDeAcarreo() {
  group('precisar acarrea y rejuzga la lectura sin recibo', () {
    final efimera = _lecturaEfimera();

    test('sin recibo guardado, la lectura de memoria sostiene el feed', () {
      final acarreada = carrySupplierNeedPortalSearch(
        stored: null,
        inMemory: efimera,
        plan: _plan(const <SupplierNeedSearchPredicate>[_wheel700]),
        currentRevisionNo: 2,
      );
      expect(acarreada, isNotNull);
      // Y responde la ficha NUEVA: se acaba de juzgar contra ella. Sin la
      // revisión vigente quedaba rotulada «Ficha anterior» recién calculada.
      expect(acarreada!.answersCurrentRevision, isTrue);
    });

    test('sin lectura por ningún lado no se inventa una', () {
      expect(
        carrySupplierNeedPortalSearch(
          stored: null,
          inMemory: null,
          plan: _plan(const <SupplierNeedSearchPredicate>[_wheel700]),
        ),
        isNull,
      );
    });

    test('refiltrar conserva la identidad de la corrida', () {
      // Rejuzgar cambia el veredicto, no quién recorrió el portal. Sin la
      // clave, el recibo pendiente ya no se puede resolver por clave y la
      // regla de procedencia deja de reconocer la misma corrida.
      final acarreada = carrySupplierNeedPortalSearch(
        stored: null,
        inMemory: efimera,
        plan: _plan(const <SupplierNeedSearchPredicate>[_wheel700]),
        currentRevisionNo: 2,
      )!;
      expect(acarreada.operationKey, efimera.operationKey);
      expect(acarreada.operationKey, isNotNull);
    });

    test('y por eso la MISMA corrida ya refiltrada se sigue reconociendo', () {
      // El caso que la pérdida rompía: la lectura de memoria ya pasó por un
      // refiltrado y su recibo sí llegó a guardarse. Son el mismo recorrido,
      // así que manda la guardada — no la hora, que acá favorecería a la otra.
      final refiltrada = rematchSupplierNeedPortalSnapshot(
        _plan(const <SupplierNeedSearchPredicate>[_wheel700]),
        efimera,
        currentRevisionNo: 2,
      );
      final guardada = SupplierNeedPortalSearchSnapshot(
        query: efimera.query,
        status: efimera.status,
        checkedAt: efimera.checkedAt!.subtract(const Duration(minutes: 5)),
        matches: efimera.matches.take(9).toList(growable: false),
        operationKey: efimera.operationKey,
      );
      final acarreada = carrySupplierNeedPortalSearch(
        stored: guardada,
        inMemory: refiltrada,
        plan: _plan(const <SupplierNeedSearchPredicate>[]),
      )!;
      expect(acarreada.matches.length, 9);
    });

    test('gana la corrida MÁS NUEVA, no la que alcanzó a guardarse', () {
      // **El caso que la regla anterior consagraba al revés.** `stored ??
      // inMemory` daba por buena la guardada por ser durable; con un recibo
      // viejo en la base y la corrida de recién sólo en memoria —porque su
      // recibo falló— el operador quedaba mirando el feed viejo. Durable no es
      // lo mismo que vigente.
      final vieja = SupplierNeedPortalSearchSnapshot(
        query: 'camara',
        status: SupplierNeedPortalSearchStatus.completed,
        checkedAt: DateTime.utc(2026, 8, 20),
        matches: matchSupplierNeedCandidates(
          _plan(const <SupplierNeedSearchPredicate>[]),
          _candidatos20260830().take(4).toList(growable: false),
        ),
        operationKey: 'corrida-vieja',
      );
      final acarreada = carrySupplierNeedPortalSearch(
        stored: vieja,
        inMemory: efimera,
        plan: _plan(const <SupplierNeedSearchPredicate>[]),
      )!;
      expect(acarreada.matches.length, _corrida20260830.length);
      expect(acarreada.checkedAt, efimera.checkedAt);
    });

    test('la misma corrida en las dos partes se resuelve por la guardada', () {
      // Misma `operationKey` = mismo recorrido. La guardada es su forma
      // durable y trae lo que el servidor validó, así que gana aunque la hora
      // no sea idéntica.
      final mismaCorridaGuardada = SupplierNeedPortalSearchSnapshot(
        query: efimera.query,
        status: efimera.status,
        checkedAt: DateTime.utc(2026, 8, 20),
        matches: efimera.matches.take(5).toList(growable: false),
        operationKey: efimera.operationKey,
      );
      final acarreada = carrySupplierNeedPortalSearch(
        stored: mismaCorridaGuardada,
        inMemory: efimera,
        plan: _plan(const <SupplierNeedSearchPredicate>[]),
      )!;
      expect(acarreada.matches.length, 5);
    });

    test('una lectura sin hora no puede declararse más nueva', () {
      final sinHora = SupplierNeedPortalSearchSnapshot(
        query: 'camara',
        status: SupplierNeedPortalSearchStatus.completed,
        checkedAt: null,
        matches: efimera.matches.take(2).toList(growable: false),
        operationKey: 'sin-hora',
      );
      // La de memoria sin hora no desplaza a una guardada que sí la tiene.
      final acarreada = carrySupplierNeedPortalSearch(
        stored: efimera,
        inMemory: sinHora,
        plan: _plan(const <SupplierNeedSearchPredicate>[]),
      )!;
      expect(acarreada.matches.length, _corrida20260830.length);
    });

    test('con recibo guardado manda el guardado, que es el durable', () {
      final guardada = SupplierNeedPortalSearchSnapshot(
        query: 'camara',
        status: SupplierNeedPortalSearchStatus.completed,
        checkedAt: DateTime.utc(2026, 8, 30, 5),
        matches: matchSupplierNeedCandidates(
          _plan(const <SupplierNeedSearchPredicate>[]),
          _candidatos20260830().take(3).toList(growable: false),
        ),
      );
      final acarreada = carrySupplierNeedPortalSearch(
        stored: guardada,
        inMemory: efimera,
        plan: _plan(const <SupplierNeedSearchPredicate>[]),
      );
      expect(acarreada!.matches.length, 3);
    });

    test(
        'rejuzgar no vuelve al portal: mismas filas, misma hora, misma '
        'cobertura', () {
      final acarreada = carrySupplierNeedPortalSearch(
        stored: null,
        inMemory: efimera,
        plan: _plan(const <SupplierNeedSearchPredicate>[_wheel700]),
        currentRevisionNo: 2,
      )!;
      // Una segunda navegación traería otras filas, otra hora y otra
      // cobertura. Que las tres sean idénticas es la prueba de que no la hubo.
      expect(
        acarreada.matches.map((match) => match.candidate.code).toSet(),
        efimera.matches.map((match) => match.candidate.code).toSet(),
      );
      expect(acarreada.matches.length, _corrida20260830.length);
      expect(acarreada.checkedAt, efimera.checkedAt);
      expect(acarreada.coverage.rowsObserved, 27);
      expect(acarreada.coverage.isComplete, isFalse);
    });

    test('con 700c quedan 17, y no pasa scooter, carretilla ni otra medida',
        () {
      final acarreada = carrySupplierNeedPortalSearch(
        stored: null,
        inMemory: efimera,
        plan: _plan(const <SupplierNeedSearchPredicate>[_wheel700]),
        currentRevisionNo: 2,
      )!;
      final vivos = acarreada.relevantMatches
          .map((match) => match.candidate.code)
          .toSet();

      expect(vivos.length, 17);
      expect(vivos, <String>{
        '14473',
        '5122',
        '6912',
        '6913',
        '12183',
        '3151',
        '7043',
        '13164',
        '10663',
        '10664',
        '13322',
        '18335',
        '18186',
        '18187',
        '10093',
        '17569',
        '10666',
      });

      // Lo que quedó fuera, nombrado por lo que es. `10873` y `1032` son
      // 28×1.5/8 —ISO 622, o sea 700c de hecho—, pero el catálogo no lo dice:
      // se quedan afuera por callarlo, que es la regla, no por contradecir.
      for (final entry in <String, String>{
        '18308': 'scooter aro 10',
        '18180': 'scooter aro 8½',
        '18207': 'carretilla 350×8',
        '14475': 'bicicleta aro 26',
        '16710': 'bicicleta aro 27.5',
        '16771': '28×1½, que es ISO 635 y no 700c',
        '10873': '28×1.5/8 sin decir 700',
        '1032': '28×1.5/8 sin decir 700',
      }.entries) {
        expect(vivos, isNot(contains(entry.key)), reason: entry.value);
      }
    });

    test('700c + válvula Auto deja EXACTAMENTE tres, y no la Dunlop', () {
      // **El objetivo real del dueño.** `700c` sólo demuestra el tamaño: de 27
      // deja 17, y eso todavía no es lo que se busca. La pregunta era cuáles
      // son 700c **y de válvula Auto**, y son tres.
      //
      // «Auto» acá es la válvula —Auto/Schrader, la gruesa de auto—, no el
      // vehículo. Por eso `V/AUTO` y `V/AMERICANA` cuentan, y `V/FRANCESA`
      // —que es Presta— no. La trampa es `13164`: se llama
      // `V/DUNLOP 35MM AUTOMATICA`, así que trae la palabra `AUTOMATICA`
      // pegada a una válvula **Dunlop**. Si el lector se quedara con la
      // palabra en vez del tipo declarado, entraría; su válvula contradice y
      // por eso no entra.
      final acarreada = carrySupplierNeedPortalSearch(
        stored: null,
        inMemory: efimera,
        plan: _plan(const <SupplierNeedSearchPredicate>[
          _wheel700,
          SupplierNeedSearchPredicate(
            field: 'valve_type',
            operator: 'eq',
            values: <Object>['schrader'],
          ),
        ]),
        currentRevisionNo: 2,
      )!;
      final vivos = acarreada.relevantMatches
          .map((match) => match.candidate.code)
          .toSet();

      expect(vivos, <String>{'14473', '10663', '18335'});
      expect(vivos.length, 3);

      for (final entry in <String, String>{
        '13164': 'V/DUNLOP 35MM AUTOMATICA: la palabra no es el tipo',
        '18308': 'scooter aro 10, que ya no era 700c',
        '18180': 'scooter aro 8½, que ya no era 700c',
        '6912': 'V/FRANCESA, o sea Presta',
        '10666': 'autosellante V/FRANCESA, o sea Presta',
      }.entries) {
        expect(vivos, isNot(contains(entry.key)), reason: entry.value);
      }

      // Y los tres que quedan lo declaran en su nombre, así que se confirman:
      // ninguno entra por callar la válvula.
      final tally = tallySupplierNeedMatchesUnder(
        matches: acarreada.matches,
        predicates: const <SupplierNeedSearchPredicate>[
          _wheel700,
          SupplierNeedSearchPredicate(
            field: 'valve_type',
            operator: 'eq',
            values: <Object>['schrader'],
          ),
        ],
        fields: _fields,
      );
      expect(tally.confirmed, 3);
      expect(tally.unverified, 0);
    });

    test('y ninguno de los 17 se declara confirmado sin decir su medida', () {
      final acarreada = carrySupplierNeedPortalSearch(
        stored: null,
        inMemory: efimera,
        plan: _plan(const <SupplierNeedSearchPredicate>[_wheel700]),
        currentRevisionNo: 2,
      )!;
      final tally = tallySupplierNeedMatchesUnder(
        matches: acarreada.matches,
        predicates: const <SupplierNeedSearchPredicate>[_wheel700],
        fields: _fields,
      );
      // Los 17 publican su aro en el nombre, así que sí se confirman. Lo que
      // no puede pasar es que se confirme más de lo que quedó vivo.
      expect(tally.confirmed + tally.unverified, 17);
      expect(tally.confirmed, lessThanOrEqualTo(17));
    });
  });
}

/// **La ficha efectiva sale de la petición, no de una inyección.**
///
/// La necesidad real se llama «Cámaras 700» y su categoría ya es cámaras, pero
/// ninguna revisión guardó `wheel_size`. Con eso el editor abría en «sin
/// especificar» **y** —lo grave— el feed se rejuzgaba como «cualquier cámara»:
/// la corrida del 2026-08-30 pasó de 18 a 22 filas «por revisar» e incluyó aro
/// 26, 27.5 y varias 28.
///
/// Estas pruebas parten de la descripción y la ficha de categoría reales. Nada
/// acá le entrega `700c` ya listo a nadie.
void _pruebasDeFichaEfectiva() {
  const peticion = 'Cámaras 700';
  const guardada = SupplyNeedCriteria(
    predicates: <SupplyNeedPredicate>[],
    categoryId: 'cat-tubes',
    categoryPath: 'Componentes / Ruedas / Cámaras',
    revisionNo: 1,
    technicalFamily: 'tube',
  );

  SupplyNeedCriteria efectiva([
    SupplyNeedCriteria stored = guardada,
    String description = peticion,
  ]) =>
      effectiveSupplyNeedCriteria(
        stored: stored,
        texts: <String>[description],
        fields: _fields,
      );

  group('la petición ya declara criterios y la ficha los recoge', () {
    test('«Cámaras 700» rinde wheel_size = 700c sin que nadie lo escriba', () {
      final ficha = efectiva();
      expect(ficha.predicates.length, 1);
      expect(ficha.predicates.single.field, 'wheel_size');
      expect(ficha.predicates.single.operator, 'eq');
      // El valor sale traducido al vocabulario de la ficha, no como el número
      // crudo que el texto trae.
      expect(ficha.predicates.single.values, <Object>['700c']);
    });

    test('lo guardado manda: una revisión explícita no se pisa', () {
      const explicita = SupplyNeedCriteria(
        predicates: <SupplyNeedPredicate>[
          SupplyNeedPredicate(
            field: 'wheel_size',
            operator: 'eq',
            values: <Object>['650b'],
          ),
        ],
        categoryId: 'cat-tubes',
        revisionNo: 4,
      );
      final ficha = efectiva(explicita);
      expect(ficha.predicates.single.values, <Object>['650b']);
    });

    test('otros specs de la petición se hidratan igual, no sólo el aro', () {
      // La válvula se lee del marcador, como en la fila del proveedor: la
      // hidratación no es una regla para `wheel_size`, es el lector completo.
      final ficha = efectiva(guardada, 'Cámara 700 x 25 válvula presta');
      final porCampo = <String, Object>{
        for (final predicate in ficha.predicates)
          predicate.field: predicate.values.single,
      };
      expect(porCampo['wheel_size'], '700c');
      expect(porCampo['valve_type'], 'presta');
    });

    test('«aro 700» también declara la medida', () {
      // La OTRA necesidad real de esta tienda. El lector exigía contexto
      // dimensional —`700x28`, `700c`, `29"`— y un número suelto no se lee,
      // que es la regla correcta: `700` puede ser un precio o un código. Pero
      // «aro» nombra el tamaño tan explícitamente como `V/` nombra la válvula,
      // y sin leerlo esta petición abría muda.
      final ficha = efectiva(
        guardada,
        'Cámaras aro 700 para reposición del taller',
      );
      expect(ficha.predicates.single.field, 'wheel_size');
      expect(ficha.predicates.single.values, <Object>['700c']);
    });

    test('un número suelto sin marcador ni medida sigue sin leerse', () {
      // La contracara: el marcador es lo que autoriza la lectura.
      for (final texto in const <String>[
        'Cámaras, presupuesto 700 pesos',
        'Cámaras código 700 del proveedor',
      ]) {
        expect(efectiva(guardada, texto).predicates, isEmpty, reason: texto);
      }
    });

    test('una petición que no declara nada no inventa criterios', () {
      final ficha = efectiva(guardada, 'Cámaras para el taller');
      expect(ficha.predicates, isEmpty);
      // Y devuelve la MISMA ficha guardada: sin derivación no hay instancia
      // nueva que dispare un resembrado del formulario.
      expect(identical(ficha, guardada), isTrue);
    });

    test('la ficha efectiva es un valor: dos derivaciones son iguales', () {
      // Sin igualdad por valor, cada build traía una instancia distinta y el
      // editor volvía a sembrarse encima de lo que el operador escribía.
      expect(efectiva(), efectiva());
      expect(efectiva().hashCode, efectiva().hashCode);
    });
  });

  group('y esa ficha es la que juzga el feed', () {
    test('con la ficha efectiva el feed deja 17 y ninguna otra medida', () {
      final ficha = efectiva();
      final predicados = ficha.predicates
          .map((predicate) => SupplierNeedSearchPredicate(
                field: predicate.field,
                operator: predicate.operator,
                values: predicate.values,
              ))
          .toList(growable: false);
      final acarreada = carrySupplierNeedPortalSearch(
        stored: null,
        inMemory: _lecturaEfimera(),
        plan: _plan(predicados),
        currentRevisionNo: 2,
      )!;
      final vivos = acarreada.relevantMatches
          .map((match) => match.candidate.code)
          .toSet();

      // **Se afirma el conjunto, no el número.** Un 17 escrito a mano no dice
      // nada sobre qué sobrevivió.
      expect(vivos, <String>{
        '14473',
        '5122',
        '6912',
        '6913',
        '12183',
        '3151',
        '7043',
        '13164',
        '10663',
        '10664',
        '13322',
        '18335',
        '18186',
        '18187',
        '10093',
        '17569',
        '10666',
      });
      for (final entry in <String, String>{
        '14475': 'aro 26',
        '16710': 'aro 27.5',
        '16771': '28×1½, que es ISO 635',
        '10873': '28×1.5/8 sin decir 700',
        '1032': '28×1.5/8 sin decir 700',
        '18308': 'scooter aro 10',
        '18180': 'scooter aro 8½',
        '18207': 'carretilla 350×8',
      }.entries) {
        expect(vivos, isNot(contains(entry.key)), reason: entry.value);
      }
    });

    test('sin ficha efectiva el feed vuelve a ser «cualquier cámara»', () {
      // El defecto que el owner vio en pantalla: sin `wheel_size`, aro 26 y
      // 27.5 entran al listado.
      final acarreada = carrySupplierNeedPortalSearch(
        stored: null,
        inMemory: _lecturaEfimera(),
        plan: _plan(const <SupplierNeedSearchPredicate>[]),
        currentRevisionNo: 2,
      )!;
      final vivos = acarreada.relevantMatches
          .map((match) => match.candidate.code)
          .toSet();
      expect(vivos, contains('14475'));
      expect(vivos, contains('16710'));
      expect(vivos.length, greaterThan(17));
    });
  });
}
