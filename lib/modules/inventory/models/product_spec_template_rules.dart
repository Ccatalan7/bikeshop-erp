import '../utils/spec_rule_evaluator.dart';
import 'product_spec_relation.dart';

/// A field's applicability/completeness expression. Rows are alternatives;
/// predicates within a row must hold together. This says when a question
/// applies, never whether an entire product fits a bicycle.
SpecTruth evaluateProductSpecTemplateCondition(
    Object? expression, Map<String, dynamic> values) {
  if (expression is! Map ||
      expression.keys.any((key) => !{'kind', 'rows'}.contains(key)) ||
      !{'always', 'never', 'when'}.contains(expression['kind'])) {
    throw const FormatException('Condición de campo inválida.');
  }
  final kind = expression['kind'];
  if (kind != 'when') {
    if (expression.containsKey('rows')) {
      throw const FormatException('Una condición constante no admite filas.');
    }
    return kind == 'always' ? SpecTruth.yes : SpecTruth.no;
  }
  final rows = expression['rows'];
  if (rows is! List || rows.isEmpty) {
    throw const FormatException('La condición necesita alternativas.');
  }
  final states = <SpecTruth>[];
  for (final row in rows) {
    if (row is! List || row.isEmpty) {
      throw const FormatException('Una alternativa necesita requisitos.');
    }
    final cellStates = <SpecTruth>[];
    for (final raw in row) {
      if (raw is! Map ||
          raw.keys.any((key) =>
              !{'field', 'operator', 'value_type', 'value'}.contains(key)) ||
          raw['field'] is! String ||
          (raw['field'] as String).isEmpty ||
          !{'token', 'decimal', 'boolean'}.contains(raw['value_type']) ||
          !{'eq', 'in', 'lt', 'lte', 'gt', 'gte'}.contains(raw['operator']) ||
          ({'lt', 'lte', 'gt', 'gte'}.contains(raw['operator']) &&
              raw['value_type'] != 'decimal')) {
        throw const FormatException('Requisito de campo inválido.');
      }
      final choices = raw['operator'] == 'in' ? raw['value'] : [raw['value']];
      if (choices is! List ||
          choices.isEmpty ||
          choices.any((choice) => raw['value_type'] == 'boolean'
              ? choice is! bool
              : choice is! String ||
                  choice.isEmpty ||
                  (raw['value_type'] == 'decimal' &&
                      SpecRuleDecimal.tryParse(choice) == null))) {
        throw const FormatException('Valor de requisito inválido.');
      }
      final condition = Map<String, dynamic>.from(raw);
      // Ordinary editor numbers predate the exact decimal transport. Convert
      // only this declared numeric operand, never model codes or booleans.
      final actual = values[raw['field']];
      final projected =
          raw['value_type'] == 'decimal' && actual is num && actual.isFinite
              ? {...values, raw['field'] as String: actual.toString()}
              : values;
      cellStates.add(evaluateSpecRelationCondition(condition, projected));
    }
    states.add(cellStates.contains(SpecTruth.no)
        ? SpecTruth.no
        : cellStates.contains(SpecTruth.unknown)
            ? SpecTruth.unknown
            : SpecTruth.yes);
  }
  return states.contains(SpecTruth.yes)
      ? SpecTruth.yes
      : states.contains(SpecTruth.unknown)
          ? SpecTruth.unknown
          : SpecTruth.no;
}

Set<String> productSpecTemplateConditionDependencies(Object? expression) {
  evaluateProductSpecTemplateCondition(expression, const {});
  final condition = expression as Map;
  return {
    for (final row in condition['rows'] as List? ?? const [])
      for (final predicate in row as List) predicate['field'] as String,
  };
}
