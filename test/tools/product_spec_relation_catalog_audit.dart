// Evaluate proposed declarations using the existing engine. This does not
// claim that the product editor or a published reference consumes them yet.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_relation.dart';

void main() {
  const path = String.fromEnvironment('SPEC_RELATION_CATALOG_CASES');
  if (path.isEmpty) {
    test('relation catalogue audit requires explicit cases', () {},
        skip: 'Pass SPEC_RELATION_CATALOG_CASES.');
    return;
  }
  final document = jsonDecode(File(path).readAsStringSync()) as Map;
  final fixtures = (document['pending_cases'] as List)
      .where((item) => item['relation_claim'] != null)
      .toList();
  if (fixtures.isEmpty) {
    throw StateError('No relation declarations to evaluate.');
  }
  for (final fixture in fixtures) {
    test('${fixture['id']}: executable declaration scope', () {
      final configuration = Map<String, dynamic>.from(fixture['configuration']);
      final before = jsonEncode(configuration);
      final relation = ProductSpecRelation.fromJson(
          Map<String, dynamic>.from(fixture['relation_claim']));
      final result = relation.evaluate(configuration);
      expect(result.verdict.name, fixture['required_verdict']);
      if (fixture['required_matched'] != null) {
        expect(result.matchingAlternatives,
            unorderedEquals(fixture['required_matched']));
      }
      if (fixture['required_unresolved'] != null) {
        expect(result.unresolvedFields,
            containsAll(fixture['required_unresolved']));
      }
      expect(
          fixture['must_not_be'] ?? [], isNot(contains(result.verdict.name)));
      expect(jsonEncode(configuration), before,
          reason: 'A verdict cannot invent or change product observations.');
    });
  }
}
