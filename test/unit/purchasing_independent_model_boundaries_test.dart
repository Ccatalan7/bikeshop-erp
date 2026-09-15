import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

const _text = 'Pieza de longitud 2 mm';
const _asked = <String, List<Object>>{
  'length': <Object>[2],
};
const _millimeters = <SupplierNeedSearchField>[
  SupplierNeedSearchField(
    key: 'length',
    label: 'Longitud',
    dataType: 'number',
    unit: 'mm',
  ),
];

Map<String, Object?> _reading({String rowId = 'peticion'}) => <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'id': rowId,
          'facts': <Object?>[
            <String, Object?>{
              'field': 'length',
              'value': 2,
              'quote': '2 mm',
              'relation': 'same',
            },
          ],
        },
      ],
    };

SupplierNeedPortalMatch _judgeSpecificMaterial(
  String rowText, {
  required bool remittedByModel,
}) {
  final plan = buildSupplierNeedSearchPlan(
    request: SupplierNeedSearchRequest(
      needId: 'material-proof',
      description: 'Pastillas, de kevlar',
      categoryId: 'brake-pads',
      categoryPath: 'Componentes / Frenos / Pastillas',
      technicalFamily: 'brake_pad',
      predicates: const <SupplierNeedSearchPredicate>[
        SupplierNeedSearchPredicate(
          field: 'compound_type',
          operator: 'eq',
          values: <Object>['Orgánico'],
        ),
      ],
      fields: const <SupplierNeedSearchField>[
        SupplierNeedSearchField(
          key: 'compound_type',
          label: 'Compuesto',
          dataType: 'single_select',
          allowedValues: <Object>['Orgánico', 'Metálico'],
        ),
      ],
      criteriaSpans: remittedByModel ? const <String>['de kevlar'] : const [],
    ),
    adapter: SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
      'version': 1,
      'generic_family_search': true,
      'result_schema': <String, dynamic>{},
    }),
    maxLength: 40,
  )!;
  return matchSupplierNeedCandidates(plan, <SupplierPortalCatalogCandidate>[
    SupplierPortalCatalogCandidate(
      code: 'direct-material-evidence',
      name: rowText,
      rowText: rowText,
      priceNet: 1000,
      technicalFacts: const <String, Object?>{
        'compound_type': 'Orgánico',
        kSupplierObjectHeadFact: 'PASTILLA',
        kSupplierFactQuotesFact: <String, Object?>{
          'compound_type': 'ORGÁNICO',
        },
      },
    ),
  ]).single;
}

SupplierNeedSearchPlan _gelPlan({required bool requiredPresent}) =>
    buildSupplierNeedSearchPlan(
      request: SupplierNeedSearchRequest(
        needId: 'same-need',
        description: requiredPresent ? 'Puños con gel' : 'Puños sin gel',
        categoryId: 'grips',
        categoryPath: 'Accesorios / Puños',
        predicates: const <SupplierNeedSearchPredicate>[],
        discoveredRequirements: <SupplyNeedUnmodelledRequirement>[
          SupplyNeedUnmodelledRequirement(
            term: 'gel',
            label: 'gel',
            affirmed: requiredPresent,
            scope: const <String>[],
          ),
        ],
      ),
      adapter: SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
        'version': 1,
        'generic_family_search': true,
        'result_schema': <String, dynamic>{},
      }),
      maxLength: 40,
    )!;

