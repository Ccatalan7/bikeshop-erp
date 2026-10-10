import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/catalog/catalog_web_models.dart';

/// Every step of the store's sale rule has words in the ERP. On 2026-10-10
/// `missing_tax` had none and 19 products that do not sell read «Todo en
/// orden»: the codes are read from the rule the database runs.
void main() {
  test('every step of the sale rule has its reason', () {
    final migrations = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final latest = migrations.lastWhere(
      (file) => file
          .readAsStringSync()
          .contains('function public.catalog_product_web_block_v1('),
    );
    final source = latest.readAsStringSync();
    final start =
        source.indexOf('function public.catalog_product_web_block_v1(');
    final body = source.substring(start, source.indexOf(r'$$;', start));
    final codes = {
      for (final match in RegExp(r"then '([a-z_]+)'").allMatches(body))
        match.group(1)!,
    };

    expect(codes, contains('missing_tax'));
    for (final code in codes) {
      final reason = CatalogReasons.block(code);
      expect(reason, isNot('Todo en orden'), reason: code);
      expect(reason, isNot('No sale a la venta'), reason: '$code has no words');
    }
    expect(CatalogReasons.block(null), 'Todo en orden');
    expect(CatalogReasons.block('a_new_step'), 'No sale a la venta');
  });
}
