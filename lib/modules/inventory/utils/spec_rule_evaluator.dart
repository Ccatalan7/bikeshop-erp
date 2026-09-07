/// Three-valued conditions shared by template visibility, prerequisites and
/// option constraints. Missing knowledge never satisfies a negative condition.
enum SpecTruth { yes, no, unknown }

bool hasKnownSpecValue(Object? value) {
  if (value == null) return false;
  if (value is List) return value.isNotEmpty && value.every(hasKnownSpecValue);
  if (value is String) {
    final text = value.trim().toLowerCase();
    return text.isNotEmpty &&
        text != 'desconocido / sin confirmar' &&
        text != 'unknown';
  }
  return true; // false and zero are answers.
}

String normalizeSpecRuleValue(Object? value) {
  if (value == null) return '';
  return specRuleNumber(value)?.canonical ?? value.toString().trim();
}

Set<String> specRuleValueSet(Object? value) =>
    (value is List ? value : [value]).map(normalizeSpecRuleValue).toSet();

/// A numeric condition describes one configuration, not an unordered list of
/// possible configurations. Units are part of the field's canonical contract.
SpecRuleDecimal? specRuleNumber(Object? value) {
  if (value is! num && value is! String) return null;
  if (value is num && !value.isFinite) return null;
  return SpecRuleDecimal.tryParse(value.toString().trim().replaceAll(',', '.'));
}

/// Exact decimal comparison, including strings beyond IEEE-754 precision.
/// No binary rounding or fixed-width integer conversion can equate two limits.
class SpecRuleDecimal implements Comparable<SpecRuleDecimal> {
  const SpecRuleDecimal._(this.negative, this.digits, this.exponent);

  final bool negative;
  final String digits;
  final int exponent;

  static final _syntax =
      RegExp(r'^([+-]?)([0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE]([+-]?[0-9]+))?$');

  static SpecRuleDecimal? tryParse(String text) {
    final match = _syntax.firstMatch(text);
    if (match == null) return null;
    final rawExponent = int.tryParse(match[3] ?? '0');
    // Reject before subtracting the mantissa scale: int64 minimum minus a
    // fractional digit can wrap to a positive exponent on native Dart.
    if (rawExponent == null || rawExponent < -16383 || rawExponent > 1073741823)
      return null;
    final mantissa = match[2]!;
    final point = mantissa.indexOf('.');
    var exponent = rawExponent - (point < 0 ? 0 : mantissa.length - point - 1);
    // PostgreSQL checks the input scale before trimming zeros, including zero
    // itself. Canonicalization cannot rescue an out-of-range wire value.
    if (exponent < -16383) return null;
    var digits = mantissa.replaceAll('.', '').replaceFirst(RegExp(r'^0+'), '');
    if (digits.isEmpty) return const SpecRuleDecimal._(false, '0', 0);
    final trimmed = digits.replaceFirst(RegExp(r'0+$'), '');
    exponent += digits.length - trimmed.length;
    digits = trimmed;
    // PostgreSQL unconstrained numeric's representable decimal bounds. These
    // are serialization bounds, never physical limits of a bicycle field.
    if (exponent < -16383 || digits.length + exponent > 131072) return null;
    return SpecRuleDecimal._(match[1] == '-', digits, exponent);
  }

  String get canonical {
    final point = digits.length + exponent;
    final magnitude = exponent >= 0
        ? digits.padRight(point, '0')
        : point > 0
            ? '${digits.substring(0, point)}.${digits.substring(point)}'
            : '0.${''.padRight(-point, '0')}$digits';
    return negative ? '-$magnitude' : magnitude;
  }

  @override
  int compareTo(SpecRuleDecimal other) {
    if (digits == '0' || other.digits == '0') {
      if (digits == other.digits) return 0;
      return digits == '0' ? (other.negative ? 1 : -1) : (negative ? -1 : 1);
    }
    if (negative != other.negative) return negative ? -1 : 1;
    var result = (digits.length + exponent)
        .compareTo(other.digits.length + other.exponent);
    if (result == 0) {
      final width = digits.length > other.digits.length
          ? digits.length
          : other.digits.length;
      result = digits
          .padRight(width, '0')
          .compareTo(other.digits.padRight(width, '0'));
    }
    return negative ? -result : result;
  }
}

