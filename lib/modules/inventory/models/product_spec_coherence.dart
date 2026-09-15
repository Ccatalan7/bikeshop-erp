import 'product_spec_number.dart';
import 'product_spec_rows.dart';
import '../utils/spec_rule_evaluator.dart';

/// Links belong to a template, not to a reusable row definition. They target
/// stable row IDs; a change to a display label cannot redirect a saved link.
class ProductSpecRowLink {
  const ProductSpecRowLink(
      this.id, this.field, this.column, this.targetField, this.labelColumns);
  final String id;
  final String field;
  final String column;
  final String targetField;
  final List<String> labelColumns;
}

/// One valid stable row ID represents one occurrence in this explicitly
/// declared collection. This never counts cells, mounting positions or rows in
/// another collection, and never derives a total from partial observations.
class ProductSpecRowCardinality {
  const ProductSpecRowCardinality(this.id, this.field, this.totalField);
  final String id;
  final String field;
  final String totalField;
}

class ProductSpecCoherenceIssue {
  const ProductSpecCoherenceIssue(this.code, this.field, this.message,
      {this.rowId, this.column, this.blocking = true});
  final String code;
  final String field;
  final String message;
  final String? rowId;
  final String? column;
  final bool blocking;
}

class ProductSpecRowLinkOptions {
  const ProductSpecRowLinkOptions(this.label, this.choices, {this.error});
  final String label;
  final Map<String, String> choices;
  final String? error;
}

class ProductSpecCoherence {
  ProductSpecCoherence._(this.links, this.scalarOrderedPairs, this.schemas,
      this._cardinalities, this._numberRules);
  final List<ProductSpecRowLink> links;
  final List<List<String>> scalarOrderedPairs;
  final Map<String, ProductSpecRowSchema> schemas;
  // A mounted client may retain a pre-extension instance across hot reload.
  final List<ProductSpecRowCardinality>? _cardinalities;
  List<ProductSpecRowCardinality> get cardinalities =>
      _cardinalities ?? const [];
  final Map<String, Map<String, dynamic>>? _numberRules;

