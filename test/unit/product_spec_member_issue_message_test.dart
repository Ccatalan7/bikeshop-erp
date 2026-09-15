import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_member_profile.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

void main() {
  final fixture = (jsonDecode(
      File('test/fixtures/product_spec_member_profiles.json')
          .readAsStringSync()) as Map)['active'] as Map<String, dynamic>;
  final root =
      SpecEngineService.decodeProductSpecEditorContext(fixture).template;
  final members = decodeProductSpecMemberProfiles(fixture).profiles;

  test('server details identify the failed piece and resolve its own labels',
      () {
    final errors = productSpecServerIssues(jsonEncode([
      for (final member in members)
        {
          'code': 'numeric_domain',
          'field': 'member_test_length',
          'message': 'Debe ser positivo.',
          'blocking': true,
          'profile_id': member.id
        },
    ]));
    expect(errors.map((error) => error.memberProfileId),
        members.map((member) => member.id));
    for (var index = 0; index < members.length; index++) {
      final message = productSpecIssueMessage(
          errors[index], root, fixture['values'] as Map<String, dynamic>,
          memberContext: (id) {
        final member = members.singleWhere((member) => member.id == id);
        return ProductSpecIssueContext(
            label: 'Pieza ${members.indexOf(member) + 1}',
            template: member.template,
            values: member.values);
      });
      expect(message, 'Pieza ${index + 1} · Length: Debe ser positivo.');
      expect(message, isNot(contains('member_test_length')));
    }
  });

  test('unknown member scope never falls back to root field labels', () {
    const issue = ProductSpecIssue(
        'numeric_domain', 'member_test_collection', 'Revisa este dato.',
        memberProfileId: 'unavailable');
    expect(productSpecIssueMessage(issue, root, {}),
        'Pieza incluida: Revisa este dato.');
  });

  test('root issues keep their existing labels without a member prefix', () {
    const issue = ProductSpecIssue(
        'required', 'member_test_collection', 'Falta contenido.');
    expect(productSpecIssueMessage(issue, root, {}),
        'Included parts: Falta contenido.');
  });

  test('server constraint text does not repeat the same field label', () {
    const issue = ProductSpecIssue('field_constraint', 'member_test_length',
        'Length: Ingresa un valor mayor que cero.');
    expect(productSpecIssueMessage(issue, members.first.template, {}),
        'Length: Ingresa un valor mayor que cero.');
  });
}
