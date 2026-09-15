import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_row_conditions.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_rows.dart';

Map<String, dynamic> map(Object? value) =>
    Map<String, dynamic>.from(value as Map);

void main() {
  final fixture = map(jsonDecode(
      File('test/fixtures/product_spec_row_conditions.json')
          .readAsStringSync()));
  final schemas = {
    for (final entry in map(fixture['fields']).entries)
      if (entry.value['schema'] is Map)
        entry.key: ProductSpecRowSchema.fromJson(map(entry.value['schema']))
  };
  final conditions =
      ProductSpecRowConditions.fromContract(map(fixture['contract']), schemas);
  test('SQL and Dart share the exact same fixture document', () {
    final sql = File('supabase/tests/fixtures/product_spec_row_conditions.sql')
        .readAsStringSync();
    expect(jsonDecode(sql.split(r'$row_fixture$')[1]), fixture);
  });
  for (final item in fixture['cases']) {
    test('same-row conditions ${item['id']}', () {
      final values = map(item['values']);
      final before = jsonEncode(values);
      final result = conditions
          .validate(values)
          .map((i) => {
                'code': i.code,
                'field': i.field,
                'row_id': i.rowId,
                'column': i.column,
                'blocking': i.blocking
              })
          .toList();
      expect(result, item['expected']);
      expect(jsonEncode(values), before,
          reason: 'Re-evaluation must preserve observations.');
    });
  }
  for (final item in fixture['invalid_metadata']) {
    test('row metadata rejects ${item['id']}', () {
      expect(
          () => ProductSpecRowConditions.fromContract(
              map(item['contract']), schemas),
          throwsFormatException);
    });
  }
  test('legacy schema with no row conditions keeps the previous behavior', () {
    expect(ProductSpecRowConditions.fromContract({}, schemas).validate({}),
        isEmpty);
  });
  test('shape owner handles invalid boolean without a second conditions error',
      () {
    final raw = {
      'schema_version': 1,
      'rows': [
        {
          'id': 'a',
          'values': {'adapter_required': 'false'},
          'sources': []
        }
      ]
    };
    expect(() => schemas['configurations']!.parse(raw), throwsFormatException);
    expect(conditions.validate({'configurations': raw}), isEmpty);
  });
}
