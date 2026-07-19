import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('storefront separates general contact from sales operations', () {
    final migration = File(
      'supabase/migrations/20260718250000_sync_storefront_sales_contact.sql',
    ).readAsStringSync();
    final policy = File(
      'lib/public_store/pages/static_policy_page.dart',
    ).readAsStringSync();
    final layout = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();
    final snapshots = File(
      'scripts/generate_product_seo_snapshots.dart',
    ).readAsStringSync();

    expect(migration, contains("'contact_email'"));
    expect(migration, contains("'seo_email'"));
    expect(migration, contains("'contacto@vinabike.cl'"));
    expect(migration, contains("'payment_transfer_contact_email'"));
    expect(migration, contains("'ventas@vinabike.cl'"));
    expect(policy, contains('escribe a ventas@vinabike.cl'));
    expect(snapshots, contains('escribe a ventas@vinabike.cl'));
    expect(layout, isNot(contains('Ej: vinabikechile@gmail.com')));
  });

  test('return policy fallback uses the statutory ten-day period', () {
    final editorDefaults = File(
      'lib/modules/website/pages/content_management_page.dart',
    ).readAsStringSync();
    final publicPolicy = File(
      'lib/public_store/pages/static_policy_page.dart',
    ).readAsStringSync();
    final snapshots = File(
      'scripts/generate_product_seo_snapshots.dart',
    ).readAsStringSync();

    expect(editorDefaults, contains('Tienes 10 días corridos'));
    expect(editorDefaults, isNot(contains('Tienes 30 días')));
    expect(publicPolicy, contains('dentro de 10 días'));
    expect(snapshots, contains('dentro de 10 días'));
  });
}
