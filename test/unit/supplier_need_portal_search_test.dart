import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';

const _numberField = SupplierNeedSearchField(
  key: 'number',
  label: 'Número',
  dataType: 'number',
);

SupplierNeedSearchRequest _request({
  required String needId,
  required String description,
  required String technicalFamily,
  required List<SupplierNeedSearchPredicate> predicates,
  List<SupplierNeedSearchField> fields = const <SupplierNeedSearchField>[],
  String? categoryId,
  String? categoryPath,
}) =>
    SupplierNeedSearchRequest(
      needId: needId,
      description: description,
      categoryId: categoryId,
      technicalFamily: technicalFamily,
      categoryPath: categoryPath,
      predicates: predicates,
      fields: fields,
    );

SupplierNeedSearchRequest _motorNeed() => _request(
      needId: 'need-motor',
      description: 'Motor de centro 73 x 118 mm',
      technicalFamily: 'bottom_bracket',
      categoryPath: 'Componentes / Transmisión / Motores / Motor',
      fields: const <SupplierNeedSearchField>[
        SupplierNeedSearchField(
          key: 'bb_shell_width_mm',
          label: 'Ancho caja motor',
          dataType: 'number',
          unit: 'mm',
          allowedValues: <Object>[68, 70, 73, 83],
        ),
        SupplierNeedSearchField(
          key: 'spindle_length_mm',
          label: 'Largo eje',
          dataType: 'number',
          unit: 'mm',
          allowedValues: <Object>[107, 113, 118, 122.5],
        ),
      ],
      predicates: const <SupplierNeedSearchPredicate>[
        SupplierNeedSearchPredicate(
          field: 'bb_shell_width_mm',
          operator: 'eq',
          values: <Object>[73],
        ),
        SupplierNeedSearchPredicate(
          field: 'spindle_length_mm',
          operator: 'eq',
          values: <Object>[118],
        ),
      ],
    );

SupplierNeedPortalAdapter _adapter() => SupplierNeedPortalAdapter.fromJson(
      <String, dynamic>{
        'version': 1,
        'initial_url':
            'http://www.rburgos.cl/sitio/aplicaciones/seleccion.asp?folio=0',
        'session_error_pattern':
            r'Microsoft OLE DB Provider[\s\S]*Sintaxis incorrecta cerca de',
        'result_schema': <String, dynamic>{
          'columns': <String, dynamic>{
            'code': <String>['Código'],
            'name': <String>['Descripción'],
            'brand': <String>['Marca'],
            'origin': <String>['Origen'],
            'price': <String>['Valor'],
          },
          'no_result_phrases': <String>[
            'No hay ningún producto que mostrar',
          ],
        },
        'families': <String, dynamic>{
          'bottom_bracket': <String, dynamic>{
            'identity_family': 'bottom_bracket',
            'search_terms': <String>['eje sellado'],
            'identity_terms': <String>[
              'motor',
              'movimiento central',
              'caja pedalera',
              'eje sellado',
            ],
            'navigation': <Map<String, String>>[
              <String, String>{
                'action': 'select_option',
                'field': 'Clasificacion1',
                'value': 'TRANSMISION Y PARTES',
              },
              <String, String>{
                'action': 'select_option',
                'field': 'Clasificacion2',
                'value': 'MOTOR (MOVIMIENTO CENTRAL)',
              },
            ],
            'capture_patterns': <Map<String, dynamic>>[
              <String, dynamic>{
                'pattern':
                    r'\b(\d{2,3}(?:[.,]\d+)?)\s*[x×/]\s*(\d{2,3}(?:[.,]\d+)?)\s*(?:mm)?\b',
                'fields': <String, String>{
                  '1': 'bb_shell_width_mm',
                  '2': 'spindle_length_mm',
                },
              },
            ],
          },
          'tube': <String, dynamic>{
            'identity_family': 'tube',
            'search_terms': <String>['camara'],
            'identity_terms': <String>['camara', 'tube'],
          },
          'rotor': <String, dynamic>{
            'identity_family': 'brake_rotor',
            'search_terms': <String>['disco freno'],
            'identity_terms': <String>['disco de freno', 'rotor'],
          },
          'chain': <String, dynamic>{
            'identity_family': 'chain',
            'search_terms': <String>['cadena'],
            'identity_terms': <String>['cadena', 'chain'],
          },
          'hub': <String, dynamic>{
            'identity_family': 'hub',
            'search_terms': <String>['maza'],
            'identity_terms': <String>['maza', 'buje', 'hub'],
          },
        },
      },
    );

