// Root integration regressions derived from the frozen independent brake probe.
// Passing a candidate relation is not authority to publish it or approve stock.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_relation.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

Map<String, dynamic> m(Object? x) => Map<String, dynamic>.from(x as Map);
const dir = 'docs/development/product-specs-research-2026-09-05/';
final packet = m(jsonDecode(
    File('${dir}brake-family-implementation-packet-2026-09-07.json')
        .readAsStringSync()));
final patched = m(jsonDecode(
    File('${dir}all-family-reviewed-fields-integrated-2026-09-07.json')
        .readAsStringSync()));
final base = m(jsonDecode(
    File('${dir}all-family-reviewed-fields-2026-09-06.json')
        .readAsStringSync()));

SpecTemplate template(String key, {bool original = false}) {
  final doc = original ? base : patched;
  final t = m((doc['templates'] as List).firstWhere((x) => x['key'] == key));
  final definitions = m(doc['definitions']);
  return SpecTemplate(
      id: t['id'],
      key: key,
      name: t['name'],
      technicalFamily: t['technical_family'],
      formContract: m(t['form_contract']),
      fields: [
        for (final raw in t['fields'] as List)
          SpecTemplateField(
              specDefinitionId: definitions[raw['key']]['id'],
              sectionKey: raw['section_key'],
              sortOrder: raw['sort_order'],
              isRequired: raw['is_required'],
              visibilityRules:
                  (raw['visibility_rules'] as List).map(m).toList(),
              constraintRules:
                  (raw['constraint_rules'] as List).map(m).toList(),
              definition: SpecDefinition.fromJson(m(definitions[raw['key']])))
      ]);
}

List<ProductSpecIssue> issues(String t, Map<String, dynamic> values,
        {bool original = false}) =>
    validateProductSpecDraft(
        template: template(t, original: original), values: values);
Map<String, dynamic> rows(List<Map<String, dynamic>> data) =>
    {'schema_version': 1, 'rows': data};
Map<String, dynamic> row(String id, Map<String, dynamic> values) =>
    {'id': id, 'values': values, 'sources': <String>[]};
