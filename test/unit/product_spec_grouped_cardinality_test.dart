import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_coherence.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_rows.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

Map<String, dynamic> copy(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

void main() {
  final fixture = jsonDecode(
      File('test/fixtures/product_spec_grouped_cardinality.json')
          .readAsStringSync()) as Map;
  final contract = copy(fixture['contract'] as Map);
  final fields = copy(fixture['fields'] as Map);
  ProductSpecCoherence parse(Map<String, dynamic> c, Map<String, dynamic> f,
          [Map<String, Set<String>> dependencies = const {}]) =>
      ProductSpecCoherence.fromContract(
          c,
          {for (final e in f.entries) e.key: e.value['data_type'] as String},
          {
            for (final e in f.entries)
              if (e.value['schema'] is Map)
                e.key: ProductSpecRowSchema.fromJson(
                    copy(e.value['schema'] as Map))
          },
          dependencies,
          numberRules: {
            for (final e in f.entries)
              if (e.value['data_type'] == 'number')
                e.key: copy(e.value['validation_rules'] as Map)
          });
  SpecTemplate template([Map<String, dynamic>? c, Map<String, dynamic>? f]) =>
      SpecTemplate(
          id: 'fixture',
          key: 'fixture',
          name: 'Contenido',
          technicalFamily: 'fixture',
          formContract: c ?? contract,
          fields: [
            for (final e in (f ?? fields).entries)
              SpecTemplateField(
                  specDefinitionId: e.key,
                  sectionKey: 'contents',
                  sortOrder: 0,
                  isRequired: false,
                  visibilityRules: [],
                  definition: SpecDefinition(
                      id: e.key,
                      key: e.key,
                      label: e.value['label'] as String? ?? e.key,
                      dataType: e.value['data_type'] as String,
                      options: [],
                      sortOrder: 0,
                      validationRules: {
                        ...copy(e.value['validation_rules'] as Map),
                        if (e.value['data_type'] == 'json')
                          'rows_schema': e.value['schema']
                      }))
          ]);
  Map<String, dynamic> values(String id) =>
      copy((fixture['cases'] as List).firstWhere((c) => c['id'] == id)['values']
          as Map);
  test('SQL and Dart consume the same frozen observations and expectations',
      () {
    final sql =
        File('supabase/tests/fixtures/product_spec_grouped_cardinality.sql')
            .readAsStringSync();
    expect(jsonDecode(sql.split(r'$grouped_fixture$')[1]), fixture);
  });
  for (final entry in fixture['cases'] as List) {
    test('shared: ${entry['id']}', () {
      final input = copy(entry['values'] as Map);
      final before = jsonEncode(input);
      expect(
          parse(contract, fields)
              .validate(input)
              .map((i) => {
                    'code': i.code,
                    'field': i.field,
                    'row_id': i.rowId,
                    'column': i.column,
                    'collection_field': i.collectionField,
                    'blocking': i.blocking,
                  })
              .toList(),
          entry['expected']);
      expect(jsonEncode(input), before,
          reason: 'No removal, autofill or source rewrite.');
    });
  }
  for (final entry in fixture['invalid_metadata'] as List) {
    test('invalid metadata: ${entry['id']}', () {
      expect(
          () => parse(
              copy(entry['contract'] as Map), copy(entry['fields'] as Map)),
          throwsFormatException);
    });
  }
  test('group link closes a reverse prerequisite cycle', () {
    expect(
        () => parse(contract, fields, {
              'assemblies': {'members'}
            }),
        throwsFormatException);
  });
  test('central validator locates each issue on the parent total cell', () {
    final issues = validateProductSpecDraft(
        template: template(),
        values: values('one_short_one_long_cannot_cancel'));
    final counts =
        issues.where((i) => i.code.startsWith('row_cardinality_')).toList();
    expect(counts.map((i) => [i.fieldKey, i.rowId, i.columnKey, i.blocking]), [
      ['assemblies', 'a', 'quantity', false],
      ['assemblies', 'b', 'quantity', true]
    ]);
    expect(counts.map((i) => i.collectionFieldKey), ['members', 'members']);
  });
  test('two collections retain their owner on a shared parent total', () {
    final c = copy(contract);
    final f = copy(fields);
    f['members']['label'] = 'Arandelas';
    f['other_members'] = copy(f['members'] as Map)..['label'] = 'Tornillos';
    c['roles']['other_members'] = 'contents';
    c['row_coherence']['links'].add({
      ...copy(c['row_coherence']['links'][0] as Map),
      'id': 'other_member_assembly',
      'field': 'other_members',
    });
    c['row_coherence']['cardinalities'].add({
      ...copy(c['row_coherence']['cardinalities'][0] as Map),
      'id': 'other_assembly_quantity',
      'field': 'other_members',
      'group_by': 'other_member_assembly',
    });
    final input = values('no_children_does_not_invent_members');
    final issues =
        validateProductSpecDraft(template: template(c, f), values: input)
            .where((i) => i.code == 'row_cardinality_pending')
            .toList();
    expect(issues.map((i) => i.collectionFieldKey).toSet(),
        {'members', 'other_members'});
    expect(issues.every((i) => i.fieldKey == 'assemblies'), isTrue);
    expect(
        issues
            .where((i) => i.collectionFieldKey == 'members')
            .every((i) => i.message.contains('Arandelas')),
        isTrue);
    expect(
        issues
            .where((i) => i.collectionFieldKey == 'other_members')
            .every((i) => i.message.contains('Tornillos')),
        isTrue);
    // No parent row means both issues have the same field, code and null
    // row ID. Deduplication must still preserve the two collection owners.
    final withoutParent =
        validateProductSpecDraft(template: template(c, f), values: {})
            .where((i) => i.code == 'row_cardinality_pending')
            .toList();
    expect(withoutParent.map((i) => i.collectionFieldKey),
        ['members', 'other_members']);
  });
  test('server issue decoding retains the collection and parent cell', () {
    final issues = productSpecServerIssues(jsonEncode([
      {
        'code': 'row_cardinality_pending',
        'field': 'assemblies',
        'row_id': 'a',
        'column': 'quantity',
        'collection_field': 'members',
        'blocking': false,
        'message': 'Faltan miembros.'
      },
      {
        'code': 'row_cardinality_pending',
        'field': 'assemblies',
        'row_id': 'a',
        'column': 'quantity',
        'collection_field': 'other_members',
        'blocking': false,
        'message': 'Faltan miembros.'
      }
    ]));
    expect(
        issues.map((i) => [
              i.fieldKey,
              i.rowId,
              i.columnKey,
              i.collectionFieldKey,
              i.blocking
            ]),
        [
          ['assemblies', 'a', 'quantity', 'members', false],
          ['assemblies', 'a', 'quantity', 'other_members', false],
        ]);
  });
  test('inapplicable parent cannot request a configuration', () {
    final c = copy(contract);
    c['allowed_when']['assemblies'] = {'kind': 'never'};
    expect(
        validateProductSpecDraft(template: template(c), values: {})
            .where((i) => i.code == 'row_cardinality_pending'),
        isEmpty);
  });
  test('inapplicable child collection does not request documentation', () {
    final c = copy(contract);
    c['allowed_when']['members'] = {
      'kind': 'when',
      'rows': [
        [
          {
            'field': 'enabled',
            'operator': 'eq',
            'value_type': 'boolean',
            'value': false
          }
        ]
      ]
    };
    final input = values('no_children_does_not_invent_members')
      ..['enabled'] = true;
    expect(
        validateProductSpecDraft(template: template(c), values: input)
            .where((i) => i.code == 'row_cardinality_pending'),
        isEmpty);
  });
}
