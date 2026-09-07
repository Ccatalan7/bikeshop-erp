import '../utils/spec_rule_evaluator.dart';

/// A result concerns one named interface and the cited alternatives only.
/// It never certifies installation of the whole product or bicycle.
enum SpecRelationVerdict {
  supported,
  excluded,
  outsideDeclaredScope,
  unknown,
}

class SpecRelationAssessment {
  const SpecRelationAssessment(
      this.verdict, this.matchingAlternatives, this.unresolvedFields);

  final SpecRelationVerdict verdict;
  final List<String> matchingAlternatives;
  final Set<String> unresolvedFields;
}

/// Alternatives are rows (OR); a row's conditions must hold together (AND).
/// Sources stay attached to the row, so widths/BSDs, upper/lower headset ends,
/// adapter endpoints or electrical protocols cannot become independent lists.
class ProductSpecRelation {
  ProductSpecRelation._(
      this.interface, this.label, this.alternatives, this.exclusions);

  final String interface;
  final String label;
  final List<SpecRelationRow> alternatives;
  final List<SpecRelationRow> exclusions;

  factory ProductSpecRelation.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 2 ||
        json['interface'] is! String ||
        (json['interface'] as String).trim().isEmpty ||
        json['label'] is! String ||
        (json['label'] as String).trim().isEmpty ||
        json.keys.any((key) => !{
              'schema_version',
              'interface',
              'label',
              'alternatives',
              'exclusions'
            }.contains(key))) {
      throw const FormatException(
          'La relación necesita versión, interfaz y título.');
    }
    List<SpecRelationRow> rows(String key) {
      final raw = json[key];
      if (raw is! List || (key == 'alternatives' && raw.isEmpty)) {
        throw FormatException('La relación necesita filas válidas en $key.');
      }
      final result = raw.map((row) {
        if (row is! Map) {
          throw const FormatException('Fila de relación inválida.');
        }
        return SpecRelationRow.fromJson(Map<String, dynamic>.from(row));
      }).toList(growable: false);
      if (result.map((row) => row.id).toSet().length != result.length) {
        throw const FormatException(
            'Los identificadores de fila deben ser únicos.');
      }
      return List<SpecRelationRow>.unmodifiable(result);
    }

    final alternatives = rows('alternatives');
    final exclusions = rows('exclusions');
    final ids = [...alternatives, ...exclusions].map((row) => row.id).toList();
    if (ids.toSet().length != ids.length) {
      throw const FormatException(
          'Una exclusión y una alternativa no pueden compartir identificador.');
    }
    return ProductSpecRelation._(
        json['interface'], json['label'], alternatives, exclusions);
  }

  SpecRelationAssessment evaluate(Map<String, dynamic> configuration) {
    final unresolved = <String>{};
    SpecTruth assess(SpecRelationRow row) {
      // One target per evaluation. Multiple installed/possible configurations
      // must be evaluated separately, never collapsed into a Cartesian set.
      final values = Map<String, dynamic>.from(configuration);
      final rowUnknown = <String>{};
      for (final condition in row.conditions) {
        final field = condition['field'] as String;
        // V2 transports decimal magnitudes as strings from PostgreSQL. A JSON
        // number may have lost precision before reaching Dart (especially web)
        // and therefore cannot serve as an exact compatibility observation.
        if (values[field] is List ||
            values[field] is Map ||
            values[field] is num) {
          values[field] = null;
        }
        if (evaluateSpecRelationCondition(condition, values) ==
            SpecTruth.unknown) {
          rowUnknown.add(field);
        }
      }
      final states = row.conditions
          .map((condition) => evaluateSpecRelationCondition(condition, values))
          .toList(growable: false);
      final result = states.contains(SpecTruth.no)
          ? SpecTruth.no
          : states.contains(SpecTruth.unknown)
              ? SpecTruth.unknown
              : SpecTruth.yes;
      if (result == SpecTruth.unknown) unresolved.addAll(rowUnknown);
      return result;
    }

    final positive = {for (final row in alternatives) row.id: assess(row)};
    final negative = exclusions.map(assess).toList(growable: false);
    final matched = positive.entries
        .where((e) => e.value == SpecTruth.yes)
        .map((e) => e.key)
        .toList(growable: false);
    // An explicit exclusion narrows the positive coverage, including when a
    // broad positive row also matches. Not matching a positive row alone is
    // only outside this declaration, never a physical incompatibility proof.
    final verdict = negative.contains(SpecTruth.yes)
        ? SpecRelationVerdict.excluded
        : negative.contains(SpecTruth.unknown)
            ? SpecRelationVerdict.unknown
            : matched.isNotEmpty
                ? SpecRelationVerdict.supported
                : positive.containsValue(SpecTruth.unknown)
                    ? SpecRelationVerdict.unknown
                    : SpecRelationVerdict.outsideDeclaredScope;
    return SpecRelationAssessment(verdict, matched,
        verdict == SpecRelationVerdict.unknown ? unresolved : const {});
  }
}

class SpecRelationRow {
  SpecRelationRow._(this.id, this.label, this.conditions, this.sources);

