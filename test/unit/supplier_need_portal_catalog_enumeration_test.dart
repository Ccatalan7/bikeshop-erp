import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';

/// Enumeración por taxonomía: recall, terminación y cobertura.
///
/// El defecto que originó todo esto no era de calce sino de descubrimiento: la
/// primera página del buscador por palabra se presentaba como el catálogo de
/// la necesidad. Estas pruebas cubren lo único que lo evita — enumerar el nodo
/// completo, saber cuándo parar, y decir cuánto se alcanzó a mirar.

const String _routeTemplate =
    'http://www.rburgos.cl/sitio/aplicaciones/catalogo.asp'
    '?url=cat_sel_cf.asp&url1=cat_sel_sf.asp&folio=0'
    '&Clasificacion2={node}&paginaabsoluta={page}&tamanopagina={page_size}';

SupplierNeedPortalAdapter _adapter({
  bool taxonomy = true,
  int? resultCap,
  Map<String, dynamic>? budget,
}) =>
    SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
      'version': 1,
      'generic_family_search': true,
      if (resultCap != null) 'result_cap': resultCap,
      if (budget != null) 'budget': budget,
      'result_schema': <String, dynamic>{
        'columns': <String, dynamic>{
          'code': <String>['Código'],
          'name': <String>['Descripción'],
          'brand': <String>['Marca'],
          'origin': <String>['Origen'],
          'price': <String>['Valor'],
        },
        'no_result_phrases': <String>['No hay ningún producto que mostrar'],
      },
      if (taxonomy)
        'catalog_route': <String, dynamic>{
          'url_template': _routeTemplate,
          'page_size': 9,
          'first_page': 1,
          'max_pages_per_node': 12,
        },
      if (taxonomy)
        'taxonomy_discovery': <String, dynamic>{
          'url': 'http://www.rburgos.cl/sitio/aplicaciones/seleccion.asp'
              '?folio=0',
          'parent_field': 'Clasificacion1',
          'child_field': 'Clasificacion2',
        },
    });

SupplierNeedSearchRequest _tubeNeed({
  List<SupplierNeedSearchPredicate>? predicates,
  List<SupplierNeedSearchField>? fields,
}) =>
    SupplierNeedSearchRequest(
      needId: 'need-general-tubes',
      description: 'Cámaras aro 700 para reposición del taller',
      categoryId: 'category-tubes',
      categoryPath: 'Componentes / Ruedas / Cámaras',
      technicalFamily: 'tube',
      fields: fields ??
          const <SupplierNeedSearchField>[
            SupplierNeedSearchField(
              key: 'wheel_size',
              label: 'Tamaño de rueda',
              dataType: 'single_select',
              allowedValues: <Object>['700c'],
            ),
          ],
      predicates: predicates ??
          const <SupplierNeedSearchPredicate>[
            SupplierNeedSearchPredicate(
              field: 'wheel_size',
              operator: 'eq',
              values: <Object>['700c'],
            ),
          ],
    );

SupplierNeedSearchPlan _plan({
  bool taxonomy = true,
  int? resultCap,
  Map<String, dynamic>? budget,
  List<SupplierNeedSearchPredicate>? predicates,
}) =>
    buildSupplierNeedSearchPlan(
      request: _tubeNeed(predicates: predicates),
      adapter: _adapter(
        taxonomy: taxonomy,
        resultCap: resultCap,
        budget: budget,
      ),
      maxLength: 15,
    )!;

SupplierPortalTaxonomyNode _node(String id, String label) =>
    SupplierPortalTaxonomyNode(
      id: id,
      label: label,
      parentId: '13',
      parentLabel: 'NEUMATICOS Y CAMARAS',
    );

SupplierPortalCatalogTaxonomy _taxonomy({bool extraTubeNode = false}) =>
    SupplierPortalCatalogTaxonomy.fromNodes(
      <SupplierPortalTaxonomyNode>[
        _node('171', 'CAMARAS RUTA'),
        _node('172', 'CAMARAS MTB'),
        _node('173', 'CAMARAS BMX'),
        _node('112', 'NEUMATICOS RUTA'),
        _node('301', 'PARCHES Y PEGAMENTOS'),
        if (extraTubeNode) _node('174', 'CAMARAS PASEO'),
      ],
      discoveredAt: DateTime.utc(2026, 8, 28, 12),
    );

SupplierPortalCatalogCandidate _row(String code, String name) =>
    SupplierPortalCatalogCandidate(code: code, name: name, priceNet: 2240);

List<SupplierPortalCatalogCandidate> _rows(int count, {int from = 0}) =>
    List<SupplierPortalCatalogCandidate>.generate(
      count,
      (index) => _row(
        '${1000 + from + index}',
        'CAMARA 700X28/38C V/AUTO 48MM ${from + index}',
      ),
    );

SupplierNeedCatalogEnumerator _enumerator({
  required List<SupplierPortalTaxonomyNode> nodes,
  int? nodesAvailable,
  SupplierNeedPortalBudget budget = const SupplierNeedPortalBudget(),
  DateTime Function()? clock,
}) =>
    SupplierNeedCatalogEnumerator(
      route: SupplierNeedPortalCatalogRoute.fromJson(<String, dynamic>{
        'url_template': _routeTemplate,
        'page_size': 9,
        'first_page': 1,
        'max_pages_per_node': 12,
      }),
      budget: budget,
      nodes: nodes,
      nodesAvailable: nodesAvailable ?? nodes.length,
      clock: clock,
    );

