import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every public account prompt uses the canonical storefront login', () {
    final chatSource = File(
      'lib/public_store/pages/customer_chat_list_page.dart',
    ).readAsStringSync();
    final accountSource = File(
      'lib/public_store/pages/customer_account_page.dart',
    ).readAsStringSync();

    final canonicalLoginNavigation = RegExp(
      r'''PublicStoreLayout\.navigateToHref\(\s*context,\s*['"]/cuenta/login['"]\s*\)''',
    );
    expect(chatSource, matches(canonicalLoginNavigation));
    expect(accountSource, matches(canonicalLoginNavigation));

    final legacyLoginNavigation = RegExp(
      r'''context\.(?:go|push|replace)\(\s*['"]/login['"]''',
    );
    final publicStoreSources = Directory('lib/public_store')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in publicStoreSources) {
      expect(
        file.readAsStringSync(),
        isNot(matches(legacyLoginNavigation)),
        reason: '${file.path} must not route a customer into ERP login.',
      );
    }
  });

  test('checkout address management cannot navigate during handoff', () {
    final source =
        File('lib/public_store/pages/checkout_page.dart').readAsStringSync();

    expect(
      source,
      matches(
        RegExp(
          r'''onPressed:\s*_checkoutLocked\s*\?\s*null\s*:\s*\(\)\s*=>\s*PublicStoreLayout\.navigateToHref\(\s*context,\s*['"]/tienda/cuenta/direcciones['"],?\s*\)''',
        ),
      ),
    );
  });
}
