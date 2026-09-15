import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_member_profile.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

// Synthetic template and reference. The values exercise the shared validator's
// reference scope rules; they are not measurements or manufacturer claims.
SpecTemplateField _field(String key, String dataType,
        {Map<String, dynamic> validation = const {}}) =>
    SpecTemplateField(
      specDefinitionId: 'definition-$key',
      sectionKey: 'general',
      sortOrder: 0,
      isRequired: false,
      visibilityRules: const [],
      definition: SpecDefinition(
        id: 'definition-$key',
        key: key,
        label: 'Label $key',
        dataType: dataType,
        options: const [],
        sortOrder: 0,
        validationRules: validation,
      ),
    );

final _rows = {
  'rows_schema': {
    'version': 2,
    'columns': [
      {'key': 'inner', 'label': 'Inner', 'type': 'decimal', 'unit': 'mm'},
    ],
  }
};

SpecTemplate _template() => SpecTemplate(
      id: 'scope-template',
      key: 'scope_template',
      name: 'Scope fixture',
      technicalFamily: 'scope_family',
      contractVersion: 2,
      formContract: const {
        'rules_version': 2,
        'roles': {
          'old_width': 'legacy',
          'old_code': 'legacy',
          'old_rows': 'legacy',
        },
      },
      fields: [
        _field('length', 'number'),
        _field('note', 'text'),
        _field('old_width', 'number'),
        _field('old_code', 'text'),
        _field('old_rows', 'json', validation: _rows),
      ],
    );

ProductSpecReference _reference(Map<String, dynamic> facts,
        {String family = 'scope_family', String? manufacturerSku}) =>
    ProductSpecReference(
      id: 'scope-reference',
      family: family,
      brand: 'Fixture',
      model: 'Model A',
      label: 'Synthetic reference',
      facts: facts,
      sources: const [],
      manufacturerSku: manufacturerSku,
    );

/// The root product and a component call the same validator; only the
/// identity arguments differ.
List<String> _codes(Map<String, dynamic> values, Map<String, dynamic> facts,
        {String family = 'scope_family', String manufacturerSku = ''}) =>
    validateProductSpecDraft(
      template: _template(),
      values: values,
      reference: _reference(facts, family: family),
      brand: 'Fixture',
      model: 'Model A',
      manufacturerSku: manufacturerSku,
    )
        .map((issue) => '${issue.code}:${issue.fieldKey}:${issue.blocking}')
        .toList();

Map<String, dynamic> _rowsWith(String inner) => {
      'schema_version': 2,
      'rows': [
        {
          'id': 'r1',
          'values': {'inner': inner},
          'sources': ['https://example.test/rows'],
        }
      ],
    };

Map<String, dynamic> _memberContext() =>
    (jsonDecode(File('test/fixtures/product_spec_member_profiles.json')
        .readAsStringSync()) as Map)['active'] as Map<String, dynamic>;

Map<String, dynamic> _memberReference(Map<String, dynamic> facts) {
  final fixtures = jsonDecode(
      File('test/fixtures/product_spec_member_profiles.json')
          .readAsStringSync()) as Map;
  final historical =
      (fixtures['archived']['member_profiles']['archived_profiles'] as List)
          .first as Map;
  return {
    ...Map<String, dynamic>.from(historical['reference'] as Map),
    'facts': facts,
  };
}

