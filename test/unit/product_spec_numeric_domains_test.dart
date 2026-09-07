import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

void main() {
  final rows = jsonDecode(File(
          'docs/development/product-specs-research-2026-09-05/numeric-domain-template-fixtures.json')
      .readAsStringSync()) as List;
  final templates = <String, SpecTemplate>{
    for (final row in rows)
      row['key']: SpecTemplate(
        id: row['key'],
        key: row['key'],
        name: row['key'],
        technicalFamily: row['technical_family'],
        formContract: Map<String, dynamic>.from(row['form_contract']),
        fields: [
          for (final f in row['fields'])
            SpecTemplateField(
              specDefinitionId: f['key'],
              sectionKey: f['section'],
              sortOrder: f['sort_order'],
              isRequired: f['required'],
              visibilityRules: (f['visibility_rules'] as List)
                  .map((r) => Map<String, dynamic>.from(r))
                  .toList(),
              constraintRules: (f['constraint_rules'] as List)
                  .map((r) => Map<String, dynamic>.from(r))
                  .toList(),
              definition: SpecDefinition(
                id: f['key'],
                key: f['key'],
                label: f['label'],
                dataType: f['data_type'],
                options: List<String>.from(f['allowed_values']),
                sortOrder: 0,
                validationRules:
                    Map<String, dynamic>.from(f['validation_rules']),
              ),
            ),
        ],
      ),
  };
  List<ProductSpecIssue> blocking(String key, Map<String, dynamic> values) =>
      validateProductSpecDraft(template: templates[key]!, values: values)
          .where((issue) => issue.blocking)
          .toList();

  test('documented BCDs outside the former stock range remain recordable', () {
    for (final diameter in [58, 145, 146]) {
      expect(blocking('chainring', {'chainring_bcd_mm': diameter}), isEmpty);
    }
  });
  test('132 mm has no range error; an absent shell fails is_set applicability',
      () {
    final issues = validateProductSpecDraft(
        template: templates['bottom_bracket']!,
        values: {'bb_shell_width_mm': 132});
    expect(issues.where((issue) => issue.code == 'range'), isEmpty);
    // The legacy is_set guard is false (not unknown) without a shell.
    // A numeric-domain assertion must retain that field-applicability block.
    expect(
        issues.any((issue) =>
            issue.code == 'field_applicability' && issue.blocking),
        isTrue);
  });
  test('cassette and freewheel cannot declare fractional physical teeth', () {
    for (final family in ['cassette', 'freewheel']) {
      expect(
          blocking(family, {'smallest_cog_teeth': 11.5})
              .any((issue) => issue.code == 'integer'),
          isTrue);
    }
  });
  test('rim, spoke, hose and rotor measurements must be positive', () {
    for (final item in [
      ['rim', 'rim_erd_mm'],
      ['spoke', 'spoke_length_mm'],
      ['hydraulic_disc_brake', 'hose_length_mm'],
      ['rotor', 'rotor_thickness_mm'],
    ]) {
      expect(blocking(item[0], {item[1]: 0}), isNotEmpty);
      expect(blocking(item[0], {item[1]: -1}), isNotEmpty);
    }
  });
  test('zero stack, fractional spacer and signed offset retain their meaning',
      () {
    expect(blocking('bottom_bracket', {'bb_spacer_stack_mm': 0}), isEmpty);
    expect(blocking('cassette_spacer', {'spacer_thickness_mm': 0.25}), isEmpty);
    expect(blocking('chainring', {'chainring_offset_mm': -12}), isEmpty);
  });
  test('tube width range cannot reverse, and absent widths remain unknown', () {
    expect(
        blocking('tube', {'tube_width_min_mm': 37, 'tube_width_max_mm': 33})
            .any((issue) => issue.code == 'range_order'),
        isTrue);
    expect(blocking('tube', {}), isEmpty);
  });
}
