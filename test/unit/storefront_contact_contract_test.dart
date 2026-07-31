import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../support/library_source.dart';

void main() {
  test('storefront separates general contact from sales operations', () {
    final migration = File(
      'supabase/migrations/20260718250000_sync_storefront_sales_contact.sql',
    ).readAsStringSync();
    final policy = File(
      'lib/public_store/pages/static_policy_page.dart',
    ).readAsStringSync();
    final layout = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');
    final snapshots = File(
      'scripts/generate_product_seo_snapshots.dart',
    ).readAsStringSync();

    expect(migration, contains("'contact_email'"));
    expect(migration, contains("'seo_email'"));
    expect(migration, contains("'contacto@vinabike.cl'"));
    expect(migration, contains("'payment_transfer_contact_email'"));
    expect(migration, contains("'ventas@vinabike.cl'"));
    expect(
      policy,
      isNot(contains("replaceAll('vinabikechile@gmail.com'")),
    );
    expect(
      snapshots,
      isNot(contains("replaceAll('vinabikechile@gmail.com'")),
    );
    expect(snapshots, isNot(contains('escribe a ventas@vinabike.cl')));
    expect(layout, isNot(contains('Ej: vinabikechile@gmail.com')));
    expect(layout, isNot(contains('Ej: contacto@vinabike.cl')));
    expect(
      layout,
      isNot(
          contains('Todo lo que necesitas para tu bicicleta en Viña del Mar')),
    );
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
    expect(publicPolicy, isNot(contains('dentro de 10 días')));
    expect(snapshots, isNot(contains('dentro de 10 días')));
  });
}
