import 'dart:convert';
import 'dart:io';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/inventory/utils/spec_rule_evaluator.dart';

SpecTemplateField fact(String key, String type,
        {List<String> options = const [],
        List<Map<String, dynamic>> visibility = const [],
        List<Map<String, dynamic>> constraints = const []}) =>
    SpecTemplateField(
        specDefinitionId: key,
        sectionKey: 'primary',
        sortOrder: 0,
        isRequired: false,
        visibilityRules: visibility,
        constraintRules: constraints,
        definition: SpecDefinition(
            id: key,
            key: key,
            label: key,
            dataType: type,
            options: options,
            sortOrder: 0));

SpecTemplate chainTemplate() => SpecTemplate(
        id: 'chain',
        key: 'chain',
        name: 'Cadena',
        technicalFamily: 'chain',
        formContract: {
          'prerequisites': {
            'chain_speeds': ['drivetrain_mode']
          },
          'roles': {
            'drivetrain_platform': 'declaration',
            'spec_evidence_source': 'declaration'
          }
        },
        fields: [
          fact('spec_evidence_source', 'text'),
          fact('drivetrain_platform', 'single_select', options: ['SRAM Eagle']),
          fact('chain_speeds', 'multi_select',
              options: ['1', '5', '6', '7', '8', '9', '10', '11', '12', '13']),
          fact('chain_width_family', 'single_select',
              options: ['1/8', '3/32', '11/128']),
          fact('chain_outer_width_mm', 'number'),
          fact('link_count', 'number'),
          fact('quick_link_included', 'boolean'),
          fact('drivetrain_mode', 'single_select',
              options: ['Derailleur', 'Single speed / BMX / IGH']),
        ]);