void main() {
  group('reference scope', () {
    test('a fact of a definition the template lacks blocks the save', () {
      final codes = _codes({'length': '7.1'}, {'length': '7.1', 'other': 'x'});
      expect(codes, ['reference_scope:other:true']);
      expect(codes.where((c) => c.startsWith('reference_conflict')), isEmpty);
      expect(codes.where((c) => c.startsWith('reference_identity')), isEmpty);
    });

    test('the identity checks are unchanged and run beside the scope check',
        () {
      expect(_codes({}, {'other': 'x'}, family: 'other_family'),
          ['reference_identity::true', 'reference_scope:other:true']);
      final sku = validateProductSpecDraft(
          template: _template(),
          values: const {},
          reference: _reference(const {}, manufacturerSku: 'MPN-1'),
          brand: 'Fixture',
          model: 'Model A');
      expect(sku.map((i) => i.code), ['reference_identity']);
    });

    test('a retired number is accepted only with the exact conserved value',
        () {
      expect(_codes({'old_width': '7.1'}, {'old_width': '7.10'}), isEmpty);
      expect(
          _codes({'old_width': '9007199254740993.2'},
              {'old_width': '9007199254740993.20'}),
          isEmpty);
      // A double would round both beyond 2^53 to the same value.
      expect(
          _codes({'old_width': '9007199254740993.2'},
              {'old_width': '9007199254740993.3'}),
          ['reference_scope:old_width:true']);
      expect(
          _codes({}, {'old_width': '7.1'}), ['reference_scope:old_width:true']);
      expect(_codes({'old_width': 'x'}, {'old_width': '7.1'}),
          ['reference_scope:old_width:true']);
    });

    test('a retired non-numeric field compares without coercion', () {
      expect(_codes({'old_code': 'A'}, {'old_code': 'A'}), isEmpty);
      expect(_codes({'old_code': 'A'}, {'old_code': 'B'}),
          ['reference_scope:old_code:true']);
      expect(_codes({'old_code': '7'}, {'old_code': 7}),
          ['reference_scope:old_code:true']);
      expect(_codes({'old_code': '7'}, {'old_code': '7.0'}),
          ['reference_scope:old_code:true']);
      expect(_codes({}, {'old_code': 'A'}), ['reference_scope:old_code:true']);
    });

    test('retired rows compare through their schema, decimals exactly', () {
      expect(
          _codes({'old_rows': _rowsWith('10.50')},
              {'old_rows': _rowsWith('10.5')}),
          isEmpty);
      expect(
          _codes(
              {'old_rows': _rowsWith('10.5')}, {'old_rows': _rowsWith('10.6')}),
          ['reference_scope:old_rows:true']);
      expect(_codes({'old_rows': _rowsWith('10.5')}, {'old_rows': 'rows'}),
          ['reference_scope:old_rows:true']);
    });

    test('an active manual answer against the reference is still a conflict',
        () {
      expect(_codes({'length': '8'}, {'length': '7.1'}),
          ['reference_conflict:length:true']);
      expect(_codes({'note': 'a'}, {'note': 'b'}),
          ['reference_conflict:note:true']);
      expect(_codes({'length': '7.10'}, {'length': '7.1'}), isEmpty);
    });

    test('omitted automatic answers of active fields raise nothing', () {
      expect(_codes({}, {'length': '7.1', 'note': 'x'}), isEmpty);
      expect(_codes({'note': 'x'}, {'length': '7.1', 'note': 'x'}), isEmpty);
    });

    test('a component profile reaches the same rules through its own identity',
        () {
      final context = _memberContext();
      for (final profile
          in (context['member_profiles'] as Map)['profiles'] as List) {
        ((profile['template'] as Map)['form_contract'] as Map)['roles']
            ['member_test_included'] = 'legacy';
      }
      final profile = ((context['member_profiles'] as Map)['profiles'] as List)
          .first as Map;
      profile['reference_id'] = 'member-test-reference';
      profile['reference'] = _memberReference({
        'member_test_length': '7.1',
        'member_test_included': true,
        'member_test_other': 'x',
      });
      var issues = decodeProductSpecMemberProfiles(context)
          .profiles
          .first
          .validate()
          .map((i) => '${i.code}:${i.fieldKey}');
      expect(issues, contains('reference_scope:member_test_other'));
      expect(issues, isNot(contains('reference_scope:member_test_included')));
      expect(issues, isNot(contains('reference_identity:')));

      profile['reference'] = _memberReference({
        'member_test_length': '7.1',
        'member_test_included': false,
      });
      issues = decodeProductSpecMemberProfiles(context)
          .profiles
          .first
          .validate()
          .map((i) => '${i.code}:${i.fieldKey}');
      expect(issues, contains('reference_scope:member_test_included'));
      expect(issues, isNot(contains('reference_scope:member_test_other')));
    });
  });
}
