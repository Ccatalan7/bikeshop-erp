import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification timeline exposes one compact category menu', () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(panel, contains('PopupMenuButton<_ActivityFilter>'));
    expect(panel, contains("label: 'Filtrar actividad: \${selected.label}'"));
    expect(panel, contains('enum _ActivityFilter'));
    expect(panel, contains('_ActivityFilter.jobs'));
    expect(panel, contains('_ActivityFilter.payments'));
    expect(panel, contains('_ActivityFilter.emails'));
    expect(panel, contains('_ActivityFilter.chats'));
    expect(panel, contains('_ActivityFilter.orders'));
    expect(panel, contains('_ActivityFilter.files'));
    expect(panel, isNot(contains('ChoiceChip(')));
    expect(panel, isNot(contains('FilterChip(')));
    expect(
      registry,
      contains('one compact icon dropdown for quickly filtering'),
    );
  });
}
