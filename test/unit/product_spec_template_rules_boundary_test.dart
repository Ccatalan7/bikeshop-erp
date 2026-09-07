import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_relation.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_template_rules.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/inventory/utils/spec_rule_evaluator.dart';

// Synthetic form contracts. These assertions do not establish bicycle fitment.
Map<String, dynamic> _when(
        String field, String type, String operator, Object value) =>
    {
      'kind': 'when',
      'rows': [
        [
          {
            'field': field,
            'value_type': type,
            'operator': operator,
            'value': value,
          },
        ],
      ],
    };

SpecTemplate _template({
  Map<String, dynamic> contract = const {},
  List<Map<String, dynamic>> visibility = const [],
  List<Map<String, dynamic>> constraints = const [],
}) {
  const definitions = [
    SpecDefinition(
        id: 'mode',
        key: 'mode',
        label: 'Mode',
        dataType: 'single_select',
        options: ['A', 'B', '01', '1'],
        sortOrder: 1),
    SpecDefinition(
        id: 'child',
        key: 'child',
        label: 'Child',
        dataType: 'single_select',
        options: ['01', '1'],
        optionIds: {'01': 'option-01', '1': 'option-1'},
        sortOrder: 2),
    SpecDefinition(
        id: 'amount',
        key: 'amount',
        label: 'Amount',
        dataType: 'number',
        options: [],
        sortOrder: 3),
    SpecDefinition(
        id: 'list',
        key: 'list',
        label: 'List',
        dataType: 'multi_select',
        options: ['01', '1'],
        sortOrder: 4),
    SpecDefinition(
        id: 'flag',
        key: 'flag',
        label: 'Flag',
        dataType: 'boolean',
        options: [],
        sortOrder: 5),
  ];
  return SpecTemplate(
    id: 'boundary',
    key: 'boundary',
    name: 'Boundary',
    technicalFamily: 'fixture',
    fields: [
      for (final definition in definitions)
        SpecTemplateField(
          specDefinitionId: definition.id,
          definition: definition,
          sectionKey: 'primary',
          sortOrder: definition.sortOrder,
          isRequired: false,
          visibilityRules: definition.key == 'child' ? visibility : [],
          constraintRules: definition.key == 'child' ? constraints : [],
        ),
    ],
    formContract: {
      'rules_version': 2,
      'allowed_when': <String, dynamic>{},
      'required_when': <String, dynamic>{},
      'allowed_options': <String, dynamic>{},
      'prerequisites': <String, dynamic>{},
      ...contract,
    },
  );
}

List<ProductSpecIssue> _issues(
        SpecTemplate template, Map<String, dynamic> values) =>
    validateProductSpecDraft(template: template, values: values);

