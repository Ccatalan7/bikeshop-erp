import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_coherence.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_rows.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

void main() {
  final fixture = jsonDecode(
          File('test/fixtures/product_spec_coherence.json').readAsStringSync())
      as Map;
  test('PostgreSQL and Dart consume the same canonical fixture document', () {
    final sql = File('supabase/tests/fixtures/product_spec_coherence.sql')
        .readAsStringSync();
    final encoded = sql.split(r'$coherence_fixture$')[1];
    expect(jsonDecode(encoded), fixture);
  });
  final types = Map<String, String>.from(fixture['types'] as Map);
  final schemas = {
    for (final e in (fixture['schemas'] as Map).entries)
      e.key as String: ProductSpecRowSchema.fromJson(
          Map<String, dynamic>.from(e.value as Map))
  };
  Map<String, dynamic> contract() => Map<String, dynamic>.from(
      jsonDecode(jsonEncode(fixture['contract'])) as Map);
  ProductSpecCoherence parse(
          [Map<String, dynamic>? raw,
          Map<String, Set<String>> deps = const {}]) =>
      ProductSpecCoherence.fromContract(
          raw ?? contract(), types, schemas, deps);

  for (final entry in fixture['cases'] as List) {
    test(entry['id'] as String, () {
      final values = Map<String, dynamic>.from(entry['values'] as Map);
      final before = jsonEncode(values);
      expect(
          parse()
              .validate(values)
              .map((i) => {
                    'code': i.code,
                    'field': i.field,
                    'row_id': i.rowId,
                    'blocking': i.blocking,
                  })
              .toList(),
          entry['expected']);
      expect(jsonEncode(values), before,
          reason: 'Validation cannot rewrite observations.');
    });
  }
  test('label changes affect choice text without changing the stored identity',
      () {
    final values = Map<String, dynamic>.from(
        (fixture['cases'] as List).first['values'] as Map);
    final options =
        parse().optionsFor('allocations', values, (k) => k)['port_row_id']!;
    expect(options.choices.keys, ['p1', 'p2']);
    expect(options.choices['p1'], contains('USB-C 1'));
    expect(options.choices.containsKey('USB-C 1'), isFalse);
  });
  test('bad target shape disables choices and reports the error', () {
    final options = parse().optionsFor(
        'allocations',
        {
          'ports': {'rows': 'bad'}
        },
        (k) => k)['port_row_id']!;
    expect(options.choices, isEmpty);
    expect(options.error, isNotNull);
  });
  final invalidChanges = <String, void Function(Map<String, dynamic>)>{
    'unknown version': (c) => c['row_coherence']['version'] = 2,
    'null block': (c) => c['row_coherence'] = null,
    'unknown metadata': (c) => c['row_coherence']['automatic_fit'] = true,
    'unknown link key': (c) =>
        c['row_coherence']['links'][0]['cascade_delete'] = true,
    'self reference': (c) =>
        c['row_coherence']['links'][0]['target_field'] = 'allocations',
    'foreign field': (c) =>
        c['row_coherence']['links'][0]['target_field'] = 'foreign',
    'scalar target': (c) =>
        c['row_coherence']['links'][0]['target_field'] = 'lower',
    'unknown source column': (c) =>
        c['row_coherence']['links'][0]['column'] = 'missing',
    'numeric source column': (c) =>
        c['row_coherence']['links'][0]['column'] = 'power_w',
    'unknown label column': (c) =>
        c['row_coherence']['links'][0]['label_columns'] = ['missing'],
    'duplicate label column': (c) =>
        c['row_coherence']['links'][0]['label_columns'] = ['name', 'name'],
    'duplicate link': (c) => c['row_coherence']['links']
        .add(<String, dynamic>{...c['row_coherence']['links'][0]}),
    'duplicate cell under another id': (c) => c['row_coherence']['links']
        .add({...c['row_coherence']['links'][0], 'id': 'second'}),
    'scalar pair uses rows': (c) => c['scalar_ordered_pairs'] = [
          ['ports', 'upper']
        ],
    'scalar pair uses foreign': (c) => c['scalar_ordered_pairs'] = [
          ['foreign', 'upper']
        ],
    'scalar pair duplicates': (c) => c['scalar_ordered_pairs'] = [
          ['lower', 'lower']
        ],
    'scalar pair duplicate constraint': (c) => c['scalar_ordered_pairs'] = [
          ['lower', 'upper'],
          ['lower', 'upper']
        ],
    'v1 contract cannot opt in': (c) => c['rules_version'] = 1,
  };
  for (final e in invalidChanges.entries) {
    test('metadata rejects ${e.key}', () {
      final c = contract();
      e.value(c);
      expect(() => parse(c), throwsFormatException);
    });
  }
  test('row links cannot cycle through existing field prerequisites', () {
    expect(
        () => parse(null, {
              'ports': {'lower'},
              'lower': {'allocations'}
            }),
        throwsFormatException);
  });
  test('templates without coherence keep their current behavior', () {
    expect(parse({}).links, isEmpty);
    expect(parse({}).scalarOrderedPairs, isEmpty);
  });
  test('central draft validation enforces links and excludes legacy endpoints',
      () {
    SpecTemplate template([bool legacy = false]) => SpecTemplate(
            id: 't',
            key: 't',
            name: 'Fixture',
            technicalFamily: 'fixture',
            formContract: {
              ...contract(),
              'roles': {if (legacy) 'ports': 'legacy'}
            },
            fields: [
              for (final e in types.entries)
                SpecTemplateField(
                    specDefinitionId: e.key,
                    sectionKey: 'measurement',
                    sortOrder: 0,
                    isRequired: false,
                    visibilityRules: [],
                    definition: SpecDefinition(
                        id: e.key,
                        key: e.key,
                        label: e.key,
                        dataType: e.value,
                        options: [],
                        sortOrder: 0,
                        validationRules: {
                          if (schemas.containsKey(e.key))
                            'rows_schema': fixture['schemas'][e.key]
                        }))
            ]);
    final values = Map<String, dynamic>.from(
        (fixture['cases'] as List)[2]['values'] as Map);
    expect(
        validateProductSpecDraft(template: template(), values: values)
            .any((i) => i.code == 'row_reference_unresolved' && i.blocking),
        isTrue);
    expect(
        validateProductSpecDraft(template: template(true), values: values)
            .any((i) => i.code == 'configuration' && i.blocking),
        isTrue);
  });
}
