import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_rows.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

void main() {
  final fixture = jsonDecode(
      File('test/fixtures/product_spec_strict_row_order.json')
          .readAsStringSync()) as Map<String, dynamic>;
  for (final entry in fixture['cases'] as List) {
    test('strict row order: ${entry['id']}', () {
      final rawSchema = Map<String, dynamic>.from(fixture['schema']);
      if (entry['legacy_schema'] == true) {
        rawSchema['version'] = 1;
        rawSchema.remove('strict_ordered_pairs');
        rawSchema['ordered_pairs'] = [
          ['inner', 'outer']
        ];
      }
      rawSchema.addAll(Map<String, dynamic>.from(entry['schema_set'] ?? {}));
      final schema = ProductSpecRowSchema.fromJson(rawSchema);
      final values = entry['values'] as List;
      final value = {
        'schema_version': entry['envelope_version'] ?? schema.version,
        'rows': [
          for (var index = 0; index < values.length; index++)
            {
              'id': 'piece-$index',
              'values': values[index],
              'sources': <String>[]
            }
        ]
      };
      final definition = SpecDefinition(
          id: 'strict-row-body',
          key: 'body',
          label: 'Cuerpo',
          dataType: 'json',
          options: const [],
          sortOrder: 0,
          validationRules: {'rows_schema': rawSchema});
      final template = SpecTemplate(
          id: 'strict-row-template',
          key: 'test_body',
          name: 'Test',
          technicalFamily: 'fixture',
          fields: [
            SpecTemplateField(
                specDefinitionId: definition.id,
                definition: definition,
                sectionKey: 'measurement',
                sortOrder: 0,
                isRequired: false,
                visibilityRules: const [])
          ]);
      final issues =
          validateProductSpecDraft(template: template, values: {'body': value});
      if (entry['valid'] == true) {
        final parsed = schema.parse(value);
        expect(
            parsed.missingRequired(schema).length, entry['missing_required']);
        expect(schema.parse(parsed.toJson()).toJson(), parsed.toJson());
        expect(issues.where((issue) => issue.blocking), isEmpty);
        expect(
            SpecEngineService.buildFactPayload(
                template, {'body': value})[definition.id],
            {'rows': parsed.toJson()});
      } else {
        expect(() => schema.parse(value), throwsFormatException);
        expect(
            issues.any((issue) => issue.code == 'row_shape' && issue.blocking),
            true);
        expect(
            () => SpecEngineService.buildFactPayload(template, {'body': value}),
            throwsFormatException);
      }
    });
  }
  for (final entry in fixture['invalid_schemas'] as List) {
    test('strict row metadata: ${entry['id']}', () {
      final schema = {
        ...Map<String, dynamic>.from(fixture['schema']),
        ...Map<String, dynamic>.from(entry['set'])
      };
      for (final key in entry['remove'] ?? []) {
        schema.remove(key);
      }
      expect(
          () => ProductSpecRowSchema.fromJson(schema), throwsFormatException);
    });
  }
}
