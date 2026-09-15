// Independent boundary regressions for the row-coherence contract.
// Synthetic fixtures only: no SKU, no OEM claim, `sources: []` everywhere.
// Every case is green against the corrected contract; the review names which
// gaps they reproduced before the fix, see
// docs/development/product-specs-research-2026-09-05/row-coherence-implementation-review-2026-09-07.md
// (R1–R3 there).
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_coherence.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_rows.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

const _schemas = <String, Map<String, dynamic>>{
  'ports': {
    'version': 1,
    'columns': [
      {'key': 'name', 'label': 'Puerto', 'type': 'text'},
      {'key': 'fast', 'label': 'Rápido', 'type': 'boolean'},
    ],
  },
  'allocations': {
    'version': 1,
    'columns': [
      {
        'key': 'port_row_id',
        'label': 'Puerto de esta ficha',
        'type': 'text',
        'required': true
      },
      {
        'key': 'port_kind',
        'label': 'Clase',
        'type': 'token',
        'allowed_values': ['A', 'B']
      },
      {'key': 'power_w', 'label': 'Potencia', 'type': 'decimal', 'unit': 'W'},
    ],
  },
  'groups': {
    'version': 1,
    'columns': [
      {'key': 'alloc_row_id', 'label': 'Reparto', 'type': 'text'},
      {'key': 'title', 'label': 'Título', 'type': 'text'},
    ],
  },
};

const _types = <String, String>{
  'ports': 'json',
  'allocations': 'json',
  'groups': 'json',
  'lower': 'number',
  'upper': 'number',
  'upper_in': 'number',
  'tube_width_min_mm': 'number',
  'tube_width_max_mm': 'number',
  'smallest_cog_teeth': 'number',
  'largest_cog_teeth': 'number',
};

const _units = <String, String?>{
  'lower': 'mm',
  'upper': 'mm',
  'upper_in': 'in',
  'tube_width_min_mm': 'mm',
  'tube_width_max_mm': 'in', // deliberately mismatched: fallback must skip it
  'smallest_cog_teeth': null,
  'largest_cog_teeth': null,
};

Map<String, dynamic> _link(
        {String id = 'allocation_port',
        String field = 'allocations',
        String column = 'port_row_id',
        String target = 'ports',
        List<String> labels = const ['name']}) =>
    {
      'id': id,
      'field': field,
      'column': column,
      'target_field': target,
      'label_columns': labels,
    };

Map<String, dynamic> _contract(
        {List<Map<String, dynamic>>? links, List<List<String>>? pairs}) =>
    {
      'rules_version': 2,
      if (links != null)
        'row_coherence': {'version': 1, 'links': links},
      if (pairs != null) 'scalar_ordered_pairs': pairs,
    };

final _parsedSchemas = {
  for (final e in _schemas.entries)
    e.key: ProductSpecRowSchema.fromJson(Map<String, dynamic>.from(e.value))
};

ProductSpecCoherence _parse(Map<String, dynamic> contract) =>
    ProductSpecCoherence.fromContract(contract, _types, _parsedSchemas, const {},
        units: _units);

Map<String, dynamic> _rows(List<Map<String, dynamic>> rows) => {
      'schema_version': 1,
      'rows': [
        for (final r in rows)
          {'id': r['id'], 'values': r['values'], 'sources': const <String>[]}
      ],
    };

final _ports = _rows([
  {
    'id': 'p1',
    'values': {'name': 'USB-C', 'fast': true}
  },
  {
    'id': 'p2',
    'values': {'name': 'USB-C', 'fast': false}
  },
  {
    'id': 'p3',
    'values': <String, dynamic>{'fast': true}
  },
]);

List<Map<String, Object?>> _project(Iterable<ProductSpecCoherenceIssue> issues) =>
    [
      for (final i in issues)
        {'code': i.code, 'field': i.field, 'row': i.rowId, 'blocking': i.blocking}
    ];

