import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/services/supply_need_effective_criteria.dart';

SpecTemplateField field(String key, String type,
        {List<Map<String, dynamic>> visibility = const [],
        List<Map<String, dynamic>> options = const [],
        List<Map<String, dynamic>> constraints = const []}) =>
    SpecTemplateField(
      specDefinitionId: key,
      sectionKey: 'test',
      sortOrder: 0,
      isRequired: false,
      visibilityRules: visibility,
      optionRules: options,
      constraintRules: constraints,
      definition: SpecDefinition(
        id: key,
        key: key,
        label: key,
        dataType: type,
        options: const ['A', 'B', 'C'],
        sortOrder: 0,
      ),
    );

SpecTemplate template(List<SpecTemplateField> fields,
        {Map<String, dynamic> contract = const {}}) =>
    SpecTemplate(
      id: 'synthetic-criteria',
      key: 'synthetic-criteria',
      name: 'Synthetic criteria',
      technicalFamily: 'fixture',
      fields: fields,
      formContract: contract,
    );

SupplyNeedPredicate predicate(String key, String op, List<Object> values) =>
    SupplyNeedPredicate(field: key, operator: op, values: values);

Map<String, dynamic> when(String key, String value) => {
      'kind': 'when',
      'rows': [
        [
          {
            'field': key,
            'operator': 'eq',
            'value_type': 'token',
            'value': value,
          }
        ]
      ]
    };

void main() {
  final scalar = template([
    field('number', 'number'),
    field('flag', 'boolean'),
    field('text', 'text'),
    field('choice', 'select'),
    field('many', 'multi_select'),
  ]);
  for (final op in [
    'lt',
    'lte',
    'gt',
    'gte',
    'neq',
    'between',
    'in',
    'contains'
  ]) {
    test('$op does not assert an exact prerequisite value', () {
      expect(
          supplyNeedExactPrerequisiteValues(scalar, [
            predicate('number', op, op == 'between' ? [30, 40] : [30]),
          ]),
          isEmpty);
    });
  }
  test('zero and false are exact answers; unknown and malformed values are not',
      () {
    expect(
        supplyNeedExactPrerequisiteValues(scalar, [
          predicate('number', 'eq', [0]),
          predicate('flag', 'eq', [false]),
          predicate('text', 'eq', ['unknown']),
          predicate('choice', 'eq', ['not-an-option']),
          predicate('many', 'eq', ['A']),
        ]),
        {'number': 0, 'flag': false});
    expect(
        supplyNeedExactPrerequisiteValues(scalar, [
          predicate('number', 'eq', [double.infinity]),
          predicate('flag', 'eq', ['false']),
          predicate('text', 'eq', [
            <String, Object>{'fake': 'text'}
          ]),
        ]),
        isEmpty);
  });
  test('ambiguous duplicate clauses remain unknown', () {
    expect(
        supplyNeedExactPrerequisiteValues(scalar, [
          predicate('number', 'eq', [30]),
          predicate('number', 'eq', [40]),
          predicate('choice', 'eq', ['A']),
          predicate('choice', 'neq', ['B']),
        ]),
        isEmpty);
  });
  test('v2 applicability uses exact requests, and omitting criteria is unknown',
      () {
    final t = template([
      field('choice', 'select'),
      field('child', 'text')
    ], contract: {
      'rules_version': 2,
      'allowed_when': {'child': when('choice', 'A')}
    });
    List<String> visible(Map<String, dynamic> values) =>
        supplyNeedCriterionFieldsOf(t, exactValues: values)
            .map((f) => f.definition!.key)
            .toList();
    expect(visible({}), ['choice', 'child']);
    expect(visible({'choice': 'A'}), ['choice', 'child']);
    expect(visible({'choice': 'B'}), ['choice']);
    expect(
        supplyNeedExactPrerequisiteValues(t, [
          predicate('choice', 'eq', ['B']),
          predicate('child', 'eq', ['old draft']),
        ]),
        {'choice': 'B'});
  });
  test('presence conditions do not turn an absent request into a product fact',
      () {
    final t = template([
      field('choice', 'select'),
      field('present', 'text', visibility: [
        {'field': 'choice', 'operator': 'is_set'}
      ]),
      field('absent', 'text', visibility: [
        {'field': 'choice', 'operator': 'not_set'}
      ]),
      field('retired', 'text'),
      field('never', 'text'),
      field('rows', 'structured_rows'),
    ], contract: {
      'roles': {'retired': 'legacy'},
      'allowed_when': {
        'never': {'kind': 'never'}
      }
    });
    expect(supplyNeedCriterionFieldsOf(t).map((f) => f.definition!.key),
        ['choice', 'present', 'absent']);
  });
  test(
      'legacy and v2 option constraints intersect, without missing-input claims',
      () {
    final choice = field('choice', 'select', options: [
      {
        'field': 'number',
        'operator': 'gt',
        'value': 30,
        'allow': ['A', 'B']
      },
      {
        'field': 'text',
        'operator': 'not_set',
        'allow': ['C']
      }
    ], constraints: [
      {
        'field': 'number',
        'operator': 'gt',
        'value': 30,
        'allow': ['B', 'C']
      }
    ]);
    final t = template([
      field('number', 'number'),
      choice
    ], contract: {
      'rules_version': 2,
      'allowed_options': {
        'choice': ['A', 'B']
      }
    });
    expect(supplyNeedCriterionOptionsOf(t, choice, {}), ['A', 'B']);
    expect(supplyNeedCriterionOptionsOf(t, choice, {'number': 31}), ['B']);
  });
}
