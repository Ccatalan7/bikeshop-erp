import '../utils/spec_rule_evaluator.dart';
import 'product_spec_relation.dart';

/// A row is one configuration. Its cells and sources stay together; callers
/// must never turn separate rows into a Cartesian product of possible values.
class ProductSpecRowSchema {
  ProductSpecRowSchema._(
      this.version, this.columns, this.orderedPairs, this.uniqueBy);

  final int version;
  final List<ProductSpecRowColumn> columns;
  final List<List<String>> orderedPairs;
  final List<List<String>> uniqueBy;

  factory ProductSpecRowSchema.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['columns'] is! List ||
        (json['columns'] as List).isEmpty ||
        json.keys.any((key) => !{
              'version',
              'columns',
              'ordered_pairs',
              'unique_by'
            }.contains(key))) {
      throw const FormatException('El esquema de filas no está disponible.');
    }
    final columns = (json['columns'] as List).map((column) {
      if (column is! Map) {
        throw const FormatException('Columna de ficha inválida.');
      }
      return ProductSpecRowColumn.fromJson(Map<String, dynamic>.from(column));
    }).toList(growable: false);
    final keys = columns.map((column) => column.key).toSet();
    if (keys.length != columns.length) {
      throw const FormatException('El esquema repite una columna.');
    }
    List<List<String>> groups(String key) {
      final raw = json.containsKey(key) ? json[key] : const [];
      if (raw is! List) {
        throw const FormatException('Relación de filas inválida.');
      }
      return raw.map((group) {
        if (group is! List ||
            group.isEmpty ||
            group.any((value) => value is! String || !keys.contains(value)) ||
            group.toSet().length != group.length ||
            (key == 'ordered_pairs' &&
                (group.length != 2 ||
                    group.any((value) => !{'decimal', 'integer'}.contains(
                        columns
                            .firstWhere((column) => column.key == value)
                            .type))))) {
          throw const FormatException('Relación de columnas inválida.');
        }
        return List<String>.from(group);
      }).toList(growable: false);
    }

    return ProductSpecRowSchema._(
        1, columns, groups('ordered_pairs'), groups('unique_by'));
  }

  /// Missing cells are an incomplete observation, not a negative declaration.
  /// Wrong types, unknown columns, duplicate positions and reversed ranges
  /// are contradictions and cannot be persisted.
  ProductSpecRows parse(Object? value) {
    if (value is! Map ||
        value['schema_version'] != version ||
        value['rows'] is! List ||
        (value['rows'] as List).isEmpty ||
        value.keys.any((key) => !{'schema_version', 'rows'}.contains(key))) {
      throw const FormatException(
          'Las configuraciones necesitan filas válidas.');
    }
    final rows = <ProductSpecRow>[];
    final ids = <String>{};
    for (final raw in value['rows'] as List) {
      if (raw is! Map ||
          raw['id'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(raw['id'] as String) ||
          !ids.add(raw['id'] as String) ||
          raw['values'] is! Map ||
          (raw['values'] as Map).isEmpty ||
          raw['sources'] is! List ||
          raw.keys.any((key) => !{'id', 'values', 'sources'}.contains(key))) {
        throw const FormatException(
            'Cada fila necesita identidad y datos propios.');
      }
      final values = Map<String, dynamic>.from(raw['values'] as Map);
      if (values.keys
          .any((key) => !columns.any((column) => column.key == key))) {
        throw const FormatException(
            'La fila contiene un campo de otra configuración.');
      }
      for (final column in columns) {
        if (values.containsKey(column.key)) {
          values[column.key] = column.validate(values[column.key]);
        }
      }
      final sources = raw['sources'] as List;
      if (sources.any((source) =>
              source is! String || !isSpecRelationSourceUrl(source)) ||
          sources.toSet().length != sources.length) {
        throw const FormatException(
            'La fuente de la fila necesita una URL válida, sin duplicados.');
      }
      for (final pair in orderedPairs) {
        final lower = specRuleNumber(values[pair[0]]);
        final upper = specRuleNumber(values[pair[1]]);
        if (lower != null && upper != null && lower.compareTo(upper) > 0) {
          throw const FormatException(
              'El límite inferior de una fila supera el superior.');
        }
      }
      rows.add(ProductSpecRow(
          raw['id'] as String, values, List<String>.from(sources)));
    }
    for (final group in uniqueBy) {
      for (var i = 0; i < rows.length; i++) {
        if (group.any((key) => !rows[i].values.containsKey(key))) continue;
        for (var j = 0; j < i; j++) {
          if (group
              .every((key) => rows[i].values[key] == rows[j].values[key])) {
            throw const FormatException(
                'Dos filas repiten la misma posición o identidad.');
          }
        }
      }
    }
    return ProductSpecRows(version, rows);
  }
}