SupplierNeedPortalAdapter _genericAdapter() =>
    SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
      'version': 1,
      'generic_family_search': true,
      'initial_url':
          'http://www.rburgos.cl/sitio/aplicaciones/seleccion.asp?folio=0',
      'result_schema': <String, dynamic>{
        'columns': <String, dynamic>{
          'code': <String>['Código'],
          'name': <String>['Descripción'],
        },
      },
      // The provider keeps its richer native route where one was observed;
      // every other recognised family uses the same reviewed word search.
      'families': <String, dynamic>{
        'bottom_bracket': <String, dynamic>{
          'identity_family': 'bottom_bracket',
          'search_terms': <String>['eje sellado'],
        },
      },
    });

SupplierPortalCatalogCandidate _candidate(
  String name, {
  Map<String, Object?> facts = const <String, Object?>{},
}) =>
    SupplierPortalCatalogCandidate(
      code: 'P-1',
      name: name,
      technicalFacts: facts,
    );

SupplierNeedSearchPlan _plan(SupplierNeedSearchRequest request) =>
    buildSupplierNeedSearchPlan(
      request: request,
      adapter: _adapter(),
      maxLength: 15,
    )!;

void main() {
  group('plan de búsqueda por necesidad', () {
    test('la ruta, término y parser provienen del adaptador', () {
      final plan = _plan(_motorNeed());

      expect(plan.query, 'eje sellado');
      expect(plan.queries, <String>['eje sellado']);
      expect(plan.family.identityFamily, 'bottom_bracket');
      expect(plan.family.navigation, hasLength(2));
      expect(plan.family.navigation.first.fieldName, 'Clasificacion1');
      expect(plan.resultSchema.columnAliases['code'], contains('Código'));
    });

    test('una familia no configurada se rehúsa en vez de improvisar', () {
      final plan = buildSupplierNeedSearchPlan(
        request: _request(
          needId: 'need-unknown',
          description: 'Un repuesto desconocido',
          technicalFamily: 'unregistered_family',
          predicates: const <SupplierNeedSearchPredicate>[],
        ),
        adapter: _adapter(),
        maxLength: 15,
      );

      expect(plan, isNull);
    });

    test('el buscador genérico usa la familia canónica de una necesidad amplia',
        () {
      final request = _request(
        needId: 'need-general-tubes',
        description: 'Cámaras aro 700 para reposición',
        categoryId: 'category-tubes',
        categoryPath: 'Componentes / Ruedas / Cámaras',
        technicalFamily: 'tube',
        fields: const <SupplierNeedSearchField>[
          SupplierNeedSearchField(
            key: 'wheel_size',
            label: 'Tamaño de rueda',
            dataType: 'single_select',
            allowedValues: <Object>['700c'],
          ),
        ],
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'wheel_size',
            operator: 'eq',
            values: <Object>['700c'],
          ),
        ],
      );
      final plan = buildSupplierNeedSearchPlan(
        request: request,
        adapter: _genericAdapter(),
        maxLength: 15,
      )!;
      const queryUrl =
          'http://www.rburgos.cl/sitio/aplicaciones/catalogo.asp?Clasificacion2=camara';

      expect(plan.query, 'camara 700');
      expect(plan.queries, <String>['camara 700', 'camara']);
      expect(plan.family.identityFamily, 'tube');
      expect(plan.initialUrlFor(queryUrl), queryUrl);

      final matches = matchSupplierNeedCandidates(
        plan,
        <SupplierPortalCatalogCandidate>[
          _candidate('CAMARA 700 X 28/38C V/AUTO 48MM'),
          _candidate('CAMARA 29 X 1.75/2.35 V/AMERICANA 48MM'),
        ],
      );
      expect(matches.first.candidate.name, contains('700'));
      expect(matches.first.state, SupplierNeedMatchState.exact);
      expect(matches.last.state, SupplierNeedMatchState.conflict);
    });

    test('una búsqueda amplia nunca toma nombre de producto ni SKU', () {
      final request = _request(
        needId: 'need-general-tires',
        description: 'Necesito neumáticos aro 29 para reposición',
        categoryId: 'category-tires',
        technicalFamily: 'tire',
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'wheel_size',
            operator: 'eq',
            values: <Object>['29"'],
          ),
        ],
      );
      final plan = buildSupplierNeedSearchPlan(
        request: request,
        adapter: _genericAdapter(),
        maxLength: 15,
      )!;

      expect(plan.queries, <String>['neumatico 29', 'neumatico']);
      expect(plan.queries.join(' '), isNot(contains('SKU')));
      expect(plan.queries.join(' '), isNot(contains('JACK RABBIT')));
    });

    test('un portal puede declarar sólo su buscador genérico revisado', () {
      final adapter = SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
        'version': 1,
        'generic_family_search': true,
      });
      final request = _request(
        needId: 'need-generic-only',
        description: 'Cámaras aro 700 para reposición',
        categoryId: 'category-tubes',
        technicalFamily: 'tube',
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'wheel_size',
            operator: 'eq',
            values: <Object>['700c'],
          ),
        ],
      );

      expect(
        buildSupplierNeedSearchPlan(
          request: request,
          adapter: adapter,
          maxLength: 15,
        )?.queries,
        <String>['camara 700', 'camara'],
      );
    });

    test('un override por category id puede reemplazar la familia', () {
      final adapter = SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
        'version': 1,
        'families': <String, dynamic>{
          'tube': <String, dynamic>{
            'identity_family': 'tube',
            'search_terms': <String>['camara'],
          },
        },
        'categories': <String, dynamic>{
          'category-a': <String, dynamic>{
            'identity_family': 'tube',
            'search_terms': <String>['tripas'],
          },
        },
      });
      const request = SupplierNeedSearchRequest(
        needId: 'need-category',
        description: 'Cámara 29',
        categoryId: 'category-a',
        technicalFamily: 'tube',
        predicates: <SupplierNeedSearchPredicate>[],
      );

      expect(
        buildSupplierNeedSearchPlan(
          request: request,
          adapter: adapter,
          maxLength: 15,
        )?.query,
        'tripas',
      );
    });
  });

  group('sesión y evidencia', () {
    test('abre el formulario conocido sin inventar rutas para otros', () {
      expect(
        supplierNeedPortalLoginUrl('https://portal.rburgos.cl/'),
        'https://portal.rburgos.cl/login/',
      );
      expect(
        supplierNeedPortalLoginUrl('https://proveedor.example/catalogo'),
        'https://proveedor.example/catalogo',
      );
      expect(supplierNeedPortalLoginUrl(null), isNull);
    });

    test('la evidencia no conserva parámetros, usuario ni fragmentos', () {
      expect(
        sanitizeSupplierNeedPortalEvidenceUrl(
          'https://cliente:secreto@portal.rburgos.cl:443/catalogo'
          '?token=privado&query=motor#cuenta',
        ),
        'https://portal.rburgos.cl/catalogo',
      );
      expect(
        sanitizeSupplierNeedPortalEvidenceUrl('javascript:alert(1)'),
        isNull,
      );
    });

    test('un error de sesión se configura por portal, no por hostname', () {
      const body = 'Microsoft OLE DB Provider for ODBC Drivers '
          "Sintaxis incorrecta cerca de '='.";
      final pattern = _adapter().sessionErrorPattern;

      expect(
        supplierNeedPortalSessionExpired(
          sourceUrl: 'https://cualquier-proveedor.example/catalogo',
          sessionErrorPattern: pattern,
          report: const <String, dynamic>{
            'session': <String, dynamic>{
              'hasPasswordField': false,
              'phrases': <String>[],
            },
            'bodySample': body,
          },
        ),
        isTrue,
      );
      expect(
        supplierNeedPortalSessionExpired(
          sourceUrl: 'http://www.rburgos.cl/catalogo',
          report: const <String, dynamic>{
            'session': <String, dynamic>{
              'hasPasswordField': false,
              'phrases': <String>[],
            },
            'bodySample': body,
          },
        ),
        isFalse,
      );
    });
  });

  group('matcher de ficha técnica', () {
    test('bottom bracket usa capturas configuradas, no código RBX', () {
      final matches = matchSupplierNeedCandidates(
        _plan(_motorNeed()),
        <SupplierPortalCatalogCandidate>[
          _candidate('MOTOR NECO SELLADO EJE CUADRADO 73 X 118 MM'),
          _candidate('MOTOR NECO SELLADO 68 X 118 MM'),
          _candidate('MOTOR SELLADO EJE CUADRADO'),
          _candidate('CAMARA 29 X 1.75 VALVULA AUTO'),
        ],
      );

      expect(matches.first.state, SupplierNeedMatchState.exact);
      expect(
        matches.first.provenFields,
        containsAll(<String>[
          'product_family',
          'bb_shell_width_mm',
          'spindle_length_mm',
        ]),
      );
      expect(
        matches.where((item) => item.state == SupplierNeedMatchState.possible),
        hasLength(1),
      );
      expect(
        matches.where((item) => item.state == SupplierNeedMatchState.conflict),
        hasLength(2),
      );
    });

    test('cámara 29 Presta 60 usa taxonomía y registro de specs', () {
      final request = _request(
        needId: 'need-tube',
        description: 'Cámara aro 29 válvula francesa de 60 mm',
        technicalFamily: 'tube',
        fields: const <SupplierNeedSearchField>[
          SupplierNeedSearchField(
            key: 'wheel_size',
            label: 'Tamaño de rueda',
            dataType: 'single_select',
            allowedValues: <Object>['29"'],
          ),
          SupplierNeedSearchField(
            key: 'valve_type',
            label: 'Tipo de válvula',
            dataType: 'single_select',
            allowedValues: <Object>['Presta (francesa)'],
          ),
          SupplierNeedSearchField(
            key: 'valve_length_mm',
            label: 'Largo de válvula',
            dataType: 'single_select',
            unit: 'mm',
            allowedValues: <Object>[33, 48, 60, 80],
          ),
        ],
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'wheel_size',
            operator: 'eq',
            values: <Object>[29],
          ),
          SupplierNeedSearchPredicate(
            field: 'valve_type',
            operator: 'eq',
            values: <Object>['Presta (francesa)'],
          ),
          SupplierNeedSearchPredicate(
            field: 'valve_length_mm',
            operator: 'eq',
            values: <Object>[60],
          ),
        ],
      );

      final match = matchSupplierNeedCandidates(
        _plan(request),
        <SupplierPortalCatalogCandidate>[
          _candidate('CAMARA ARO 29 X 1.75/2.10 F/V PRESTA 60MM'),
        ],
      ).single;

      expect(match.state, SupplierNeedMatchState.exact);
      expect(match.observedFacts['valve_length_mm'], 60);
    });

    test('rotor, cadena y maza reutilizan el extractor canónico', () {
      final rotor = _request(
        needId: 'need-rotor',
        description: 'Disco 180 mm',
        technicalFamily: 'rotor',
        fields: const <SupplierNeedSearchField>[
          SupplierNeedSearchField(
            key: 'rotor_diameter_mm',
            label: 'Diámetro del rotor',
            dataType: 'single_select',
            allowedValues: <Object>[160, 180, 203],
          ),
        ],
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'rotor_diameter_mm',
            operator: 'eq',
            values: <Object>[180],
          ),
        ],
      );
      expect(
        matchSupplierNeedCandidates(
          _plan(rotor),
          <SupplierPortalCatalogCandidate>[
            _candidate('DISCO DE FRENO CENTERLOCK 180MM'),
          ],
        ).single.state,
        SupplierNeedMatchState.exact,
      );

      final chain = _request(
        needId: 'need-chain',
        description: 'Cadena 12 velocidades',
        technicalFamily: 'chain',
        fields: const <SupplierNeedSearchField>[
          SupplierNeedSearchField(
            key: 'chain_speeds',
            label: 'Velocidades cadena',
            dataType: 'multi_select',
          ),
        ],
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'chain_speeds',
            operator: 'in',
            values: <Object>[12],
          ),
        ],
      );
      expect(
        matchSupplierNeedCandidates(
          _plan(chain),
          <SupplierPortalCatalogCandidate>[_candidate('CADENA KMC 12V 126L')],
        ).single.state,
        SupplierNeedMatchState.exact,
      );

      final hub = _request(
        needId: 'need-hub',
        description: 'Maza trasera 148 mm 32H Micro Spline',
        technicalFamily: 'hub',
        fields: const <SupplierNeedSearchField>[
          SupplierNeedSearchField(
            key: 'hub_spacing_mm',
            label: 'Ancho de maza',
            dataType: 'single_select',
          ),
          SupplierNeedSearchField(
            key: 'spoke_holes',
            label: 'Número de rayos',
            dataType: 'single_select',
          ),
          SupplierNeedSearchField(
            key: 'freehub_type',
            label: 'Driver / Freehub',
            dataType: 'single_select',
          ),
        ],
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'hub_spacing_mm',
            operator: 'eq',
            values: <Object>[148],
          ),
          SupplierNeedSearchPredicate(
            field: 'spoke_holes',
            operator: 'eq',
            values: <Object>[32],
          ),
          SupplierNeedSearchPredicate(
            field: 'freehub_type',
            operator: 'eq',
            values: <Object>['Micro Spline'],
          ),
        ],
      );
      expect(
        matchSupplierNeedCandidates(
          _plan(hub),
          <SupplierPortalCatalogCandidate>[
            _candidate('MAZA TRASERA BOOST 148X12 32H MICRO SPLINE'),
          ],
        ).single.state,
        SupplierNeedMatchState.exact,
      );
    });

    test('evalúa operadores numéricos sobre hechos estructurados', () {
      final request = _request(
        needId: 'need-range',
        description: 'Producto entre 100 y 120',
        technicalFamily: 'chain',
        fields: const <SupplierNeedSearchField>[_numberField],
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'number',
            operator: 'between',
            values: <Object>[100, 120],
          ),
        ],
      );

      expect(
        matchSupplierNeedCandidates(
          _plan(request),
          <SupplierPortalCatalogCandidate>[
            // La fila **dice** el número. Un hecho estructurado que el texto
            // no sostiene ya no prueba nada: es la misma regla que impide que
            // un recibo antiguo confirme por omisión.
            _candidate(
              'CADENA DE PRUEBA 110',
              facts: <String, Object?>{'number': 110},
            ),
          ],
        ).single.state,
        SupplierNeedMatchState.exact,
      );
    });

    test('un campo no observado queda posible y jamás se inventa', () {
      final request = _request(
        needId: 'need-unknown-field',
        description: 'Cadena con tratamiento secreto',
        technicalFamily: 'chain',
        fields: const <SupplierNeedSearchField>[
          SupplierNeedSearchField(
            key: 'secret_treatment',
            label: 'Tratamiento secreto',
            dataType: 'text',
          ),
        ],
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'secret_treatment',
            operator: 'eq',
            values: <Object>['X'],
          ),
        ],
      );

      final match = matchSupplierNeedCandidates(
        _plan(request),
        <SupplierPortalCatalogCandidate>[_candidate('CADENA GENERICA 9V')],
      ).single;

      expect(match.state, SupplierNeedMatchState.possible);
      expect(match.missingFields, contains('secret_treatment'));
    });
  });
}
