// Representation coverage is separate from OEM approval and inventory adoption.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

Map<String, dynamic> object(Object? value) =>
    Map<String, dynamic>.from(value as Map);

void main() {
  const directory = 'docs/development/product-specs-research-2026-09-05/';
  final catalog = object(jsonDecode(
      File('${directory}all-family-port-cardinality-integrated-2026-09-07.json')
          .readAsStringSync()));
  final fixtures = object(jsonDecode(
      File('${directory}all-family-port-cardinality-cases-integrated-2026-09-07.json')
          .readAsStringSync()));
  final definitions = object(catalog['definitions']);
  final templates = <String, SpecTemplate>{};
  for (final raw in catalog['templates'] as List) {
    final data = object(raw);
    templates[data['key']] = SpecTemplate(
        id: data['id'],
        key: data['key'],
        name: data['name'],
        technicalFamily: data['technical_family'],
        formContract: object(data['form_contract']),
        fields: [
          for (final field in data['fields'] as List)
            SpecTemplateField(
                specDefinitionId: definitions[field['key']]['id'],
                sectionKey: field['section_key'],
                sortOrder: field['sort_order'],
                isRequired: field['is_required'],
                visibilityRules:
                    (field['visibility_rules'] as List).map(object).toList(),
                constraintRules:
                    (field['constraint_rules'] as List).map(object).toList(),
                definition:
                    SpecDefinition.fromJson(object(definitions[field['key']])))
        ]);
  }
  for (final template in templates.values) {
    test('${template.key}: executable template and row metadata', () {
      for (final field in template.fields) {
        if (field.definition!.validationRules.containsKey('rows_schema')) {
          expect(field.definition!.rowSchema, isNotNull);
        }
      }
      expect(() => template.coherence, returnsNormally);
      expect(() => template.rowConditions, returnsNormally);
      final issues = validateProductSpecDraft(template: template, values: {});
      expect(issues.where((issue) => issue.blocking), isEmpty,
          reason: 'Absent observations must not conceal invalid metadata.');
    });
  }
  for (final raw in fixtures['cases'] as List) {
    final fixture = object(raw);
    test('${fixture['id']}: adjudicated representation result', () {
      final values = object(fixture['values']);
      final before = jsonEncode(values);
      final issues = validateProductSpecDraft(
          template: templates[fixture['template']]!,
          values: values);
      expect(jsonEncode(values), before,
          reason: 'Validation must preserve declared values, row IDs and sources.');
      for (final expected in
          object(fixture['expected_row_counts'] ?? {}).entries) {
        final field = templates[fixture['template']]!
            .fields
            .singleWhere((field) => field.definition!.key == expected.key);
        expect(field.definition!.rowSchema!.parse(values[expected.key]).rows.length,
            expected.value,
            reason: 'Separate documents and printed units retain their rows.');
      }
      final actual = issues
          .where((issue) => issue.blocking)
          .map((issue) => '${issue.code}:${issue.fieldKey}')
          .toSet();
      final expected = (fixture['expected_blocking'] as List)
          .map((issue) => '${issue['code']}:${issue['field']}')
          .toSet();
      expect(actual, expected,
          reason: 'A documentary conflict can remain outside the row DSL; '
              'a passing representation never makes that claim verified.');
      if (fixture.containsKey('expected_issue_subset')) {
        final normalized = issues
            .map((issue) => {
                  'code': issue.code,
                  'field': issue.fieldKey,
                  'blocking': issue.blocking,
                })
            .toList();
        for (final expectedIssue in fixture['expected_issue_subset'] as List) {
          expect(normalized, contains(equals(expectedIssue)));
        }
      }
      for (final field in fixture['forbidden_issue_fields'] as List? ?? []) {
        expect(issues.where((issue) => issue.fieldKey == field), isEmpty,
            reason:
                'An inapplicable feature must not create impossible missing data.');
      }
      if (fixture.containsKey('expected_row_condition_issues')) {
        final conditions = templates[fixture['template']]!
            .rowConditions
            .validate(object(fixture['values']));
        expect(
            conditions
                .map((issue) => {
                      'code': issue.code,
                      'field': issue.field,
                      'row_id': issue.rowId,
                      'column': issue.column,
                      'blocking': issue.blocking,
                    })
                .toList(),
            fixture['expected_row_condition_issues']);
      }
      expect(fixture['automatic_fill_authorized'], isNot(true));
      expect(fixture['facts_verified_for_product'], isNot(true));
    });
  }
  final proposal = object(jsonDecode(
      File('${directory}all-family-row-conditions-proposal-2026-09-07.json')
          .readAsStringSync()));
  for (final raw in proposal['metadata_negative_cases'] as List) {
    final fixture = object(raw);
    test('${fixture['id']}: unsupported row condition fails closed', () {
      final original = templates[fixture['template']]!;
      final contract = object(jsonDecode(jsonEncode(original.formContract)));
      contract['row_conditions']['fields'][fixture['field']] =
          fixture['replace_rules'];
      final invalid = SpecTemplate(
          id: original.id,
          key: original.key,
          name: original.name,
          technicalFamily: original.technicalFamily,
          fields: original.fields,
          formContract: contract);
      expect(() => invalid.rowConditions, throwsFormatException);
    });
  }
}