void main() {
  group('brake packet schema2 executable claims', () {
    for (final raw in packet['relation_cases'] as List) {
      final fixture = m(raw);
      test(fixture['id'], () {
        final data = m((packet['relations'] as List)
            .firstWhere((x) => x['id'] == fixture['relation_id']));
        final claim = m(data['claim']);
        final verdict = ProductSpecRelation.fromJson(claim)
            .evaluate(m(fixture['configuration']))
            .verdict;
        final expected = switch (fixture['expected']) {
          'supported' => SpecRelationVerdict.supported,
          'excluded' => SpecRelationVerdict.excluded,
          'outside_declared_scope' => SpecRelationVerdict.outsideDeclaredScope,
          _ => SpecRelationVerdict.unknown,
        };
        expect(verdict, expected);
        for (final block in [
          ...claim['alternatives'] as List,
          ...claim['exclusions'] as List
        ]) {
          expect(
              (data['sources'] as List)
                  .toSet()
                  .containsAll(block['sources'] as List),
              isTrue);
        }
      });
    }
  });
  group('brake packet field representation', () {
    test('all new row definitions parse as executable schema1', () {
      for (final raw in m(packet['new_definitions']).values) {
        final d =
            SpecDefinition.fromJson({...m(raw), 'id': 'probe-${raw['key']}'});
        if (d.dataType == 'json') expect(d.rowSchema, isNotNull);
      }
    });
    test('A13 and A15 already exist in frozen base', () {
      final data = {
        'braking_surface': 'Disco',
        'brake_actuation': 'Híbrido (cable a hidráulico)',
        'cable_pull_required': 'Tiro corto (ruta / cantilever / caliper)'
      };
      expect(
          issues('brake_caliper', data, original: true)
              .where((i) => i.fieldKey == 'cable_pull_required' && i.blocking),
          isEmpty);
      final defs = m(base['definitions']);
      expect(defs['lever_cable_pull']['allowed_values'],
          contains('Tiro largo (V-brake / disco mecánico tiro largo)'));
      expect(defs['cable_pull_required']['allowed_values'],
          contains('Tiro largo (V-brake / disco mecánico tiro largo)'));
    });
    test('local hydraulic caliper cannot claim an external hose', () {
      final data = {
        'braking_surface': 'Disco',
        'brake_actuation': 'Híbrido (cable a hidráulico)',
        'brake_external_hose_connection': false,
        'hose_system_code': 'Unrelated hose'
      };
      expect(
          issues('brake_caliper', data)
              .where((i) => i.fieldKey == 'hose_system_code' && i.blocking),
          isNotEmpty);
    });
    test('caliper intended rotor nominal is dimensional and disc-specific', () {
      final data = {
        'braking_surface': 'Disco',
        'brake_actuation': 'Híbrido (cable a hidráulico)',
        'caliper_rotor_nominal_thickness_mm': '1.8'
      };
      expect(
          issues('brake_caliper', data).where((i) =>
              i.fieldKey == 'caliper_rotor_nominal_thickness_mm' && i.blocking),
          isEmpty);
      expect(
          issues('brake_caliper', {...data, 'braking_surface': 'Llanta'}).where(
              (i) =>
                  i.fieldKey == 'caliper_rotor_nominal_thickness_mm' &&
                  i.blocking),
          isNotEmpty);
      expect(
          template('brake_caliper')
              .fields
              .firstWhere((x) =>
                  x.definition?.key == 'caliper_rotor_nominal_thickness_mm')
              .definition
              ?.unit,
          'mm');
    });
    test('unknown external hose does not become false or confirmed', () {
      final data = {
        'braking_surface': 'Disco',
        'brake_actuation': 'Híbrido (cable a hidráulico)',
        'hose_system_code': 'Documented hose'
      };
      final result = issues('brake_caliper', data)
          .where((i) => i.fieldKey == 'hose_system_code')
          .toList();
      expect(
          result.any((i) => i.code == 'prerequisite' && !i.blocking), isTrue);
      expect(result.any((i) => i.blocking), isFalse);
    });
    test('upstream local to external changes hose applicability', () {
      final common = {
        'braking_surface': 'Disco',
        'brake_actuation': 'Híbrido (cable a hidráulico)',
        'hose_system_code': 'Documented hose'
      };
      expect(
          issues('brake_caliper', {
            ...common,
            'brake_external_hose_connection': true
          }).where((i) => i.fieldKey == 'hose_system_code' && i.blocking),
          isEmpty);
      expect(
          issues('brake_caliper', {
            ...common,
            'brake_external_hose_connection': false
          }).where((i) => i.fieldKey == 'hose_system_code' && i.blocking),
          isNotEmpty);
    });
    test('hydraulic rim brake does not require cable pull', () {
      final common = {
        'brake_actuation': 'Hidráulico',
        'rim_brake_style': 'Otra arquitectura documentada',
        'rim_brake_frame_mount': 'HSi'
      };
      expect(
          issues('rim_brake', common)
              .where((i) => i.fieldKey == 'lever_pull_required'),
          isEmpty);
      expect(
          issues('rim_brake', {
            ...common,
            'lever_pull_required': 'Tiro corto (ruta / cantilever / caliper)'
          }).where((i) => i.fieldKey == 'lever_pull_required' && i.blocking),
          isNotEmpty);
    });
    test('hydraulic combined control forbids a retained cable pull', () {
      final data = {
        'brake_actuation': 'Hidráulico',
        'lever_cable_pull': 'Tiro corto (ruta / cantilever / caliper)'
      };
      expect(
          issues('brake_shift_combined_control', data)
              .where((i) => i.fieldKey == 'lever_cable_pull' && i.blocking),
          isNotEmpty);
    });
    test('DOT5 can be described as a different stocked fluid', () {
      expect(
          issues('brake_fluid', {'fluid_type': 'DOT 5', 'volume_ml': '100'})
              .where((i) => i.fieldKey == 'fluid_type' && i.blocking),
          isEmpty);
    });
    test('different front and rear hose lengths stay in their rows', () {
      final data = rows([
        row('front', {
          'circuit_id': 'front',
          'position': 'Delantero',
          'hose_length_mm': '950.5',
          'rotor_diameter_mm': '180',
          'source_url': 'https://example.com/review-fixture'
        }),
        row('rear', {
          'circuit_id': 'rear',
          'position': 'Trasero',
          'hose_length_mm': '1650.5',
          'rotor_diameter_mm': '160',
          'source_url': 'https://example.com/review-fixture'
        }),
      ]);
      final field = template('hydraulic_disc_brake').fields.firstWhere(
          (x) => x.definition?.key == 'brake_assembly_configurations');
      final parsed = field.definition!.rowSchema!.parse(data);
      expect(parsed.toJson()['rows'][0]['values']['hose_length_mm'], '950.5');
      expect(parsed.toJson()['rows'][1]['values']['rotor_diameter_mm'], '160');
      expect(
          issues('hydraulic_disc_brake', {
            'brake_assembly_configurations': data
          }).where((i) =>
              i.fieldKey == 'brake_assembly_configurations' && i.blocking),
          isEmpty);
    });
    test('rim fitment lower and upper dimension preserve order', () {
      final data = rows([
        row('x', {
          'position': 'Delantero',
          'mount_spec': 'Explicit fixture',
          'brake_model': 'Fixture only',
          'rim_width_min_mm': '28',
          'rim_width_max_mm': '18',
          'source_url': 'https://example.com/review-fixture'
        })
      ]);
      expect(
          issues('rim_brake', {
            'brake_actuation': 'Hidráulico',
            'rim_brake_mount_fitments': data
          }).where(
              (i) => i.fieldKey == 'rim_brake_mount_fitments' && i.blocking),
          isNotEmpty);
    });
    test('0200 link uses circuit row ID and rejects an absent target', () {
      final target = rows([
        row('front-id', {
          'circuit_id': 'display-name',
          'position': 'Delantero',
          'source_url': 'https://example.com/review-fixture'
        })
      ]);
      final connection = {
        'circuit_id': 'front-id',
        'component_role': 'Cáliper',
        'end_role': 'Entrada',
        'component_brand': 'Fixture',
        'component_model': 'Fixture',
        'hose_brand': 'Fixture',
        'hose_model': 'Fixture',
        'source_url': 'https://example.com/review-fixture'
      };
      final valid = {
        'brake_assembly_configurations': target,
        'brake_hydraulic_connections': rows([row('port', connection)])
      };
      expect(
          issues('hydraulic_disc_brake', valid)
              .where((i) => i.code == 'row_reference_unresolved'),
          isEmpty);
      final wrong = {
        ...valid,
        'brake_hydraulic_connections': rows([
          row('port', {...connection, 'circuit_id': 'display-name'})
        ])
      };
      expect(
          issues('hydraulic_disc_brake', wrong)
              .any((i) => i.code == 'row_reference_unresolved' && i.blocking),
          isTrue);
    });
    test('0200 link missing target remains pending instead of assumed valid',
        () {
      final data = rows([
        row('port', {
          'circuit_id': 'unknown-circuit',
          'component_role': 'Cáliper',
          'end_role': 'Entrada',
          'component_brand': 'Fixture',
          'component_model': 'Fixture',
          'hose_brand': 'Fixture',
          'hose_model': 'Fixture',
          'source_url': 'https://example.com/review-fixture'
        })
      ]);
      expect(
          issues('hydraulic_disc_brake', {'brake_hydraulic_connections': data})
              .any((i) => i.code == 'row_reference_pending' && !i.blocking),
          isTrue);
    });
    test('0200 scalar reach interval rejects lower above upper', () {
      final data = {
        'brake_actuation': 'Mecánico (cable)',
        'rim_brake_style': 'Dual pivot',
        'reach_min_mm': '57.5',
        'reach_max_mm': '39'
      };
      expect(
          issues('rim_brake', data)
              .where((i) => i.code == 'range_order' && i.blocking)
              .length,
          2);
    });
    test('gap: existing recipe does not conditionally require adapter identity',
        () {
      final data = rows([
        row('x', {
          'position': 'Delantero',
          'rotor_diameter_mm': '180',
          'frame_mount': 'Post Mount',
          'adapter_required': true,
          'source_url': 'https://example.com/review-fixture'
        })
      ]);
      final result = issues('brake_caliper', {
        'braking_surface': 'Disco',
        'brake_actuation': 'Mecánico (cable)',
        'rotor_size_recipe': data
      });
      expect(
          result.where((i) => i.fieldKey == 'rotor_size_recipe' && i.blocking),
          isEmpty);
    });
    test('gap: mineral row needs separate completeness gate for formulation',
        () {
      final data = rows([
        row('x', {
          'system_brand': 'Fixture only',
          'system_model': 'Fixture',
          'fluid_class': 'Aceite Mineral',
          'source_url': 'https://example.com/review-fixture'
        })
      ]);
      expect(
          issues('brake_caliper', {
            'braking_surface': 'Disco',
            'brake_actuation': 'Hidráulico',
            'brake_fluid_approvals': data
          }).where((i) => i.fieldKey == 'brake_fluid_approvals' && i.blocking),
          isEmpty);
    });
    test('a missing OEM source is incomplete, not automatically verified', () {
      final data = rows([
        row('x', {
          'system_brand': 'Fixture only',
          'system_model': 'Fixture',
          'fluid_class': 'DOT 4'
        })
      ]);
      final result = issues('brake_caliper', {
        'braking_surface': 'Disco',
        'brake_actuation': 'Hidráulico',
        'brake_fluid_approvals': data
      }).where((i) => i.fieldKey == 'brake_fluid_approvals');
      expect(
          result.any((i) => i.code == 'row_incomplete' && !i.blocking), isTrue);
    });
  });
}