class ProductSpecRowColumn {
  ProductSpecRowColumn._(this.key, this.label, this.type, this.unit,
      this.required, this.allowedValues, this.validation);

  final String key;
  final String label;
  final String type;
  final String? unit;
  final bool required;
  final List<String> allowedValues;
  final Map<String, dynamic> validation;

  factory ProductSpecRowColumn.fromJson(Map<String, dynamic> json) {
    if (json['key'] is! String ||
        !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(json['key'] as String) ||
        json['label'] is! String ||
        (json['label'] as String).trim().isEmpty ||
        !{'text', 'token', 'decimal', 'integer', 'boolean', 'url'}
            .contains(json['type']) ||
        (json['unit'] != null && json['unit'] is! String) ||
        (json.containsKey('required') && json['required'] is! bool) ||
        json.keys.any((key) => !{
              'key',
              'label',
              'type',
              'unit',
              'required',
              'allowed_values',
              'validation'
            }.contains(key))) {
      throw const FormatException('Definición de columna inválida.');
    }
    final allowed =
        json.containsKey('allowed_values') ? json['allowed_values'] : const [];
    final validation = json.containsKey('validation')
        ? json['validation']
        : const <String, dynamic>{};
    if (allowed is! List ||
        allowed.any((v) => v is! String || v.isEmpty) ||
        allowed.toSet().length != allowed.length ||
        (allowed.isNotEmpty && json['type'] != 'token') ||
        validation is! Map ||
        validation.keys
            .any((key) => !{'positive', 'min', 'max'}.contains(key)) ||
        (validation.containsKey('positive') &&
            validation['positive'] is! bool) ||
        ['min', 'max'].any((key) =>
            validation.containsKey(key) &&
            (validation[key] is! String ||
                specRuleNumber(validation[key]) == null)) ||
        (validation.isNotEmpty &&
            !{'decimal', 'integer'}.contains(json['type']))) {
      throw const FormatException('Dominio de columna inválido.');
    }
    final min = specRuleNumber(validation['min']);
    final max = specRuleNumber(validation['max']);
    if (min != null && max != null && min.compareTo(max) > 0) {
      throw const FormatException('Dominio numérico invertido.');
    }
    return ProductSpecRowColumn._(
        json['key'] as String,
        json['label'] as String,
        json['type'] as String,
        json['unit'] as String?,
        json['required'] == true,
        List<String>.from(allowed),
        Map<String, dynamic>.from(validation));
  }

  Object validate(Object? value) {
    if (type == 'boolean') {
      if (value is bool) return value;
    } else if (value is String && value.trim().isNotEmpty) {
      if (type == 'decimal' || type == 'integer') {
        final number = SpecRuleDecimal.tryParse(value);
        if (number == null || (type == 'integer' && number.exponent < 0)) {
          throw FormatException(
              '$label: número ${type == 'integer' ? 'entero ' : ''}inválido.');
        }
        final min = specRuleNumber(validation['min']);
        final max = specRuleNumber(validation['max']);
        if ((validation['positive'] == true &&
                number.compareTo(SpecRuleDecimal.tryParse('0')!) <= 0) ||
            (min != null && number.compareTo(min) < 0) ||
            (max != null && number.compareTo(max) > 0)) {
          throw FormatException('$label: valor fuera del dominio del campo.');
        }
        return number.canonical;
      }
      if (type == 'url' && !isSpecRelationSourceUrl(value)) {
        throw FormatException('$label: ingresa una URL de la fuente.');
      }
      if (type == 'token' &&
          allowedValues.isNotEmpty &&
          !allowedValues.contains(value)) {
        throw FormatException('$label: opción desconocida.');
      }
      return value;
    }
    throw FormatException('$label: tipo de respuesta inválido.');
  }
}

class ProductSpecRow {
  ProductSpecRow(this.id, Map<String, dynamic> values, List<String> sources)
      : values = Map.unmodifiable(values),
        sources = List.unmodifiable(sources);
  final String id;
  final Map<String, dynamic> values;
  final List<String> sources;
  Map<String, dynamic> toJson() =>
      {'id': id, 'values': values, 'sources': sources};
}

class ProductSpecRows {
  ProductSpecRows(this.version, List<ProductSpecRow> rows)
      : rows = List.unmodifiable(rows);
  final int version;
  final List<ProductSpecRow> rows;
  Map<String, dynamic> toJson() => {
        'schema_version': version,
        'rows': rows.map((row) => row.toJson()).toList(growable: false)
      };

  List<String> missingRequired(ProductSpecRowSchema schema) => [
        for (var index = 0; index < rows.length; index++)
          for (final column in schema.columns)
            if (column.required &&
                !hasKnownSpecValue(rows[index].values[column.key]))
              'Configuración ${index + 1}: ${column.label}',
      ];
}