  final String id;
  final String label;
  final List<Map<String, dynamic>> conditions;
  final List<String> sources;

  factory SpecRelationRow.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        (json['id'] as String).trim().isEmpty ||
        json['label'] is! String ||
        (json['label'] as String).trim().isEmpty ||
        json['conditions'] is! List ||
        (json['conditions'] as List).isEmpty ||
        json['sources'] is! List ||
        (json['sources'] as List).isEmpty ||
        json.keys.any(
            (key) => !{'id', 'label', 'conditions', 'sources'}.contains(key))) {
      throw const FormatException(
          'Cada fila necesita identidad, condiciones y fuentes.');
    }
    final sources = (json['sources'] as List).map((source) {
      if (source is! String || !isSpecRelationSourceUrl(source)) {
        throw const FormatException('La fuente debe ser una URL web absoluta.');
      }
      return source;
    }).toList(growable: false);
    final conditions = (json['conditions'] as List).map((raw) {
      if (raw is! Map) {
        throw const FormatException('Condición de relación inválida.');
      }
      final condition = Map<String, dynamic>.from(raw);
      final operator = condition['operator'];
      final valueType = condition['value_type'];
      if (condition['field'] is! String ||
          (condition['field'] as String).trim().isEmpty ||
          !{'eq', 'in', 'lt', 'lte', 'gt', 'gte'}.contains(operator) ||
          !{'decimal', 'token', 'boolean'}.contains(valueType) ||
          condition.keys.any((key) =>
              !{'field', 'operator', 'value_type', 'value'}.contains(key)) ||
          !hasKnownSpecValue(condition['value'])) {
        throw const FormatException(
            'La condición debe comparar un campo conocido de una configuración.');
      }
      final value = condition['value'];
      bool scalar(Object? value) => valueType == 'boolean'
          ? value is bool
          : value is String &&
              (valueType != 'decimal' || specRuleNumber(value) != null);
      if (operator == 'in'
          ? value is! List || value.isEmpty || !value.every(scalar)
          : !scalar(value)) {
        throw const FormatException(
            'Cardinalidad inválida en la condición de relación.');
      }
      if (!{'eq', 'in'}.contains(operator) && valueType != 'decimal') {
        throw const FormatException(
            'Los límites requieren magnitudes decimales.');
      }
      // Validate the numeric operand even when the target is not known yet.
      evaluateSpecRelationCondition(condition, const {});
      return Map<String, dynamic>.unmodifiable({
        ...condition,
        if (value is List) 'value': List<Object?>.unmodifiable(value),
      });
    }).toList(growable: false);
    return SpecRelationRow._(
        json['id'],
        json['label'],
        List<Map<String, dynamic>>.unmodifiable(conditions),
        List<String>.unmodifiable(sources));
  }
}

/// A token such as model "01" is not the decimal 1. The declared value type
/// determines equality; magnitudes compare exactly, token and bool types stay
/// distinct. JSON numbers cannot carry a v2 observation without losslessness.
SpecTruth evaluateSpecRelationCondition(
    Map<String, dynamic> condition, Map<String, dynamic> values) {
  final actual = values[condition['field']];
  if (!hasKnownSpecValue(actual) ||
      actual is num ||
      actual is List ||
      actual is Map) {
    return SpecTruth.unknown;
  }
  final type = condition['value_type'];
  if (type == 'boolean' ? actual is! bool : actual is! String) {
    return SpecTruth.unknown;
  }
  final operator = condition['operator'];
  final choices =
      operator == 'in' ? condition['value'] as List : [condition['value']];
  if (type != 'decimal') {
    return choices.contains(actual) ? SpecTruth.yes : SpecTruth.no;
  }
  final number = specRuleNumber(actual);
  if (number == null) return SpecTruth.unknown;
  final matches = choices.any((choice) {
    final limit = specRuleNumber(choice);
    if (limit == null) {
      throw const FormatException('Magnitud decimal inválida.');
    }
    final comparison = number.compareTo(limit);
    return switch (operator) {
      'lt' => comparison < 0,
      'lte' => comparison <= 0,
      'gt' => comparison > 0,
      'gte' => comparison >= 0,
      _ => comparison == 0,
    };
  });
  return matches ? SpecTruth.yes : SpecTruth.no;
}

/// The same intentionally bounded HTTP(S)/DNS URL grammar is used in SQL.
/// Percent-encoded paths are supported; credentials and IP literals are not
/// part of this reference-source format. No platform-specific Uri exceptions.
bool isSpecRelationSourceUrl(String source) {
  final match = RegExp(
          r"^https?://([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*)(?::([0-9]{1,5}))?([/?#][A-Za-z0-9._~!$&'()*+,;=:@/?%#-]*)?$")
      .firstMatch(source);
  if (match == null || match.end != source.length) return false;
  final port = match[2] == null ? null : int.parse(match[2]!);
  if (port != null && (port < 1 || port > 65535)) return false;
  return !source.replaceAll(RegExp(r'%[0-9A-Fa-f]{2}'), '').contains('%');
}