void main() {
  test('retired and foreign fields cannot influence the active draft', () {
    final template = SpecTemplate(
        id: 'fixture',
        key: 'fixture',
        name: 'Fixture',
        technicalFamily: 'fixture',
        formContract: {
          'roles': {'legacy_type': 'legacy'},
          'prerequisites': {
            'answer': ['legacy_type']
          }
        },
        fields: [
          fact('legacy_type', 'single_select', options: ['Current']),
          fact('answer', 'single_select', options: [
            'Yes'
          ], visibility: [
            {'field': 'legacy_type', 'value': 'Current'}
          ]),
        ]);
    final issues = validateProductSpecDraft(template: template, values: {
      'legacy_type': 'Retired invalid option',
      'answer': 'Yes',
      'tube_width_min_mm': 200,
      'tube_width_max_mm': 10,
    });
    expect(issues.where((issue) => issue.blocking), isEmpty);
    expect(issues.any((issue) => issue.fieldKey == 'answer' && !issue.blocking),
        isTrue);
    expect(issues.any((issue) => issue.fieldKey == 'legacy_type'), isFalse);
  });

  test('a stock refresh cannot bless concurrent commercial edits', () {
    final before = Product(
        tenantId: 't',
        name: 'X8',
        sku: 'x8',
        price: 10,
        cost: 5,
        inventoryQty: 1);
    final stock =
        before.copyWith(inventoryQty: 2, updatedAt: DateTime(2026, 9, 6));
    expect(canRefreshProductEditAfterStockAdjustment(before, stock), isTrue);
    expect(
        canRefreshProductEditAfterStockAdjustment(
            before, stock.copyWith(price: 20)),
        isFalse);
  });

  final references = (jsonDecode(File(
              'docs/development/product-specs-research-2026-09-05/reference-fixtures.json')
          .readAsStringSync()) as List)
      .map((row) =>
          ProductSpecReference.fromJson(Map<String, dynamic>.from(row as Map)))
      .toList(growable: false);

  test('missing knowledge never proves a negative predicate', () {
    for (final operator in [
      'eq',
      'neq',
      'in',
      'not_in',
      'contains_any',
      'contains_all'
    ]) {
      expect(
          evaluateSpecCondition(
              {'field': 'mount', 'operator': operator, 'value': 'A'}, {}),
          SpecTruth.unknown);
    }
    expect(hasKnownSpecValue(false), isTrue);
    expect(hasKnownSpecValue(0), isTrue);
    expect(hasKnownSpecValue('Desconocido / sin confirmar'), isFalse);
  });

  test('set-valued requirements are typed and order independent', () {
    expect(
        evaluateSpecCondition({
          'field': 'speed',
          'operator': 'eq',
          'value': [6, 7, 8]
        }, {
          'speed': ['8', '6.0', '7']
        }),
        SpecTruth.yes);
    expect(
        evaluateSpecCondition({
          'field': 'speed',
          'operator': 'in',
          'value': [6, 7, 8]
        }, {
          'speed': [6, 12]
        }),
        SpecTruth.no);
    expect(
        evaluateSpecCondition({
          'field': 'speed',
          'operator': 'contains_any',
          'value': [6, 7, 8]
        }, {
          'speed': [6, 12]
        }),
        SpecTruth.yes);
  });

  test('a malformed rule fails closed instead of permitting every option', () {
    expect(
        () =>
            evaluateSpecCondition({'field': 'x', 'operator': 'typo'}, {'x': 1}),
        throwsFormatException);
    expect(() => evaluateSpecCondition({'operator': 'eq'}, {}),
        throwsFormatException);
  });

  test('empty intersection stays empty and the manual draft survives', () {
    final field = fact('diameter', 'number', constraints: [
      {
        'field': 'mount',
        'value': 'A',
        'allow': [24]
      },
      {
        'field': 'construction',
        'value': 'B',
        'allow': [30]
      },
    ]);
    final values = <String, dynamic>{
      'mount': 'A',
      'construction': 'B',
      'diameter': 24
    };
    final before = jsonEncode(values);
    expect(field.constrainedOptionsFor(values), isEmpty);
    final template = SpecTemplate(
        id: 't',
        key: 't',
        name: 't',
        technicalFamily: 'bottom_bracket',
        fields: [fact('mount', 'text'), fact('construction', 'text'), field]);
    expect(
        validateProductSpecDraft(template: template, values: values)
            .single
            .code,
        'constraint');
    expect(jsonEncode(values), before);
  });

  test('legacy suggested options are not promoted to mechanical constraints',
      () {
    final field = SpecTemplateField(
        specDefinitionId: 'width',
        sectionKey: 'measurements',
        sortOrder: 0,
        isRequired: false,
        visibilityRules: [],
        optionRules: [
          {
            'field': 'mount',
            'value': 'BSA',
            'allow': [68, 73]
          },
        ],
        definition: fact('width', 'number').definition);
    expect(field.allowedOptionsFor({'mount': 'BSA'}), {'68', '73'});
    expect(field.constrainedOptionsFor({'mount': 'BSA'}), isNull);
  });

  for (final reference in references) {
    test('${reference.id}: independent manufacturer facts are accepted', () {
      expect(
          validateProductSpecDraft(
              template: chainTemplate(),
              values: reference.facts,
              reference: reference,
              brand: reference.brand,
              model: reference.model,
              manufacturerSku: reference.manufacturerSku!),
          isEmpty);
    });
    test('${reference.id}: changing the variant invalidates the binding', () {
      expect(
          validateProductSpecDraft(
                  template: chainTemplate(),
                  values: reference.facts,
                  reference: reference,
                  brand: reference.brand,
                  model: reference.model,
                  manufacturerSku: 'different')
              .any((issue) => issue.code == 'reference_identity'),
          isTrue);
    });
  }

  test('X8 114-link EU edition cannot retain 11/128 or a US pack length', () {
    final x8 = references.first;
    final draft = {
      ...x8.facts,
      'chain_width_family': '11/128',
      'link_count': 116
    };
    final issues = validateProductSpecDraft(
        template: chainTemplate(),
        values: draft,
        reference: x8,
        brand: 'KMC',
        model: 'X8',
        manufacturerSku: 'BX08NG114');
    expect(
        issues
            .where((i) => i.code == 'reference_conflict')
            .map((i) => i.fieldKey)
            .toSet(),
        {'chain_width_family', 'link_count'});
    expect(draft['chain_width_family'], '11/128',
        reason: 'a conflict is preserved for review');
  });

  test('eGlide 5.4 mm does not become 12-speed through an outer-width band',
      () {
    final ref = references[1];
    expect(ref.facts['chain_speeds'], ['9', '10', '11']);
    expect(ref.claims.single['platform'], 'Shimano LINKGLIDE');
    expect(ref.claims.single['exclusive'], isTrue);
    final values = {
      ...ref.facts,
      'chain_speeds': ['12']
    };
    expect(
        validateProductSpecDraft(
                template: chainTemplate(),
                values: values,
                reference: ref,
                brand: 'KMC',
                model: 'eGlide',
                manufacturerSku: 'CN11245')
            .any((i) => i.fieldKey == 'chain_speeds'),
        isTrue);
  });

  test('a reference does not authorize an extra manual platform claim', () {
    final ref = references.first;
    final issues = validateProductSpecDraft(
        template: chainTemplate(),
        values: {...ref.facts, 'drivetrain_platform': 'SRAM Eagle'},
        reference: ref,
        brand: ref.brand,
        model: ref.model,
        manufacturerSku: ref.manufacturerSku!);
    expect(
        issues.any((issue) =>
            issue.code == 'unsupported_declaration' && issue.blocking),
        isTrue);
  });
  test('missing prerequisites are pending knowledge, not contradictions', () {
    final issues = validateProductSpecDraft(template: chainTemplate(), values: {
      'chain_speeds': ['8']
    });
    expect(issues, hasLength(1));
    expect(issues.single.blocking, isFalse);
  });
  test('the KMC screenshot combination is signalled without a width oracle',
      () {
    final issues = validateProductSpecDraft(
        template: chainTemplate(),
        brand: 'KMC',
        values: {
          'chain_speeds': ['6', '7', '8'],
          'chain_width_family': '11/128',
          'chain_outer_width_mm': 7.1
        });
    expect(
        issues.any((issue) => issue.code == 'verify_model' && !issue.blocking),
        isTrue);
  });
  test('X11 manufacturer declaration includes Campagnolo', () {
    expect(references[2].claims.single['systems'],
        containsAll(['Shimano', 'SRAM', 'Campagnolo']));
  });

  test('an unknown model is not rejected by nominal width as a speed oracle',
      () {
    // Sheldon describes narrower chains on older systems; Park gives nominal
    // widths. These numbers alone cannot prove physical incompatibility.
    expect(
        validateProductSpecDraft(template: chainTemplate(), values: {
          'chain_speeds': ['7', '8'],
          'chain_width_family': '11/128',
          'chain_outer_width_mm': 7.1,
        }).where((i) => i.blocking),
        isEmpty);
  });

  test('false is a recorded answer and an absent boolean stays absent', () {
    final values = <String, dynamic>{'quick_link_included': false};
    expect(validateProductSpecDraft(template: chainTemplate(), values: values),
        isEmpty);
    expect(values, {'quick_link_included': false});
  });

  test('a hidden manual value is reported and never removed', () {
    final field = fact('offset', 'number', visibility: [
      {'field': 'symmetry', 'value': 'asymmetric'}
    ]);
    final template = SpecTemplate(
        id: 'rim',
        key: 'rim',
        name: 'Aro',
        technicalFamily: 'rim',
        fields: [field]);
    final values = <String, dynamic>{'symmetry': 'symmetric', 'offset': 3};
    expect(
        validateProductSpecDraft(template: template, values: values)
            .single
            .code,
        'prerequisite');
    expect(values['offset'], 3);
  });

  test('tube interval comparison is independent of field build order', () {
    final template = SpecTemplate(
        id: 'tube',
        key: 'tube',
        name: 'Cámara',
        technicalFamily: 'tube',
        fields: [
          fact('tube_width_max_mm', 'number'),
          fact('tube_width_min_mm', 'number')
        ]);
    expect(
        validateProductSpecDraft(
                template: template,
                values: {'tube_width_min_mm': 50, 'tube_width_max_mm': 40})
            .where((issue) => issue.code == 'range_order')
            .map((issue) => issue.fieldKey),
        ['tube_width_min_mm', 'tube_width_max_mm']);
  });
}