SpecTruth evaluateSpecCondition(
  Map<String, dynamic> rule,
  Map<String, dynamic> values,
) {
  for (final group in ['all', 'any']) {
    if (!rule.containsKey(group)) continue;
    final children = rule[group];
    if (children is! List || children.isEmpty) {
      throw FormatException('Una condición $group necesita condiciones.');
    }
    final states = children.map((child) =>
        evaluateSpecCondition(Map<String, dynamic>.from(child as Map), values));
    if (group == 'all') {
      if (states.contains(SpecTruth.no)) return SpecTruth.no;
      return states.contains(SpecTruth.unknown)
          ? SpecTruth.unknown
          : SpecTruth.yes;
    }
    if (states.contains(SpecTruth.yes)) return SpecTruth.yes;
    return states.contains(SpecTruth.unknown)
        ? SpecTruth.unknown
        : SpecTruth.no;
  }
  final field = rule['field'];
  if (field is! String || field.isEmpty) {
    throw const FormatException('La condición no identifica un campo.');
  }
  final actual = values[field];
  final operator = rule['operator'] ?? 'eq';
  if (operator == 'is_set') {
    return hasKnownSpecValue(actual) ? SpecTruth.yes : SpecTruth.no;
  }
  if (operator == 'not_set') {
    return hasKnownSpecValue(actual) ? SpecTruth.no : SpecTruth.yes;
  }
  if (const {'lt', 'lte', 'gt', 'gte'}.contains(operator)) {
    final expected = specRuleNumber(rule['value']);
    if (expected == null) {
      throw const FormatException(
          'El límite de la condición debe ser numérico y finito.');
    }
    final number = specRuleNumber(actual);
    if (number == null) return SpecTruth.unknown;
    final comparison = number.compareTo(expected);
    final matches = switch (operator) {
      'lt' => comparison < 0,
      'lte' => comparison <= 0,
      'gt' => comparison > 0,
      _ => comparison >= 0,
    };
    return matches ? SpecTruth.yes : SpecTruth.no;
  }
  const operators = {
    'eq',
    'neq',
    'in',
    'not_in',
    'contains_any',
    'contains_all'
  };
  if (!operators.contains(operator)) {
    throw FormatException('Operador de ficha no soportado: $operator');
  }
  if (!hasKnownSpecValue(actual)) return SpecTruth.unknown;
  final actualSet = specRuleValueSet(actual);
  final expected = specRuleValueSet(rule['value']);
  final same =
      actualSet.length == expected.length && actualSet.containsAll(expected);
  final matches = switch (operator) {
    'eq' => same,
    'neq' => !same,
    'in' => actualSet.every(expected.contains),
    'not_in' => actualSet.intersection(expected).isEmpty,
    'contains_any' => actualSet.intersection(expected).isNotEmpty,
    'contains_all' => actualSet.containsAll(expected),
    _ => false,
  };
  return matches ? SpecTruth.yes : SpecTruth.no;
}

SpecTruth evaluateSpecConditions(
  List<Map<String, dynamic>> rules,
  Map<String, dynamic> values,
) {
  if (rules.isEmpty) return SpecTruth.yes;
  return evaluateSpecCondition({'all': rules}, values);
}

Set<String>? intersectSpecOptionRules(
  List<Map<String, dynamic>> rules,
  Map<String, dynamic> values,
) {
  Set<String>? result;
  for (final rule in rules) {
    if (evaluateSpecCondition(rule, values) != SpecTruth.yes) continue;
    final allow = rule['allow'];
    if (allow is! List) {
      throw const FormatException('La restricción no declara sus opciones.');
    }
    final offered = specRuleValueSet(allow);
    result = result == null ? offered : result.intersection(offered);
  }
  return result;
}

Set<String> specConditionDependencies(Iterable<Map<String, dynamic>> rules) => {
      for (final rule in rules) ...{
        if (rule['field'] is String) rule['field'] as String,
        for (final group in ['all', 'any'])
          if (rule[group] is List)
            ...specConditionDependencies((rule[group] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))),
      }
    };
