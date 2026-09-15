import '../utils/spec_rule_evaluator.dart';
import 'product_spec_relation.dart';
import 'product_spec_rows.dart';
import 'product_spec_template_rules.dart';

class ProductSpecRowConditionIssue {
  const ProductSpecRowConditionIssue(
      this.code, this.field, this.rowId, this.column, this.message,
      {this.blocking = true});
  final String code;
  final String field;
  final String rowId;
  final String column;
  final String message;
  final bool blocking;
}

/// One implication. Its target is the containing column, never another row.
/// Expected decimals retain exact text and token literals retain their spelling.
class ProductSpecRowValueRule {
  ProductSpecRowValueRule._(this.when, this.valueType, this.expected);
  final Map<String, dynamic> when;
  final String valueType;
  final Object expected;

  factory ProductSpecRowValueRule.fromJson(
      Object? raw, ProductSpecRowColumn column) {
    if (raw is! Map ||
        raw.length != 2 ||
        !raw.containsKey('when') ||
        !raw.containsKey('expected') ||
        raw['when'] is! Map ||
        raw['expected'] is! Map) {
      throw const FormatException('Regla de valor condicionado inválida.');
    }
    final expected = raw['expected'] as Map;
    final type = expected['value_type'];
    if (expected.length != 2 ||
        !expected.containsKey('value') ||
        !{'boolean', 'token', 'decimal'}.contains(type) ||
        (type == 'boolean' && column.type != 'boolean') ||
        (type == 'token' && column.type != 'token') ||
        (type == 'decimal' && !{'decimal', 'integer'}.contains(column.type)) ||
        !hasKnownSpecValue(expected['value'])) {
      throw const FormatException(
          'El valor condicionado necesita el tipo y dominio de su columna.');
    }
    // The ordinary row parser owns exact decimal grammar, range and cardinality.
    final literal = column.validate(expected['value']);
    final when = Map<String, dynamic>.from(raw['when'] as Map);
    productSpecTemplateConditionDependencies(when);
    return ProductSpecRowValueRule._(when, type as String, literal);
  }
}

/// A template may narrow a reusable row schema without changing its cells.
/// Operands belong to the same row; another member cannot satisfy a condition.
class ProductSpecRowFieldConditions {
  ProductSpecRowFieldConditions._(this.schema, this.allowedWhen,
      this.requiredWhen, this.allowedOptions, this._valueWhen);
  final ProductSpecRowSchema schema;
  final Map<String, dynamic> allowedWhen;
  final Map<String, dynamic> requiredWhen;
  final Map<String, List<String>> allowedOptions;
  // A live template decoded before this extension can survive hot reload.
  // Its existing metadata did not contain this bucket, so absence is empty.
  final Map<String, List<ProductSpecRowValueRule>>? _valueWhen;
  Map<String, List<ProductSpecRowValueRule>> get valueWhen =>
      _valueWhen ?? const {};

  SpecTruth applicabilityFor(String column, Map<String, dynamic> values) =>
      allowedWhen.containsKey(column)
          ? evaluateProductSpecTemplateCondition(allowedWhen[column], values)
          : SpecTruth.yes;

  SpecTruth requiredFor(String column, Map<String, dynamic> values) => schema
          .columns
          .firstWhere((c) => c.key == column)
          .required
      ? SpecTruth.yes
      : requiredWhen.containsKey(column)
          ? evaluateProductSpecTemplateCondition(requiredWhen[column], values)
          : SpecTruth.no;

  Set<String> dependenciesFor(String column) => {
        if (allowedWhen.containsKey(column))
          ...productSpecTemplateConditionDependencies(allowedWhen[column]),
        if (requiredWhen.containsKey(column))
          ...productSpecTemplateConditionDependencies(requiredWhen[column]),
        for (final rule
            in valueWhen[column] ?? const <ProductSpecRowValueRule>[])
          ...productSpecTemplateConditionDependencies(rule.when),
      };