SpecTemplate _template({Map<String, String> roles = const {}}) => SpecTemplate(
        id: 't',
        key: 't',
        name: 'Boundary',
        technicalFamily: 'fixture',
        formContract: {
          ..._contract(links: [_link()], pairs: [
            ['lower', 'upper']
          ]),
          'roles': roles,
        },
        fields: [
          for (final e in _types.entries)
            SpecTemplateField(
                specDefinitionId: e.key,
                sectionKey: 'measurement',
                sortOrder: 0,
                isRequired: false,
                visibilityRules: const [],
                definition: SpecDefinition(
                    id: e.key,
                    key: e.key,
                    label: e.key,
                    dataType: e.value,
                    options: const [],
                    unit: _units[e.key],
                    sortOrder: 0,
                    validationRules: {
                      if (_schemas.containsKey(e.key))
                        'rows_schema': _schemas[e.key]
                    }))
        ]);

void main() {
  group('metadata endpoints', () {
    test('a token column with a closed vocabulary cannot carry a row id', () {
      expect(() => _parse(_contract(links: [_link(column: 'port_kind')])),
          throwsFormatException);
    });
    test('a chained target cannot label itself with another link column', () {
      expect(
          () => _parse(_contract(links: [
                _link(),
                _link(
                    id: 'group_alloc',
                    field: 'groups',
                    column: 'alloc_row_id',
                    target: 'allocations',
                    labels: ['port_row_id']),
              ])),
          throwsFormatException);
    });
    test('a chain that labels with the target own data is accepted', () {
      final coherence = _parse(_contract(links: [
        _link(),
        _link(
            id: 'group_alloc',
            field: 'groups',
            column: 'alloc_row_id',
            target: 'allocations',
            labels: ['power_w']),
      ]));
      expect(coherence.links.map((l) => l.id), ['allocation_port', 'group_alloc']);
    });
    test('a reversed duplicate pair is rejected as an order cycle', () {
      // [[lower,upper],[upper,lower]] would fire range_order for any
      // lower != upper; the evaluator rejects the contradiction up front.
      expect(
          () => _parse(_contract(pairs: [
                ['lower', 'upper'],
                ['upper', 'lower']
              ])),
          throwsFormatException);
    });
    test('an order cycle longer than two pairs is rejected', () {
      expect(
          () => _parse(_contract(pairs: [
                ['lower', 'upper'],
                ['upper', 'tube_width_min_mm'],
                ['tube_width_min_mm', 'lower']
              ])),
          throwsFormatException);
    });
    test('a declared pair cannot contradict an inherited one', () {
      expect(
          () => _parse(_contract(pairs: [
                ['largest_cog_teeth', 'smallest_cog_teeth']
              ])),
          throwsFormatException);
    });
    test('a transitive chain of bounds is accepted', () {
      final coherence = _parse(_contract(pairs: [
        ['lower', 'upper'],
        ['upper', 'tube_width_min_mm']
      ]));
      expect(coherence.scalarOrderedPairs.length, greaterThanOrEqualTo(2));
      expect(coherence.validate({'lower': '1', 'upper': '2', 'tube_width_min_mm': '3'}), isEmpty);
    });
    test('a declared pair with different units is rejected', () {
      expect(
          () => _parse(_contract(pairs: [
                ['lower', 'upper_in']
              ])),
          throwsFormatException);
    });
  });

  group('inherited pairs live in the same evaluator', () {
    test('the inherited tube-width pair is skipped when its units differ', () {
      final issues = _parse(_contract())
          .validate({'tube_width_min_mm': '30', 'tube_width_max_mm': '20'});
      expect(issues, isEmpty);
    });
    test('an inherited pair without declared pairs flags both bounds', () {
      final issues = _parse(_contract())
          .validate({'smallest_cog_teeth': '12', 'largest_cog_teeth': '11'});
      expect(_project(issues), [
        {'code': 'range_order', 'field': 'smallest_cog_teeth', 'row': null, 'blocking': true},
        {'code': 'range_order', 'field': 'largest_cog_teeth', 'row': null, 'blocking': true},
      ]);
    });
    test('declaring an inherited pair does not evaluate it twice', () {
      final coherence = _parse(_contract(pairs: [
        ['smallest_cog_teeth', 'largest_cog_teeth']
      ]));
      expect(
          coherence.scalarOrderedPairs
              .where((p) => p[0] == 'smallest_cog_teeth')
              .length,
          1);
      expect(
          coherence
              .validate({'smallest_cog_teeth': '12', 'largest_cog_teeth': '11'})
              .length,
          2);
    });
  });

  group('exact bounds', () {
    final coherence = _parse(_contract(pairs: [
      ['lower', 'upper']
    ]));
    test('mixed wire types compare by value, not by representation', () {
      expect(coherence.validate({'lower': '2', 'upper': 2.0}), isEmpty);
      expect(coherence.validate({'lower': '2.50', 'upper': 2.5}), isEmpty);
      expect(_project(coherence.validate({'lower': 2.5, 'upper': '2.25'})).map((i) => i['field']),
          ['lower', 'upper']);
    });
    test('a non-numeric bound is owned by the field validator, not by the pair',
        () {
      expect(coherence.validate({'lower': 'abc', 'upper': '1'}), isEmpty);
    });
  });

  group('row identity', () {
    final coherence = _parse(_contract(links: [_link()]));
    test('an id is never trimmed', () {
      final issues = coherence.validate({
        'ports': _ports,
        'allocations': _rows([
          {
            'id': 'c1',
            'values': {'port_row_id': ' p1'}
          }
        ]),
      });
      expect(_project(issues), [
        {'code': 'row_reference_unresolved', 'field': 'allocations', 'row': 'c1', 'blocking': true}
      ]);
    });
    test('re-minting every target id orphans every source row (F1b)', () {
      final reminted = _rows([
        {
          'id': 'p9',
          'values': {'name': 'USB-C', 'fast': true}
        },
        {
          'id': 'p8',
          'values': {'name': 'USB-C', 'fast': false}
        },
      ]);
      final issues = coherence.validate({
        'ports': reminted,
        'allocations': _rows([
          {
            'id': 'c1',
            'values': {'port_row_id': 'p1'}
          },
          {
            'id': 'c2',
            'values': {'port_row_id': 'p2'}
          },
        ]),
      });
      expect(issues.map((i) => i.rowId), ['c1', 'c2']);
      expect(issues.every((i) => i.blocking && i.code == 'row_reference_unresolved'), isTrue);
    });
  });

  group('derived labels', () {
    final coherence = _parse(_contract(links: [_link(labels: ['name', 'fast'])]));
    test('duplicates get a position suffix, blanks get a generic name, booleans read Sí/No',
        () {
      final options = coherence.optionsFor('allocations', {'ports': _ports}, (k) => k)['port_row_id']!;
      expect(options.error, isNull);
      expect(options.choices, {
        'p1': 'USB-C · Sí',
        'p2': 'USB-C · No',
        'p3': 'Sí',
      });
      final same = coherence.optionsFor(
          'allocations',
          {
            'ports': _rows([
              {
                'id': 'a',
                'values': {'name': 'X', 'fast': true}
              },
              {
                'id': 'b',
                'values': {'name': 'X', 'fast': true}
              },
            ])
          },
          (k) => k)['port_row_id']!;
      expect(same.choices, {'a': 'X · Sí · configuración 1', 'b': 'X · Sí · configuración 2'});
    });
    test('an unknown target offers no choices and no error', () {
      final options = coherence.optionsFor(
          'allocations', {'ports': 'Desconocido / sin confirmar'}, (k) => k)['port_row_id']!;
      expect(options.choices, isEmpty);
      expect(options.error, isNull);
    });
  });

  group('central validator', () {
    test('row and column identity reach the issue list and both bounds are blocking',
        () {
      final issues = validateProductSpecDraft(template: _template(), values: {
        'ports': _ports,
        'allocations': _rows([
          {
            'id': 'c1',
            'values': {'port_row_id': 'ghost'}
          }
        ]),
        'lower': '3',
        'upper': '2',
      });
      final link = issues.singleWhere((i) => i.code == 'row_reference_unresolved');
      expect(link.rowId, 'c1');
      expect(link.columnKey, 'port_row_id');
      expect(link.blocking, isTrue);
      expect(
          issues.where((i) => i.code == 'range_order').map((i) => (i.fieldKey, i.blocking)),
          [('lower', true), ('upper', true)]);
    });
    test('an inherited pair with a retired bound is not evaluated', () {
      final issues = validateProductSpecDraft(
          template: _template(roles: {'largest_cog_teeth': 'legacy'}),
          values: {'smallest_cog_teeth': '12', 'largest_cog_teeth': '11'});
      expect(issues.where((i) => i.code == 'range_order'), isEmpty);
    });
  });
}