  factory ProductSpecCoherence.fromContract(
      Map<String, dynamic> contract,
      Map<String, String> activeTypes,
      Map<String, ProductSpecRowSchema> schemas,
      Map<String, Set<String>> dependencies,
      {Map<String, String?> units = const {},
      Map<String, Map<String, dynamic>> numberRules = const {}}) {
    final raw = contract['row_coherence'];
    final ordered = contract['scalar_ordered_pairs'];
    if ((contract.containsKey('row_coherence') ||
            contract.containsKey('scalar_ordered_pairs')) &&
        contract['rules_version'] != 2) {
      throw const FormatException(
          'La coherencia requiere condiciones de ficha v2.');
    }
    final links = <ProductSpecRowLink>[];
    final cardinalities = <ProductSpecRowCardinality>[];
    final ids = <String>{};
    final cells = <String>{};
    final edges = {
      for (final key in activeTypes.keys) key: {...?dependencies[key]}
    };
    bool key(Object? value) =>
        value is String &&
        RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value) &&
        !RegExp(r'\s').hasMatch(value);
    if (contract.containsKey('row_coherence')) {
      if (raw is! Map ||
          (raw['version'] != 1 &&
              !(raw['version'] is int && raw['version'] == 2)) ||
          raw['links'] is! List ||
          (raw['version'] == 1
              ? raw.keys.any((k) => !{'version', 'links'}.contains(k))
              : raw.length != 3 ||
                  raw['cardinalities'] is! List ||
                  raw.keys.any((k) =>
                      !{'version', 'links', 'cardinalities'}.contains(k)))) {
        throw const FormatException(
            'Contrato de vínculos de configuración inválido.');
      }
      for (final item in raw['links'] as List) {
        if (item is! Map ||
            item.length != 5 ||
            item.keys.any((k) => !{
                  'id',
                  'field',
                  'column',
                  'target_field',
                  'label_columns'
                }.contains(k)) ||
            !['id', 'field', 'column', 'target_field']
                .every((k) => key(item[k])) ||
            item['field'] == item['target_field'] ||
            !ids.add(item['id'] as String) ||
            !cells.add('${item['field']}.${item['column']}')) {
          throw const FormatException(
              'Vínculo de configuración inválido o duplicado.');
        }
        final source = schemas[item['field']];
        final target = schemas[item['target_field']];
        final column =
            source?.columns.where((c) => c.key == item['column']).firstOrNull;
        final labels = item['label_columns'];
        if (activeTypes[item['field']] != 'json' ||
            activeTypes[item['target_field']] != 'json' ||
            source == null ||
            target == null ||
            column == null ||
            !{'text', 'token'}.contains(column.type) ||
            column.allowedValues.isNotEmpty ||
            labels is! List ||
            labels.isEmpty ||
            labels.any((k) =>
                k is! String || !target.columns.any((c) => c.key == k)) ||
            labels.toSet().length != labels.length) {
          throw const FormatException(
              'El vínculo usa un campo o una columna no disponible.');
        }
        edges[item['field']]!.add(item['target_field'] as String);
        links.add(ProductSpecRowLink(
            item['id'] as String,
            item['field'] as String,
            item['column'] as String,
            item['target_field'] as String,
            List.unmodifiable(labels.cast<String>())));
      }
      final collections = <String>{};
      for (final item in raw['cardinalities'] as List? ?? const []) {
        if (item is! Map ||
            item.length != 3 ||
            item.keys.any((k) => !{'id', 'field', 'total_field'}.contains(k)) ||
            !['id', 'field', 'total_field'].every((k) => key(item[k])) ||
            !ids.add(item['id'] as String) ||
            !collections.add(item['field'] as String) ||
            activeTypes[item['field']] != 'json' ||
            schemas[item['field']] == null ||
            activeTypes[item['total_field']] != 'number') {
          throw const FormatException(
              'La cardinalidad necesita una tabla y un total de esta ficha, sin duplicados.');
        }
        final rules = numberRules[item['total_field']];
        final minimum = productSpecNumber(rules?['min']);
        final maximum = productSpecNumber(rules?['max']);
        if (rules == null ||
            rules['integer'] != true ||
            minimum == null ||
            minimum.negative ||
            maximum != null && minimum.compareTo(maximum) > 0 ||
            productSpecNumberErrorCode(minimum.canonical, rules) ==
                'invalid_rules') {
          throw const FormatException(
              'El total de filas necesita un dominio entero con mínimo no negativo.');
        }
        edges[item['field']]!.add(item['total_field'] as String);
        cardinalities.add(ProductSpecRowCardinality(item['id'] as String,
            item['field'] as String, item['total_field'] as String));
      }
      final visited = <String>{};
      final visiting = <String>{};
      void visit(String key) {
        if (visiting.contains(key)) {
          throw const FormatException(
              'Los vínculos y requisitos forman un ciclo.');
        }
        if (visited.contains(key)) return;
        if (!edges.containsKey(key)) {
          throw const FormatException(
              'El vínculo depende de un campo no disponible.');
        }
        visiting.add(key);
        for (final dep in edges[key]!) {
          visit(dep);
        }
        visiting.remove(key);
        visited.add(key);
      }

      for (final key in edges.keys) {
        visit(key);
      }
      for (final link in links) {
        if (link.labelColumns
            .any((column) => cells.contains('${link.targetField}.$column'))) {
          throw const FormatException(
              'La etiqueta del destino debe usar sus datos, no otro vínculo.');
        }
      }
    }
    final pairs = <List<String>>[];
    if (contract.containsKey('scalar_ordered_pairs')) {
      if (ordered is! List) {
        throw const FormatException(
            'El orden de límites de ficha es inválido.');
      }
      final seen = <String>{};
      for (final pair in ordered) {
        if (pair is! List ||
            pair.length != 2 ||
            pair[0] == pair[1] ||
            pair.any((k) => k is! String || activeTypes[k] != 'number') ||
            units[pair[0]] != units[pair[1]] ||
            !seen.add(pair.join('.'))) {
          throw const FormatException(
              'Los límites requieren dos campos numéricos distintos con la misma unidad.');
        }
        pairs.add(List.unmodifiable(pair.cast<String>()));
      }
    }
    // One owner for inherited and declarative pairs. Until legacy metadata is
    // migrated, preserve its four constraints without duplicating evaluators.
    for (final pair in const [
      ['smallest_cog_teeth', 'largest_cog_teeth'],
      ['tube_width_min_mm', 'tube_width_max_mm'],
      ['tube_width_min_in', 'tube_width_max_in'],
      ['bearing_inner_diameter_mm', 'bearing_outer_diameter_mm'],
    ]) {
      if (pair.every((key) => activeTypes[key] == 'number') &&
          units[pair[0]] == units[pair[1]] &&
          !pairs.any(
              (existing) => existing[0] == pair[0] && existing[1] == pair[1])) {
        pairs.add(pair);
      }
    }
    final rangeEdges = <String, Set<String>>{};
    for (final pair in pairs) {
      (rangeEdges[pair[0]] ??= {}).add(pair[1]);
    }
    final visitedRanges = <String>{};
    final visitingRanges = <String>{};
    void visitRange(String key) {
      if (visitingRanges.contains(key)) {
        throw const FormatException(
            'El orden de límites no puede contradecirse en un ciclo.');
      }
      if (!visitedRanges.add(key)) return;
      visitingRanges.add(key);
      for (final next in rangeEdges[key] ?? <String>{}) {
        visitRange(next);
      }
      visitingRanges.remove(key);
    }

