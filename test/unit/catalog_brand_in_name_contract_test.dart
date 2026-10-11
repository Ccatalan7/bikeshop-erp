import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_public_core/public_store/models/public_product_brand_names.dart';

/// The store and the catalog agree on what is not a brand. The store hides
/// «Andes Industrial» as a brand (`isPublicProductBrand`); on 2026-10-11 two
/// Vision rims carried it and Google flagged them without an identifier. The
/// catalog's «La marca está en el nombre» (20261011010000) reads the same
/// list in the database.
void main() {
  test('the database and the store share the not-a-brand list', () {
    final migrations = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    const header = 'function public.catalog_is_public_brand_v1(';
    final source = migrations
        .lastWhere((file) => file.readAsStringSync().contains(header))
        .readAsStringSync();
    final start = source.indexOf(header);
    final body = source.substring(start, source.indexOf(r'$$;', start));
    final list = RegExp(r"not in \(([^)]*)\)").firstMatch(body)!.group(1)!;
    final sqlNames = {
      for (final match in RegExp(r"'([^']+)'").allMatches(list)) match[1]!,
    };

    final dart = File('packages/vinabike_public_core/lib/public_store/models/'
            'public_product_brand_names.dart')
        .readAsStringSync();
    final set = RegExp(r'!const \{([^}]*)\}').firstMatch(dart)!.group(1)!;
    final dartNames = {
      for (final match in RegExp(r"'([^']+)'").allMatches(set)) match[1]!,
    };

    expect(sqlNames, dartNames);
    for (final name in sqlNames) {
      expect(isPublicProductBrand(name), isFalse, reason: name);
    }
    expect(isPublicProductBrand('Vision'), isTrue);
  });
}