void main() {
  setUp(resetSupplyNeedCriteriaSpansCache);

  test('semantic reading identity includes the full phrase the model read', () {
    const water = SupplyNeedUnmodelledRequirement(
      term: 'resistente',
      label: 'resistente al agua',
      affirmed: true,
      scope: <String>[],
    );
    const heat = SupplyNeedUnmodelledRequirement(
      term: 'resistente',
      label: 'resistente al calor',
      affirmed: true,
      scope: <String>[],
    );
    expect(water.signature, isNot(heat.signature),
        reason: 'the supplier reader receives these different full phrases; '
            'the same longest word cannot authorize reuse of its answer');
  });

  test('a supplier reading cannot answer the opposite requested polarity', () {
    final original = _gelPlan(requiredPresent: true);
    const rowText = 'PUÑOS CON ESPUMA AMORTIGUADORA';
    final readings = verifySupplierRequirementReadings(
      rows: const <SupplierSpecExtractionRow>[
        SupplierSpecExtractionRow(id: 'same-row', text: rowText),
      ],
      requirements: supplyNeedUnmodelledRequirements(original),
      response: <String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'id': 'same-row',
            'requirements': <Object?>[
              <String, Object?>{
                'term': 'gel',
                'meets': true,
                'quote': 'ESPUMA AMORTIGUADORA',
              },
            ],
          },
        ],
      },
    );
    final candidates = attachSupplierRequirementReadings(
      candidates: const <SupplierPortalCatalogCandidate>[
        SupplierPortalCatalogCandidate(
          code: 'same-row',
          name: rowText,
          rowText: rowText,
          priceNet: 1000,
        ),
      ],
      readings: readings,
    );
    final originalMatch =
        matchSupplierNeedCandidates(original, candidates).single;
    expect(
      originalMatch.requirementFindings
          .singleWhere((f) => f.label == 'gel')
          .status,
      SupplyRequirementStatus.inferred,
      reason:
          'the semantic reading remains useful for the question it answered',
    );
    final changedMatch = matchSupplierNeedCandidates(
      _gelPlan(requiredPresent: false),
      candidates,
    ).single;
    expect(
      changedMatch.requirementFindings
          .singleWhere((f) => f.label == 'gel')
          .status,
      SupplyRequirementStatus.unknown,
      reason:
          'the same term and label do not make present and absent the same question',
    );
  });

  test('a malformed persisted semantic reading does not break the feed', () {
    expect(
      () => matchSupplierNeedCandidates(
        _gelPlan(requiredPresent: true),
        const <SupplierPortalCatalogCandidate>[
          SupplierPortalCatalogCandidate(
            code: 'malformed-reading',
            name: 'PUÑOS DE GOMA',
            priceNet: 1000,
            technicalFacts: <String, Object?>{
              kSupplierRequirementReadingFact: 'not a map',
            },
          ),
        ],
      ),
      returnsNormally,
    );
  });

  test('whole-request discovery keeps the material, not its connector', () {
    final requirements = verifySupplyNeedDiscoveredRequirements(
      requestText: 'Puños con gel',
      response: <String, Object?>{
        'requirements': <Object?>[
          <String, Object?>{
            'quote': 'con gel',
            'required': true,
            'scope': <Object?>[],
          },
        ],
      },
    );
    expect(requirements, hasLength(1));
    expect(requirements.single.term, isNot('con'),
        reason:
            'the connector occurs in unrelated products and is not proof of gel');
  });

  test('whole-request discovery cannot inject an unasked scope', () {
    final requirements = verifySupplyNeedDiscoveredRequirements(
      requestText: 'Puños con gel',
      response: <String, Object?>{
        'requirements': <Object?>[
          <String, Object?>{
            'quote': 'gel',
            'required': true,
            'scope': <Object?>['ambos lados'],
          },
        ],
      },
    );
    expect(requirements.expand((requirement) => requirement.scope), isEmpty,
        reason:
            'a literal material quote cannot authorize a scope nobody asked for');
  });

  test('whole-request discovery preserves short dimensional requirements', () {
    final requirements = verifySupplyNeedDiscoveredRequirements(
      requestText: 'Piñón para cadena de 3/32',
      response: <String, Object?>{
        'requirements': <Object?>[
          <String, Object?>{
            'quote': '3/32',
            'required': true,
            'scope': <Object?>[],
          },
        ],
      },
    );
    expect(requirements, hasLength(1),
        reason:
            'the model found the complete dimension; word length must not erase it');
    expect(requirements.single.label, '3/32');
  });

  test('uncertain AI mapping cannot erase direct proof in the supplier row',
      () {
    const row = 'PASTILLA COMPUESTO ORGÁNICO DE KEVLAR';
    expect(_judgeSpecificMaterial(row, remittedByModel: false).state,
        SupplierNeedMatchState.exact);
    expect(_judgeSpecificMaterial(row, remittedByModel: true).state,
        SupplierNeedMatchState.exact,
        reason:
            'the specific fiber is stated in the row, not inferred from Orgánico');
  });

  test('uncertain AI mapping cannot hide an explicit supplier contradiction',
      () {
    const row = 'PASTILLA COMPUESTO ORGÁNICO SIN KEVLAR';
    expect(_judgeSpecificMaterial(row, remittedByModel: false).state,
        SupplierNeedMatchState.conflict);
    expect(_judgeSpecificMaterial(row, remittedByModel: true).state,
        SupplierNeedMatchState.conflict,
        reason:
            'a broad material mapping cannot rescue a row denying the fiber');
  });

  for (final malformed in <String, Object?>{
    'rows is an object': <String, Object?>{'rows': <String, Object?>{}},
    'rows is a string': <String, Object?>{'rows': 'not rows'},
    'facts is an object': <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{'id': 'peticion', 'facts': <String, Object?>{}},
      ],
    },
  }.entries) {
    test('optional model malformed shape falls back: ${malformed.key}',
        () async {
      final result = await readSupplyNeedCriteriaSpansWithModel(
        requestText: _text,
        fields: _millimeters,
        askedValues: _asked,
        extractor: (_) async => malformed.value,
      );
      expect(result.spans, isEmpty);
    });
  }

  test('a reading assigned to another row cannot discharge this request', () {
    final result = verifySupplyNeedCriteriaSpans(
      requestText: _text,
      fields: _millimeters,
      askedValues: _asked,
      response: _reading(rowId: 'another-request'),
    );
    expect(result.spans, isEmpty);
  });

  test('a field absent from the actual ficha cannot discharge a requirement',
      () {
    final result = verifySupplyNeedCriteriaSpans(
      requestText: _text,
      fields: const <SupplierNeedSearchField>[],
      askedValues: _asked,
      response: _reading(),
    );
    expect(result.spans, isEmpty);
  });

  test('reuse includes ficha units, not only field keys and asked numbers',
      () async {
    var calls = 0;
    Future<Object?> extractor(String prompt) async {
      calls += 1;
      return calls == 1 ? _reading() : <String, Object?>{'rows': <Object?>[]};
    }

    final first = await readSupplyNeedCriteriaSpansWithModel(
      requestText: _text,
      fields: _millimeters,
      askedValues: _asked,
      extractor: extractor,
    );
    expect(first.spans, <String>['2 mm']);

    final changedDefinition = await readSupplyNeedCriteriaSpansWithModel(
      requestText: _text,
      fields: const <SupplierNeedSearchField>[
        SupplierNeedSearchField(
          key: 'length',
          label: 'Longitud',
          dataType: 'number',
          unit: 'cm',
        ),
      ],
      askedValues: _asked,
      extractor: extractor,
    );
    expect(calls, 2,
        reason:
            '2 cm is a different criterion from 2 mm despite equal keys/numbers');
    expect(changedDefinition.spans, isEmpty);
  });
}