  List<ProductSpecRowConditionIssue> validateRow(
      String field, String rowId, Map<String, dynamic> values) {
    final result = <ProductSpecRowConditionIssue>[];
    for (final column in schema.columns) {
      final known = hasKnownSpecValue(values[column.key]);
      final allowed = applicabilityFor(column.key, values);
      void issue(String code, String message, {bool blocking = true}) =>
          result.add(ProductSpecRowConditionIssue(
              code, field, rowId, column.key, message,
              blocking: blocking));
      if (allowed == SpecTruth.no) {
        if (known) {
          issue('row_field_applicability',
              '${column.label}: el dato no corresponde a los requisitos de esta configuración.');
        }
        continue;
      }
      if (allowed == SpecTruth.unknown) {
        issue('row_prerequisite',
            '${column.label}: confirma primero los requisitos de esta configuración.',
            blocking: false);
      } else if (!known &&
          requiredFor(column.key, values) == SpecTruth.unknown) {
        issue('row_prerequisite',
            '${column.label}: falta determinar si este dato es necesario.',
            blocking: false);
      } else if (!known && requiredFor(column.key, values) == SpecTruth.yes) {
        // Static required cells already have one owner in rows.missingRequired.
        if (!column.required) {
          issue('row_required_missing',
              '${column.label}: falta confirmar este dato de la configuración.',
              blocking: false);
        }
      }
      final options = allowedOptions[column.key];
      if (known && options != null && !options.contains(values[column.key])) {
        issue('row_option',
            '${column.label}: la opción no pertenece a esta ficha.');
      }
      if (allowed != SpecTruth.yes) continue;
      var pending = false;
      var conflict = false;
      var expectationsConflict = false;
      ProductSpecRowValueRule? active;
      for (final rule
          in valueWhen[column.key] ?? const <ProductSpecRowValueRule>[]) {
        final antecedent =
            evaluateProductSpecTemplateCondition(rule.when, values);
        if (antecedent == SpecTruth.no) continue;
        if (antecedent == SpecTruth.unknown) {
          pending = true;
          continue;
        }
        // Every confirmed implication applies. An empty observation cannot
        // conceal mutually exclusive expectations, and list order is not
        // precedence. Compare through the same typed exact-decimal evaluator.
        if (active != null) {
          expectationsConflict = expectationsConflict ||
              evaluateSpecRelationCondition({
                    'field': column.key,
                    'operator': 'eq',
                    'value_type': rule.valueType,
                    'value': rule.expected,
                  }, {
                    column.key: active.expected
                  }) ==
                  SpecTruth.no;
        }
        active ??= rule;
        if (!known) {
          pending = true;
          continue;
        }
        final equal = evaluateSpecRelationCondition({
          'field': column.key,
          'operator': 'eq',
          'value_type': rule.valueType,
          'value': rule.expected,
        }, values);
        conflict = conflict || equal == SpecTruth.no;
        pending = pending || equal == SpecTruth.unknown;
      }
      final expectedLabel = active == null
          ? null
          : active.expected is bool
              ? (active.expected == true ? 'Sí' : 'No')
              : '${active.expected}${active.valueType == 'decimal' && column.unit != null ? ' ${column.unit}' : ''}';
      if (expectationsConflict) {
        issue('row_value_conflict',
            '${column.label}: hay condiciones confirmadas que exigen valores incompatibles para esta configuración.');
      } else if (conflict) {
        issue('row_value_conflict',
            '${column.label}: se espera «$expectedLabel» para las condiciones confirmadas de esta configuración.');
      } else if (pending) {
        issue('row_value_pending',
            '${column.label}: ${expectedLabel == null ? '' : 'se espera «$expectedLabel»; '}falta confirmar el valor o los requisitos de esta configuración.',
            blocking: false);
      }
    }
    return result;
  }
}

class ProductSpecRowConditions {
  ProductSpecRowConditions._(this.fields);
  final Map<String, ProductSpecRowFieldConditions> fields;

