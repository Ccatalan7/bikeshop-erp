import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/modules/purchases/pages/supplier_list_page.dart',
    ).readAsStringSync();
  });

  test('entry is Explore plus Directory, not a chip-filtered list', () {
    expect(source, contains('VbSubTabs<SupplierHubTab>'));
    expect(source, contains("label: 'Explorar'"));
    expect(source, contains("label: 'Directorio"));
    expect(source, isNot(contains('FilterChip(')));
    expect(source, isNot(contains('ChoiceChip(')));
    expect(source, isNot(contains('InputChip(')));
  });

  test('featured gallery uses the six approved real category assets', () {
    for (final asset in [
      'goods-inventory.webp',
      'digital-services.webp',
      'utilities.webp',
      'logistics.webp',
      'lease-landlord.webp',
      'government-tax.webp',
    ]) {
      expect(source, contains(asset));
    }
    expect(source, contains('final columns = compact ? 2 : 3'));
    expect(
      source,
      contains('Un proveedor puede estar en más de una categoría'),
    );

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains('assets/images/supplier_categories/'),
      reason: 'Flutter asset directories are not recursive.',
    );
  });

  test('category scope is confirmed and resource cost is not a role', () {
    expect(source, contains("role.assignmentSource != 'observed'"));
    expect(source, isNot(contains('role.isEffectiveAt(')));
    expect(source, isNot(contains('DateTime.now()')));
    expect(source, contains("!item.code.startsWith('free_service')"));
    expect(source, isNot(contains("code: 'free_service_provider'")));
  });

  test('attention is driven only by typed server projections', () {
    expect(source, contains('profile.attentionSignals'));
    expect(source, contains('incident.displayReason'));
    expect(source, contains('SupplierProfileClassificationStatus'));
    expect(source, contains('SupplierProfileAccountingPolicyStatus'));
    expect(
      source,
      isNot(contains('profile.relationship.email == null')),
    );
    expect(source, isNot(contains('profile.party.identifiers.isEmpty')));
  });

  test('directory consumes server relationship summary and opens profile', () {
    expect(source, contains('profile.serviceRelationshipSummary'));
    expect(
      source,
      contains("'/purchases/suppliers/\${profile.relationship.id}'"),
    );
    expect(
      source,
      isNot(
          contains("'/purchases/suppliers/\${profile.relationship.id}/edit'")),
    );
  });
}
