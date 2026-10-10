import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:vinabike_erp/modules/website/catalog/catalog_ui_parts.dart';
import 'package:vinabike_erp/modules/website/catalog/catalog_web_models.dart';

/// Every step of the store's sale rule has words in the ERP. On 2026-10-10
/// `missing_tax` had none and 19 products that do not sell read «Todo en
/// orden»: the codes are read from the rule the database runs.
void main() {
  final migrations = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  String latestBody(String function) {
    final header = 'function public.$function(';
    final source = migrations
        .lastWhere((file) => file.readAsStringSync().contains(header))
        .readAsStringSync();
    final start = source.indexOf(header);
    return source.substring(start, source.indexOf(r'$$;', start));
  }

  final codes = {
    for (final match in RegExp(r"then '([a-z_]+)'")
        .allMatches(latestBody('catalog_product_web_block_v1')))
      match.group(1)!,
  };

  test('every step of the sale rule has its reason', () {
    expect(codes, contains('missing_tax'));
    for (final code in codes) {
      final reason = CatalogReasons.block(code);
      expect(reason, isNot('Todo en orden'), reason: code);
      expect(reason, isNot('No sale a la venta'), reason: '$code has no words');
    }
    expect(CatalogReasons.block(null), 'Todo en orden');
    expect(CatalogReasons.block('a_new_step'), 'No sale a la venta');
  });

  test('a featured pick that stopped selling says why, in words', () {
    // 20261010060000 refuses it with the step of the rule it failed.
    final replace = latestBody('catalog_replace_featured_v1');
    for (final code in codes) {
      expect(replace, contains("when '$code' then"), reason: code);
    }

    const message = 'Ya no se vende en la web: «Extractor de cono» '
        '(el precio quedó bajo el costo). No se agregó a destacados.';
    expect(
      catalogErrorMessage(const PostgrestException(
        message: message,
        code: 'P0001',
        hint: 'catalog_featured_not_on_sale',
      )),
      message,
    );
  });
}