void main() {
  group('ordinary numeric answers at the condition boundary', () {
    for (final value in <Object>[2, 2.5, '2', '2.5']) {
      test('number or decimal text $value activates its dependent field', () {
        final template = _template(contract: {
          'allowed_when': {'child': _when('amount', 'decimal', 'gte', '2')},
          'required_when': {
            'child': {'kind': 'always'}
          },
        });
        final issues = _issues(template, {'amount': value});
        expect(template.applicabilityFor(template.fields[1], {'amount': value}),
            SpecTruth.yes);
        expect(issues, hasLength(1));
        expect(issues.single.code, 'required_missing');
        expect(issues.single.blocking, isFalse);
      });
    }

    test('writer payload and numeric editor answer retain the same condition',
        () {
      final template = _template(contract: {
        'allowed_when': {'child': _when('amount', 'decimal', 'gte', '2')},
      });
      final payload =
          SpecEngineService.buildFactPayload(template, {'amount': '2.5'});
      expect(payload, {
        'amount': {'number': '2.5'}
      });
      expect(
          template.applicabilityFor(template.fields[1],
              {'amount': (payload['amount'] as Map)['number']}),
          SpecTruth.yes);
    });

    test('form projection does not relax the relation transport', () {
      final expression = _when('amount', 'decimal', 'eq', '2');
      final condition = Map<String, dynamic>.from(
          (expression['rows'] as List).first.first as Map);
      expect(evaluateProductSpecTemplateCondition(expression, {'amount': 2}),
          SpecTruth.yes);
      expect(evaluateSpecRelationCondition(condition, {'amount': 2}),
          SpecTruth.unknown);
    });

    test('decimal text keeps exact comparison beyond binary integer precision',
        () {
      expect(
          evaluateProductSpecTemplateCondition(
              _when('amount', 'decimal', 'gte', '9007199254740993.1'),
              {'amount': '9007199254740993.0'}),
          SpecTruth.no);
    });

    for (final invalid in ['2,5', ' 2 ', '2 ', '\n2']) {
      test('metadata operand rejects noncanonical decimal ${invalid.codeUnits}',
          () {
        expect(
            () => evaluateProductSpecTemplateCondition(
                _when('amount', 'decimal', 'eq', invalid), {'amount': '2'}),
            throwsFormatException);
      });
    }

    test('zero and false remain answers while a missing operand stays unknown',
        () {
      expect(
          evaluateProductSpecTemplateCondition(
              _when('amount', 'decimal', 'eq', '0'), {'amount': 0}),
          SpecTruth.yes);
      expect(
          evaluateProductSpecTemplateCondition(
              _when('flag', 'boolean', 'eq', false), {'flag': false}),
          SpecTruth.yes);
      expect(
          evaluateProductSpecTemplateCondition(
              _when('flag', 'boolean', 'eq', false), {'flag': 'false'}),
          SpecTruth.unknown);
      expect(
          evaluateProductSpecTemplateCondition(
              _when('amount', 'decimal', 'gte', '2'), {}),
          SpecTruth.unknown);
    });
  });

  group('new applicability and inherited visibility', () {
    final template = _template(
      contract: {
        'allowed_when': {'child': _when('amount', 'decimal', 'gte', '2')},
        'required_when': {
          'child': {'kind': 'always'}
        },
      },
      visibility: [
        {'field': 'mode', 'operator': 'eq', 'value': 'A'}
      ],
    );
    test('a known upstream contradiction blocks without deleting its answer',
        () {
      final values = <String, dynamic>{'mode': 'B', 'amount': 2, 'child': '01'};
      final issues = _issues(template, values);
      expect(issues.any((issue) => issue.blocking), isTrue);
      expect(
          template.applicabilityFor(template.fields[1], values), SpecTruth.no);
      expect(values, {'mode': 'B', 'amount': 2, 'child': '01'});
    });
    test(
        'unknown inherited visibility is nonblocking and does not require child',
        () {
      expect(_issues(template, {'amount': 2}), isEmpty);
      final issues = _issues(template, {'amount': 2, 'child': '01'});
      expect(issues, isNotEmpty);
      expect(issues.every((issue) => !issue.blocking), isTrue);
      expect(template.applicabilityFor(template.fields[1], {'amount': 2}),
          SpecTruth.unknown);
    });
    test('both conditions must hold and both contribute dependencies', () {
      expect(_issues(template, {'mode': 'A', 'amount': 2, 'child': '01'}),
          isEmpty);
      expect(template.applicabilityDependencies(template.fields[1]),
          {'mode', 'amount'});
      expect(_issues(template, {'mode': 'B', 'amount': 2}), isEmpty);
    });
  });

  group('literal options and explicit boolean options', () {
    final template = _template();
    for (final value in <Object>[
      1,
      true,
      {'value': '1'}
    ]) {
      test('single select rejects non-string $value', () {
        expect(
            _issues(template, {'child': value}).any((i) => i.blocking), isTrue);
      });
    }
    for (final value in <Object>[
      1,
      false,
      {'value': '1'}
    ]) {
      test('multi select rejects non-string member $value', () {
        expect(
            _issues(template, {
              'list': [value]
            }).any((i) => i.blocking),
            isTrue);
      });
    }
    test('valid literal lists and string 01 remain valid', () {
      expect(
          _issues(template, {
            'child': '01',
            'list': ['01', '1']
          }),
          isEmpty);
      expect(
          evaluateProductSpecTemplateCondition(
              _when('mode', 'token', 'eq', '01'), {'mode': '1'}),
          SpecTruth.no);
    });
    test('legacy allow and v2 subset intersect without normalizing 01 to 1',
        () {
      final narrowed = _template(
        contract: {
          'allowed_options': {
            'child': ['01']
          }
        },
        constraints: [
          {
            'field': 'mode',
            'operator': 'eq',
            'value': 'A',
            'allow': ['01']
          }
        ],
      );
      expect(narrowed.constrainedOptionsFor(narrowed.fields[1], {'mode': 'A'}),
          {'01'});
      expect(_issues(narrowed, {'mode': 'A', 'child': '01'}), isEmpty);
      expect(
          _issues(narrowed, {'mode': 'A', 'child': '1'}).any((i) => i.blocking),
          isTrue);
    });
    test(
        'boolean option restriction compares bool values by its explicit tokens',
        () {
      final narrowed = _template(contract: {
        'allowed_options': {
          'flag': ['true']
        }
      });
      expect(_issues(narrowed, {'flag': true}), isEmpty);
      expect(_issues(narrowed, {'flag': false}).any((i) => i.blocking), isTrue);
      expect(
          _issues(narrowed, {'flag': 'true'}).any((i) => i.blocking), isTrue);
    });
    test('reference model 01 cannot be satisfied by model 1', () {
      const reference = ProductSpecReference(
          id: 'reference',
          family: 'fixture',
          brand: 'B',
          model: 'M',
          label: 'Ref',
          facts: {'child': '01'},
          sources: []);
      expect(
          validateProductSpecDraft(
                  template: template,
                  values: {'child': '1'},
                  reference: reference,
                  brand: 'B',
                  model: 'M')
              .any((i) => i.code == 'reference_conflict' && i.blocking),
          isTrue);
    });
  });

  test('foreign and retired answers cannot change active draft validation', () {
    final template = _template(contract: {
      'roles': {'amount': 'legacy'}
    });
    final values = <String, dynamic>{
      'amount': 'invalid-number',
      'alien': '01',
      'child': '01'
    };
    expect(_issues(template, values), isEmpty);
    expect(values['amount'], 'invalid-number');
    expect(values['alien'], '01');
  });
}