    for (final key in rangeEdges.keys) {
      visitRange(key);
    }
    return ProductSpecCoherence._(
        List.unmodifiable(links),
        List.unmodifiable(pairs),
        Map.unmodifiable(schemas),
        List.unmodifiable(cardinalities),
        Map.unmodifiable({
          for (final entry in numberRules.entries)
            entry.key: Map<String, dynamic>.unmodifiable(entry.value)
        }));
  }

  List<ProductSpecCoherenceIssue> validate(Map<String, dynamic> values) {
    final issues = <ProductSpecCoherenceIssue>[];
    final parsed = <String, ProductSpecRows>{};
    final invalid = <String>{};
    for (final key in {
      for (final link in links) ...[link.field, link.targetField],
      for (final cardinality in cardinalities) cardinality.field,
    }) {
      if (!hasKnownSpecValue(values[key]) &&
          !(cardinalities.any((c) => c.field == key) &&
              values[key] != null &&
              values[key] is! String)) continue;
      try {
        parsed[key] = schemas[key]!.parse(values[key]);
      } on FormatException {
        invalid.add(key);
        issues.add(ProductSpecCoherenceIssue('row_shape', key,
            'La configuración tiene un formato inválido. Sus datos se conservan.'));
      }
    }
    for (final link in links) {
      if (invalid.contains(link.field) || invalid.contains(link.targetField))
        continue;
      final target = parsed[link.targetField];
      for (final row in parsed[link.field]?.rows ?? <ProductSpecRow>[]) {
        final value = row.values[link.column];
        if (value == null) continue;
        if (target == null) {
          issues.add(ProductSpecCoherenceIssue('row_reference_pending',
              link.field, 'Define primero la configuración de destino.',
              rowId: row.id, column: link.column, blocking: false));
        } else if (!target.rows.any((r) => r.id == value)) {
          issues.add(ProductSpecCoherenceIssue(
              'row_reference_unresolved',
              link.field,
              'La configuración vinculada no existe en esta ficha. Revisa el vínculo.',
              rowId: row.id,
              column: link.column));
        }
      }
    }
    for (final cardinality in cardinalities) {
      // A malformed collection cannot become a smaller, apparently valid one
      // by discarding malformed rows or duplicate IDs.
      if (invalid.contains(cardinality.field)) continue;
      final rawTotal = values[cardinality.totalField];
      if (rawTotal == null ||
          rawTotal is String && !hasKnownSpecValue(rawTotal)) {
        issues.add(ProductSpecCoherenceIssue(
            'row_cardinality_pending',
            cardinality.field,
            'Falta confirmar el total declarado de esta colección.',
            blocking: false));
        continue;
      }
      final total = productSpecNumber(rawTotal);
      if (total == null ||
          total.negative ||
          total.exponent < 0 ||
          productSpecNumberErrorCode(rawTotal,
                  _numberRules?[cardinality.totalField] ?? const {}) !=
              null) {
        issues.add(ProductSpecCoherenceIssue(
            'row_cardinality_total',
            cardinality.totalField,
            'El total debe ser una cantidad entera no negativa dentro del dominio del campo.'));
        continue;
      }
      final rows = parsed[cardinality.field]?.rows;
      final count = SpecRuleDecimal.tryParse('${rows?.length ?? 0}')!;
      final comparison = count.compareTo(total);
      if (comparison > 0) {
        issues.add(ProductSpecCoherenceIssue(
            'row_cardinality_conflict',
            cardinality.field,
            'Hay más filas documentadas que el total declarado. Revisa el total o las filas; sus datos se conservan.'));
      } else if (comparison < 0) {
        issues.add(ProductSpecCoherenceIssue(
            'row_cardinality_pending',
            cardinality.field,
            'Faltan filas por documentar para completar el total declarado.',
            blocking: false));
      }
    }
    for (final pair in scalarOrderedPairs) {
      final lower = productSpecNumber(values[pair[0]]);
      final upper = productSpecNumber(values[pair[1]]);
      if (lower != null && upper != null && lower.compareTo(upper) > 0) {
        for (final field in pair) {
          issues.add(ProductSpecCoherenceIssue('range_order', field,
              'El límite inferior no puede superar el superior.'));
        }
      }
    }
    return issues;
  }

  Map<String, ProductSpecRowLinkOptions> optionsFor(String field,
          Map<String, dynamic> values, String Function(String) fieldLabel) =>
      {
        for (final link in links.where((l) => l.field == field))
          link.column: _options(link, values, fieldLabel(link.targetField)),
      };

  ProductSpecRowLinkOptions _options(
      ProductSpecRowLink link, Map<String, dynamic> values, String label) {
    if (!hasKnownSpecValue(values[link.targetField])) {
      return ProductSpecRowLinkOptions(label, const {});
    }
    try {
      final rows =
          schemas[link.targetField]!.parse(values[link.targetField]).rows;
      final labels = [
        for (final row in rows)
          link.labelColumns
              .where((c) => row.values.containsKey(c))
              .map((c) => row.values[c] is bool
                  ? (row.values[c] == true ? 'Sí' : 'No')
                  : row.values[c])
              .join(' · ')
      ];
      return ProductSpecRowLinkOptions(
          label,
          Map.unmodifiable({
            for (var i = 0; i < rows.length; i++)
              rows[i].id: labels[i].isEmpty
                  ? 'Configuración ${i + 1}'
                  : labels.where((label) => label == labels[i]).length > 1
                      ? '${labels[i]} · configuración ${i + 1}'
                      : labels[i],
          }));
    } on FormatException {
      return ProductSpecRowLinkOptions(label, const {},
          error:
              'Revisa el formato de $label antes de vincular una configuración.');
    }
  }
}