  factory ProductSpecRowConditions.fromContract(Map<String, dynamic> contract,
      Map<String, ProductSpecRowSchema> schemas) {
    if (!contract.containsKey('row_conditions')) {
      return ProductSpecRowConditions._(const {});
    }
    final raw = contract['row_conditions'];
    if (contract['rules_version'] != 2 ||
        raw is! Map ||
        raw['version'] != 1 ||
        raw['fields'] is! Map ||
        raw.keys.any((key) => !{'version', 'fields'}.contains(key))) {
      throw const FormatException('Condiciones de configuración inválidas.');
    }
    final fields = <String, ProductSpecRowFieldConditions>{};
    for (final entry in (raw['fields'] as Map).entries) {
      final schema = schemas[entry.key];
      final rules = entry.value;
      if (schema == null ||
          rules is! Map ||
          rules.isEmpty ||
          rules.keys.any((key) => !{
                'allowed_when',
                'required_when',
                'allowed_options',
                'value_when'
              }.contains(key))) {
        throw const FormatException(
            'Las condiciones usan un campo de filas no disponible.');
      }
      final columns = {for (final column in schema.columns) column.key: column};
      final dependencies = {
        for (final column in schema.columns) column.key: <String>{}
      };
      final allowed = <String, dynamic>{};
      final required = <String, dynamic>{};
      final options = <String, List<String>>{};
      final valueWhen = <String, List<ProductSpecRowValueRule>>{};
      for (final bucket in rules.entries) {
        if (bucket.value is! Map) {
          throw const FormatException(
              'Falta un mapa de condiciones de columnas.');
        }
        for (final cell in (bucket.value as Map).entries) {
          final column = columns[cell.key];
          if (column == null) {
            throw const FormatException(
                'Una condición apunta a otra configuración.');
          }
          if (bucket.key == 'allowed_options') {
            final choices = cell.value;
            if (column.type != 'token' ||
                choices is! List ||
                choices.any((v) =>
                    v is! String ||
                    v.isEmpty ||
                    column.allowedValues.isNotEmpty &&
                        !column.allowedValues.contains(v)) ||
                choices.toSet().length != choices.length) {
              throw const FormatException(
                  'Las opciones exceden el dominio de la columna.');
            }
            options[column.key] = List.unmodifiable(choices.cast<String>());
            continue;
          }
          final expressions = <Object?>[];
          if (bucket.key == 'value_when') {
            if (cell.value is! List || (cell.value as List).isEmpty) {
              throw const FormatException(
                  'Una columna necesita reglas de valor condicionado.');
            }
            final rules = (cell.value as List)
                .map((raw) => ProductSpecRowValueRule.fromJson(raw, column))
                .toList(growable: false);
            valueWhen[column.key] = List.unmodifiable(rules);
            expressions.addAll(rules.map((rule) => rule.when));
          } else {
            productSpecTemplateConditionDependencies(cell.value);
            expressions.add(cell.value);
          }
          if (bucket.key == 'allowed_when' &&
              column.required &&
              (cell.value as Map)['kind'] != 'always') {
            throw const FormatException(
                'Una columna obligatoria del esquema no puede hacerse condicional.');
          }
          for (final expression in expressions) {
            dependencies[column.key]!
                .addAll(productSpecTemplateConditionDependencies(expression));
            for (final row
                in (expression as Map)['rows'] as List? ?? const []) {
              for (final predicate in row as List) {
                final input = columns[predicate['field']];
                final type = predicate['value_type'];
                if (input == null ||
                    (type == 'boolean' && input.type != 'boolean') ||
                    (type == 'decimal' &&
                        !{'decimal', 'integer'}.contains(input.type)) ||
                    (type == 'token' &&
                        !{'text', 'token'}.contains(input.type))) {
                  throw const FormatException(
                      'Un requisito usa una columna o un tipo ajeno.');
                }
                final choices = predicate['operator'] == 'in'
                    ? predicate['value'] as List
                    : [predicate['value']];
                if (input.allowedValues.isNotEmpty &&
                    choices
                        .any((value) => !input.allowedValues.contains(value))) {
                  throw const FormatException(
                      'Un requisito usa una opción ajena a la columna.');
                }
              }
            }
          }
          if (bucket.key != 'value_when') {
            (bucket.key == 'allowed_when' ? allowed : required)[column.key] =
                cell.value;
          }
        }
      }
      final visited = <String>{};
      final visiting = <String>{};
      void visit(String key) {
        if (visiting.contains(key)) {
          throw const FormatException(
              'Los requisitos de una configuración forman un ciclo.');
        }
        if (visited.contains(key)) return;
        visiting.add(key);
        for (final dep in dependencies[key]!) {
          visit(dep);
        }
        visiting.remove(key);
        visited.add(key);
      }

      for (final key in columns.keys) {
        visit(key);
      }
      for (final entry in valueWhen.entries) {
        final scoped = options[entry.key];
        if (scoped != null &&
            entry.value.any((rule) => !scoped.contains(rule.expected))) {
          throw const FormatException(
              'El valor condicionado excede las opciones de esta ficha.');
        }
      }
      fields[entry.key as String] = ProductSpecRowFieldConditions._(
          schema,
          Map.unmodifiable(allowed),
          Map.unmodifiable(required),
          Map.unmodifiable(options),
          Map.unmodifiable(valueWhen));
    }
    return ProductSpecRowConditions._(Map.unmodifiable(fields));
  }

  List<ProductSpecRowConditionIssue> validate(Map<String, dynamic> values) {
    final result = <ProductSpecRowConditionIssue>[];
    for (final entry in fields.entries) {
      if (!hasKnownSpecValue(values[entry.key])) continue;
      ProductSpecRows rows;
      try {
        rows = entry.value.schema.parse(values[entry.key]);
      } on FormatException {
        continue; // The row-shape validator owns malformed documents once.
      }
      for (final row in rows.rows) {
        result.addAll(entry.value.validateRow(entry.key, row.id, row.values));
      }
    }
    return result;
  }
}
