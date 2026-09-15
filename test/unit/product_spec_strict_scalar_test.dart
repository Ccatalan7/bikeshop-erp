import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_coherence.dart';

void main() {
  final fixture = jsonDecode(
      File('test/fixtures/product_spec_strict_scalar.json')
          .readAsStringSync()) as Map;
  final types = Map<String, String>.from(fixture['types'] as Map);
  final units = Map<String, String>.from(fixture['units'] as Map);
  final contract = Map<String, dynamic>.from(fixture['contract'] as Map);
  ProductSpecCoherence parse(Map<String, dynamic> c,
          {Map<String, String>? unitOverride}) =>
      ProductSpecCoherence.fromContract(c, types, const {}, const {},
          units: unitOverride ?? units);

  for (final c in fixture['cases'] as List) {
    test(c['id'] as String, () {
      final values = Map<String, dynamic>.from(c['values'] as Map);
      final before = jsonEncode(values);
      final issues = parse(contract).validate(values);
      expect(issues.map((i) => i.field).toList(), c['expected_fields']);
      expect(
          issues.every((i) => i.blocking && i.code == 'range_order'), isTrue);
      expect(jsonEncode(values), before);
    });
  }
  for (final c in fixture['invalid_contracts'] as List) {
    test('rejects ${c['id']}', () {
      expect(() => parse(Map<String, dynamic>.from(c['contract'] as Map)),
          throwsFormatException);
    });
  }
  test('strict order rejects mismatched units and old rule versions', () {
    expect(() => parse(contract, unitOverride: {...units, 'frame_mm': 'in'}),
        throwsFormatException);
    expect(
        () => parse({...contract, 'rules_version': 1}), throwsFormatException);
  });
  test('ordinary ranges still admit equality', () {
    final nonStrict = {
      'rules_version': 2,
      'scalar_ordered_pairs': [
        ['post_mm', 'frame_mm']
      ]
    };
    expect(parse(nonStrict).validate({'post_mm': '27.2', 'frame_mm': '27.2'}),
        isEmpty);
  });
  test('declared strict order replaces the inherited pair only once', () {
    final c = ProductSpecCoherence.fromContract({
      'rules_version': 2,
      'scalar_ordered_pairs': [
        ['bearing_inner_diameter_mm', 'bearing_outer_diameter_mm', 'lt']
      ]
    }, {
      'bearing_inner_diameter_mm': 'number',
      'bearing_outer_diameter_mm': 'number'
    }, const {}, const {});
    expect(c.scalarOrderedPairs.length, 1);
    expect(
        c.validate({
          'bearing_inner_diameter_mm': '30',
          'bearing_outer_diameter_mm': '30'
        }).length,
        2);
  });
}
