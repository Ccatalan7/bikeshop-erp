import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

const fixtures = 'docs/development/product-specs-research-2026-09-05/';

void main() {
  final templates = {
    for (final row in jsonDecode(
        File('${fixtures}chain-connector-template-fixtures.json')
            .readAsStringSync()) as List)
      row['key'] as String: SpecTemplate(
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
                      Map<String, dynamic>.from(f['validation_rules'])),
            )
        ],
      ),
  };
  final references = (jsonDecode(
          File('${fixtures}chain-connector-reference-fixtures.json')
              .readAsStringSync()) as List)
      .map((r) => ProductSpecReference.fromJson(Map<String, dynamic>.from(r)))
      .toList();
  List<ProductSpecIssue> issues(String family, Map<String, dynamic> values) =>
      validateProductSpecDraft(template: templates[family]!, values: values);

  for (final reference in references) {
    test('${reference.id} retains exactly its documented facts', () {
      expect(
          validateProductSpecDraft(
              template: templates[reference.family]!,
              values: reference.facts,
              reference: reference,
              brand: reference.brand,
              model: reference.model,
              manufacturerSku:
                  reference.manufacturerSku ?? 'store-entered-mpn'),
          isEmpty);
    });
  }
  test(
      'wide single-speed chains can record 9 mm; chain packs can exceed 136 links',
      () {
    expect(
        issues('chain', {
          'chain_width_family': '1/8',
          'chain_outer_width_mm': 9,
          'link_count': 138
        }),
        isEmpty);
    expect(issues('chain', {'link_count': 192}), isEmpty);
  });
  test('measurements must be positive and counts integral', () {
    expect(issues('chain', {'link_count': 114.5}).single.code, 'integer');
    expect(
        issues('chain', {'chain_outer_width_mm': 0}).single.blocking, isTrue);
    expect(issues('chain_link', {'chain_link_pack_qty': -1}).single.blocking,
        isTrue);
    expect(issues('chain_link', {'chain_link_pack_qty': 0.5}).single.code,
        'integer');
  });
  test(
      '1/8 contradicts explicit modern derailleur coverage and preserves draft',
      () {
    final values = <String, dynamic>{
      'drivetrain_mode': 'Derailleur',
      'chain_speeds': ['7'],
      'chain_width_family': '1/8'
    };
    expect(issues('chain', values).single.code, 'constraint');
    expect(values['chain_width_family'], '1/8');
  });
  test('missing mode/speeds never activate the wide-chain prohibition', () {
    expect(issues('chain', {'chain_width_family': '1/8'}), isEmpty);
    expect(
        issues('chain', {
          'chain_width_family': '1/8',
          'chain_speeds': ['7']
        }).every((i) => !i.blocking),
        isTrue);
    expect(
        issues('chain',
            {'chain_width_family': '1/8', 'drivetrain_mode': 'Derailleur'}),
        isEmpty);
  });
  test('a connector begins with type and can remain an incomplete manual draft',
      () {
    expect(templates['chain_link']!.prerequisitesFor('chain_speeds'),
        ['chain_connector_type']);
    expect(
        issues('chain_link', {
          'chain_speeds': ['10']
        }).every((i) => !i.blocking),
        isTrue);
    expect(
        issues('chain_link', {
          'chain_connector_type': 'Missing link',
          'chain_speeds': ['10']
        }),
        isEmpty);
  });
  test('replacement rivets cannot be declared reusable', () {
    final common = <String, dynamic>{
      'chain_connector_type': 'Pin',
      'spec_evidence_source': 'Envase del fabricante'
    };
    expect(
        issues('chain_link', {...common, 'chain_link_reusable': true})
            .single
            .code,
        'constraint');
    expect(issues('chain_link', {...common, 'chain_link_reusable': false}),
        isEmpty);
    expect(issues('chain_link', common), isEmpty);
  });
  test('CL552 cannot be marked reusable; absent pack quantity is not inferred',
      () {
    final ref = references.firstWhere((r) => r.model == 'CL552');
    expect(ref.facts.containsKey('chain_link_pack_qty'), isFalse);
    expect(
        validateProductSpecDraft(
                template: templates['chain_link']!,
                values: {...ref.facts, 'chain_link_reusable': true},
                reference: ref,
                brand: 'KMC',
                model: 'CL552')
            .any((i) => i.code == 'reference_conflict'),
        isTrue);
    expect(productSpecClaimSummary(ref.claims.single),
        contains('Excluye: Cualquier cadena Flattop'));
  });
  test('model suggestions distinguish the connector from its target chain', () {
    expect(
        suggestProductSpecModels(
            name: 'Missing Link KMC CL573R compatible con X8',
            brand: 'KMC',
            family: 'chain_link',
            references: references),
        ['CL573R']);
    expect(
        suggestProductSpecModels(
            name: 'Conector RISK compatible con KMC CL573R',
            brand: 'RISK',
            family: 'chain_link',
            references: references),
        isEmpty);
    expect(
        suggestProductSpecModels(
            name: 'Cadena KMC HV408',
            brand: 'KMC',
            family: 'chain',
            references: references),
        isEmpty);
    expect(
        suggestProductSpecModels(
            name: 'Cadena KMC Z8.3 DISPLAY 116 eslabones',
            brand: 'KMC',
            family: 'chain',
            references: references),
        isEmpty,
        reason:
            'The canonical extractor does not resolve this dotted model; do not guess Z8 versus Z8.3.');
  });
  test('operator evidence supplements a reference without changing OEM facts',
      () {
    final ref = references.firstWhere((r) => r.model == 'CL573R');
    expect(
        validateProductSpecDraft(
            template: templates['chain_link']!,
            values: {...ref.facts, 'spec_evidence_source': 'Envase revisado'},
            reference: ref,
            brand: 'KMC',
            model: 'CL573R'),
        isEmpty);
    expect(ref.sources.single, startsWith('https://www.kmcchain.com/'));
  });
  test('broad coverage stays distinct from an exclusive platform', () {
    final claim = references.firstWhere((r) => r.model == 'Z8.3').claims.single;
    expect(claim.containsKey('platform'), isFalse);
    expect(productSpecClaimSummary(claim),
        'Todos los sistemas · 6/7/8 velocidades');
  });
  test('confirming a model cannot legitimize the wrong presentation', () {
    final ref = references.firstWhere((r) => r.model == 'Z8.3');
    expect(
        validateProductSpecDraft(
                template: templates['chain']!,
                values: {...ref.facts, 'link_count': 116},
                reference: ref,
                brand: 'KMC',
                model: 'Z8.3',
                manufacturerSku: ref.manufacturerSku!)
            .any((i) => i.code == 'reference_conflict'),
        isTrue);
  });
}
