import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_rows.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

void main() {
  final fixture = jsonDecode(
      File('test/fixtures/product_spec_rows.json').readAsStringSync()) as Map;
  final cases = fixture['cases'] as List;
  for (final raw in cases) {
    final entry = Map<String, dynamic>.from(raw as Map);
    test('paired rows ${entry['id']}', () {
      final schema = ProductSpecRowSchema.fromJson(
          Map<String, dynamic>.from(entry['schema'] as Map));
      if (entry['valid'] == true) {
        final result = schema.parse(entry['value']);
        expect(
            result.missingRequired(schema).length, entry['missing_required']);
        expect(schema.parse(result.toJson()).toJson(), result.toJson());
      } else {
        expect(() => schema.parse(entry['value']), throwsFormatException);
      }
    });
  }
  final base = Map<String, dynamic>.from(cases.first as Map);
  final definition = SpecDefinition(
      id: '99ba0000-0000-4000-8000-000000000051',
      key: 'fitment_rows',
      label: 'Configuraciones',
      dataType: 'json',
      options: const [],
      validationRules: {'rows_schema': base['schema']},
      sortOrder: 1);
  final template = SpecTemplate(
      id: '99ba0000-0000-4000-8000-000000000050',
      key: 'rows_fixture',
      name: 'Fixture',
      technicalFamily: 'fixture',
      fields: [
        SpecTemplateField(
            specDefinitionId: definition.id,
            definition: definition,
            sectionKey: 'measurement',
            sortOrder: 1,
            isRequired: false,
            visibilityRules: const [])
      ]);

  test('payload preserves row identities, sources, pairing and false', () {
    final values = <String, dynamic>{'fitment_rows': base['value']};
    final payload = SpecEngineService.buildFactPayload(template, values);
    expect(payload[definition.id], {'rows': base['value']});
    expect(
        validateProductSpecDraft(template: template, values: values), isEmpty);
    final rows = (payload[definition.id]['rows']['rows'] as List);
    expect(rows[0]['values']['bsd'], '622');
    expect(rows[0]['values']['width_max'], '47');
    expect(rows[1]['values']['bsd'], '584');
    expect(rows[1]['values']['width_max'], '62');
    expect(rows[0]['values']['adapter'], false);
    expect(rows[0]['values']['token'], '01');
  });

  test('an incomplete row remains an observation with a nonblocking issue', () {
    final incomplete =
        cases.firstWhere((entry) => entry['id'] == 'partial_is_unknown');
    final issues = validateProductSpecDraft(
        template: template, values: {'fitment_rows': incomplete['value']});
    expect(issues.single.code, 'row_incomplete');
    expect(issues.single.blocking, false);
  });

  test('invalid row blocks before the product command', () {
    final invalid =
        cases.firstWhere((entry) => entry['id'] == 'reversed_within_row');
    final values = <String, dynamic>{'fitment_rows': invalid['value']};
    expect(() => SpecEngineService.buildFactPayload(template, values),
        throwsFormatException);
    expect(
        validateProductSpecDraft(template: template, values: values)
            .single
            .blocking,
        true);
  });

  test('reference equality uses row structure, not map insertion order', () {
    final referenceValue = <String, dynamic>{
      'rows': (base['value']['rows'] as List)
          .map((row) => {
                'sources': row['sources'],
                'values': Map.fromEntries(
                    (row['values'] as Map).entries.toList().reversed),
                'id': row['id'],
              })
          .toList(),
      'schema_version': 1,
    };
    final reference = ProductSpecReference(
        id: 'ref',
        family: 'fixture',
        brand: 'Fixture',
        model: 'A',
        label: 'Fixture A',
        facts: {'fitment_rows': referenceValue},
        sources: const []);
    expect(
        validateProductSpecDraft(
            template: template,
            values: {'fitment_rows': base['value']},
            reference: reference,
            brand: 'Fixture',
            model: 'A'),
        isEmpty);
    referenceValue['rows'][0]['values']['width_max'] = '48';
    expect(
        validateProductSpecDraft(
                template: template,
                values: {'fitment_rows': base['value']},
                reference: reference,
                brand: 'Fixture',
                model: 'A')
            .single
            .code,
        'reference_conflict');
  });

  test('text cell punctuation cannot masquerade as another cell', () {
    final textDef = SpecDefinition(
        id: 'text-row',
        key: 'text_rows',
        label: 'Rows',
        dataType: 'json',
        options: const [],
        sortOrder: 0,
        validationRules: {
          'rows_schema': {
            'version': 1,
            'columns': [
              {'key': 'a', 'label': 'A', 'type': 'text'},
              {'key': 'b', 'label': 'B', 'type': 'text'}
            ]
          }
        });
    final textTemplate = SpecTemplate(
        id: 'text-template',
        key: 'text',
        name: 'Text',
        technicalFamily: 'fixture',
        fields: [
          SpecTemplateField(
              specDefinitionId: textDef.id,
              definition: textDef,
              sectionKey: 'measurement',
              sortOrder: 0,
              isRequired: false,
              visibilityRules: const [])
        ]);
    Map<String, dynamic> rows(Map<String, String> cells) => {
          'schema_version': 1,
          'rows': [
            {'id': 'x', 'values': cells, 'sources': <String>[]}
          ]
        };
    final reference = ProductSpecReference(
        id: 'ref',
        family: 'fixture',
        brand: 'Fixture',
        model: 'A',
        label: 'Fixture A',
        facts: {
          'text_rows': rows({'a': 'x', 'b': 'y'})
        },
        sources: const []);
    final issues = validateProductSpecDraft(
        template: textTemplate,
        values: {
          'text_rows': rows({'a': 'x, b: y'})
        },
        reference: reference,
        brand: 'Fixture',
        model: 'A');
    expect(issues.single.code, 'reference_conflict');
  });

  for (final bad in [
    {...Map<String, dynamic>.from(base['schema']), 'ordered_pairs': null},
    {...Map<String, dynamic>.from(base['schema']), 'unique_by': null},
    for (final entry in {
      'required': null,
      'allowed_values': null,
      'validation': null,
      'positive': null
    }.entries)
      {
        'version': 1,
        'columns': [
          {
            'key': 'n',
            'label': 'N',
            'type': 'decimal',
            if (entry.key == 'positive')
              'validation': {'positive': null}
            else
              entry.key: entry.value
          }
        ]
      },
    {...Map<String, dynamic>.from(base['schema']), 'version': 2},
    {'version': 1, 'columns': []},
    {
      'version': 1,
      'columns': [
        {'key': 'model', 'label': 'Model', 'type': 'token'}
      ],
      'ordered_pairs': [
        ['model', 'model']
      ]
    },
    {
      'version': 1,
      'columns': [
        {
          'key': 'width',
          'label': 'Width',
          'type': 'decimal',
          'validation': {'min': 0}
        }
      ]
    },
    {
      'version': 1,
      'columns': [
        {
          'key': 'model',
          'label': 'Model',
          'type': 'token',
          'allowed_values': ['01', '01']
        }
      ]
    },
  ]) {
    test('malformed schema ${jsonEncode(bad)}', () {
      expect(() => ProductSpecRowSchema.fromJson(bad), throwsFormatException);
    });
  }
}
