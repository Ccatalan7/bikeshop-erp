import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_template_rules.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/inventory/utils/spec_rule_evaluator.dart';

void main() {
  final fixtures = jsonDecode(
      File('test/fixtures/product_spec_template_rules.json')
          .readAsStringSync()) as Map;
  for (final c in fixtures['cases']) {
    test(
        'field condition ${c['id']}',
        () => expect(
            evaluateProductSpecTemplateCondition(
                c['expression'], Map<String, dynamic>.from(c['values'])),
            SpecTruth.values.byName(c['expected'])));
  }
  for (final c in fixtures['invalid']) {
    test(
        'reject invalid field condition ${jsonEncode(c)}',
        () => expect(() => evaluateProductSpecTemplateCondition(c, const {}),
            throwsFormatException));
  }
  final actuation = SpecDefinition(
      id: 'actuation',
      key: 'actuation',
      label: 'Accionamiento',
      dataType: 'single_select',
      options: ['Mechanical', 'Hydraulic'],
      sortOrder: 1);
  final cable = SpecDefinition(
      id: 'cable',
      key: 'cable',
      label: 'Cable',
      dataType: 'single_select',
      options: ['01', '1', 'A'],
      sortOrder: 2);
  final condition = {
    'kind': 'when',
    'rows': [
      [
        {
          'field': 'actuation',
          'operator': 'eq',
          'value_type': 'token',
          'value': 'Mechanical'
        }
      ]
    ]
  };
  final template = SpecTemplate(
      id: 'fixture',
      key: 'fixture',
      name: 'Fixture',
      technicalFamily: 'fixture',
      fields: [
        for (final d in [actuation, cable])
          SpecTemplateField(
              specDefinitionId: d.id,
              definition: d,
              sectionKey: 'primary',
              sortOrder: d.sortOrder,
              isRequired: false,
              visibilityRules: [])
      ],
      formContract: {
        'rules_version': 2,
        'allowed_when': {'cable': condition},
        'required_when': {'cable': condition},
        'allowed_options': {
          'cable': ['01']
        }
      });
  test(
      'required answer follows the actual upstream choice and remains nonblocking',
      () {
    expect(validateProductSpecDraft(template: template, values: {}), isEmpty);
    expect(
        validateProductSpecDraft(
            template: template, values: {'actuation': 'Hydraulic'}),
        isEmpty);
    final missing = validateProductSpecDraft(
        template: template, values: {'actuation': 'Mechanical'}).single;
    expect(missing.code, 'required_missing');
    expect(missing.blocking, false);
  });
  test(
      'changing upstream keeps a contradictory saved answer visible for correction',
      () {
    final issues = validateProductSpecDraft(
        template: template, values: {'actuation': 'Hydraulic', 'cable': '01'});
    expect(issues.single.code, 'field_applicability');
    expect(issues.single.blocking, true);
  });
  test(
      'template options preserve literal models instead of treating them as numbers',
      () {
    expect(
        validateProductSpecDraft(
            template: template,
            values: {'actuation': 'Mechanical', 'cable': '01'}),
        isEmpty);
    expect(
        validateProductSpecDraft(
            template: template,
            values: {'actuation': 'Mechanical', 'cable': '1'}).single.code,
        'constraint');
  });
  test('literal reference does not equate model 01 to model 1', () {
    final reference = ProductSpecReference(
        id: 'ref',
        family: 'fixture',
        brand: 'B',
        model: 'M',
        label: 'Ref',
        facts: {'cable': '01'},
        sources: []);
    final issues = validateProductSpecDraft(
        template: template,
        values: {'actuation': 'Mechanical', 'cable': '1'},
        reference: reference,
        brand: 'B',
        model: 'M');
    expect(issues.map((issue) => issue.code), contains('reference_conflict'));
  });
  test('dependencies include every alternative prerequisite', () {
    expect(template.applicabilityDependencies(template.fields.last),
        {'actuation'});
  });
}
