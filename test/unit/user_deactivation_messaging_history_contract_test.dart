import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String serviceSource;
  late String pageSource;

  setUpAll(() {
    serviceSource = File(
      'lib/shared/services/user_management_service.dart',
    ).readAsStringSync();
    pageSource = File(
      'lib/modules/settings/pages/user_management_page.dart',
    ).readAsStringSync();
  });

  test('account removal callers retain the explicit server outcome', () {
    expect(
      serviceSource,
      contains('Future<Map<String, dynamic>> deleteUser(String userId)'),
    );
    expect(
      serviceSource,
      contains('Future<Map<String, dynamic>> deleteCustomerAccount({'),
    );
    expect(
      serviceSource,
      contains('Future<Map<String, dynamic>> deleteWebsiteAuthAccount({'),
    );
  });

  test('admin UI distinguishes deactivation from hard deletion', () {
    expect(pageSource, contains('_confirmAccountRemoval('));
    expect(
      pageSource,
      contains("'deactivated_preserved_messaging_history'"),
    );
    expect(
      pageSource,
      contains('La identidad sigue activa por otro acceso vigente'),
    );
    expect(pageSource, contains("'auth_deleted'"));
    expect(pageSource, isNot(contains("title: 'Eliminar cuenta interna'")));
    expect(pageSource, isNot(contains("title: 'Eliminar cuenta web'")));
  });
}
