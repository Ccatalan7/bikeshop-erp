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
      File('test/fixtures/product_spec_row_cardinality.json')
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
                      label: e.key,
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
    final sql = File('supabase/tests/fixtures/product_spec_row_cardinality.sql')
        .readAsStringSync();
    expect(jsonDecode(sql.split(r'$cardinality_fixture$')[1]), fixture);
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
  test('v1 remains valid with its existing closed key set', () {
    final c = copy(contract)..['row_coherence'] = {'version': 1, 'links': []};
    expect(parse(c, fields).cardinalities, isEmpty);
    expect(parse(c, fields).validate({}), isEmpty);
  });
  test('total cannot depend back on the counted collection', () {
    expect(
        () => parse(contract, fields, {
              'total': {'items'}
            }),
        throwsFormatException);
    final c = copy(contract);
    c['prerequisites']['total'] = ['items'];
    expect(
        validateProductSpecDraft(template: template(c), values: {})
            .any((i) => i.code == 'configuration' && i.blocking),
        isTrue);
  });
  test('legacy total is not an available endpoint', () {
    final c = copy(contract);
    c['roles']['total'] = 'legacy';
    expect(
        validateProductSpecDraft(template: template(c), values: {})
            .any((i) => i.code == 'configuration' && i.blocking),
        isTrue);
  });
  test('one ID cannot name both a row link and a cardinality', () {
    final c = copy(contract);
    c['row_coherence']['links'] = [
      {
        'id': 'contents_total',
        'field': 'items',
        'column': 'label',
        'target_field': 'other_items',
        'label_columns': ['label']
      }
    ];
    expect(() => parse(c, fields), throwsFormatException);
  });
  test('known inapplicability owns zero plus populated table once', () {
    final c = copy(contract);
    c['allowed_when']['items'] = {
      'kind': 'when',
      'rows': [
        [
          {
            'field': 'total',
            'operator': 'gt',
            'value_type': 'decimal',
            'value': '0'
          }
        ]
      ]
    };
    final issues = validateProductSpecDraft(
        template: template(c), values: values('zero_does_not_delete_rows'));
    expect(issues.where((i) => i.blocking).map((i) => i.code),
        ['field_applicability']);
  });
  test('unknown applicability cannot suppress a known excess', () {
    final c = copy(contract);
    c['allowed_when']['items'] = {
      'kind': 'when',
      'rows': [
        [
          {
            'field': 'other_total',
            'operator': 'gt',
            'value_type': 'decimal',
            'value': '0'
          }
        ]
      ]
    };
    expect(
        validateProductSpecDraft(
                template: template(c), values: values('more_rows_than_total'))
            .where((i) => i.blocking)
            .map((i) => i.code),
        ['row_cardinality_conflict']);
  });
  test('an inapplicable collection does not request its missing total', () {
    final c = copy(contract);
    c['allowed_when']['items'] = {'kind': 'never'};
    final issues = validateProductSpecDraft(template: template(c), values: {});
    expect(issues.where((i) => i.code == 'row_cardinality_pending'), isEmpty);
  });
  test('inapplicable saved rows retain the applicability rejection', () {
    final c = copy(contract);
    c['allowed_when']['items'] = {'kind': 'never'};
    final input = values('total_missing_with_rows');
    final before = jsonEncode(input);
    final issues =
        validateProductSpecDraft(template: template(c), values: input);
    expect(issues.where((i) => i.blocking).map((i) => i.code),
        ['field_applicability']);
    expect(issues.where((i) => i.code == 'row_cardinality_pending'), isEmpty);
    expect(jsonEncode(input), before);
  });
  test('unknown applicability keeps incomplete cardinality pending', () {
    final c = copy(contract);
    c['allowed_when']['items'] = {
      'kind': 'when',
      'rows': [
        [
          {
            'field': 'description',
            'operator': 'eq',
            'value_type': 'token',
            'value': 'Charger'
          }
        ]
      ]
    };
    final issues = validateProductSpecDraft(template: template(c), values: {});
    expect(issues.where((i) => i.code == 'row_cardinality_pending').length, 1);
  });
  test('legacy visibility participates in cardinality applicability', () {
    final t = template();
    t.fields
        .firstWhere((f) => f.definition?.key == 'items')
        .visibilityRules
        .add({'field': 'description', 'operator': 'eq', 'value': 'Charger'});
    final issues =
        validateProductSpecDraft(template: t, values: {'description': 'Cable'});
    expect(issues.where((i) => i.code == 'row_cardinality_pending'), isEmpty);
  });
  test('ordinary scalar validation owns an invalid total without duplicates',
      () {
    final issues = validateProductSpecDraft(
        template: template(), values: values('invalid_total_fractional'));
    expect(issues.where((i) => i.blocking).map((i) => i.code), ['integer']);
  });
  test('required cells and occurrence completeness are independent', () {
    final issues = validateProductSpecDraft(
        template: template(),
        values: values('partial_cells_still_count_occurrences'));
    expect(issues.map((i) => i.code), ['row_incomplete']);
    expect(issues.single.blocking, isFalse);
  });
  test('matching reference cannot approve an excess over the declared total',
      () {
    final input = values('more_rows_than_total');
    final reference = ProductSpecReference(
        id: 'r',
        family: 'fixture',
        brand: 'Fixture',
        model: 'Model',
        label: 'Referencia',
        facts: copy(input),
        sources: ['https://example.com/document']);
    final issues = validateProductSpecDraft(
        template: template(),
        values: input,
        reference: reference,
        brand: 'Fixture',
        model: 'Model');
    expect(issues.where((i) => i.blocking).map((i) => i.code),
        ['row_cardinality_conflict']);
  });
  test(
      'wire packaging retains stable IDs and row sources, with no inferred total',
      () {
    final input = values('total_missing_with_rows');
    final payload = SpecEngineService.buildFactPayload(template(), input);
    expect(payload.containsKey('total'), isFalse);
    expect(payload['items'], {'rows': input['items']});
  });
  test(
      'unsafe legacy binary number is rejected instead of inventing its digits',
      () {
    final input = values('equal_two_rows')..['total'] = 9007199254740992;
    expect(parse(contract, fields).validate(input).single.code,
        'row_cardinality_total');
    expect(() => SpecEngineService.buildFactPayload(template(), input),
        throwsFormatException);
  });
}
