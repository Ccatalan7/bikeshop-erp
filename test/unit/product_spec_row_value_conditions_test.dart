import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_row_conditions.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_rows.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);

void main() {
  final fixture = _map(jsonDecode(
      File('test/fixtures/product_spec_row_value_conditions.json')
          .readAsStringSync()));
  final schemaJson = _map(fixture['fields']['configurations']['schema']);
  final schemas = {
    'configurations': ProductSpecRowSchema.fromJson(schemaJson),
  };
  SpecTemplate template(Map<String, dynamic> contract) => SpecTemplate(
        id: 'row-value-template',
        key: 'row_value_template',
        name: 'Same-row implications',
        technicalFamily: 'row_value_fixture',
        formContract: {
          'allowed_when': <String, dynamic>{},
          'required_when': <String, dynamic>{},
          'prerequisites': <String, dynamic>{},
          'allowed_options': <String, dynamic>{},
          'roles': {'configurations': 'measurement'},
          ...contract,
        },
        fields: [
          SpecTemplateField(
            specDefinitionId: 'row-value-definition',
            sectionKey: 'measurement',
            sortOrder: 0,
            isRequired: false,
            visibilityRules: const [],
            definition: SpecDefinition(
              id: 'row-value-definition',
              key: 'configurations',
              label: 'Configuraciones observadas',
              dataType: 'json',
              options: const [],
              sortOrder: 0,
              validationRules: {'rows_schema': schemaJson},
            ),
          ),
        ],
      );

  test('SQL, Dart and Python use the same fixture document', () {
    final sql =
        File('supabase/tests/fixtures/product_spec_row_value_conditions.sql')
            .readAsStringSync();
    expect(jsonDecode(sql.split(r'$row_value_fixture$')[1]), fixture);
  });
  for (final raw in fixture['cases']) {
    final item = _map(raw);
    test('typed implication ${item['id']}', () {
      final values = _map(item['values']);
      final contract = _map(item['contract']);
      final before = jsonEncode({'contract': contract, 'values': values});
      final rules = ProductSpecRowConditions.fromContract(contract, schemas);
      expect(
          rules
              .validate(values)
              .map((i) => {
                    'code': i.code,
                    'field': i.field,
                    'row_id': i.rowId,
                    'column': i.column,
                    'blocking': i.blocking,
                  })
              .toList(),
          item['expected']);
      final issues = validateProductSpecDraft(
          template: template(contract), values: values);
      expect(issues.where((i) => i.code == 'configuration'), isEmpty);
      expect(
          issues
              .where((i) => i.code.startsWith('row_'))
              .map((i) => {
                    'code': i.code,
                    'field': i.fieldKey,
                    'row_id': i.rowId,
                    'column': i.columnKey,
                    'blocking': i.blocking,
                  })
              .toList(),
          item['expected'],
          reason: 'The real draft consumer must retain typed row findings.');
      for (final issue in issues.where((i) => i.code == 'row_value_conflict')) {
        expect(issue.message, contains('Configuraciones observadas'));
        expect(issue.message, isNot(contains('clamp_included')));
      }
      expect(jsonEncode({'contract': contract, 'values': values}), before,
          reason: 'Neither upstream changes nor rules rewrite an observation.');
    });
  }
  for (final item in fixture['valid_metadata']) {
    test('accepts valid typed metadata ${item['id']}', () {
      expect(
          () => ProductSpecRowConditions.fromContract(
              _map(item['contract']), schemas),
          returnsNormally);
    });
  }
  for (final item in fixture['invalid_metadata']) {
    test('rejects invalid typed metadata ${item['id']}', () {
      expect(
          () => ProductSpecRowConditions.fromContract(
              _map(item['contract']), schemas),
          throwsFormatException);
      expect(
          validateProductSpecDraft(
                  template: template(_map(item['contract'])), values: const {})
              .any((i) => i.code == 'configuration' && i.blocking),
          isTrue,
          reason: 'Malformed metadata is never silently treated as no rule.');
    });
  }
  test('value dependencies reach the existing UI prerequisite API', () {
    final rules = ProductSpecRowConditions.fromContract(
        _map(fixture['contract']), schemas);
    expect(rules.fields['configurations']!.dependenciesFor('clamp_included'),
        {'configuration_state'});
  });
  test('messages distinguish expected yes from contradictory active rules', () {
    List<ProductSpecRowConditionIssue> issues(String id) {
      final item = fixture['cases'].firstWhere((c) => c['id'] == id);
      return ProductSpecRowConditions.fromContract(
              _map(item['contract']), schemas)
          .validate(_map(item['values']));
    }

    expect(issues('included_false').single.message, contains('«Sí»'));
    expect(issues('included_missing').single.message, contains('«Sí»'));
    expect(issues('simultaneous_conflict_missing').single.message,
        contains('condiciones confirmadas que exigen valores incompatibles'));
    expect(issues('unknown_antecedent').single.message,
        isNot(contains('se espera')));
    expect(issues('decimal_conflict_beyond_2_53').single.message,
        contains('«9007199254740993.125 mm»'));
  });
  test('new clients still reject an unrecognized future bucket', () {
    final contract = _map(jsonDecode(jsonEncode(fixture['contract'])));
    contract['row_conditions']['fields']['configurations']
        ['autofill_when'] = {};
    expect(() => ProductSpecRowConditions.fromContract(contract, schemas),
        throwsFormatException);
  });
  test('malformed allowed_when on static required remains a format error', () {
    final schema = _map(jsonDecode(jsonEncode(schemaJson)));
    schema['columns'][1]['required'] = true;
    final contract = _map(jsonDecode(jsonEncode(fixture['contract'])));
    contract['row_conditions']['fields']['configurations']
        ['allowed_when'] = {'clamp_included': []};
    expect(
        () => ProductSpecRowConditions.fromContract(contract,
            {'configurations': ProductSpecRowSchema.fromJson(schema)}),
        throwsFormatException);
  });
}