/// Corre la enumeración entregando páginas ya preparadas.
SupplierNeedCatalogEnumerator _drive(
  SupplierNeedCatalogEnumerator enumerator,
  List<SupplierNeedCatalogPageResult> pages, {
  List<String>? visitedUrls,
}) {
  var index = 0;
  while (true) {
    final request = enumerator.next();
    if (request == null) break;
    visitedUrls?.add(request.url);
    enumerator.offer(
      index < pages.length
          ? pages[index]
          : const SupplierNeedCatalogPageResult(
              candidates: <SupplierPortalCatalogCandidate>[],
            ),
    );
    index++;
  }
  return enumerator;
}

void main() {
  group('ranking de nodos de taxonomía', () {
    test('elige los nodos de la familia y descarta los de otra', () {
      final nodes = _plan().rankNodes(_taxonomy());

      expect(
        nodes.map((node) => node.label),
        containsAll(<String>['CAMARAS RUTA', 'CAMARAS MTB', 'CAMARAS BMX']),
      );
      // El padre «NEUMATICOS Y CAMARAS» desempata, nunca califica: si bastara,
      // se enumerarían neumáticos para pedir cámaras.
      expect(
          nodes.map((node) => node.label), isNot(contains('NEUMATICOS RUTA')));
      expect(
        nodes.map((node) => node.label),
        isNot(contains('PARCHES Y PEGAMENTOS')),
      );
    });

    test('«700» es criterio de la ficha, no universo del proveedor', () {
      final withSize = _plan().rankNodes(_taxonomy());
      final withoutSize = _plan(
        predicates: const <SupplierNeedSearchPredicate>[],
      ).rankNodes(_taxonomy());

      // El predicado técnico no puede cambiar QUÉ se mira: sólo qué califica
      // después. Si acotara el descubrimiento, volvería el defecto original.
      expect(
        withSize.map((node) => node.id),
        withoutSize.map((node) => node.id),
      );
    });

    test('el presupuesto de nodos no se excede y queda declarado', () {
      final nodes = _plan().rankNodes(_taxonomy(extraTubeNode: true));
      expect(nodes.length, 3);

      final available = countSupplierTaxonomyCandidates(
        taxonomy: _taxonomy(extraTubeNode: true),
        familyTerms: _plan().familyTerms,
        excludedTerms: _plan().excludedTerms,
      );
      expect(available, 4);
    });

    test('la frescura la fecha el servidor, no el payload', () {
      final forged = SupplierPortalCatalogTaxonomy.fromJson(<String, dynamic>{
        'nodes': <Map<String, dynamic>>[
          <String, dynamic>{'id': '171', 'label': 'CAMARAS RUTA'},
        ],
        'fingerprint': 'abc12345',
        // Una fecha futura dentro del jsonb dejaría el caché fresco para
        // siempre y el portal no se volvería a leer nunca.
        'discoveredAt': '2099-01-01T00:00:00Z',
      });
      expect(forged.isFresh(const Duration(hours: 24)), isTrue);

      final serverStamped = forged.withServerDiscoveredAt(
        DateTime.now().toUtc().subtract(const Duration(days: 3)),
      );
      expect(serverStamped.isFresh(const Duration(hours: 24)), isFalse);
      expect(serverStamped.nodes, forged.nodes);
      expect(serverStamped.fingerprint, forged.fingerprint);
    });

    test('sin fecha del servidor la taxonomía se trata como vencida', () {
      // Conservar la del payload «porque es lo único que hay» es el agujero:
      // el reemplazo es siempre, incluso con null.
      final forged = SupplierPortalCatalogTaxonomy.fromJson(<String, dynamic>{
        'nodes': <Map<String, dynamic>>[
          <String, dynamic>{'id': '171', 'label': 'CAMARAS RUTA'},
        ],
        'fingerprint': 'abc12345',
        'discoveredAt': '2099-01-01T00:00:00Z',
      });

      expect(
        forged.withServerDiscoveredAt(null).isFresh(const Duration(hours: 24)),
        isFalse,
      );
    });

    test('la huella es estable y cambia cuando cambia la taxonomía', () {
      expect(_taxonomy().fingerprint, _taxonomy().fingerprint);
      expect(
        _taxonomy().fingerprint,
        isNot(_taxonomy(extraTubeNode: true).fingerprint),
      );
    });
  });

  group('enumeración paginada', () {
    test('9 / 9 / 1 cierra el nodo con 19 códigos únicos', () {
      final enumerator = _drive(
        _enumerator(
            nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')]),
        <SupplierNeedCatalogPageResult>[
          SupplierNeedCatalogPageResult(candidates: _rows(9)),
          SupplierNeedCatalogPageResult(candidates: _rows(9, from: 9)),
          SupplierNeedCatalogPageResult(candidates: _rows(1, from: 18)),
        ],
      );

      final coverage = enumerator.coverage();
      expect(enumerator.candidates.length, 19);
      expect(coverage.pagesFetched, 3);
      expect(coverage.rowsUnique, 19);
      expect(coverage.isComplete, isTrue);
      expect(coverage.limit, SupplierNeedCoverageLimit.enumerated);
      expect(coverage.isActionable, isTrue);
    });

    test('9 / 9 / 9 / 0 necesita la página vacía para cerrar', () {
      final enumerator = _drive(
        _enumerator(
            nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')]),
        <SupplierNeedCatalogPageResult>[
          SupplierNeedCatalogPageResult(candidates: _rows(9)),
          SupplierNeedCatalogPageResult(candidates: _rows(9, from: 9)),
          SupplierNeedCatalogPageResult(candidates: _rows(9, from: 18)),
          const SupplierNeedCatalogPageResult(
            candidates: <SupplierPortalCatalogCandidate>[],
          ),
        ],
      );

      final coverage = enumerator.coverage();
      expect(enumerator.candidates.length, 27);
      expect(coverage.pagesFetched, 4);
      expect(coverage.isComplete, isTrue);
    });

    test('la URL pedida lleva nodo, página y tamaño reales', () {
      final visited = <String>[];
      _drive(
        _enumerator(
            nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')]),
        <SupplierNeedCatalogPageResult>[
          SupplierNeedCatalogPageResult(candidates: _rows(9)),
          SupplierNeedCatalogPageResult(candidates: _rows(1, from: 9)),
        ],
        visitedUrls: visited,
      );

      expect(visited.first, contains('Clasificacion2=171'));
      expect(visited.first, contains('paginaabsoluta=1'));
      expect(visited.first, contains('tamanopagina=9'));
      expect(visited[1], contains('paginaabsoluta=2'));
    });

    test('una página que repite lo anterior corta por ciclo, no por fe', () {
      final repeated = _rows(9);
      final enumerator = _drive(
        _enumerator(
            nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')]),
        <SupplierNeedCatalogPageResult>[
          SupplierNeedCatalogPageResult(candidates: repeated),
          SupplierNeedCatalogPageResult(candidates: repeated),
        ],
      );

      final coverage = enumerator.coverage();
      expect(enumerator.candidates.length, 9);
      expect(coverage.limit, SupplierNeedCoverageLimit.loopDetected);
      expect(coverage.isComplete, isFalse);
      // Las filas se vieron de verdad: el corte fue defensivo, no una rotura.
      expect(coverage.isActionable, isTrue);
    });

    test('el tope de páginas deja la cobertura parcial y accionable', () {
      final enumerator = _drive(
        _enumerator(
          nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')],
          budget: const SupplierNeedPortalBudget(maxPages: 2),
        ),
        <SupplierNeedCatalogPageResult>[
          SupplierNeedCatalogPageResult(candidates: _rows(9)),
          SupplierNeedCatalogPageResult(candidates: _rows(9, from: 9)),
          SupplierNeedCatalogPageResult(candidates: _rows(9, from: 18)),
        ],
      );

      final coverage = enumerator.coverage();
      expect(coverage.pagesFetched, 2);
      expect(coverage.limit, SupplierNeedCoverageLimit.maxPages);
      expect(coverage.isComplete, isFalse);
      expect(coverage.isActionable, isTrue);
    });

    test('el tope de filas detiene antes de pedir otra página', () {
      final enumerator = _drive(
        _enumerator(
          nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')],
          budget: const SupplierNeedPortalBudget(maxRows: 9),
        ),
        <SupplierNeedCatalogPageResult>[
          SupplierNeedCatalogPageResult(candidates: _rows(9)),
          SupplierNeedCatalogPageResult(candidates: _rows(9, from: 9)),
        ],
      );

      expect(enumerator.coverage().pagesFetched, 1);
      expect(enumerator.coverage().limit, SupplierNeedCoverageLimit.maxRows);
    });

    test('el reloj de pared corta aunque el portal siga contestando', () {
      var now = DateTime.utc(2026, 8, 28, 12);
      final enumerator = _enumerator(
        nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')],
        budget: const SupplierNeedPortalBudget(
          wallClock: Duration(seconds: 30),
        ),
        clock: () => now,
      );

      expect(enumerator.next(), isNotNull);
      enumerator.offer(SupplierNeedCatalogPageResult(candidates: _rows(9)));
      now = now.add(const Duration(seconds: 31));

      expect(enumerator.next(), isNull);
      expect(
        enumerator.coverage().limit,
        SupplierNeedCoverageLimit.wallClock,
      );
    });

    test('varios nodos se deduplican por código', () {
      final enumerator = _drive(
        _enumerator(
          nodes: <SupplierPortalTaxonomyNode>[
            _node('171', 'CAMARAS RUTA'),
            _node('172', 'CAMARAS MTB'),
          ],
        ),
        <SupplierNeedCatalogPageResult>[
          SupplierNeedCatalogPageResult(candidates: _rows(4)),
          SupplierNeedCatalogPageResult(candidates: _rows(6)),
        ],
      );

      // 4 + 6 filas observadas, 4 repetidas: 6 únicas.
      expect(enumerator.coverage().rowsObserved, 10);
      expect(enumerator.candidates.length, 6);
      expect(enumerator.duplicates, 4);
      expect(enumerator.coverage().isComplete, isTrue);
    });

    test('dejar nodos sin revisar nunca se declara completo', () {
      final enumerator = _drive(
        _enumerator(
          nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')],
          nodesAvailable: 4,
        ),
        <SupplierNeedCatalogPageResult>[
          SupplierNeedCatalogPageResult(candidates: _rows(1)),
        ],
      );

      final coverage = enumerator.coverage();
      expect(coverage.limit, SupplierNeedCoverageLimit.maxNodes);
      expect(coverage.isComplete, isFalse);
      expect(coverage.sentence, contains('sin revisar'));
    });

    test('truncar para guardar tampoco es cobertura completa', () {
      final enumerator = _drive(
        _enumerator(
            nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')]),
        <SupplierNeedCatalogPageResult>[
          SupplierNeedCatalogPageResult(candidates: _rows(9)),
          SupplierNeedCatalogPageResult(candidates: _rows(1, from: 9)),
        ],
      );

      expect(enumerator.coverage().isComplete, isTrue);
      final capped = enumerator.coverage(rowsPersisted: 5);
      expect(capped.limit, SupplierNeedCoverageLimit.storageCap);
      expect(capped.isComplete, isFalse);
      expect(capped.truncatedForStorage, isTrue);
    });
  });

  group('invariantes rotas: evidencia, no opciones', () {
    test('la sesión vencida a mitad de camino invalida lo enumerado', () {
      final enumerator = _drive(
        _enumerator(
            nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')]),
        <SupplierNeedCatalogPageResult>[
          SupplierNeedCatalogPageResult(candidates: _rows(9)),
          const SupplierNeedCatalogPageResult.sessionExpired(),
        ],
      );

      final coverage = enumerator.coverage();
      expect(coverage.limit, SupplierNeedCoverageLimit.sessionExpired);
      expect(coverage.isComplete, isFalse);
      // Vio 9 filas y no sirven como opciones: no se puede distinguir «el
      // portal mostró menos» de «dejamos de ver».
      expect(coverage.isActionable, isFalse);
      expect(coverage.rowsUnique, 9);
    });

    test('una tabla que existe y no calza es deriva, no página vacía', () {
      final enumerator = _drive(
        _enumerator(
            nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')]),
        <SupplierNeedCatalogPageResult>[
          const SupplierNeedCatalogPageResult(
            candidates: <SupplierPortalCatalogCandidate>[],
            tablesSeen: 2,
            schemaMatched: false,
          ),
        ],
      );

      final coverage = enumerator.coverage();
      expect(coverage.limit, SupplierNeedCoverageLimit.parserDrift);
      expect(coverage.isComplete, isFalse);
      expect(coverage.isActionable, isFalse);
    });

    test('texto mal decodificado se reporta como tal, no como catálogo vacío',
        () {
      final enumerator = _drive(
        _enumerator(
            nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')]),
        <SupplierNeedCatalogPageResult>[
          const SupplierNeedCatalogPageResult(
            candidates: <SupplierPortalCatalogCandidate>[],
            misdecoded: true,
          ),
        ],
      );

      expect(
        enumerator.coverage().limit,
        SupplierNeedCoverageLimit.encoding,
      );
      expect(enumerator.coverage().isActionable, isFalse);
    });

    test('el transporte caído no es un catálogo sin productos', () {
      final enumerator = _drive(
        _enumerator(
            nodes: <SupplierPortalTaxonomyNode>[_node('171', 'CAMARAS RUTA')]),
        const <SupplierNeedCatalogPageResult>[
          SupplierNeedCatalogPageResult.transportFailed(),
        ],
      );

      expect(
        enumerator.coverage().limit,
        SupplierNeedCoverageLimit.transport,
      );
      expect(enumerator.coverage().isActionable, isFalse);
    });
  });

  group('encoding real de la fixture', () {
    File fixture(int page) =>
        File('test/fixtures/supplier_portal/rbx_camaras_ruta_page$page.html');

    test('los bytes del portal son Windows-1252, no UTF-8', () {
      final bytes = fixture(1).readAsBytesSync();

      final asLatin1 = latin1.decode(bytes);
      expect(asLatin1, contains('Código'));
      expect(asLatin1, contains('Descripción'));
      expect(supplierPortalTextLooksMisdecoded(asLatin1), isFalse);

      final asUtf8 = utf8.decode(bytes, allowMalformed: true);
      expect(asUtf8, isNot(contains('Código')));
      expect(supplierPortalTextLooksMisdecoded(asUtf8), isTrue);
    });

    test('la fixture reparte 9 / 9 / 1 / 0 con 19 códigos únicos', () {
      final codes = <String>[];
      var pagesWithRows = 0;
      for (var page = 1; page <= 4; page++) {
        final html = latin1.decode(fixture(page).readAsBytesSync());
        final rows = RegExp(r'<td>(\d{5})</td>').allMatches(html);
        if (rows.isNotEmpty) pagesWithRows++;
        codes.addAll(rows.map((match) => match.group(1)!));
      }

      expect(pagesWithRows, 3);
      expect(codes.length, 19);
      expect(codes.toSet().length, 19);
      // La página vacía sigue dibujando «Siguiente»: por eso no se le cree.
      expect(
        latin1.decode(fixture(4).readAsBytesSync()),
        contains('Siguiente'),
      );
    });
  });

  group('calce determinista sobre lo enumerado', () {
    List<SupplierPortalCatalogCandidate> fixtureRows() {
      final rows = <SupplierPortalCatalogCandidate>[];
      for (var page = 1; page <= 3; page++) {
        final html = latin1.decode(
          File('test/fixtures/supplier_portal/rbx_camaras_ruta_page$page.html')
              .readAsBytesSync(),
        );
        for (final match
            in RegExp(r'<td>(\d{5})</td><td>([^<]+)</td>').allMatches(html)) {
          rows.add(_row(match.group(1)!, match.group(2)!));
        }
      }
      return rows;
    }

    test('los dos neumáticos mal clasificados caen por contradicción', () {
      final matches = matchSupplierNeedCandidates(_plan(), fixtureRows());
      final byCode = <String, SupplierNeedPortalMatch>{
        for (final match in matches) match.candidate.code: match,
      };

      expect(byCode['12010']!.state, SupplierNeedMatchState.conflict);
      expect(byCode['17570']!.state, SupplierNeedMatchState.conflict);
      expect(byCode['12010']!.conflictingFields, contains('product_family'));
      // Caen por lo que SON, no por su medida: ambos son 700 y aun así no son
      // cámaras. Un nodo mal clasificado del proveedor no reclasifica nada.
      expect(byCode['17570']!.observedFacts['wheel_size'], 700);
    });

    test('un número suelto no se toma por una medida', () {
      final matches = matchSupplierNeedCandidates(
        _plan(),
        <SupplierPortalCatalogCandidate>[
          // El 48 es el largo de la válvula, y el 60 también: sin contexto
          // dimensional no hay tamaño que afirmar.
          _row('90001', 'CAMARA V/AUTO 48MM CAJA 60 UNIDADES'),
        ],
      );

      expect(matches.single.observedFacts.containsKey('wheel_size'), isFalse);
      expect(matches.single.state, SupplierNeedMatchState.possible);
      expect(matches.single.missingFields, contains('wheel_size'));
    });

    test('dos tamaños distintos en la misma fila quedan sin afirmar', () {
      final matches = matchSupplierNeedCandidates(
        _plan(),
        <SupplierPortalCatalogCandidate>[
          _row('90002', 'CAMARA 700X28C Y 26X1.75 SURTIDO'),
        ],
      );

      expect(matches.single.observedFacts.containsKey('wheel_size'), isFalse);
      expect(matches.single.state, SupplierNeedMatchState.possible);
    });

    test('700 califica y las otras medidas quedan fuera de las opciones', () {
      final matches = matchSupplierNeedCandidates(_plan(), fixtureRows());
      final snapshot = SupplierNeedPortalSearchSnapshot(
        query: 'camara',
        status: SupplierNeedPortalSearchStatus.completed,
        checkedAt: DateTime.utc(2026, 8, 28),
        matches: matches,
        coverage: SupplierNeedPortalCoverage(
          method: SupplierNeedCoverageMethod.taxonomy,
          isComplete: true,
          limit: SupplierNeedCoverageLimit.enumerated,
          nodeLabels: const <String>['CAMARAS RUTA'],
          rowsUnique: matches.length,
          rowsPersisted: matches.length,
        ),
      );

      expect(matches.length, 19);
      // Enumerar sin leer la medida sólo cambia 10 filas vagas por 19: las
      // diez cámaras 700 se prueban, las otras siete medidas se eliminan.
      expect(snapshot.exactCount, 10);
      expect(snapshot.relevantCount, 10);
      for (final match in snapshot.relevantMatches) {
        expect(match.candidate.name, startsWith('CAMARA 700'));
        expect(match.observedFacts['wheel_size'], 700);
        expect(match.provenFields, contains('wheel_size'));
      }
      expect(snapshot.conflictCount, 9);
      expect(snapshot.optionsSummaryLabel, contains('10 opciones exactas'));
      expect(snapshot.optionsSummaryLabel, contains('19 productos revisados'));
      expect(snapshot.optionsSummaryLabel, contains('Cobertura completa'));
    });
  });

  group('lo que la fila del proveedor puede afirmar', () {
    SupplierNeedPortalSearchSnapshot snapshot({
      required bool complete,
      SupplierNeedPortalSearchStatus status =
          SupplierNeedPortalSearchStatus.noMatches,
    }) =>
        SupplierNeedPortalSearchSnapshot(
          query: 'camara',
          status: status,
          checkedAt: DateTime.utc(2026, 8, 28),
          matches: const <SupplierNeedPortalMatch>[],
          coverage: SupplierNeedPortalCoverage(
            method: SupplierNeedCoverageMethod.taxonomy,
            isComplete: complete,
            limit: complete
                ? SupplierNeedCoverageLimit.enumerated
                : SupplierNeedCoverageLimit.maxPages,
            nodeLabels: const <String>['CAMARAS RUTA'],
            rowsUnique: 19,
          ),
          // Afirmar la ausencia exige además que la lectura responda la ficha
          // vigente: sin esto la fixture prueba media invariante.
          searchRevisionNo: 3,
          currentRevisionNo: 3,
        );

    test('sin cobertura completa jamás se afirma la ausencia', () {
      expect(snapshot(complete: false).rowLabel, 'No apareció');
      expect(snapshot(complete: false).canAssertAbsence, isFalse);
      expect(
        snapshot(complete: false).detailLabel,
        contains('no se alcanzó a revisar el catálogo completo'),
      );
    });

    test('con el catálogo recorrido entero sí se puede decir que no lo tiene',
        () {
      expect(snapshot(complete: true).rowLabel, 'No lo tiene');
      expect(snapshot(complete: true).canAssertAbsence, isTrue);
      expect(
        snapshot(complete: true).detailLabel,
        contains('«CAMARAS RUTA»'),
      );
    });

    test('omitido por tope y contradicho no son lo mismo', () {
      // 200 enumeradas, 120 guardadas por el tope, 100 relevantes. Sumar
      // 200-100 diría «100 contradicen la ficha» sobre 80 productos que nadie
      // llegó a comparar.
      final snapshot = SupplierNeedPortalSearchSnapshot(
        query: 'camara',
        status: SupplierNeedPortalSearchStatus.completed,
        checkedAt: DateTime.utc(2026, 8, 28),
        matches: <SupplierNeedPortalMatch>[
          for (var index = 0; index < 100; index++)
            SupplierNeedPortalMatch(
              candidate: _row('7$index', 'CAMARA 700X28C $index'),
              state: SupplierNeedMatchState.exact,
              provenFields: const <String>['product_family', 'wheel_size'],
              missingFields: const <String>[],
              conflictingFields: const <String>[],
            ),
          for (var index = 0; index < 20; index++)
            SupplierNeedPortalMatch(
              candidate: _row('9$index', 'NEUMATICO 700X23C $index'),
              state: SupplierNeedMatchState.conflict,
              provenFields: const <String>[],
              missingFields: const <String>[],
              conflictingFields: const <String>['product_family'],
            ),
        ],
        coverage: const SupplierNeedPortalCoverage(
          method: SupplierNeedCoverageMethod.taxonomy,
          isComplete: false,
          limit: SupplierNeedCoverageLimit.storageCap,
          nodeLabels: <String>['CAMARAS RUTA'],
          rowsObserved: 210,
          rowsUnique: 200,
          rowsPersisted: 120,
        ),
      );

      expect(snapshot.relevantCount, 100);
      expect(snapshot.discardedByConflict, 20);
      expect(snapshot.omittedByCap, 80);
      expect(snapshot.optionsSummaryLabel, contains('100 opciones exactas'));
      expect(
        snapshot.optionsSummaryLabel,
        contains('20 de 120 contradicen la ficha'),
      );
      expect(
        snapshot.optionsSummaryLabel,
        contains('80 quedaron sin evaluar por el tope de guardado'),
      );
      // Lo que NO puede decir: que los 80 omitidos contradigan nada.
      expect(
        snapshot.optionsSummaryLabel,
        isNot(contains('100 de 120 contradicen')),
      );
      expect(snapshot.canAssertAbsence, isFalse);
    });

    test('sin truncamiento el encabezado no inventa omitidos', () {
      final snapshot = SupplierNeedPortalSearchSnapshot(
        query: 'camara',
        status: SupplierNeedPortalSearchStatus.completed,
        checkedAt: DateTime.utc(2026, 8, 28),
        matches: <SupplierNeedPortalMatch>[
          SupplierNeedPortalMatch(
            candidate: _row('10001', 'CAMARA 700X28C'),
            state: SupplierNeedMatchState.exact,
            provenFields: const <String>['product_family', 'wheel_size'],
            missingFields: const <String>[],
            conflictingFields: const <String>[],
          ),
        ],
        coverage: const SupplierNeedPortalCoverage(
          method: SupplierNeedCoverageMethod.taxonomy,
          isComplete: true,
          limit: SupplierNeedCoverageLimit.enumerated,
          nodeLabels: <String>['CAMARAS RUTA'],
          rowsUnique: 1,
          rowsPersisted: 1,
        ),
      );

      expect(snapshot.omittedByCap, 0);
      expect(snapshot.discardedByConflict, 0);
      expect(snapshot.optionsSummaryLabel, contains('1 opción exacta'));
      expect(snapshot.optionsSummaryLabel, contains('Cobertura completa'));
      expect(snapshot.optionsSummaryLabel, isNot(contains('sin evaluar')));
      expect(snapshot.optionsSummaryLabel, isNot(contains('contradice')));
    });

    test('la cobertura sobrevive al viaje por la base', () {
      final coverage = SupplierNeedPortalCoverage(
        method: SupplierNeedCoverageMethod.taxonomy,
        isComplete: false,
        limit: SupplierNeedCoverageLimit.maxNodes,
        nodeIds: const <String>['171', '172'],
        nodeLabels: const <String>['CAMARAS RUTA', 'CAMARAS MTB'],
        nodesAvailable: 4,
        nodesPlanned: 2,
        nodesCompleted: 2,
        pagesFetched: 5,
        rowsObserved: 28,
        rowsUnique: 19,
        rowsPersisted: 19,
        checkedAt: DateTime.utc(2026, 8, 28),
      );

      final restored = SupplierNeedPortalCoverage.fromJson(
        jsonDecode(jsonEncode(coverage.toJson())),
      );

      expect(restored.limit, SupplierNeedCoverageLimit.maxNodes);
      expect(restored.isComplete, isFalse);
      expect(restored.nodeLabels, coverage.nodeLabels);
      expect(restored.rowsUnique, 19);
      expect(restored.isActionable, isTrue);
    });
  });

  group('una lectura sabe a qué pregunta contestó', () {
    SupplierNeedPortalSearchSnapshot snapshot({
      int? searchRevision,
      int? currentRevision,
      bool complete = true,
    }) =>
        SupplierNeedPortalSearchSnapshot(
          query: 'camara',
          status: SupplierNeedPortalSearchStatus.completed,
          checkedAt: DateTime.now().toUtc(),
          matches: <SupplierNeedPortalMatch>[
            SupplierNeedPortalMatch(
              candidate: _row('10001', 'CAMARA 700X28C'),
              state: SupplierNeedMatchState.exact,
              provenFields: const <String>['product_family', 'wheel_size'],
              missingFields: const <String>[],
              conflictingFields: const <String>[],
              observedFacts: const <String, Object?>{'wheel_size': 700},
            ),
          ],
          coverage: SupplierNeedPortalCoverage(
            method: SupplierNeedCoverageMethod.taxonomy,
            isComplete: complete,
            limit: complete
                ? SupplierNeedCoverageLimit.enumerated
                : SupplierNeedCoverageLimit.maxPages,
            nodeLabels: const <String>['CAMARAS RUTA'],
            rowsUnique: 1,
            rowsPersisted: 1,
          ),
          searchRevisionNo: searchRevision,
          currentRevisionNo: currentRevision,
        );

    test('la antigüedad que importa no es la del reloj', () {
      // Una lectura de hace dos minutos contra la ficha anterior es más vieja,
      // para esta pregunta, que una de ayer contra la ficha vigente.
      final stale = snapshot(searchRevision: 2, currentRevision: 3);
      expect(stale.answersCurrentRevision, isFalse);
      expect(stale.rowLabel, 'Ficha anterior');
      expect(
        stale.optionsSummaryLabel,
        contains('revisadas con la ficha anterior'),
      );

      final fresh = snapshot(searchRevision: 3, currentRevision: 3);
      expect(fresh.answersCurrentRevision, isTrue);
      expect(fresh.rowLabel, isNot('Ficha anterior'));
    });

    test('la ausencia exige cobertura completa Y revisión vigente', () {
      expect(
        snapshot(searchRevision: 3, currentRevision: 3).canAssertAbsence,
        isTrue,
      );
      // Recorrer entero el catálogo de la ficha ANTERIOR no autoriza a decir
      // «no lo tiene» sobre la ficha nueva.
      expect(
        snapshot(searchRevision: 2, currentRevision: 3).canAssertAbsence,
        isFalse,
      );
      expect(
        snapshot(searchRevision: 3, currentRevision: 3, complete: false)
            .canAssertAbsence,
        isFalse,
      );
    });

    test('un recibo sin revisiones falla cerrado', () {
      // Anterior a este contrato: no se puede demostrar que sea vigente.
      expect(snapshot().answersCurrentRevision, isFalse);
      expect(snapshot().canAssertAbsence, isFalse);
    });

    test('volver a evaluar sí responde la pregunta nueva', () {
      final stale = snapshot(searchRevision: 2, currentRevision: 3);
      final rematched = rematchSupplierNeedPortalSnapshot(_plan(), stale);

      expect(rematched.answersCurrentRevision, isTrue);
      // La procedencia no se toca: no se pretende una segunda visita.
      expect(rematched.checkedAt, stale.checkedAt);
      expect(rematched.coverage.pagesFetched, stale.coverage.pagesFetched);
    });
  });

  group('precisar filtra el feed ya leído, sin red', () {
    /// El feed real: dos cámaras 700 que sólo se distinguen por la válvula.
    SupplierNeedPortalSearchSnapshot feed() => SupplierNeedPortalSearchSnapshot(
          query: 'camara',
          status: SupplierNeedPortalSearchStatus.completed,
          checkedAt: DateTime.utc(2026, 8, 29, 10),
          matches: matchSupplierNeedCandidates(
            _plan(),
            <SupplierPortalCatalogCandidate>[
              _row('10001', 'CAMARA 700X28C V/PRESTA 60MM'),
              _row('10002', 'CAMARA 700X28C V/AUTO 48MM'),
            ],
          ),
          coverage: const SupplierNeedPortalCoverage(
            method: SupplierNeedCoverageMethod.taxonomy,
            isComplete: true,
            limit: SupplierNeedCoverageLimit.enumerated,
            nodeLabels: <String>['CAMARAS RUTA'],
            pagesFetched: 3,
            rowsUnique: 2,
            rowsPersisted: 2,
          ),
          searchRevisionNo: 3,
          currentRevisionNo: 4,
          evaluatedRevisionNo: 3,
        );

    /// La ficha nueva: además de 700, válvula Presta.
    SupplierNeedSearchPlan prestaPlan() => buildSupplierNeedSearchPlan(
          request: _tubeNeed(
            predicates: const <SupplierNeedSearchPredicate>[
              SupplierNeedSearchPredicate(
                field: 'wheel_size',
                operator: 'eq',
                values: <Object>['700c'],
              ),
              SupplierNeedSearchPredicate(
                field: 'valve_type',
                operator: 'eq',
                values: <Object>['presta'],
              ),
            ],
            // El calce sólo puede juzgar un campo que la ficha declara: sin
            // esta definición la válvula queda «no observada» y las dos
            // cámaras siguen siendo opciones.
            fields: const <SupplierNeedSearchField>[
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
            ],
          ),
          adapter: _adapter(),
          maxLength: 15,
        )!;

    test('la lista visible queda sólo con lo que cumple la ficha nueva', () {
      final before = feed();
      // Con la ficha anterior las dos son opciones: sólo se pedía 700.
      expect(before.relevantCount, 2);

      final after = rematchSupplierNeedPortalSnapshot(prestaPlan(), before);

      expect(after.matches.length, 2, reason: 'el feed crudo no se pierde');
      expect(after.relevantCount, 1);
      expect(
        after.relevantMatches.single.candidate.name,
        contains('PRESTA'),
      );
      expect(after.exactCount, 1);
      expect(after.conflictCount, 1);
    });

    test('el veredicto pasa a ser de ahora sin inventar una segunda visita',
        () {
      final before = feed();
      final after = rematchSupplierNeedPortalSnapshot(prestaPlan(), before);

      // Responde la pregunta de ahora…
      expect(after.answersCurrentRevision, isTrue);
      expect(after.verdictRevisionNo, 4);
      // …pero la procedencia no se toca: cuándo se leyó, para qué ficha, y
      // con qué cobertura. Pisar esto haría parecer que hubo otra consulta.
      expect(after.searchRevisionNo, 3);
      expect(after.checkedAt, before.checkedAt);
      expect(after.coverage.pagesFetched, 3);
      expect(after.reusesEarlierReading, isTrue);
      expect(
        after.optionsSummaryLabel,
        contains('evaluadas sobre lo que ya habíamos leído'),
      );
    });

    test('la ausencia se puede volver a afirmar sobre la ficha nueva', () {
      // La cobertura sigue siendo completa y el veredicto ya es el de ahora:
      // el universo no cambió, cambió el criterio.
      final after = rematchSupplierNeedPortalSnapshot(prestaPlan(), feed());
      expect(after.canAssertAbsence, isTrue);

      // Sin volver a evaluar, no: el veredicto guardado es de otra ficha.
      expect(feed().canAssertAbsence, isFalse);
    });
  });

  group('cuántas cumplirían con otra ficha, sin volver a consultar', () {
    List<SupplierNeedPortalMatch> rows() => <SupplierNeedPortalMatch>[
          SupplierNeedPortalMatch(
            candidate: _row('1', 'CAMARA 700X28C V/AUTO'),
            state: SupplierNeedMatchState.exact,
            provenFields: const <String>['product_family', 'wheel_size'],
            missingFields: const <String>[],
            conflictingFields: const <String>[],
            observedFacts: const <String, Object?>{
              'wheel_size': 700,
              'valve_type': 'schrader',
            },
          ),
          SupplierNeedPortalMatch(
            candidate: _row('2', 'CAMARA 700X23C V/PRESTA'),
            state: SupplierNeedMatchState.exact,
            provenFields: const <String>['product_family', 'wheel_size'],
            missingFields: const <String>[],
            conflictingFields: const <String>[],
            observedFacts: const <String, Object?>{
              'wheel_size': 700,
              'valve_type': 'presta',
            },
          ),
          SupplierNeedPortalMatch(
            candidate: _row('3', 'CAMARA 700X30C'),
            state: SupplierNeedMatchState.possible,
            provenFields: const <String>['product_family', 'wheel_size'],
            missingFields: const <String>['valve_type'],
            conflictingFields: const <String>[],
            observedFacts: const <String, Object?>{'wheel_size': 700},
          ),
          SupplierNeedPortalMatch(
            candidate: _row('4', 'NEUMATICO 700X23C'),
            state: SupplierNeedMatchState.conflict,
            provenFields: const <String>[],
            missingFields: const <String>[],
            conflictingFields: const <String>['product_family'],
            observedFacts: const <String, Object?>{'wheel_size': 700},
          ),
        ];

    test('una precisión acota, y el número se puede decir antes de guardar',
        () {
      expect(
        tallySupplierNeedMatchesUnder(
          matches: rows(),
          predicates: const <SupplierNeedSearchPredicate>[
            SupplierNeedSearchPredicate(
              field: 'valve_type',
              operator: 'eq',
              values: <Object>['presta'],
            ),
          ],
        ),
        // La schrader se contradice; la presta y la que no publica válvula
        // siguen. El neumático ya estaba fuera por no ser una cámara. Pero las
        // dos que quedan no valen lo mismo: una lo dice y la otra calla.
        const SupplierNeedMatchTally(confirmed: 1, unverified: 1),
      );
    });

    test('una omisión no es un rechazo', () {
      // La fila 3 no publica válvula: sigue siendo una opción por revisar,
      // igual que en el calce real. Descartarla sería inventar una medida.
      final surviving = tallySupplierNeedMatchesUnder(
        matches: rows(),
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'valve_type',
            operator: 'eq',
            values: <Object>['schrader'],
          ),
        ],
      );
      expect(surviving.total, 2);
      // Y sigue sin ser una fila cumplida: quedarse no es cumplir.
      expect(surviving.confirmed, 1);
      expect(surviving.unverified, 1);
    });

    test('sin precisiones sobreviven todas menos la de otra familia', () {
      final surviving = tallySupplierNeedMatchesUnder(
        matches: rows(),
        predicates: const <SupplierNeedSearchPredicate>[],
      );
      expect(surviving.total, 3);
      // Sin criterios no hay nada probado: ninguna puede rotularse cumplida.
      expect(surviving.confirmed, 0);
    });
  });

  group('la búsqueda por palabra sigue siendo el peldaño de abajo', () {
    test('un portal sin ruta de catálogo no puede recorrer taxonomía', () {
      expect(_plan(taxonomy: false).canBrowseTaxonomy, isFalse);
      expect(_plan().canBrowseTaxonomy, isTrue);
    });

    test('cuando sólo queda el buscador, se pregunta primero lo ancho', () {
      // Preguntar «camara 700» y quedarse con lo que trajo es exactamente
      // cómo 18 cámaras se convirtieron en 10.
      expect(_plan().queries, <String>['camara 700', 'camara']);
      expect(_plan().recallOrderedQueries, <String>['camara', 'camara 700']);
    });

    test('el rótulo de una enumeración cabe en el límite del proveedor', () {
      // No hubo «consulta» —se recorrió la taxonomía— pero el recibo igual
      // exige una palabra dentro del límite. Tomarla sin acotar haría fallar
      // el guardado con 22023 con el catálogo ya recorrido entero.
      final plan = _plan();
      expect(plan.broadQuery, 'camara');
      expect(plan.broadQuery.length, lessThanOrEqualTo(15));
      expect(plan.queries.last, plan.broadQuery);
    });

    test('un mapa vacío no declara ninguna capacidad, tampoco en Dart', () {
      // La otra mitad del contrato que el CHECK de la base ahora exige: si
      // esto cambiara y Dart empezara a aceptar `families: {}`, la base
      // seguiría rechazándolo y el desacuerdo volvería, al revés.
      expect(
        () => SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
          'version': 1,
          'families': <String, dynamic>{},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
          'version': 1,
          'families': <String, dynamic>{},
          'categories': <String, dynamic>{},
        }),
        throwsA(isA<FormatException>()),
      );
      // Con el flag genérico, el mapa vacío es sólo ruido: la capacidad la
      // declara el flag.
      expect(
        SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
          'version': 1,
          'families': <String, dynamic>{},
          'generic_family_search': true,
        }).genericFamilySearch,
        isTrue,
      );
    });

    test('el tope del cliente lo pone el adaptador, junto con el del RPC', () {
      expect(_plan().resultCap, kSupplierNeedPortalDefaultResultCap);
      expect(_plan(resultCap: 120).resultCap, 120);
    });

    test('el presupuesto es dato del adaptador', () {
      final plan = _plan(budget: <String, dynamic>{
        'max_nodes': 2,
        'max_pages': 6,
        'max_rows': 60,
        'wall_clock_seconds': 45,
      });

      expect(plan.budget.maxNodes, 2);
      expect(plan.budget.maxPages, 6);
      expect(plan.budget.maxRows, 60);
      expect(plan.budget.wallClock, const Duration(seconds: 45));
    });
  });
}
