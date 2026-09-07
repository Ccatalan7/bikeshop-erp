import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_relation.dart';
import 'package:vinabike_erp/modules/inventory/utils/spec_rule_evaluator.dart';

void main() {
  final fixture = jsonDecode(
          File('test/fixtures/product_spec_relations.json').readAsStringSync())
      as Map;
  final relations = fixture['relations'] as Map;
  const verdicts = {
    'supported': SpecRelationVerdict.supported,
    'excluded': SpecRelationVerdict.excluded,
    'outside_declared_scope': SpecRelationVerdict.outsideDeclaredScope,
    'unknown': SpecRelationVerdict.unknown,
  };

  test('PostgreSQL and Dart exercise the same contract scenarios', () {
    final sql = File('supabase/tests/product_spec_scoped_relations.sql')
        .readAsStringSync();
    final embedded = sql.split(r'$fixture$')[1];
    expect(jsonDecode(embedded), fixture);
  });

  for (final raw in fixture['cases'] as List) {
    final example = raw as Map;
    test(example['name'] as String, () {
      final relation = ProductSpecRelation.fromJson(
          Map<String, dynamic>.from(relations[example['relation']] as Map));
      final result = relation
          .evaluate(Map<String, dynamic>.from(example['configuration'] as Map));
      expect(result.verdict, verdicts[example['verdict']]);
      expect(result.unresolvedFields.toList()..sort(),
          example['unresolved_fields']);
    });
  }

  Map<String, dynamic> copy(String key) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(relations[key])) as Map);

  for (final source in fixture['valid_sources'] as List) {
    test('supported source URL $source', () {
      final relation = copy('tube');
      relation['alternatives'][0]['sources'] = [source];
      expect(() => ProductSpecRelation.fromJson(relation), returnsNormally);
    });
  }
  for (final source in fixture['invalid_sources'] as List) {
    test('invalid source URL is rejected: $source', () {
      final relation = copy('tube');
      relation['alternatives'][0]['sources'] = [source];
      expect(
          () => ProductSpecRelation.fromJson(relation), throwsFormatException);
    });
  }

  test('numeric JSON operands and untyped conditions are rejected', () {
    final relation = copy('precision');
    relation['alternatives'][0]['conditions'][0]['value'] = 1.0000000000000001;
    expect(() => ProductSpecRelation.fromJson(relation), throwsFormatException);
    final untyped = copy('precision');
    untyped['alternatives'][0]['conditions'][0].remove('value_type');
    expect(() => ProductSpecRelation.fromJson(untyped), throwsFormatException);
  });

  test('unbounded declarations and source-free rows are rejected', () {
    final empty = copy('tube')..['alternatives'] = [];
    expect(() => ProductSpecRelation.fromJson(empty), throwsFormatException);
    final noSource = copy('tube');
    noSource['alternatives'][0]['sources'] = [];
    expect(() => ProductSpecRelation.fromJson(noSource), throwsFormatException);
    final duplicate = copy('tube');
    duplicate['alternatives'][1]['id'] = '622';
    expect(
        () => ProductSpecRelation.fromJson(duplicate), throwsFormatException);
  });

  test('a declaration cannot approve missing knowledge or non-finite limits',
      () {
    final missing = copy('tube');
    missing['alternatives'][0]['conditions'][0]['operator'] = 'not_set';
    expect(() => ProductSpecRelation.fromJson(missing), throwsFormatException);
    final invalid = copy('numeric');
    invalid['alternatives'][0]['conditions'][0]['value'] = 'NaN';
    expect(() => ProductSpecRelation.fromJson(invalid), throwsFormatException);
  });

  test('all numeric boundary operators distinguish equality', () {
    for (final operator in ['lt', 'lte', 'gt', 'gte']) {
      expect(
          evaluateSpecCondition(
              {'field': 'x', 'operator': operator, 'value': 1}, {'x': 1}),
          {'lte', 'gte'}.contains(operator) ? SpecTruth.yes : SpecTruth.no);
    }
  });

  test('presentation retains alternative rows and explicit exclusions', () {
    final text = productSpecClaimSummary(copy('tube'));
    expect(text, contains('BSD 622, 28–47 mm o BSD 635, 35–47 mm'));
    expect(productSpecClaimSummary(copy('exception')),
        contains('Excluye: Excludes this compound'));
  });
}
